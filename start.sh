#!/usr/bin/env bash
set -euo pipefail
export APP_NAME="dusty-utility"

# Detect TRAEFIK_HOST: prefer shell env var (injected by CI via secrets.SERVER_DOMAIN),
# fall back to reading from service .env files.
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
  echo "==> Production mode (TRAEFIK_HOST=${_TRAEFIK_HOST})"
  SERVICES=(traefik kuma freellm)
  docker network inspect traefik-net >/dev/null 2>&1 || docker network create traefik-net
else
  echo "==> Local mode (TRAEFIK_HOST not set — running on localhost without SSL)"
  SERVICES=(kuma freellm)
  unset TRAEFIK_HOST
fi

for svc in "${SERVICES[@]}"; do
  echo "==> $svc"
  if [ ! -f "$svc/.env" ]; then
    cp "$svc/.env.example" "$svc/.env"
    echo "    Copied $svc/.env.example → $svc/.env (edit before re-running)"
  fi
  if [ "$svc" = "kuma" ]; then
    docker run --rm -v "dusty-utility_kuma_data:/app/data" busybox \
      sh -c 'mkdir -p /app/data && [ -f /app/data/db-config.json ] || printf "{\"type\":\"sqlite\"}" > /app/data/db-config.json'
  fi
  if [ -n "$_TRAEFIK_HOST" ]; then
    docker compose -f "$svc/docker-compose.yml" --env-file "$svc/.env" up -d --build
  else
    docker compose -f "$svc/docker-compose.yml" -f "$svc/docker-compose.local.yml" --env-file "$svc/.env" up -d --build
  fi
done

echo ""
echo "Done. Services available at:"
if [ -n "$_TRAEFIK_HOST" ]; then
  echo "  traefik: https://traefik.${_TRAEFIK_HOST}"
  echo "  kuma: https://kuma.${_TRAEFIK_HOST}"
  echo "  freellm: https://freellm.${_TRAEFIK_HOST}"
else
  echo "  Uptime Kuma: http://localhost:3001"
  echo "  FreeLLMAPI: http://localhost:3002"
fi

echo ""
echo "==> Provisioning..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

if [ -n "$_TRAEFIK_HOST" ]; then
  # Insert/update Uptime Kuma monitors
  bash "$SCRIPT_DIR/configure-kuma.sh"

else
  # Insert/update Uptime Kuma monitors (local)
  bash "$SCRIPT_DIR/configure-kuma-local.sh"

fi
echo ""
echo "Provisioning complete."
