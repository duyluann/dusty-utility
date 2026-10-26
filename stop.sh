#!/usr/bin/env bash
set -euo pipefail

if [ -n "${TRAEFIK_HOST:-}" ] && [ "$TRAEFIK_HOST" != "example.com" ]; then
  _TRAEFIK_HOST="$TRAEFIK_HOST"
else
  _TRAEFIK_HOST=""
  for svc in kuma freellm; do
    [ -f "$svc/.env" ] || continue
    _h=$(grep -m1 '^TRAEFIK_HOST=' "$svc/.env" 2>/dev/null | cut -d= -f2- || true)
    [ -n "$_h" ] && [ "$_h" != "example.com" ] && { _TRAEFIK_HOST="$_h"; break; }
  done
fi

if [ -n "$_TRAEFIK_HOST" ]; then
  SERVICES=(traefik kuma freellm)
else
  SERVICES=(kuma freellm)
fi

for svc in "${SERVICES[@]}"; do
  echo "==> stopping $svc"
  docker compose -f "$svc/docker-compose.yml" down
done

echo "Done. All services stopped."
