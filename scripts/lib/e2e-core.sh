#!/usr/bin/env bash
# Duke's Bank E2E core — runs inside anchor-demo-dukesbank-runner (Docker).
# MySQL must be reachable at $MYSQL_HOST (compose service name: mysql).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

resolve_demo_paths
assert_demo_layout

log_step "Schema SSOT (db-metadata in container)"
pip_install_db_metadata
mkdir -p "${DB_META_ROOT}/metadata"
db-migration export --url "$MYSQL_URL" --out "${DB_META_ROOT}/metadata/dukesbank.db"
db-migration verify "${DB_META_ROOT}/metadata/dukesbank.db" --url "$MYSQL_URL"

log_step "Build java-ast-ssot"
mvn_package "$JAVA_AST_ROOT"

log_step "Code SSOT export (javaee-ejb2-jboss)"
mkdir -p "${JAVA_AST_ROOT}/metadata"
java -jar "$(java_ast_jar)" export \
  -s "$DUKESBANK_BANK_ROOT" \
  --profile javaee-ejb2-jboss \
  -o "${JAVA_AST_ROOT}/metadata/dukesbank-code.db"

log_step "Crosswalk -> linked SSOT"
java -jar "$(java_ast_jar)" crosswalk \
  --code-db "${JAVA_AST_ROOT}/metadata/dukesbank-code.db" \
  --schema-db "${DB_META_ROOT}/metadata/dukesbank.db" \
  --db-schema dukesbank \
  -o "${JAVA_AST_ROOT}/metadata/dukesbank-linked.db"

assert_path "${JAVA_AST_ROOT}/metadata/dukesbank-linked.db" "linked SSOT"

printf '\nE2E complete.\n'
printf '  Linked SSOT: %s/metadata/dukesbank-linked.db\n' "$JAVA_AST_ROOT"
printf '\nNext — Anchor Explorer:\n'
printf '  cd %s/anchor-explorer && npm run dev\n' "$ANCHOR_ROOT"
printf '  Load: %s/metadata/dukesbank-linked.db\n' "$JAVA_AST_ROOT"
printf '  Expected: 32 links, 0 issues\n'
