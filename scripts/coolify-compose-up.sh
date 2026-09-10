#!/usr/bin/env bash
# Coolify Custom Start Command for this repo:
#   bash scripts/coolify-compose-up.sh
#
# Rewrites UUID/coolify networks whose IPv6 gateway is CIDR (so the
# Compose Go client can inspect them), then runs `docker compose up -d`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/coolify_strip_ipv6_cidr_gateways.sh"

compose=(docker compose)
if [[ -f "$ROOT/.env" ]]; then
  compose+=(--env-file "$ROOT/.env")
fi
if [[ -n "${COOLIFY_RESOURCE_UUID:-}" ]]; then
  compose+=(--project-name "$COOLIFY_RESOURCE_UUID")
fi
compose+=(--project-directory "$ROOT" -f "$ROOT/docker-compose.yml" up -d)

echo "running: ${compose[*]}"
exec "${compose[@]}"
