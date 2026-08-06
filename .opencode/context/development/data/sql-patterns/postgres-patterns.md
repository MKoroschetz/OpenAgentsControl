---
id: postgres-patterns
name: PostgreSQL Patterns
description: "Remote PostgreSQL access, monitoring, and index optimization patterns with the workbench"
category: development
type: pattern
version: 1.0.0
---

<!-- Context: development/data | Priority: high | Version: 1.0 | Updated: 2026-08-06 -->

# PostgreSQL Patterns

**Purpose**: Safe remote access, slow-query monitoring, and index improvement workflow for the app's PostgreSQL database
**Scope**: Connection setup, read-only reporting access, pg_stat_statements monitoring, schema analysis, index tuning
**Last Updated**: 2026-08-06

---

## Remote Connection

- Access via **pgAdmin + psql** from a workstation.
- **Direct connection on port 5432** is available via:
  - **OpenVPN** → production server
  - **Local private network** `192.168.100.x/24`
- Server config: `listen_addresses = '*'` in postgresql.conf, plus a
  `pg_hba.conf` entry scoped to your network
  (`host all <user> 192.168.100.0/24 scram-sha-256`).
- **Fallback option** if direct access is unavailable: SSH tunnel
  ```bash
  ssh -L 5432:localhost:5432 user@server -N &
  ```

## Read-Only Reporting Role

- Data mining runs as a dedicated `reporter` role, **not** the app superuser.
- **App data lives in the `aspa` schema (85 tables)** — NOT `public`. The
  setup grants USAGE + SELECT on `aspa` (and `public`), plus default
  privileges for future tables/sequences in both.
- **Setup script**: `workbench/setup-roles.sql` (run as superuser):
  ```bash
  export PGPASSWORD='superuser-password'   # auth
  psql -v dbname=aspadb -f setup-roles.sql
  ```
  Remote variant reads the reporter password from `REPORTER_PW` so
  `PGPASSWORD` can hold the superuser password (see README).
  Idempotent; never hardcodes passwords.
- Equivalent manual SQL:
  ```sql
  CREATE ROLE reporter LOGIN PASSWORD '...';
  GRANT CONNECT ON DATABASE aspadb TO reporter;
  GRANT USAGE ON SCHEMA aspa, public TO reporter;
  GRANT SELECT ON ALL TABLES IN SCHEMA aspa TO reporter;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporter;
  ALTER DEFAULT PRIVILEGES IN SCHEMA aspa GRANT SELECT ON TABLES TO reporter;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO reporter;
  -- harden: PG grants CREATE on public to PUBLIC by default
  REVOKE CREATE ON SCHEMA public FROM reporter;
  ```
- Credentials live in `workbench/.env` (gitignored); template in `env.example`.
  Note: `.env` is protected from automated edits — switch users manually
  (`PGUSER=reporter` for data mining, `mkoroschetz`/superuser for setup).
- **Multiple environments**: scripts take `-e <profile>` (or `WORKBENCH_PROFILE`)
  to load `.env.prod` / `.env.dev` — see `workbench/README.md`.
- Schemas: `aspa` (85 tables, app data), `public` (11 scratch tables),
  `tax_reports` (7), `winery` (10). Reporter is scoped to `aspa` + `public`.

## Monitoring

- `pg_stat_statements` must be enabled (needs restart):
  `shared_preload_libraries = 'pg_stat_statements'` + `CREATE EXTENSION`.
- Slow-query analysis: `workbench/slow-queries/top-slow.sql`.
- Live queries: `workbench/slow-queries/active-queries.sql`.
- Performance snapshots: `workbench/scripts/snapshot.sh` (txt + CSV for diffing).

## Index Workflow

1. Find slow queries (pg_stat_statements).
2. `EXPLAIN (ANALYZE, BUFFERS)` the failing query; save before-output.
3. Look for Seq Scan on big tables, low-selectivity Bitmap scans, Sort nodes.
4. Add one index at a time with `CREATE INDEX CONCURRENTLY`.
5. Re-explain, then compare snapshots after production traffic.
6. Log changes in `workbench/index-work/findings.md`.

## Schema Analysis

- Table sizes/rows/index counts: `workbench/schema-analysis/tables-overview.sql`.
- All index definitions: `workbench/schema-analysis/indexes.sql`.
- Unused index candidates (`idx_scan = 0`): `workbench/schema-analysis/unused-indexes.sql`.

---

## Related Context

- **Data Navigation** → `../navigation.md`
- **Code Standards** → `../../core/standards/code-quality.md`
- **Security Patterns** → `../../core/standards/security-patterns.md`
