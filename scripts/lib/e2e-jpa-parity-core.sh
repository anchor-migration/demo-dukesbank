#!/usr/bin/env bash
# Duke's Bank multi-entity JPA E2E + parity — runs inside runner container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

resolve_demo_paths
assert_jpa_layout

ACCOUNT_BEAN_REL="src/com/sun/ebank/ejb/account/AccountBean.java"
CUSTOMER_BEAN_REL="src/com/sun/ebank/ejb/customer/CustomerBean.java"
TX_BEAN_REL="src/com/sun/ebank/ejb/tx/TxBean.java"
NEXT_ID_BEAN_REL="src/com/sun/ebank/ejb/util/NextIdBean.java"

apply_recipe() {
  local abs_path="$1"
  local recipe="$2"
  local target_class="${3:-}"
  mvn -B -q -f "${REWRITE_ROOT}/pom.xml" \
    compile dependency:build-classpath \
    -Dmdep.outputFile=target/cp.txt \
    -Dmdep.includeScope=compile
  local cp
  cp="$(cat "${REWRITE_ROOT}/target/cp.txt")"
  local -a java_args=(
    -cp "${REWRITE_ROOT}/target/classes:${cp}"
    com.anchor.migration.rewrite.cli.ApplyRecipeMain
    "$recipe"
    "$abs_path"
  )
  if [[ -n "$target_class" ]]; then
    java_args+=("$target_class")
  fi
  java "${java_args[@]}"
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$file"; then
    echo "Missing expected pattern in ${file}: ${pattern}" >&2
    exit 1
  fi
}

run_parity_matrix() {
  local touchpoint="$1"
  local matrix_file="$2"
  local report_base="$3"
  mkdir -p "${PARITY_ROOT}/metadata"
  java -jar "$(parity_jar)" compare \
    --before-db "${JAVA_AST_ROOT}/metadata/dukesbank-code-before.db" \
    --after-db "${JAVA_AST_ROOT}/metadata/dukesbank-code-after.db" \
    --linked-before "${JAVA_AST_ROOT}/metadata/dukesbank-linked-before.db" \
    --linked-after "${JAVA_AST_ROOT}/metadata/dukesbank-linked-after.db" \
    --matrix-file "$matrix_file" \
    --touchpoint-source "$touchpoint" \
    -o "${PARITY_ROOT}/metadata/${report_base}.json" \
    --html-out "${PARITY_ROOT}/metadata/${report_base}.html" \
    --fail-on-matrix
}

