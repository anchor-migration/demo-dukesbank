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

| File | Purpose |
|------|---------|
| `docker-compose.yml` | MySQL 5.7 container, port 3306, health check |
| `scripts/run-e2e.ps1` | **End-to-end** — schema + code + crosswalk (Windows PowerShell) |
| `README.md` | Setup and runbook (this file) |

There is no application code, no SQL file, and no exported SQLite here. Those come from the **sibling** `dukesbank/` checkout and from `../db-metadata/metadata/` after export.

---

## Prerequisites

- Docker Desktop
- Duke's Bank cloned as **sibling of `anchor-migration`** (see layout contract above)
- `db-metadata` installed: `pip install -e "../db-metadata[mysql]"`

---

## Start database

```bash
cd demo-dukesbank
docker compose up -d
docker compose ps
```

Wait until the container is `healthy`. First start runs the init SQL (~30s).

If tables are empty or missing, check that the volume path resolves and re-create the container:

```bash
docker compose down -v
docker compose up -d
```

---

## Export schema SSOT

```bash
cd ../db-metadata
db-migration export \
  --url "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank" \
  --out metadata/dukesbank.db

db-migration verify metadata/dukesbank.db \
  --url "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank"

db-migration info metadata/dukesbank.db
```

**Last verified:** 2026-06-27 — `verify` exits 0 (36 matched entities).

For the **code** side of the demo (Java + EJB XML), see [java-ast-ssot](../java-ast-ssot) and point `--source-root` at your `dukesbank/.../examples/bank` checkout.

## End-to-end runbook (schema → code → crosswalk → Explorer)

Full narrative: [DUKESBANK-DEMO.md — E2E quick path](../migration-hub/docs/DUKESBANK-DEMO.md#e2e-quick-path).

### One-shot script (Windows)

Requires Docker, `db-metadata` on PATH, Duke's Bank at `../../dukesbank`:

```powershell
cd demo-dukesbank
.\scripts\run-e2e.ps1
# MySQL already up:
.\scripts\run-e2e.ps1 -SkipDocker
```

Produces `java-ast-ssot/metadata/dukesbank-linked.db` (32 links, 0 errors — last verified 2026-06-27).

### JPA re-export + parity (ADR-004 Step 4d / ADR-007 v0.4 multi-entity)

Applies CMP→JPA recipes to **AccountBean**, **CustomerBean**, and **TxBean**, re-exports with JPA profile, and runs per-entity parity matrices:

```powershell
cd demo-dukesbank
.\scripts\run-e2e-jpa-parity.ps1
# MySQL already up:
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
| `parity-verify/metadata/dukesbank-parity-account.json` (+ `.html`) | AccountBean matrix |
| `parity-verify/metadata/dukesbank-parity-customer.json` (+ `.html`) | CustomerBean matrix |
| `parity-verify/metadata/dukesbank-parity-txbean.json` (+ `.html`) | TxBean matrix |

Apply recipe to a single file (Docker):

```bash
cd rewrite-recipes
docker run --rm -v "$PWD:/app" -v "/path/to/bank:/work" -w /app \
  maven:3.9-eclipse-temurin-17 bash -lc \
  'mvn -B -q compile dependency:build-classpath -Dmdep.outputFile=target/cp.txt -Dmdep.includeScope=compile && \
   java -cp target/classes:$(cat target/cp.txt) com.anchor.migration.rewrite.cli.ApplyRecipeMain \
   CmpScalarEntityToJpa /work/src/com/sun/ebank/ejb/tx/TxBean.java TxBean'
```

Supported recipes: `CmpScalarEntityToJpa`, `CmpManyToManyToJpa`, `CmpForeignKeyToJpa`. Optional third argument sets `targetClassName` for `CmpScalarEntityToJpa`.

### Anchor Explorer

```powershell
cd ..\anchor-explorer
npm install
npm run dev
```

Open http://127.0.0.1:5173/ → **Choose File** → `java-ast-ssot\metadata\dukesbank-linked.db`

Expected: crosswalk graph, link table, **Links: 32**, **Issues: 0**.

---

## Manual steps (all platforms)

### End-to-end crosswalk (Docker MySQL + Docker Maven)

MySQL runs in Docker (above). Build and run `java-ast-ssot` with Docker Maven if local JDK/Maven are not installed:

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

**Last verified (2026-06-27):** 4 CMP entities → **32** canonical links (`stack_bridge`, `type_maps_to_table`, `field_maps_to_column`), **0** crosswalk errors, Explorer loads linked DB.

Windows: use `C:/github/anchor-migration/...` mount paths; or `.\scripts\run-e2e.ps1`. Delete stale `metadata/dukesbank-code.db` if export fails with missing `profiles` column (pre-1.0 SQLite).

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
