# SQL Workbench
**Project**: aspaDB-workbench | **Path**: workbench/README.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-11 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.0.0 (2026-08-11): Initial standard header

Local workspace for developing, testing, and running PostgreSQL queries
against the remote database — for data mining reports and index
performance work.

## Features

- Run any `.sql` file against the remote DB with one command
- Snapshot `pg_stat_statements` over time to track query performance
- Schema analysis queries (table sizes, indexes, unused indexes)
- Slow-query monitoring queries
- Documented index-improvement workflow with before/after tracking

## Prerequisites

- `psql` installed locally (`which psql`)
- Network access to the remote Postgres (direct or SSH tunnel)
- On the server: `pg_stat_statements` extension enabled for slow-query
  features (see Setup)

## Setup

1. Copy the environment template and fill in your connection details:
   ```bash
   cp .env.example .env
   ```

### Multiple environments (prod / dev)

The scripts support named profiles via `-e <profile>` (or the
`WORKBENCH_PROFILE` env var). Each profile is its own env file:

```bash
cp .env.example .env.prod    # production host
cp .env.example .env.dev     # dev host
```

Then select one at run time:

```bash
./scripts/run.sh -e prod schema-analysis/tables-overview.sql
./scripts/run.sh -e dev slow-queries/top-slow.sql
```

Without `-e`, scripts fall back to `.env` (backward compatible).
2. Create the read-only reporting role (run on the server as superuser):
   ```bash
   export PGPASSWORD='your-strong-password'
   psql -v dbname=yourdb -f setup-roles.sql
   ```
   The script is idempotent and reads the password from `PGPASSWORD`
   (never hardcoded). See `setup-roles.sql` for details.
3. Optional — enable `pg_stat_statements` on the server
   (needs a restart, so coordinate with your team):
   ```ini
   # postgresql.conf
   shared_preload_libraries = 'pg_stat_statements'
   pg_stat_statements.max = 10000
   pg_stat_statements.track = all
   ```
   then `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`

## Quick Start

```bash
# Run the schema overview report
./scripts/run.sh schema-analysis/tables-overview.sql

# Capture a slow-query snapshot
./scripts/snapshot.sh

# View a report
cat reports/tables-overview.txt
```

## Folder Layout

```
workbench/
├── scripts/            # run.sh (execute queries), snapshot.sh (perf snapshots)
├── schema-analysis/    # overall DB picture: sizes, indexes, unused indexes
├── slow-queries/       # monitoring: top slow + currently running queries
├── index-work/         # failing-query diagnosis + index changes (findings.md)
└── reports/            # generated output (gitignored)
```

## Usage

### Run a query file

```bash
./scripts/run.sh slow-queries/top-slow.sql
./scripts/run.sh -e prod slow-queries/top-slow.sql   # explicit prod profile
```

Output is written to `reports/<file>-<timestamp>.txt`.

### Track performance over time

```bash
./scripts/snapshot.sh before-index
./scripts/snapshot.sh -e prod after-index
diff reports/snapshots/before-index.csv reports/snapshots/after-index.csv
```

### SSH tunnel (no public 5432 exposure)

```bash
ssh -L 5432:localhost:5432 user@your-server -N &
# then set PG_USE_SSH_TUNNEL=1 in .env (connects to localhost:5432)
```

## Security

- `.env` is gitignored — never commit real credentials
- Use a read-only reporting role for data mining
- Prefer an SSH tunnel over opening 5432 to the internet
- Only use `CREATE INDEX CONCURRENTLY` on production tables