migrate_entity() {
  local label="$1"
  local rel_path="$2"
  shift 2
  local file_path="${WORK_BANK}/${rel_path}"
  assert_path "$file_path" "${label}.java in work copy"
  log_step "Apply recipes — ${label}"
  while [[ $# -ge 2 ]]; do
    local recipe="$1"
    local target="$2"
    shift 2
    printf '  %s%s\n' "$recipe" "${target:+ ($target)}"
    apply_recipe "$file_path" "$recipe" "$target"
  done
}

log_step "Schema SSOT (db-metadata in container)"
pip_install_db_metadata
mkdir -p "${DB_META_ROOT}/metadata"
db-migration export --url "$MYSQL_URL" --out "${DB_META_ROOT}/metadata/dukesbank.db"
db-migration verify "${DB_META_ROOT}/metadata/dukesbank.db" --url "$MYSQL_URL"

log_step "Build tool JARs"
mvn_package "$JAVA_AST_ROOT"
mvn_package "$REWRITE_ROOT"
mvn_package "$PARITY_ROOT"

log_step "Export BEFORE code SSOT (EJB profile)"
mkdir -p "${JAVA_AST_ROOT}/metadata"
java -jar "$(java_ast_jar)" export \
  -s "$DUKESBANK_BANK_ROOT" \
  --profile javaee-ejb2-jboss \
  -o "${JAVA_AST_ROOT}/metadata/dukesbank-code-before.db"

WORK_BANK="$(mktemp -d)"
trap 'rm -rf "$WORK_BANK"' EXIT
cp -a "${DUKESBANK_BANK_ROOT}/." "${WORK_BANK}/"

log_step "Apply CMP->JPA recipes (multi-entity)"

migrate_entity "AccountBean" "$ACCOUNT_BEAN_REL" \
  CmpScalarEntityToJpa "" \
  CmpManyToManyToJpa ""
assert_file_contains "${WORK_BANK}/${ACCOUNT_BEAN_REL}" "@javax.persistence.Entity"
assert_file_contains "${WORK_BANK}/${ACCOUNT_BEAN_REL}" "@javax.persistence.ManyToMany"
assert_file_contains "${WORK_BANK}/${ACCOUNT_BEAN_REL}" "CUSTOMER_ACCOUNT_XREF"
log_ok "AccountBean transform verified"

migrate_entity "CustomerBean" "$CUSTOMER_BEAN_REL" \
  CmpScalarEntityToJpa CustomerBean
assert_file_contains "${WORK_BANK}/${CUSTOMER_BEAN_REL}" "@javax.persistence.Entity"
assert_file_contains "${WORK_BANK}/${CUSTOMER_BEAN_REL}" '@javax.persistence.Table(name = "CUSTOMER")'
log_ok "CustomerBean transform verified"

migrate_entity "TxBean" "$TX_BEAN_REL" \
  CmpScalarEntityToJpa TxBean \
  CmpForeignKeyToJpa ""
assert_file_contains "${WORK_BANK}/${TX_BEAN_REL}" "@javax.persistence.Entity"
assert_file_contains "${WORK_BANK}/${TX_BEAN_REL}" "@javax.persistence.ManyToOne"
assert_file_contains "${WORK_BANK}/${TX_BEAN_REL}" "account_id"
log_ok "TxBean transform verified"

migrate_entity "NextIdBean" "$NEXT_ID_BEAN_REL" \
  NextIdTableToJpa ""
assert_file_contains "${WORK_BANK}/${NEXT_ID_BEAN_REL}" "@javax.persistence.Entity"
assert_file_contains "${WORK_BANK}/${NEXT_ID_BEAN_REL}" "getNextId()"
log_ok "NextIdBean transform verified"

log_step "Export AFTER code SSOT (auto-detect profiles)"
java -jar "$(java_ast_jar)" export \
  -s "$WORK_BANK" \
  --auto-detect-profiles \
  -o "${JAVA_AST_ROOT}/metadata/dukesbank-code-after.db"

log_step "Crosswalk before / after"
java -jar "$(java_ast_jar)" crosswalk \
  --code-db "${JAVA_AST_ROOT}/metadata/dukesbank-code-before.db" \
  --schema-db "${DB_META_ROOT}/metadata/dukesbank.db" \
  --db-schema dukesbank \
  -o "${JAVA_AST_ROOT}/metadata/dukesbank-linked-before.db"

java -jar "$(java_ast_jar)" crosswalk \
  --code-db "${JAVA_AST_ROOT}/metadata/dukesbank-code-after.db" \
  --schema-db "${DB_META_ROOT}/metadata/dukesbank.db" \
  --db-schema dukesbank \
  -o "${JAVA_AST_ROOT}/metadata/dukesbank-linked-after.db"

log_step "parity-verify behavioral matrices (per entity)"

declare -a PARITY_REPORTS=()

run_entity_parity() {
  local label="$1"
  local rel_path="$2"
  local matrix_path="$3"
  local report_base="dukesbank-parity-$(echo "$label" | tr '[:upper:]' '[:lower:]')"
  printf '  --- matrix: %s ---\n' "$matrix_path"
  run_parity_matrix "${WORK_BANK}/${rel_path}" "$matrix_path" "$report_base"
  PARITY_REPORTS+=("${label}:${PARITY_ROOT}/metadata/${report_base}")
}

run_entity_parity "AccountBean" "$ACCOUNT_BEAN_REL" \
  "${PARITY_ROOT}/examples/matrices/dukesbank-cmp-jpa-multi-account.yaml"
run_entity_parity "CustomerBean" "$CUSTOMER_BEAN_REL" \
  "${PARITY_ROOT}/examples/matrices/dukesbank-cmp-jpa-multi-customer.yaml"
run_entity_parity "TxBean" "$TX_BEAN_REL" \
  "${PARITY_ROOT}/examples/matrices/dukesbank-cmp-jpa-multi-tx.yaml"
run_entity_parity "NextIdBean" "$NEXT_ID_BEAN_REL" \
  "${PARITY_ROOT}/examples/matrices/dukesbank-cmp-jpa-multi-nextid.yaml"

printf '\nMulti-entity JPA E2E + parity complete.\n'
printf '  Before code:  %s/metadata/dukesbank-code-before.db\n' "$JAVA_AST_ROOT"
printf '  After code:   %s/metadata/dukesbank-code-after.db\n' "$JAVA_AST_ROOT"
printf '  Linked after: %s/metadata/dukesbank-linked-after.db\n' "$JAVA_AST_ROOT"

for entry in "${PARITY_REPORTS[@]}"; do
  label="${entry%%:*}"
  base="${entry#*:}"
  printf '  Parity %s JSON: %s.json\n' "$label" "$base"
  printf '  Parity %s HTML: %s.html\n' "$label" "$base"
done

printf '\nAll entity matrices passed (--fail-on-matrix).\n'
