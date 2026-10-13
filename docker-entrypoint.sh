#!/usr/bin/env bash
# Starts Mailcheap on $PORT with uploads on the persistent volume.
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
UPLOADS_DIR="${UPLOADS_DIR:-$DATA_DIR/uploads}"
APP_USER=node

log() { echo "[railway-entrypoint] $*"; }

# Railway mounts volumes as root. Fix ownership once, then drop privileges.
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$UPLOADS_DIR"
  if [ "$(stat -c %U "$DATA_DIR")" != "$APP_USER" ] || [ "$(stat -c %U "$UPLOADS_DIR")" != "$APP_USER" ]; then
    log "Giving $APP_USER ownership of $DATA_DIR"
    chown -R "$APP_USER:$APP_USER" "$DATA_DIR"
  fi
  exec gosu "$APP_USER" "$0" "$@"
fi

# Links in emails and uploaded images use APP_URL. Fall back to the Railway domain.
if [ -z "${APP_URL:-}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export APP_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi
if [ -z "${APP_URL:-}" ]; then
  log "WARNING: APP_URL is not set. Links in emails will point at http://localhost:3000."
fi
if [ -z "${MONGODB_URI:-}" ]; then
  log "WARNING: MONGODB_URI is not set. Pages that read the database will fail."
fi
if [ "${SENDING_ENABLED:-}" = "true" ] && [ -z "${SES_ACCESS_KEY_ID:-}" ]; then
  log "WARNING: SENDING_ENABLED is true but SES_ACCESS_KEY_ID is empty. Sends will fail."
fi

log "Starting Mailcheap $(cut -c1-12 /app/.mailcheap-ref) on port ${PORT:-8080}"
exec /app/node_modules/.bin/next start -p "${PORT:-8080}" "$@"
