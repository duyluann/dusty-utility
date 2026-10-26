#!/usr/bin/env bash
set -euo pipefail

# Check Docker
if ! command -v docker &>/dev/null; then
  echo "Error: Docker not installed. Install from https://docs.docker.com/get-docker/"
  exit 1
fi

# Check port 80
if nc -zw2 127.0.0.1 80 2>/dev/null; then
  echo "Warning: something already listening on port 80 -- Let's Encrypt HTTP-01 may fail"
else
  echo "Note: port 80 must be open on your firewall for Let's Encrypt to issue certificates"
fi

# Detect public IP (IPv4 only — sslip.io requires IPv4)
PUBLIC_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s api.ipify.org 2>/dev/null || echo "")
if [ -z "$PUBLIC_IP" ]; then
  echo "Error: could not detect public IPv4 address"
  exit 1
fi
TRAEFIK_HOST="dusty-utility.${PUBLIC_IP}.sslip.io"
echo "Domain: $TRAEFIK_HOST"

# Create traefik-net if not exists
docker network create traefik-net 2>/dev/null || true

# Inject TRAEFIK_HOST and ACME_EMAIL into each service .env
for svc_dir in */; do
  svc_dir="${svc_dir%/}"
  [ -f "$svc_dir/.env.example" ] || continue
  [ -f "$svc_dir/.env" ] || cp "$svc_dir/.env.example" "$svc_dir/.env"
  grep -q "^TRAEFIK_HOST=" "$svc_dir/.env" && sed -i'' "s|^TRAEFIK_HOST=.*|TRAEFIK_HOST=$TRAEFIK_HOST|" "$svc_dir/.env" || true
  grep -q "^ACME_EMAIL=" "$svc_dir/.env" && sed -i'' "s|^ACME_EMAIL=.*|ACME_EMAIL=dl97.app@gmail.com|" "$svc_dir/.env" || true
done

# Create acme.json (required by Traefik)
touch acme.json && chmod 600 acme.json

# Launch
./start.sh

echo ""
echo "Your app is live at: https://dusty-utility.${PUBLIC_IP}.sslip.io"
echo "Note: SSL certificate issuance takes ~30 seconds after startup"
