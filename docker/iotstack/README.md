# IOTstack Snapshot (dev, 2026-08-15)

**Project**: aspaDB-workbench | **Path**: docker/iotstack/README.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-15 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.0.0 (2026-08-15): Captured current IOTstack postgres/pgagent/pgadmin setup from dev for compose review + migration planning

## Purpose

This folder is a **read-only reference snapshot** of the current container
setup on the dev host, captured so the updated `docker-compose.yml` section can
be reviewed carefully before activating the revised containers. It is NOT the
source of truth — the live files are on the Docker hosts.

- **Source host:** dev `192.168.100.32` (`aspaDB-dev`), IOTstack root `/mnt/db/IOTstack`
- **Captured:** 2026-08-15, compose file `docker-compose.yml` (28.5 KB) + `services/postgres/*` + `services/pgadmin/*`
- **Project name:** `iotstack` · interface `docker compose up -d` · UI: Portainer CE :9000

## Files

| Path | Notes |
|------|-------|
| `docker-compose.yml` | Verbatim capture of the ACTIVE compose (drives `aspaDB`) |
| `docker-compose.target-postgres.yml` | **DRAFT** revised postgres+pgadmin sections for review (NOT active) |
| `services/postgres/service.yml` | postgres+pgagent combined section (target backup) |
| `services/postgres/Dockerfile` | Existing pgagent image build (`FROM postgres:17` + pgagent) |
| `services/postgres/pgagent.env` | PGHOST/PGPORT/PGUSER/PGPASSFILE (no secret) |
| `services/postgres/pgagent.sql` | Extension + role setup SQL template |
| `services/postgres/postgres.env` | **REDACTED** (password on host, mode 600) |
| `services/postgres/pgagent.pgpass` | **REDACTED** (password on host, mode 600) |
| `services/pgadmin/service.yml` | pgadmin template (`dpage/pgadmin4:6.3`) — not deployed |
| `services/pgadmin/pgadmin.env` | **REDACTED** (password on host, mode 600) |

## Key findings (verified on dev, 2026-08-15)

1. **The live DB data is NOT in `volumes/postgres/data`.**
   - `aspaDB` runs `postgres:12.13` with `PGDATA=/var/lib/postgresql/data`,
     which is an **anonymous docker volume** (`f8e585da…`, host
     `/mnt/docker-data/volumes/f8e585…/_data`).
   - The compose mapping `./volumes/postgres/data:/var/lib/postgresql/16/data`
     points at a **stale PG-12 data dir** (last modified 2025-08-30). The
     bind mount is a leftover and is NOT the active cluster.
   - Implication: IOTstack's "host persistence, no docker volumes" convention
     is **violated for aspaDB**. Any `docker compose down -v` or `docker rm -v`
     would destroy the live database. Fix during migration (see below).
2. **pgagent service is commented out** in the active compose → container
   `aspaDB_AGENT` is not running.
3. **pgadmin is a template only** — `dpage/pgadmin4:6.3` (2022), not in the
   active compose, not running. Data dir in template points at `/mnt/data/pgadmin`,
   while `volumes/pgadmin/` holds an older `pgadmin4.db`.
4. **Existing `services/postgres/Dockerfile` is a *combined* postgres+pgagent**
   image (`FROM postgres:17`, installs pgagent). **Decision: adopt architecture C**
   — `docker/iotstack/services/postgres17/Dockerfile` (official `postgres:17.11`
   base + pgagent, with entrypoint running server + daemon) supersedes both the
   old combined file and the earlier minimal sidecar experiment.

## Migration question — how to move the existing DB

The data cannot be moved by simply changing the compose `image:` — PG 12 and
PG 17 clusters cannot read each other's data directories, and the live PGDATA
is an anonymous volume anyway. Use **logical dump/restore** (the in-repo
tooling, per `docs/CORE-PLATFORM-UPGRADE.md` Part A):

```bash
# 1. fresh backup from the LIVE cluster (over the socket/TCP, not the stale bind mount)
./workbench/scripts/pg_backup.sh -m pre-upgrade-dev --verify

# 2. run the new postgres:17 container on a side port (5434) with a NEW data dir
#    backup dir stays on the host and is MOUNTED in (no docker cp needed)
docker run -d --name pg17 -e POSTGRES_PASSWORD=*** -p 5434:5432 \
  -v /mnt/db/IOTstack/volumes/postgres17/data:/var/lib/postgresql/17/data \
  -v /mnt/db/IOTstack/DB_Backup:/mnt/DB-Backup \
  aspadb-postgres:17

# 3. restore globals → postgres → aspadb into pg17 (pg_restore.sh, from the
#    container shell — tooling + .pgpass already in <backup>/utilities/)
docker exec -it -u postgres pg17 bash
cd /mnt/DB-Backup/<date>-pre-upgrade-dev/utilities/
./pg_restore.sh .. --no-owner --no-privileges

# 4. verify (row counts, roles, pg_stat_statements + pgagent extension), then cut over
#    in docker-compose.yml: image postgres:17.11, volume volumes/postgres17/data,
#    port 5432; docker compose up -d
```

Key compose changes to review in the updated section:
- `image: postgres:12.13` → `postgres:17.11` (Debian 13 base per runbook)
- volume `volumes/postgres/data:/var/lib/postgresql/16/data` →
  `volumes/postgres17/data:/var/lib/postgresql/17/data` (fresh dir for the dump/restore;
  **stop trusting the old bind mount**, it is stale)
- add `pg_stat_statements` shared_preload + `pgagent` extension reconciliation (§A.7)
- re-check the anonymous-volume trap: prefer a **named/bind** host path for PGDATA
  so `docker compose down -v` can never wipe the DB

## Update plan (3 containers → 2)

Decision (2026-08-15): **architecture C** — postgres + pgagent run in ONE
combined container, built from `docker/iotstack/services/postgres17/Dockerfile`.

| # | Container | Current | Target | Activate |
|---|-----------|---------|--------|----------|
| 1 | postgres + pgagent (aspaDB) | `postgres:12.13`; live data in anonymous volume; pgagent sidecar commented out | combined `aspadb-postgres:17` (PG 17 + pgagent daemon), fresh `volumes/postgres17/data` via dump/restore | after restore verified |
| 2 | pgadmin (pgAdmin4) | template only; `dpage/pgadmin4:6.3` | `dpage/pgadmin4:9.8`, port 9081, `volumes/pgadmin` | after DB migration |

Activation order: **postgres(+pgagent) → pgadmin**, each with its own checkpoint
(runbook §8 / §10 validation matrix).

## Versioning & per-container backup (convention, adopted 2026-08-15)

- The IOTstack `docker-compose.yml` is kept **properly versioned**: the live
  host keeps dated/versioned copies (`docker-compose.yml.03232026`,
  `docker-compose.yml.v1.0.0`), and this repo captures a **verbatim, git-tracked
  baseline** (`docker/iotstack/docker-compose.yml`, checksum-verified, commit
  80c4f17).
- Each container's compose **service section is hosted as a backup** in the
  corresponding `./services/<container name>/` folder:
  - `services/postgres/service.yml` ← combined postgres+pgagent section (target)
  - `services/pgadmin/service.yml` ← pgadmin section (target)
  - These mirror the IOTstack convention (menu.sh composes
    `docker-compose.yml` from `services/<name>/service.yml`).
- **Proposed future compose** (NOT active): `docker/docker-compose.target-postgres.yml`
  captures the reviewed postgres+pgadmin sections for review before enabling.
- Rule: when any container section changes, update BOTH its
  `services/<name>/service.yml` and the compose, and bump the compose backup
  copy (host) + this repo capture.
