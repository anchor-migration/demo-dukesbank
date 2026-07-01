#!/usr/bin/env bash
# Host entry: Duke's Bank Step 7 — anchor-stubborn LLM context (Docker-first).
#
# Delegates to anchor-stubborn/docker-compose.yml dukesbank-e2e service.
# Requires sibling dukesbank clone at ../../dukesbank.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_demo_paths
STUBBORN_ROOT="${ANCHOR_ROOT}/anchor-stubborn"
assert_path "$STUBBORN_ROOT" "anchor-stubborn repo"

log_step "anchor-stubborn Duke's Bank E2E (Docker)"
(
  cd "$STUBBORN_ROOT"
  docker compose build anchor-stubborn
  docker compose run --rm dukesbank-e2e
)

log_step "Verify context artifacts"
(
  cd "$STUBBORN_ROOT"
  docker compose run --rm --entrypoint python \
    -w /opt/anchor-stubborn \
    dukesbank-e2e scripts/verify_dukesbank_context.py
)

printf '\nDone. Artifacts under %s/examples/dukesbank/metadata/\n' "$STUBBORN_ROOT"
