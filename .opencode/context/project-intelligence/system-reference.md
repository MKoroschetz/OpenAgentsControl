<!-- Context: project-intelligence/system-reference | Priority: high | Version: 1.1 | Updated: 2026-08-15 -->

# System Reference — aspaDB Infrastructure

> The **living, always-current** reference for the aspaDB infrastructure: what versions run where, when things expire, when maintenance is allowed, and the rules that keep dev and prod in sync. Consult this file before any infra/maintenance work. Detailed procedures live in the **runbook** (`docs/CORE-PLATFORM-UPGRADE.md`).

**Project**: aspaDB-workbench | **Path**: .opencode/context/project-intelligence/system-reference.md
**Version**: v1.1.0 | **Last Updated**: 2026-08-15
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.3.0 (2026-08-15): Added §11 IOTstack layout & deployment conventions (dev + prod); verified dev layout on host (`/mnt/db/IOTstack`).
- v1.2.0 (2026-08-15): Recorded dev Docker baseline — Engine 29.3.0 (5927d80), Compose v5.1.0, driver overlay2, root `/mnt/docker-data` (§1 + §6).
- v1.1.0 (2026-08-15): Backup §5 — pointed to in-repo tooling (`workbench/scripts/pg_backup.sh` + `restore-cluster.sh`), recorded freshest full backup 2026-08-11.
- v1.0.0 (2026-08-15): Initial living reference — version matrix, EOL calendar, seasonal windows, Docker sync policy, backup cadence, monitoring endpoints, upgrade history.

---

## 1. Environment Topology

| Env | Docker host (IP) | Host OS | PG container OS | PostgreSQL | Docker Engine | Status |
|-----|------------------|---------|-----------------|-----------|---------------|--------|
| Dev | 192.168.100.32 | Debian 13.3 | Debian 11.6 (Bullseye) | 12.13 | **29.3.0** / Compose v5.1.0 / overlay2 | ❌ PG + container EOL |
| Prod | 172.20.61.220 | Debian 10.13 (Buster) | Debian 11.6 (Bullseye) | 12.13 | *record §6* | ❌ Host + PG + container EOL |

**Target state (post-upgrade):**
| Env | Docker host OS | PG container OS | PostgreSQL |
|-----|----------------|-----------------|------------|
| Dev | Debian 13.3 (unchanged) | Debian 13 | 17.11 |
| Prod | Debian 13 (new host) | Debian 13 | 17.11 |

## 2. EOL Calendar (check quarterly + before any maintenance)

| Component | EOL / LTS end | Status (2026-08-15) | Action |
|-----------|---------------|---------------------|--------|
| Debian 10 (Buster) — prod host | 2024-06-30 | ❌ EOL (paid ELTS only) | Replace host in Part B |
| Debian 11 (Bullseye) — both containers | **2026-08-31** | ⚠️ ~2 weeks left | Rebuild containers on Debian 13 |
| PostgreSQL 12 | 2024-11-21 | ❌ EOL | Upgrade to 17.11 |
| PostgreSQL 16 | 2028-11-09 | ✅ supported | Fallback target only |
| **PostgreSQL 17** | **2029-11-08** | ✅ supported | **Chosen target** |
| PostgreSQL 18 | 2030-11-14 | ✅ supported | Too new for reliability-first |
| Debian 13 (Trixie) — target | 2028 + LTS to 2030-06 | ✅ current stable | Adopted |
| Debian 12 (Bookworm) | LTS to 2028-06 | ✅ oldstable | Not adopted |

## 3. Seasonal Operating Model (HARD CONSTRAINT)

- **Active season:** Feb–Jun each year — prod carries live business load.
- **Off-season:** Jul–Jan — prod is idle; **downtime cost ≈ 0**.
- **No production maintenance in Feb–Jun.** Period.
- **Planned upgrade window:** Part A (dev) Aug–Sep 2026, Part B (prod) Sep–Oct 2026.
- **Hard deadline:** full prod upgrade + soak complete **before Feb 2027**. If missed, defer to next off-season (Jul 2027) — never migrate mid-season.

## 4. Docker Version Sync Policy (MANDATORY)

- Both Docker hosts must run the **same Docker Engine + Compose version** and **storage driver**.
- Dev is the pace-setter; prod follows. Never let prod exceed dev.
- Any Docker bump: upgrade dev first → validate → then prod. Both together.
- Pin with `apt-mark hold` after install (§8 runbook B.2).

## 5. Backup & Restore Cadence

| Item | Detail |
|------|--------|
| Schedule | crontab `6 4 * 2,6 *` (Feb + Jun — brackets the season) |
| Tooling | **in-repo**: `workbench/scripts/pg_backup.sh` (+ `pg_backup_rotated.sh`), `pg_restore.sh` (single restore tool), config `pg_backup.config` |
| Scope | `pg_dumpall --globals-only` + per-DB `.custom`/`.sql.gz` dumps |
| Restore order | **globals → postgres → aspadb** (via `pg_restore.sh`) |
| Mandatory pre-upgrade | fresh `pg_backup.sh -m pre-upgrade-<env> --verify` + dual-copy (host + external) before any migration |
| Freshest full backup | **2026-08-11** (refined scripts, logged in `workbench/scripts/log/pg_backup.log`) |
| Best data marker | June end-of-season backup (most recent pre-off-season state) |

