# Duke's Bank — MySQL demo (bridge)

**This folder is not the Duke's Bank application.** It is the **database bridge** for [Anchor Migration](https://github.com/anchor-migration/migration-hub): a small Docker Compose setup that runs a MySQL instance seeded from the legacy sample, so tools like [db-metadata](../db-metadata) can export and verify schema SSOT.

The **Java EE sample itself** lives in a separate repository that you must download and place on disk yourself.

---

## About Duke's Bank (external legacy sample)

[Duke's Bank](https://github.com/jiananwang/dukesbank) is a classic **J2EE 1.4 / Java EE** tutorial application (EJB 2.x CMP, servlets/JSP, Ant build). It originated from Sun's J2EE tutorial; this fork adds **MySQL** seed data and deployment descriptors suitable for migration demos.

| What | Where |
|------|--------|
| Java sources, EJB XML, web tier | **Not in this repo** — in your local `dukesbank` clone |
| MySQL DDL + seed data | `dukesbank/data/mysql/dukesbank.sql` |
| Bank module root (for `java-ast-ssot`) | `dukesbank/src/j2eetutorial14/examples/bank/` |

Anchor Migration does **not** vendor Duke's Bank inside the org. We only document how to wire it up.

---

## What is in *this* folder

| File | Purpose |
|------|---------|
| `docker-compose.yml` | MySQL 5.7 container, port 3306, health check |
| `README.md` | Setup and runbook (this file) |

There is no application code, no SQL file, and no exported SQLite here. Those come from your `dukesbank` clone and from `../db-metadata/metadata/` after export.

---

## Required layout (you provide `dukesbank`)

`docker-compose.yml` mounts the seed script from a **sibling** directory:

```yaml
../../dukesbank/data/mysql/dukesbank.sql → container init script
```

Default layout (recommended):

```
github/                          # or any parent you prefer
├── anchor-migration/
│   ├── demo-dukesbank/          ← this folder
│   ├── db-metadata/
│   └── java-ast-ssot/
└── dukesbank/                   ← you clone this yourself
    └── data/mysql/dukesbank.sql
```

### 1. Clone Duke's Bank

```bash
cd /path/to/github
git clone https://github.com/jiananwang/dukesbank.git
```

Use another fork if you prefer, as long as `data/mysql/dukesbank.sql` exists.

### 2. Adjust paths if your layout differs

If `dukesbank` is **not** at `../../dukesbank` relative to this folder, edit the `volumes` entry in `docker-compose.yml`:

```yaml
volumes:
  - /absolute/or/relative/path/to/dukesbank/data/mysql/dukesbank.sql:/docker-entrypoint-initdb.d/01-dukesbank.sql:ro
```

Then use the same JDBC URL in export commands (`localhost:3306/dukesbank` unless you changed the port).

---

## Prerequisites

- Docker Desktop
- Duke's Bank cloned so `dukesbank.sql` is reachable from the compose volume (see above)
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
