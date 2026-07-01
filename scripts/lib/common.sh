# Shared helpers for Duke's Bank demo scripts (bash).
# shellcheck shell=bash

set -euo pipefail

log_step() {
  printf '\n==> %s\n' "$1"
}

log_ok() {
  printf '    OK: %s\n' "$1"
}

assert_path() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

resolve_demo_paths() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DEMO_ROOT="$(cd "${lib_dir}/../.." && pwd)"
  ANCHOR_ROOT="${ANCHOR_ROOT:-$(cd "${DEMO_ROOT}/.." && pwd)}"
  GITHUB_ROOT="${GITHUB_ROOT:-$(cd "${ANCHOR_ROOT}/.." && pwd)}"
  DUKESBANK_BANK_ROOT="${DUKESBANK_BANK_ROOT:-${GITHUB_ROOT}/dukesbank/src/j2eetutorial14/examples/bank}"
  DB_META_ROOT="${ANCHOR_ROOT}/db-metadata"
  JAVA_AST_ROOT="${ANCHOR_ROOT}/java-ast-ssot"
  REWRITE_ROOT="${ANCHOR_ROOT}/rewrite-recipes"
  PARITY_ROOT="${ANCHOR_ROOT}/parity-verify"
  MYSQL_HOST="${MYSQL_HOST:-mysql}"
  MYSQL_URL="${MYSQL_URL:-mysql+pymysql://dukesbank:dukesbank@${MYSQL_HOST}:3306/dukesbank}"
}

wait_mysql_healthy() {
  local deadline=$((SECONDS + 180))
  local status=""
  while [[ $SECONDS -lt $deadline ]]; do
    status="$(docker inspect -f '{{.State.Health.Status}}' dukesbank-mysql 2>/dev/null || true)"
    printf '  health: %s\n' "${status:-unknown}"
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi
    sleep 3
  done
  echo "MySQL container not healthy within 3 minutes" >&2
  exit 1
}

ensure_mysql() {
  if [[ "${SKIP_DOCKER:-0}" == "1" ]]; then
    log_step "MySQL (skipped — SKIP_DOCKER=1)"
    return 0
  fi
  log_step "MySQL (demo-dukesbank)"
  (
    cd "$DEMO_ROOT"
    docker compose up -d mysql
  )
  wait_mysql_healthy
}

ensure_runner_image() {
  (
    cd "$DEMO_ROOT"
    docker compose build runner
  )
}

pip_install_db_metadata() {
  pip3 install -q -e "${DB_META_ROOT}[mysql]"
}

mvn_package() {
  local module_root="$1"
  mvn -B -q -f "${module_root}/pom.xml" package -DskipTests
}

java_ast_jar() {
  echo "${JAVA_AST_ROOT}/target/java-ast-ssot-1.0.0-SNAPSHOT.jar"
}

parity_jar() {
  echo "${PARITY_ROOT}/target/parity-verify-0.2.0-SNAPSHOT.jar"
}

assert_demo_layout() {
  resolve_demo_paths
  assert_path "$DUKESBANK_BANK_ROOT" "Duke's Bank module (clone dukesbank next to anchor-migration)"
  assert_path "${DB_META_ROOT}/pyproject.toml" "db-metadata repo"
  assert_path "${JAVA_AST_ROOT}/pom.xml" "java-ast-ssot repo"
}

assert_jpa_layout() {
  assert_demo_layout
  assert_path "${REWRITE_ROOT}/pom.xml" "rewrite-recipes repo"
  assert_path "${PARITY_ROOT}/pom.xml" "parity-verify repo"
}

compose_run() {
  local service="$1"
  shift
  (
    cd "$DEMO_ROOT"
    docker compose run --rm "$service" "$@"
  )
}
