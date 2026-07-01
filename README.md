# Duke's Bank — MySQL demo (bridge)

**This folder is not the Duke's Bank application.** It is the **database bridge** for [Anchor Migration](https://github.com/anchor-migration/migration-hub): a small Docker Compose setup that runs a MySQL instance seeded from the legacy sample, so tools like [db-metadata](../db-metadata) can export and verify schema SSOT.

The **Java EE sample itself** is **not part of the Anchor Migration org** (we have not forked or vendored it yet). You — and we — use an **external clone** sitting next to the `anchor-migration` folder on disk.

---

## About Duke's Bank (external legacy sample)

[Duke's Bank](https://github.com/jiananwang/dukesbank) is a classic **J2EE 1.4 / Java EE** tutorial application (EJB 2.x CMP, servlets/JSP, Ant build). It originated from Sun's J2EE tutorial; this fork adds **MySQL** seed data and deployment descriptors suitable for migration demos.

| What | Where |
|------|--------|
| Java sources, EJB XML, web tier | **Not in anchor-migration** — external `dukesbank` clone (see layout below) |
| MySQL DDL + seed data | `dukesbank/data/mysql/dukesbank.sql` |
| Bank module root (for `java-ast-ssot`) | `dukesbank/src/j2eetutorial14/examples/bank/` |

**Org policy (today):** no `anchor-migration/dukesbank` repository. This demo only documents how to wire an external checkout into Docker and our SSOT tools. A first-party fork may come later; the sibling-directory contract would stay the same.

---

## Layout contract (sibling directories)

`docker-compose.yml` assumes **`dukesbank` is a sibling of `anchor-migration`**, both under the same parent directory — not inside `anchor-migration`, not inside `demo-dukesbank`.

From this folder (`anchor-migration/demo-dukesbank`), the mount path is:

```yaml
../../dukesbank/data/mysql/dukesbank.sql → container init script
```

That means: up to `anchor-migration/`, up to the parent (e.g. `github/` or `C:\github\`), then into `dukesbank/`.

### Example (author / recommended layout)

```
C:\github\                          ← parent (one level above anchor-migration)
├── anchor-migration/
│   ├── demo-dukesbank/             ← this repo
│   ├── db-metadata/
│   └── java-ast-ssot/
└── dukesbank/                      ← external clone (same parent as anchor-migration)
    └── data/mysql/dukesbank.sql
```

On Linux/macOS the same idea applies, e.g. `~/github/anchor-migration/` and `~/github/dukesbank/`.

### 1. Clone Duke's Bank (once per machine)

```bash
cd C:\github          # parent of anchor-migration — adjust to your path
git clone https://github.com/jiananwang/dukesbank.git
```

Clone **next to** `anchor-migration`, not inside it. Another fork is fine if `data/mysql/dukesbank.sql` exists.

### 2. Adjust paths only if your layout differs

If `dukesbank` is **not** at `../../dukesbank` relative to this folder, edit the `volumes` entry in `docker-compose.yml`:

```yaml
volumes:
  - /absolute/or/relative/path/to/dukesbank/data/mysql/dukesbank.sql:/docker-entrypoint-initdb.d/01-dukesbank.sql:ro
```

Then use the same JDBC URL in export commands (`localhost:3306/dukesbank` unless you changed the port).

---

## What is in *this* folder

| File / directory | Purpose |
|------------------|---------|
| `docker-compose.yml` | MySQL + runner image + E2E compose services |
| `docker/Dockerfile.runner` | Maven + Python toolchain image (no host JDK/pip) |
| `Makefile` | Linux shortcuts (`make e2e`, `make e2e-jpa`) |
| `scripts/run-e2e.sh` | **Primary** — schema + code + crosswalk (bash, Docker-first) |
| `scripts/run-e2e-jpa-parity.sh` | **Primary** — CMP→JPA + per-entity parity |
| `scripts/run-stubborn-context.sh` | Step 7 — delegates to `anchor-stubborn` Docker E2E |
| `scripts/lib/*.sh` | Core pipeline (runs inside runner container) |
| `scripts/*.ps1` | Thin Windows wrappers (Git Bash or `docker compose`) |
| `README.md` | Setup and runbook (this file) |

There is no application code, no SQL file, and no exported SQLite here. Those come from the **sibling** `dukesbank/` checkout and from sibling repos (`db-metadata`, `java-ast-ssot`, …) after E2E runs.

---

## Prerequisites

- **Docker** (Desktop or Engine + Compose v2)
- Duke's Bank cloned as **sibling of `anchor-migration`** (see layout contract above)
- **No host JDK, Maven, or `pip install`** required for E2E — the runner container provides them

Optional: **Git Bash** on Windows so `*.ps1` wrappers can invoke `*.sh` directly.

---

## Quick start (Docker-first)

From this directory:

```bash
# Build runner image (once, or after Dockerfile changes)
docker compose build runner

# Full E2E: MySQL + schema + code + crosswalk
docker compose up -d mysql
docker compose run --rm e2e

# Or use the host wrapper (starts MySQL + runs compose):
chmod +x scripts/*.sh
./scripts/run-e2e.sh
```

**Linux / macOS** — `make` shortcuts:

```bash
make e2e          # schema -> code -> crosswalk
make e2e-jpa      # CMP->JPA + parity (4 entities)
make stubborn     # anchor-stubborn LLM context
```

**Windows PowerShell** — same pipelines via thin wrappers:

```powershell
.\scripts\run-e2e.ps1
.\scripts\run-e2e.ps1 -SkipDocker    # MySQL already up
```

Produces `java-ast-ssot/metadata/dukesbank-linked.db` (32 links, 0 errors — last verified 2026-06-27).

---

## Start database only

```bash
cd demo-dukesbank
docker compose up -d
docker compose ps
```

---

## Export schema SSOT (manual / advanced)

The E2E scripts run `db-metadata` **inside the runner container**. To export schema manually on the host:

```bash
cd ../db-metadata
pip install -e ".[mysql]"
db-migration export \
  --url "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank" \
  --out metadata/dukesbank.db
db-migration verify metadata/dukesbank.db \
  --url "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank"
```

**Last verified:** 2026-06-27 — `verify` exits 0 (36 matched entities).

For the **code** side, use `./scripts/run-e2e.sh` or see [java-ast-ssot](../java-ast-ssot).

## End-to-end runbook (schema → code → crosswalk → Explorer)

Full narrative: [DUKESBANK-DEMO.md — E2E quick path](../migration-hub/docs/DUKESBANK-DEMO.md#e2e-quick-path).

### One-shot (bash — recommended)

```bash
cd demo-dukesbank
./scripts/run-e2e.sh
# MySQL already up:
SKIP_DOCKER=1 ./scripts/run-e2e.sh
```

### One-shot (compose only)

```bash
docker compose up -d mysql
docker compose run --rm e2e
```

### JPA re-export + parity (ADR-004 Step 4d / ADR-007 v0.4 multi-entity)

```bash
./scripts/run-e2e-jpa-parity.sh
# or:
docker compose run --rm e2e-jpa-parity
```

Windows:

```powershell
.\scripts\run-e2e-jpa-parity.ps1
.\scripts\run-e2e-jpa-parity.ps1 -SkipDocker
```

| Recipe chain | Entity |
|--------------|--------|
| `CmpScalarEntityToJpa` + `CmpManyToManyToJpa` | `AccountBean` |
| `CmpScalarEntityToJpa` (`CustomerBean`) | `CustomerBean` |
| `CmpScalarEntityToJpa` (`TxBean`) + `CmpForeignKeyToJpa` | `TxBean` |
| `NextIdTableToJpa` | `NextIdBean` |

Produces:

| Artifact | Role |
|----------|------|
| `dukesbank-code-before.db` | EJB-era code SSOT |
| `dukesbank-code-after.db` | Post-CMP→JPA + auto-detected profiles |
| `dukesbank-linked-before.db` / `dukesbank-linked-after.db` | Crosswalk snapshots |
| `parity-verify/metadata/dukesbank-parity-accountbean.json` (+ `.html`) | AccountBean matrix |
| `parity-verify/metadata/dukesbank-parity-customerbean.json` (+ `.html`) | CustomerBean matrix |
| `parity-verify/metadata/dukesbank-parity-txbean.json` (+ `.html`) | TxBean matrix |
| `parity-verify/metadata/dukesbank-parity-nextidbean.json` (+ `.html`) | NextIdBean matrix |

Apply recipe to a single file (Docker):

```bash
cd rewrite-recipes
docker run --rm -v "$PWD:/app" -v "/path/to/bank:/work" -w /app \
  maven:3.9-eclipse-temurin-17 bash -lc \
  'mvn -B -q compile dependency:build-classpath -Dmdep.outputFile=target/cp.txt -Dmdep.includeScope=compile && \
   java -cp target/classes:$(cat target/cp.txt) com.anchor.migration.rewrite.cli.ApplyRecipeMain \
   CmpScalarEntityToJpa /work/src/com/sun/ebank/ejb/tx/TxBean.java TxBean'
```

Supported recipes: `CmpScalarEntityToJpa`, `CmpManyToManyToJpa`, `CmpForeignKeyToJpa`, `NextIdTableToJpa`. Optional third argument sets `targetClassName` for `CmpScalarEntityToJpa`.

### Anchor Explorer

```powershell
cd ..\anchor-explorer
npm install
npm run dev
```

Open http://127.0.0.1:5173/ → **Choose File** → `java-ast-ssot\metadata\dukesbank-linked.db`

Expected: crosswalk graph, link table, **Links: 32**, **Issues: 0**.

### Step 7 — LLM context (`anchor-stubborn`)

```bash
./scripts/run-stubborn-context.sh
```

Windows: `.\scripts\run-stubborn-context.ps1`

Full narrative: [DUKESBANK-DEMO.md Step 7](../migration-hub/docs/DUKESBANK-DEMO.md#optional--llm-context-anchor-stubborn) · [anchor-stubborn/examples/dukesbank](https://github.com/stubborn-ai/stubborn/tree/main/examples/dukesbank).

---

## Manual steps (host toolchain)

Use only when debugging outside the runner container. Prefer `./scripts/run-e2e.sh` for the supported path.

```bash
# Schema SSOT (host db-migration against localhost:3306)
cd db-metadata
db-migration export \
  --url "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank" \
  --out metadata/dukesbank.db
db-migration verify metadata/dukesbank.db \
  --url "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank"

cd ../java-ast-ssot
docker run --rm -v "$PWD:/app" -w /app maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests

docker run --rm \
  -v "$PWD:/app" \
  -v "/path/to/dukesbank/src/j2eetutorial14/examples/bank:/bank:ro" \
  -v "../db-metadata:/dbmeta:ro" \
  -w /app maven:3.9-eclipse-temurin-17 \
  java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar export \
  -s /bank --profile javaee-ejb2-jboss -o metadata/dukesbank-code.db

docker run --rm \
  -v "$PWD:/app" \
  -v "../db-metadata:/dbmeta:ro" \
  -w /app maven:3.9-eclipse-temurin-17 \
  java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar crosswalk \
  --code-db metadata/dukesbank-code.db \
  --schema-db /dbmeta/metadata/dukesbank.db \
  --db-schema dukesbank \
  -o metadata/dukesbank-linked.db
```

**Last verified (2026-06-27):** 4 CMP entities → **32** canonical links, **0** crosswalk errors.

Legacy one-liner: `.\scripts\run-e2e.ps1` (Windows) delegates to the same Docker pipeline.

---

## Path overrides

If `dukesbank` is not at `../../dukesbank`, set env vars before running (see `.env.example`):

```bash
export DUKESBANK_BANK_ROOT=/path/to/bank/module
export GITHUB_ROOT=/path/to/parent-of-anchor-migration-and-dukesbank
```

---

## Expected schema snapshot (MySQL 5.7)

| Metric | Expected |
|--------|----------|
| Tables | 5 |
| Columns | 27 |
| Primary keys | 4 |
| Foreign keys (SQL) | 0 |
| Indexes (non-PK) | 0 |

Table names: `ACCOUNT`, `CUSTOMER`, `TX`, `CUSTOMER_ACCOUNT_XREF`, `NEXT_ID`.

---

## Stop

```bash
docker compose down
docker compose down -v   # remove data volume for clean re-init
```

---

## Troubleshooting

- **Port 3306 in use:** change the host port in `docker-compose.yml` and update the JDBC URL.
- **Init script not found / empty database:** confirm `dukesbank/data/mysql/dukesbank.sql` exists at the path mounted in `docker-compose.yml`; fix the volume path and run `docker compose down -v && docker compose up -d`.
- **Table name case:** the exporter records names as returned by MySQL (uppercase table names on the Linux container).

Full program context: [DUKESBANK-DEMO.md](../migration-hub/docs/DUKESBANK-DEMO.md).