## 6. Version Baseline (RECORD AFTER INVENTORY §4)

> Fill from runbook §4 inventory — do this before any maintenance.

| Check | Dev value | Prod value |
|-------|-----------|------------|
| `SELECT version();` | | |
| `SHOW lc_collate;` | C.UTF-8 | en_US.utf8 |
| `SHOW server_encoding;` | UTF8 | UTF8 |
| `SHOW shared_preload_libraries;` | pg_stat_statements | pg_stat_statements |
| `docker --version` | **29.3.0** (build 5927d80) | |
| `docker compose version` | **v5.1.0** | |
| `docker info --format '{{.ServerVersion}} \| {{.Driver}}'` | **29.3.0 \| overlay2** (root `/mnt/docker-data`) | |
| DB size (aspadb) | | |

## 7. Monitoring & Observability

| System | Purpose | Location |
|--------|---------|----------|
| pgagent | Job scheduling | in PG container |
| pg_stat_statements | Query performance | in PG container |
| Grafana | Dashboards | *endpoint TBD* |
| `reporter` role | Read-only analytics | scoped to aspa + public |
| `grafana_user` | Monitoring queries | monitoring role |

## 8. Upgrade History

| Date | Env | From | To | Runbook ref | Status |
|------|-----|------|----|-------------|--------|
| — | Dev | PG 12.13 / Bullseye | PG 17.11 / Debian 13 | Part A (§7) | Pending |
| — | Prod | PG 12.13 / Debian 10 host | PG 17.11 / Debian 13 | Part B (§8) | Pending |
| — | future PG major (18/19) | 17.11 | next | reuse runbook | Deferred (≥ mid-2027) |

## 9. Key Decisions (cross-reference)

| Decision | Where recorded |
|----------|----------------|
| PG 17 over 16/18 | runbook §3.2 + decisions-log |
| Debian 13 target OS | runbook §3.1 + decisions-log |
| dump/restore over pg_upgrade | runbook §3.3 + decisions-log |
| Docker version sync | runbook §6 sync policy |
| Off-season scheduling | runbook §1 operational calendar |

## 10. Maintenance Checklist (quarterly, off-season preferred)

- [ ] Re-check EOL calendar (§2) — any component nearing EOL?
- [ ] Verify dev/prod Docker versions still identical (§4)
- [ ] Confirm versions in §6 match production reality (drift check)
- [ ] Test a restore from the last backup (Feb/Jun cadence)
- [ ] Confirm backup scripts still run on schedule (§5)
- [ ] Update this file + runbook changelog with any infra change
- [ ] Review decisions-log for pending infra decisions

## Related Files

- `technical-domain.md` — stack, architecture, integration points
- `decisions-log.md` — rationale for key infra decisions
- `living-notes.md` — active issues and open questions
- `docs/CORE-PLATFORM-UPGRADE.md` — the execution runbook (plumbing upgrade)

## 11. IOTstack Layout & Deployment Conventions (dev + prod)

> The container stack on both Docker hosts follows **IOTstack** conventions. Verified on dev: root is `/mnt/db/IOTstack` (space-restricted move from `/root/IOTstack`; `/root/IOTstack` also exists). Applies to prod the same way.

| # | Convention | Detail |
|---|-----------|--------|
| 1 | Project root | `IOTstack/` — typically `~/root/IOTstack`, or `/mnt/<fs>/IOTstack` when space is restricted |
| 2 | Two sibling folders | `IOTstack/volumes` = **data structures**; `IOTstack/services` = **config / security / management** |
| 3 | One folder per container | Each container gets its own folder in **both** `volumes/` and `services/` (e.g. `services/postgres/`, `volumes/postgres/`) |
| 4 | Compose paths | All refs in `docker-compose.yml` are relative to `./volumes`, `./services` (or absolute if needed) |
| 5 | Host persistence | Modern docker volumes are **skipped** in favor of host-mounted persistence (notable exception: `prkt-db_pgdata`) |
| 6 | Dockerfiles | Live in `./services/<container name>/` (e.g. `services/postgres/Dockerfile` builds the pgagent image) |
| 7 | Container interface | `docker compose up -d` (or `docker-compose up -d`) from the IOTstack root; compose project name `iotstack` |
| 8 | UI management | Portainer CE on host port **9000** (agent port 9001) — management + log tracking |

**Current pg-container setup on dev (verified 2026-08-15):**
- `services/postgres/` holds the DB + pgagent config: `Dockerfile`, `pgagent.env`, `pgagent.pgpass`, `pgagent.override`, `pgagent.sh`, `pgagent.sql`, `postgres.env`, `service.yml`.
- Active compose (`docker-compose.yml`): `postgres:` service → image `postgres:12.13`, container **`aspaDB`**, port 5432, data at `./volumes/postgres/data:/var/lib/postgresql/16/data`, socket at `/var/run/postgresql`. The `pgagent:` service (container **`aspaDB_AGENT`**, build `./services/postgres/.`, entrypoint runs pgagent → `host=postgres`) is currently **commented out** → not running.
- Canonical Dockerfile for the pgagent image: `docker/pg-agent/Dockerfile` in this repo (mirrored to `/opt/aspaDB-workbench/docker/pg-agent/`; deploy by syncing into `IOTstack/services/postgres/Dockerfile`).
