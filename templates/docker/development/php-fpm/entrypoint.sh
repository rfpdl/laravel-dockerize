#!/bin/sh
set -e

# Ensure writable dirs
mkdir -p storage/framework/{cache,sessions,testing,views} storage/logs bootstrap/cache || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

# Ensure vendor dir exists and is writable
mkdir -p vendor || true

# Only try to change ownership if running as root
if [ "$(id -u)" = "0" ]; then
  chown -R www:www vendor storage bootstrap || true
  USER_CMD="su-exec www:www"
else
  USER_CMD=""
fi

# Composer dependencies (no dev install here; mounted from host typically)
if [ ! -f vendor/autoload.php ]; then
  $USER_CMD composer install --no-interaction --prefer-dist --no-progress || true
fi

# Run migrations quietly if DB is up (skip if artisan fails due to missing packages)
$USER_CMD php artisan --version >/dev/null 2>&1 && $USER_CMD php artisan migrate --force || true

# Start PHP-FPM in foreground
exec php-fpm --nodaemonize
