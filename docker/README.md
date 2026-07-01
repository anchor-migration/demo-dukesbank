# Docker toolchain

Reproducible Duke's Bank E2E without host JDK, Maven, or `pip install db-metadata`.

## Image: `anchor-demo-dukesbank-runner`

| Tool | Source |
|------|--------|
| JDK 17 + Maven | `maven:3.9-eclipse-temurin-17` base |
| Python 3 + pip | Debian packages in `Dockerfile.runner` |
| `db-metadata` | `pip install -e /workspace/db-metadata[mysql]` at E2E runtime |

Build:

```bash
docker compose build runner
```

## Compose services

| Service | Role |
|---------|------|
| `mysql` | Duke's Bank schema (port 3306) |
| `runner` | Interactive shell with full toolchain |
| `e2e` | `scripts/lib/e2e-core.sh` |
| `e2e-jpa-parity` | `scripts/lib/e2e-jpa-parity-core.sh` |

Volumes mount `../` (anchor-migration workspace) and `../../dukesbank` (legacy sample).

Inside the runner, tools connect to MySQL at hostname `mysql` on the compose network — not `localhost`.
