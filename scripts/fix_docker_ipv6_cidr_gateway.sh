#!/usr/bin/env bash
# Fix Docker Engine 27.x IPv6 CIDR gateways that break `docker compose up`
# on Coolify with:
#   ParseAddr("fdxx::1/64"): unexpected character, want colon (at "/64")
#
# Run on the Coolify HOST as root (SSH, or Servers → Terminal in Coolify),
# NOT inside the application container. Then redeploy the app.
#
# Why this is a host fix: Coolify pre-creates an attachable network named
# after the resource UUID (`docker network create --attachable <uuid>`).
# Engine 27.x stores that network's IPv6 gateway as CIDR until the daemon
# restarts (https://github.com/moby/moby/pull/49520). Compose then
# inspects the network and exits. No change to docker-compose.yml can
# stop Coolify from injecting that already-created network.
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,16p' "$0"
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the Coolify host (sudo $0)." >&2
  exit 1
fi

echo "Docker Engine: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"

if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled docker >/dev/null 2>&1; then
  echo "Restarting docker so in-memory IPAM reports IPv6 gateways without /64..."
  systemctl restart docker
else
  echo "Restart the Docker daemon, then rerun this script." >&2
  exit 1
fi

echo "Docker is up. Redeploy the Coolify application."
echo
echo "If ParseAddr comes back on the NEXT new network (PR preview, new"
echo "resource), either upgrade Docker Engine to 28.0.1+ or persist:"
echo '  {"ipv6": false}  in /etc/docker/daemon.json, then restart docker.'
echo "See https://github.com/coollabsio/coolify/issues/8649"
