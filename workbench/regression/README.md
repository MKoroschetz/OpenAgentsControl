# Regression Suite (A.8 / B.8)

**Project**: aspaDB-workbench | **Path**: workbench/regression/README.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-17 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## What this is

The regression suite for the PG 12 → PG 17 upgrade (A.8 on dev, B.8 on prod —
see `docs/CORE-PLATFORM-UPGRADE.md`). It validates the app's **real query
layer** against the migrated cluster. Built from **live schema introspection**
on dev PG 17.11 (2026-08-17), not from guesses.

**PASS = zero ERROR lines in the report.**

## Why not the workbench/sql/ reports

The 5 report queries in `workbench/sql/` were committed 2026-08-17 but **never
executed** against the live DB (reports/ empty, no git history of runs). A
column audit against the real schema proved 4 of 5 reference non-existent
columns:

| Query | Blocking issue |
|-------|----------------|
| `sales-by-day.sql` | `orders.deleted`, `order_details.deleted` do not exist |
| `customer-revenue.sql` | `orders.deleted`, `order_details.deleted`, `customers.deleted` do not exist |
| `delivery-performance.sql` | `delivery.customer_id`, `delivery_routes.name` do not exist (wrong join model) |
| `sort-productivity.sql` | `person.full_name` does not exist (real: first_name/middle_name/last_name) |
| `inventory-by-warehouse.sql` | ✅ compiles (only one that does) |

They are **new, unvalidated reports** — not a regression baseline. The suite
below replaces them as the baseline. (Fix-up of the reports is tracked
separately.)

## Suite contents (`regression-list.sql`)

| Tier | Checks | Diffable |
|------|--------|----------|
| 0 | Server identity, locale (`pg_database.datcollate`), DB count | version line differs dev↔prod by design |
| 1 | **11 `EAR_export_*` functions** — the app's production reporting/export layer (EAR reports, exportCSV, jasperreports) — row counts + LIMIT samples | ✅ identical = same dataset |
| 2 | **All 109 aspa views** — existence + row count | ✅ identical = same dataset |
| 3 | Structure: 85 base tables, 109 views, roles, inventory (73,798 active), extensions, core table counts | ✅ |
| 4 | Catalog: aspa index count + FK missing-index candidates | ✅ schema-derived |

EAR functions are called with the **documented valid signatures** from their
own header comments (years 2020–2026, `stz` default `UTC`; the SORT/APAYMENT
2026 roadblocks are respected — `EAR_export_SORT('2026')` intentionally raises
by design, so the 2025 legacy + 2026 branches are covered via their correct
entry points).

**Known app-function bug (pre-existing, NOT a migration regression):**
`EAR_export_SORT_n` fails on **2026** data (`crosstab category value must not
be null`; `summary:=true` additionally hits `upper bound of FOR loop cannot be
null`). Its own header says "TODO: more testing / improve approach". It works
for 2025 (34 rows) and older years, so the suite invokes `SORT_n('2025')`.
`EAR_export_SORT_2026` is the supported 2026 path (33 rows) — SORT_n 2026 was
already broken on the source data before migration.

## How to run

```bash
# from the workbench/ directory:
./regression/run-regression.sh dev     # -> reports/regression/regression-dev-<ts>.txt
./regression/run-regression.sh prod    # -> reports/regression/regression-prod-<ts>.txt
```

Both profiles use the read-only `reporter` role (`.env.dev` / `.env.prod`).

## Validation protocol

1. **Dev PG 17** (192.168.100.32:5432 — currently the migrated copy of prod):
   run suite → **zero ERROR lines** = suite valid. This run is the baseline.
2. **Prod** (172.20.61.220:5432, still PG 12): run suite → zero ERROR lines
   = suite valid against the real schema, AND counts should match the dev
   baseline (dev is a migrated copy of prod). Drift is expected only where
   prod data moved after the 2026-08-16 backup (off-season: minimal).
3. **B.8 (post-cutover)**: run the same suite on the new prod PG 17 vs the
   dev baseline — must be identical (same image, same data).

```bash
diff <(sed '/T0 server/d' reports/regression/regression-dev-*.txt) \
     <(sed '/T0 server/d' reports/regression/regression-prod-*.txt)
```

Expected diffs (not failures):
- `T0 server` version line (17.11 vs 12.13)
- row counts where prod data legitimately drifted post-backup

## Privileged follow-ups (NOT in the reporter suite)

`reporter` lacks `pg_read_all_settings` and pgagent grants, so these A.7
checks are run separately as the `postgres` OS user inside the container:

```bash
docker exec -u postgres <container> psql -U postgres -c "SHOW shared_preload_libraries;"   # expect pg_stat_statements
docker exec -u postgres <container> psql -U postgres -d postgres -c "SELECT count(*) FROM pgagent.pga_job; SELECT count(*) FROM pgagent.pga_schedule;"  # expect 7 / 11
```

(Verified 2026-08-17: `pg_stat_statements` 1.11 + `pgagent` 4.2 live in the
**postgres** DB, not aspadb — confirmed in `pg_extension` there.)

## Known server quirks (documented 2026-08-17)

- `SHOW lc_collate` / `lc_ctype` / `shared_preload_libraries` **error on this
  image**: the GUCs are absent from `pg_settings` (363 settings present). The
  suite uses `pg_database.datcollate/datctype` instead (authoritative,
  reporter-readable). `SHOW lc_monetary` works (en_US.utf8).
- `reporter` cannot read `pg_stat_activity` rows for other users' backends and
  `pg_stat_statements` — runtime-stats checks (top-slow, unused-indexes) are
  therefore excluded from the suite; they remain ad-hoc analysis tools.
