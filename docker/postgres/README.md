# postgres+pgagent Container (combined image, architecture C)

**Project**: aspaDB-workbench | **Path**: docker/postgres/README.md
**Version**: v2.0.0 | **Last Updated**: 2026-08-15 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v2.0.0 (2026-08-15): Adopted architecture C — combined postgres+pgagent image (Debian 13 + PG 17 + pgagent daemon). Replaces the pg-agent-only sidecar experiment.
- v1.1.0 (2026-08-15): Measure drift of the pg-agent sidecar build (367 MB → 121 MB lesson).
- v1.0.0 (2026-08-15): Canonical pg-agent Dockerfile + drift validation.

This directory holds the canonical **postgres+pgagent combined image** used by
the aspaDB container on the Docker hosts (IOTstack, `services/postgres/`).
It is the Layer-2 "PostgreSQL 17" container from
[`docs/CORE-PLATFORM-UPGRADE.md`](../../docs/CORE-PLATFORM-UPGRADE.md) (§3.1),
running **both** the PostgreSQL 17 server and the pgagent scheduling daemon in
one container.

## Contents

| File | Purpose |
|------|---------|
| `Dockerfile` | Combined image: Debian 13 + `postgresql-17` + `postgresql-17-pgagent` + contrib |
| `entrypoint.sh` | Starts the PG 17 cluster, ensures pgagent schema, runs pgagent in foreground |
| `init-pgagent.sh` | Idempotent `CREATE EXTENSION pgagent` |
| `validate-drift.sh` | Drift validation: image inventory + running-container diff |
| `reports/` | Generated validation reports + package baseline (gitignored) |

## Image layout

```
FROM debian:13-slim            (Debian 13 = target OS, see runbook §4.1)
  + postgresql-17              (Debian 13 native; EOL 2029-11-08)
  + postgresql-17-pgagent      (PGDG trixie-pgdg: extension + daemon binary)
  + postgresql-contrib
  + helpers: curl nano cron openssh-client ca-certificates gnupg
CMD entrypoint.sh  ->  pg_ctlcluster 17 main start; init-pgagent; exec pgagent -f
```

PGDATA is the Debian cluster path `/var/lib/postgresql/17/main`. The entrypoint
`chown`s a bind-mounted data dir to the `postgres` OS user automatically, and
`initdb`s an empty dir (fresh deploy / restore target). Config edits applied
per boot: `listen_addresses='*'`, `shared_preload_libraries='pg_stat_statements'`,
and a `host all all 0.0.0.0/0 scram-sha-256` pg_hba rule for TCP clients
(pgadmin + app clients); unix-socket connections stay peer-auth.

## Build & validate (dev)

```bash
docker build -t aspadb-postgres:17 .
./validate-drift.sh image       # expects PG 17 + pgagent + helpers, no stray/EOL majors
./validate-drift.sh baseline    # pin this package set as the baseline
```

Verified build (2026-08-15): `aspadb-postgres:17` = **446 MB, 160 packages**,
PostgreSQL **17.11** (Debian 13, PGDG), pgagent **4.2.3**, `pg_stat_statements`
preloaded, `listen_addresses='*'` + SCRAM for TCP clients, peer auth on the
unix socket. Runtime smoke test: empty data dir auto-inits, server + pgagent
daemon both come up, TCP password auth roundtrips.

## Deployment (IOTstack conventions — dev + prod)

- Dockerfile lives in `services/postgres/Dockerfile` on the host (sync from here).
- Compose service is a **single** `postgres` service (`container_name: aspaDB`,
  port 5432) — the old separate `pgagent` service is obsolete.
- Data dir (host-persisted): `./volumes/postgres17/data` mounted at
  `/var/lib/postgresql/17/main` — a **fresh** dir filled by logical dump/restore.
  Do NOT reuse `volumes/postgres/data` (stale PG-12 dir) and do NOT rely on the
  old anonymous docker volume that currently holds the live data.
- Target compose section for review: `docker/iotstack/docker-compose.target-postgres.yml`.
- Migration procedure: see `docker/iotstack/README.md` + runbook Part A
  (fresh backup → side container on 5433 → restore → verify → cutover).

## Migration of the existing DB (summary)

PG 12 → 17 is a major-version jump; the two clusters cannot share a data
directory. Always **logical dump/restore**:

```bash
./workbench/scripts/pg_backup.sh -m pre-upgrade-dev --verify   # live cluster
# run aspadb-postgres:17 as pg17 on :5433 with a FRESH data dir
#   volumes/postgres17/data:/var/lib/postgresql/17/main
# restore order: globals.sql.gz -> postgres -> aspadb (restore-cluster.sh)
# verify (row counts, roles, pg_stat_statements + pgagent), then flip aspaDB to :5432
```

## Security notes

- Postgres superuser password comes from the IOTstack `postgres.env` env_file
  (kept on the host, mode 600; redacted in this repo).
- The pgagent daemon connects over the local unix socket as OS user `postgres`
  (peer auth) — no password in the image. For least-privilege job scheduling,
  follow `services/postgres/pgagent.sql` (dedicated `pgagent` role) instead.