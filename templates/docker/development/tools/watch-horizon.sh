#!/bin/sh
# Watch app code and restart Horizon gracefully when files change.
set -e

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotifywait not found; please ensure inotify-tools is installed in the image." >&2
  exec php artisan horizon
fi

# Start Horizon in background
php artisan horizon &
HORIZON_PID=$!

# Watch for changes in app/, routes/, config/, database/
while inotifywait -r -e modify,create,delete,move \
  app bootstrap config database routes resources; do
  echo "Changes detected. Asking Horizon to terminate (it will be restarted)."
  php artisan horizon:terminate || true
  # Wait a moment for the supervisor to restart Horizon
  sleep 1
  # If horizon exited, restart it
  if ! kill -0 "$HORIZON_PID" 2>/dev/null; then
    php artisan horizon &
    HORIZON_PID=$!
  fi
done
