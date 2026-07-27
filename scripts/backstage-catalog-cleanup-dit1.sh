#!/bin/bash
# Backstage DIT1 catalog cleanup script
# Run AFTER setting up port-forward:
#   kubectl -n platformnex-dit1 port-forward pod/platformnex-backend-5567f5bb56-pp8lg 7007:7007
#
# The /api/catalog/* paths are in publicPaths (no auth required).

set -euo pipefail

BASE="http://localhost:7007"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

delete_location() {
  local name="$1"
  local desc="$2"
  echo -e "${YELLOW}--- $desc ---${NC}"
  local response
  response=$(curl -s "$BASE/api/catalog/entities/by-name/location/default/$name")
  local UID
  UID=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['metadata']['uid'])" 2>/dev/null || true)
  if [ -z "$UID" ]; then
    echo -e "  ${YELLOW}SKIP: entity not found (already cleaned up)${NC}"
    return
  fi
  echo "  UID: $UID"
  local HTTP
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/catalog/entities/by-uid/$UID")
  if [ "$HTTP" = "204" ]; then
    echo -e "  ${GREEN}DELETED (HTTP 204)${NC}"
  else
    echo -e "  ${RED}FAILED (HTTP $HTTP)${NC}"
  fi
}

delete_entity() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  local desc="${4:-$name}"
  echo -e "${YELLOW}--- $desc ---${NC}"
  local response
  response=$(curl -s "$BASE/api/catalog/entities/by-name/$kind/$namespace/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote('$name'))")")
  local UID
  UID=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['metadata']['uid'])" 2>/dev/null || true)
  if [ -z "$UID" ]; then
    echo -e "  ${YELLOW}SKIP: entity not found (already cleaned up)${NC}"
    return
  fi
  echo "  UID: $UID"
  local HTTP
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/catalog/entities/by-uid/$UID")
  if [ "$HTTP" = "204" ]; then
    echo -e "  ${GREEN}DELETED (HTTP 204)${NC}"
  else
    echo -e "  ${RED}FAILED (HTTP $HTTP)${NC}"
  fi
}

echo "========================================"
echo " Backstage DIT1 Catalog Cleanup"
echo " Target: $BASE"
echo "========================================"
echo ""

# Verify port-forward is up
if ! curl -s --max-time 3 "$BASE/" > /dev/null 2>&1; then
  echo -e "${RED}ERROR: Cannot reach $BASE — is the port-forward running?${NC}"
  echo "Run: kubectl -n platformnex-dit1 port-forward pod/platformnex-backend-5567f5bb56-pp8lg 7007:7007"
  exit 1
fi
echo -e "${GREEN}Backend reachable at $BASE${NC}"
echo ""

# ── 1. Stale Location entities (file doesn't exist in cloud_configs) ───────
echo "=== [1/3] STALE LOCATION ENTITIES (file not found) ==="
delete_location \
  "generated-a81b77c38c23cdb00413cfc41f83028d671b8f94" \
  "test-k8-101-service-development.yaml (wrong name — should be 'develop')"
delete_location \
  "generated-59cf1babb3bbec4fb6a9c5329479a7e8f72290ee" \
  "test6-onboard-green-service-branch-env.yaml (file deleted from cloud_configs)"
delete_location \
  "generated-7e5c8236bee1edaa51bcb1ade5d18ce62c0efd78" \
  "github-commit-template.yaml (local file missing from container image)"

echo ""

# ── 2. Ghost component entities (files deleted from cloud_configs, still in DB) ─
echo "=== [2/3] GHOST COMPONENT ENTITIES (source files already deleted) ==="
delete_entity "component" "default" "delete-test-2-service-sample-ephemeral-env"
delete_entity "component" "default" "qa-test-1-develop"
delete_entity "component" "default" "regression-test-004-service-develop"
delete_entity "component" "default" "regression-test-dit1-001-service-develop"
delete_entity "component" "default" "regression-test-dit1-002-service-develop"
delete_entity "component" "default" "regression-test-dit1-003-service-develop"
delete_entity "component" "default" "regression-test-dit1-005-service-develop"
delete_entity "component" "default" "test-1-service-sample-ephemeral-env"
delete_entity "component" "default" "test-delete-1-service-sample-ephemeral-env"
delete_entity "component" "default" "test-delete-2-service-sample-ephemeral-env"
delete_entity "component" "default" "test-service-branch-env"

echo ""

# ── 3. Ghost resource entities (invalid metadata.name, files never existed) ─
echo "=== [3/3] GHOST RESOURCE ENTITIES (invalid metadata.name) ==="
delete_entity "resource" "default" "my-storage bucket-14"                                                   "invalid name: space in name"
delete_entity "resource" "default" "projects/prj-dev-platform-next/locations/us-central1/instances/cache-6" "invalid name: slashes"
delete_entity "resource" "default" "projects/prj-dev-platform-next/topics/queue-6"                          "invalid name: slashes"

echo ""
echo "========================================"
echo " Cleanup complete."
echo " Wait ~2 min for Backstage catalog to re-index,"
echo " then verify warnings are gone in pod logs."
echo "========================================"
