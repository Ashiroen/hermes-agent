#!/usr/bin/env bash
# Recreate Docker networks whose IPv6 gateway is stored as CIDR
# (e.g. fde4:...::1/64) so `docker compose up` no longer dies with:
#   ParseAddr("fdxx::1/64"): unexpected character, want colon
#
# Uses the Docker HTTP API over the unix socket (curl), not the Go
# client — Compose/docker CLI ParseAddr on inspect, curl does not.
#
# Coolify: Configuration → General → Custom Start Command:
#   bash scripts/coolify-compose-up.sh
#
# Or Pre-deployment Command:
#   bash scripts/coolify_strip_ipv6_cidr_gateways.sh
set -euo pipefail

SOCK="${DOCKER_SOCKET:-/var/run/docker.sock}"
API="${DOCKER_API_BASE:-http://localhost}"

if [[ ! -S "$SOCK" ]]; then
  echo "docker socket $SOCK not found; skip network rewrite" >&2
  exit 0
fi

docker_api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -sS --unix-socket "$SOCK" -X "$method" \
      -H 'Content-Type: application/json' \
      -d "$data" "$API$path"
  else
    curl -sS --unix-socket "$SOCK" -X "$method" "$API$path"
  fi
}

network_has_cidr_gateway() {
  local body="$1"
  grep -Eq '"Gateway":"[^"]*/[0-9]+"' <<<"$body"
}

# Names of user-created networks (skip bridge/host/none).
list_network_names() {
  docker_api GET /networks \
    | tr ',' '\n' \
    | sed -n 's/.*"Name":"\([^"]*\)".*/\1/p' \
    | grep -Ev '^(bridge|host|none)$' \
    | sort -u
}

container_ids_on_network() {
  local body="$1"
  # Docker inspect JSON keys Containers as { "<64-hex-id>": { ... } }
  grep -oE '[0-9a-f]{64}' <<<"$body" | sort -u
}

recreate_ipv4() {
  local name="$1"
  local body
  body="$(docker_api GET "/networks/$name" || true)"
  if [[ -z "$body" || "$body" == *'"message":'* && "$body" == *'not found'* ]]; then
    echo "network $name missing; creating IPv4-only attachable"
    docker_api POST /networks/create \
      "{\"Name\":\"$name\",\"CheckDuplicate\":false,\"Attachable\":true,\"EnableIPv6\":false}" >/dev/null \
      || true
    return 0
  fi
  if ! network_has_cidr_gateway "$body"; then
    return 0
  fi
  echo "rewriting $name (IPv6 gateway stored as CIDR)"
  local ids id
  ids="$(container_ids_on_network "$body")"
  for id in $ids; do
    docker_api POST "/networks/$name/disconnect" \
      "{\"Container\":\"$id\",\"Force\":true}" >/dev/null || true
  done
  docker_api DELETE "/networks/$name" >/dev/null || true
  docker_api POST /networks/create \
    "{\"Name\":\"$name\",\"CheckDuplicate\":false,\"Attachable\":true,\"EnableIPv6\":false}" >/dev/null
  for id in $ids; do
    docker_api POST "/networks/$name/connect" \
      "{\"Container\":\"$id\"}" >/dev/null || true
  done
}

targets="$(list_network_names || true)"
if [[ -n "${COOLIFY_RESOURCE_UUID:-}" ]]; then
  targets=$(printf '%s\n%s\n' "$targets" "$COOLIFY_RESOURCE_UUID" | sort -u)
fi

if [[ -z "$targets" ]]; then
  echo "no docker networks to scan"
  exit 0
fi

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  recreate_ipv4 "$name"
done <<<"$targets"

echo "IPv6 CIDR gateways rewritten (IPv4-only attachable networks)"
