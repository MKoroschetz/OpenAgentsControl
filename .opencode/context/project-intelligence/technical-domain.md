<!-- Context: project-intelligence/technical | Priority: high | Version: 1.3 | Updated: 2026-08-15 -->

# Technical Domain

> The technical foundation of the aspaDB workbench: a PostgreSQL-backed produce/fruit business (South Tyrol, Italy) with inventory, sorting, delivery, sales, and CRM domains.

## Quick Reference

- **Purpose**: Understand how the project works technically
- **Update When**: New features, refactoring, tech stack changes
- **Audience**: Developers, DevOps, technical stakeholders

## Primary Stack

| Layer | Technology | Version | Rationale |
|-------|-----------|---------|-----------|
| Database | PostgreSQL | 12.13 | Core data store; `aspa` schema (85 tables) is the app schema |
| DB Hosts | Prod `172.20.61.220` / Dev `192.168.100.32` | N/A | Prod is the authoritative source; dev is a Docker container (Debian 11) |
| Access | `reporter` role (read-only) | N/A | Scoped to `aspa` + `public` schemas; superuser `mkoroschetz` for admin |
| Tooling | SQL workbench scripts | N/A | `workbench/scripts/run.sh` / `snapshot.sh` with `-e prod\|dev` profiles |
| Backup | pg_dumpall-style full cluster | N/A | `globals.sql.gz` + per-DB dumps; crontab Feb + June; scripts in `workbench/scripts/` |

## Architecture Pattern

```
Type: Monolith (database-centric)
Pattern: Single PostgreSQL instance hosting multiple schemas:
        aspa (app), public (scratch), tax_reports (tax compliance), winery (secondary business)
Diagram: See .opencode/context/development/data/aspa/aspa-schema.md
```

### Why This Architecture?

The business runs on a single PostgreSQL database with schema-level separation. The `aspa` schema holds the core produce business (inventory, sorting, delivery, sales, CRM); `tax_reports` handles Italian tax compliance (corrispettivi, IVA); `winery` is a secondary business line. A read-only `reporter` role enables safe analytics without write access.

## Project Structure

```
[Project Root]
├── workbench/                # SQL workbench
│   ├── scripts/              # run.sh, snapshot.sh, lib.sh (env profiles)
│   ├── schema-analysis/      # tables-overview.sql, indexes.sql, unused-indexes.sql
│   ├── setup-roles.sql       # reporter role + grants + hardening
│   └── reports/              # Query output (gitignored)
├── .opencode/context/        # Project context (data layer, standards)
└── workbench/scripts/        # Backup/restore tooling (pg_backup.sh, pg_restore.sh)
```

**Key Directories**:
- `workbench/` - SQL workbench with profile-based env selection (`-e prod|dev`)
- `.opencode/context/` - Project knowledge: data layer, standards, project intelligence
- `workbench/scripts/` - Backup/restore tooling for the full cluster (pg_backup.sh, pg_backup_rotated.sh, pg_restore.sh, pg_backup.config)

## Key Technical Decisions

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Profile-based env (`-e prod\|dev`) | Separate `.env.prod`/`.env.dev` files over manual edits | Safe switching between hosts |
| Read-only `reporter` role | Analytics without write risk; `REVOKE CREATE ON public` hardening | Least-privilege access |
| Full-cluster backup (pg_dumpall) | `globals.sql.gz` (roles) + per-DB dumps | Restore order: globals → postgres → aspadb |
| Soft-delete convention | `deleted` boolean on most tables | Queries must filter `deleted = false` |

See `decisions-log.md` for full decision history with alternatives.

## Integration Points

| System | Purpose | Protocol | Direction |
|--------|---------|----------|-----------|
| Production DB | Authoritative data | PostgreSQL 5432 | Internal |
| Dev DB (Docker) | Restored clone for testing | PostgreSQL 5432 | Internal |
| Backup scripts | Full cluster backup | pg_dump/pg_restore | Outbound |
| Reporter role | Analytics/read access | SQL | Inbound |

## Technical Constraints

| Constraint | Origin | Impact |
|------------|--------|--------|
| Soft-delete convention | App design | Must filter `deleted = false` |
| `en_US.utf8` locale | Prod cluster | Dev container must use `C.UTF-8` |
| `pg_restore.sh` restored | 2026-08-11 | Full-cluster restore via `pg_restore.sh` (globals → postgres → per-DB) |
| Backup cadence | Crontab (Feb + June) | Freshest full backup 2026-08-11 (in-repo tooling, `workbench/scripts/`) |

## Development Environment

```
Setup: workbench/scripts/run.sh -e prod|dev <query.sql>
Requirements: psql client, credentials in ~/.bashrc or .env.<profile>
Local Dev: Dev host 192.168.100.32 (Docker, postgres 12)
Testing: Run queries against dev profile first
```

## Deployment

```
Environment: Production (172.20.61.220) / Development (192.168.100.32)
Platform: PostgreSQL 12.13 on Linux (prod); Docker container (dev)
Backup: crontab 6 4 * 2,6 * via workbench/scripts/pg_backup.sh (freshest full backup 2026-08-11)
Monitoring: pgagent, grafana_user role present
```

## Onboarding Checklist

- [x] Know the primary tech stack (PostgreSQL 12.13, aspa schema)
- [x] Understand the architecture pattern (single DB, schema separation)
- [x] Know the key project directories and their purpose
- [x] Understand major technical decisions and rationale
- [x] Know integration points and dependencies
- [x] Be able to set up local development environment
- [x] Know how to run tests and deploy
- [x] Know which agents handle which workflows (see `navigation.md` → "Tooling / Agents at a Glance")

## Related Files

- `business-domain.md` - Why this technical foundation exists
- `business-tech-bridge.md` - How business needs map to technical solutions
- `decisions-log.md` - Full decision history with context
- `../development/data/aspa/aspa-schema.md` - Full schema reference
