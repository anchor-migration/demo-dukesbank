#!/usr/bin/env bash
# Host entry: schema -> code -> crosswalk (Docker-first).
#
# Usage:
#   ./scripts/run-e2e.sh
#   SKIP_DOCKER=1 ./scripts/run-e2e.sh    # MySQL already running
#
# Equivalent:
#   docker compose up -d mysql && docker compose run --rm e2e

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_demo_paths
assert_demo_layout
ensure_runner_image
ensure_mysql

compose_run e2e
