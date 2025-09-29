#!/usr/bin/env bash
set -euo pipefail

# E2E test: spins up a fresh Laravel app, installs this package via a path repo, runs installer,
# builds & starts the Docker stack for the selected preset, verifies health, and cleans up.

# Requirements:
# - docker, docker compose v2
# - composer
# - curl

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
APP_NAME="laravel-dockerize-e2e"
# Allow overriding via environment variables
DB="${DB:-pgsql}"        # pgsql | mysql | mariadb
PRESET="${PRESET:-local}" # local | dev | prod
KEEP_ON_FAILURE="${KEEP_ON_FAILURE:-0}"

# Choose compose file based on preset
case "$PRESET" in
  local) COMPOSE_FILE="docker-compose.local.yml" ;;
  dev)   COMPOSE_FILE="docker-compose.dev.yml" ;;
  prod)  COMPOSE_FILE="docker-compose.yml" ;;
  *) echo "Unknown PRESET: $PRESET" >&2; exit 1 ;;
esac

cleanup() {
  set +e
  if [ -d "$TMP_DIR/$APP_NAME" ]; then
    pushd "$TMP_DIR/$APP_NAME" >/dev/null || true
    if [ "$KEEP_ON_FAILURE" != "1" ]; then
      if [ -f "$COMPOSE_FILE" ]; then
        echo "Bringing down docker-compose stack ($COMPOSE_FILE)..."
        docker compose -f "$COMPOSE_FILE" down -v || true
      fi
      popd >/dev/null || true
      echo "Removing temp dir: $TMP_DIR"
      rm -rf "$TMP_DIR" || true
    else
      echo "KEEP_ON_FAILURE=1 set. Leaving stack running for inspection."
      echo "Temporary app path: $TMP_DIR/$APP_NAME"
      popd >/dev/null || true
      return
    fi
  fi
}
trap cleanup EXIT

echo "[1/7] Creating fresh Laravel app in: $TMP_DIR/$APP_NAME"
echo "TMP_DIR hint: $TMP_DIR"
mkdir -p "$TMP_DIR"
pushd "$TMP_DIR" >/dev/null
composer create-project laravel/laravel "$APP_NAME" --prefer-dist --no-interaction

pushd "$APP_NAME" >/dev/null

echo "[2/7] Linking local package via Composer path repository"
composer config repositories.laravel-dockerize path "$ROOT_DIR"
# Use dev-main because this is a local workspace
# Prefer any dev version from the local path repo; fallback to dev-main if needed
composer require --dev rfpdl/laravel-dockerize:*@dev --no-interaction --no-progress \
  || composer require --dev rfpdl/laravel-dockerize:dev-main --no-interaction --no-progress

echo "[3/7] Running installer (preset=$PRESET, db=$DB)"
php artisan dockerize:install --preset="$PRESET" --db="$DB" --force

echo "[3.5/7] Preparing .env.local from .env.docker.example"
# If a local env_file is referenced by compose, ensure it exists
if [ -f .env.docker.example ]; then
  cp .env.docker.example .env.local
fi

# Ensure APP_KEY is a valid base64 key (Laravel can 500 on invalid keys)
CURRENT_KEY=$(grep '^APP_KEY=' .env.local || true)
NEED_KEY=true
if [ -n "$CURRENT_KEY" ]; then
  # Accept only base64: prefix
  echo "$CURRENT_KEY" | grep -q '^APP_KEY=base64:' && NEED_KEY=false || NEED_KEY=true
fi
if [ "$NEED_KEY" = true ]; then
  KEY="base64:$(head -c 32 /dev/urandom | base64)"
  if grep -q '^APP_KEY=' .env.local; then
    sed -i.bak "s#^APP_KEY=.*#APP_KEY=${KEY}#" .env.local && rm -f .env.local.bak
  else
    echo "APP_KEY=${KEY}" >> .env.local
  fi
fi

echo "[4/7] Building & starting Docker stack ($COMPOSE_FILE)"
docker compose -f "$COMPOSE_FILE" up -d --build

echo "[4.5/7] Ensuring Composer dependencies inside app container"
# Wait for app container to be ready to accept execs (it might be restarting)
for j in $(seq 1 20); do
  if docker compose -f "$COMPOSE_FILE" exec -T app sh -lc 'echo ok' >/dev/null 2>&1; then
    break
  fi
  echo "App container not ready for exec yet (attempt $j/20), sleeping 1s..."
  sleep 1
done
# This speeds up readiness and avoids initial 500s while vendor installs lazily
docker compose -f "$COMPOSE_FILE" exec -T app sh -lc 'if [ ! -f vendor/autoload.php ]; then composer install --no-interaction --prefer-dist --no-progress || true; fi' || true

# Optionally wait for app container to be healthy (php-fpm healthcheck)
# Not all services expose health status out of the box when running locally, so we poll HTTP.

if [ "$PRESET" = "prod" ]; then
  PORT="${NGINX_PORT:-80}"
else
  PORT=80
fi
APP_URL="http://localhost:${PORT}"
RETRIES=45
SLEEP=2

echo "[5/7] Probing HTTP ($APP_URL) until ready..."
for i in $(seq 1 $RETRIES); do
  if curl -fsS "$APP_URL" >/dev/null; then
    echo "App is responding at $APP_URL"
    break
  fi
  echo "Attempt $i/$RETRIES: App not yet ready, sleeping $SLEEP sec..."
  sleep "$SLEEP"
  if [ "$i" -eq "$RETRIES" ]; then
    echo "ERROR: App did not respond after $((RETRIES*SLEEP)) seconds. Showing recent logs..." >&2
    echo "========== APP LOGS (container stdout) ==========" >&2
    docker compose -f "$COMPOSE_FILE" logs --no-color --tail=200 app || true
    echo "========== LARAVEL LOG (storage/logs/laravel.log) ==========" >&2
    docker compose -f "$COMPOSE_FILE" exec -T app sh -lc 'tail -n 200 storage/logs/laravel.log 2>/dev/null || true' || true
    echo "========== VENDOR STATUS ==========" >&2
    docker compose -f "$COMPOSE_FILE" exec -T app sh -lc 'ls -la vendor | head -n 50 2>/dev/null || true' || true
    echo "========== NGINX LOGS ==========" >&2
    docker compose -f "$COMPOSE_FILE" logs --no-color --tail=200 nginx || true
    exit 1
  fi
done

echo "[6/7] Sanity check: artisan and PHP versions inside container"
docker compose -f "$COMPOSE_FILE" exec -T app php -v || true
# artisan may require app key when first run; this is just informational
(docker compose -f "$COMPOSE_FILE" exec -T app php artisan --version || true)

echo "[7/7] SUCCESS: E2E test completed. Cleaning up..."
# Cleanup happens in trap
popd >/dev/null
popd >/dev/null
