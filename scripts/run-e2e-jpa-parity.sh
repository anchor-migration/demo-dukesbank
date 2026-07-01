#!/usr/bin/env bash
# Host entry: multi-entity CMP->JPA + parity (Docker-first).
#
# Usage:
#   ./scripts/run-e2e-jpa-parity.sh
#   SKIP_DOCKER=1 ./scripts/run-e2e-jpa-parity.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_demo_paths
assert_jpa_layout
ensure_runner_image
ensure_mysql

compose_run e2e-jpa-parity
