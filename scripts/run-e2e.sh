#!/usr/bin/env bash
set -euo pipefail

# E2E test: spins up a fresh Laravel app, installs this package via a path repo, runs installer,
# builds & starts the local Docker stack, verifies health, and cleans up.

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
    if [ -f "$COMPOSE_FILE" ]; then
      echo "Bringing down docker-compose stack ($COMPOSE_FILE)..."
      docker compose -f "$COMPOSE_FILE" down -v || true
    fi
    popd >/dev/null || true
  fi
  echo "Removing temp dir: $TMP_DIR"
  rm -rf "$TMP_DIR" || true
}
trap cleanup EXIT

echo "[1/7] Creating fresh Laravel app in: $TMP_DIR/$APP_NAME"
mkdir -p "$TMP_DIR"
pushd "$TMP_DIR" >/dev/null
composer create-project laravel/laravel "$APP_NAME" --prefer-dist --no-interaction

pushd "$APP_NAME" >/dev/null

echo "[2/7] Linking local package via Composer path repository"
composer config repositories.laravel-dockerize path "$ROOT_DIR"
# Use dev-main because this is a local workspace
composer require --dev your-vendor/laravel-dockerize:dev-main --no-interaction --no-progress

echo "[3/7] Running installer (preset=$PRESET, db=$DB)"
php artisan dockerize:install --preset="$PRESET" --db="$DB" --force

echo "[4/7] Building & starting Docker stack ($COMPOSE_FILE)"
docker compose -f "$COMPOSE_FILE" up -d --build

# Optionally wait for app container to be healthy (php-fpm healthcheck)
# Not all services expose health status out of the box when running locally, so we poll HTTP.

if [ "$PRESET" = "prod" ]; then
  PORT="${NGINX_PORT:-80}"
else
  PORT=80
fi
APP_URL="http://localhost:${PORT}"
RETRIES=30
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
    echo "ERROR: App did not respond after $((RETRIES*SLEEP)) seconds." >&2
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
