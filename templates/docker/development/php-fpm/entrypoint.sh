#!/bin/sh
set -e

# Ensure writable dirs
mkdir -p storage/framework/{cache,sessions,testing,views} storage/logs bootstrap/cache || true
chmod -R 775 storage bootstrap/cache || true

# Composer dependencies (no dev install here; mounted from host typically)
if [ ! -d vendor ]; then
  composer install --no-interaction --prefer-dist --no-progress || true
fi

# Run migrations quietly if DB is up
php artisan migrate --force || true

exec "$@"
