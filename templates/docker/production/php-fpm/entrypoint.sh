#!/bin/sh
set -e

# Initialize storage directory if empty (as root)
if [ ! "$(ls -A /var/www/storage 2>/dev/null)" ]; then
  echo "Initializing storage directory..."
  cp -R /var/www/storage-init/. /var/www/storage || true
fi

# Ensure proper permissions for storage directory (as root)
echo "Setting storage permissions..."
chown -R www-data:www-data /var/www/storage || true
chmod -R 775 /var/www/storage || true
mkdir -p /var/www/storage/logs && chmod 775 /var/www/storage/logs || true

# Remove storage-init directory
rm -rf /var/www/storage-init || true

# Run Laravel optimizations and migrations
php artisan migrate --force || true
php artisan config:cache || true
php artisan route:cache || true

exec "$@"
