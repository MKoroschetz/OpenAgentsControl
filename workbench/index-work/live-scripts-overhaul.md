# Live Script Overhaul - Deployment Guide & Scheduler Recommendation
**Project**: aspaDB-workbench | **Path**: workbench/index-work/live-scripts-overhaul.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-11 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.0.0 (2026-08-11): Rewrite of pg_backup_rotated.sh / pg_maintenance.sh /
  aspa_IngresCleanup.sh (bugs found in analysis, fixes approved A1-A3); deployment
  guide + cron/pg_agent overlap recommendation (A4)

---

## 1. What was fixed (approved A1-A3)

All three scripts shared the same critical bugs plus script-specific ones.

### Common fixes
| Bug | Before | After |
|-----|--------|-------|
| `-c` config flag ignored | `if [ $# = 0 ]` after the arg loop is always true -> default config always overrode the custom one (verified empirically) | `if [ -z "$CONFIG_FILE_PATH" ]` - custom config honored |
| `${ECHO}` undefined | `command not found` -> exit 127 on the error path | plain `echo` |
| Unquoted tests | `[ ! $VAR ]` breaks with spaces/empty | `[ -z "$VAR" ]` |
| Symlink invocation | `dirname $0` resolves to the link's folder | `readlink -f "$0"` resolves the real script folder |
| `set -euo pipefail` placement | mid-function (after early mkdir/cp) | top of script |

### pg_backup_rotated.sh (v1.1.0)
- `mkdir ${FINAL_BACKUP_DIR}utilities` without `-p` -> under `set -e` a same-day
  rerun exits mid-backup. Now `mkdir -p`.
- Unprotected `cp -af` of the `aspa_backup` symlink and the crontab -> now
  guarded with `2>/dev/null || true` (they are optional metadata).
- Config default fallback now uses the real script folder (symlink-safe).
- Adds `PGHOST_ARGS` support (remote-host connections), matching pg_backup.sh.
- **Naming kept as `-daily` / `-weekly` / `-monthly` suffixes** (A2 decision):
  the rotation/pruning rules (`find ... -name "*-daily"` etc.) depend on the
  suffix to tell backup tiers apart. Removing it would break rotation, so the
  internal layout is unified with pg_backup.sh (globals.sql.gz, *.custom,
  *.sql.gz, utilities/, IOTstack/, crontabs/) but the suffix stays.

### pg_maintenance.sh (v1.1.0)
- `DBNAME=aspadb` hardcoded -> only aspadb was ever ANALYZE/VACUUM'd.
  Now loops ALL non-template, connectable databases (same list as
  `pg_restore.sh --maintenance-only`).
- `exexuting` typo fixed.
- `VACUUM;` / `ANALYZE;` kept separate (matches pg_restore.sh; avoids
  autovacuum lock contention with a combined command).
- Per-DB SUCCESS/ERROR logging retained.

### aspa_IngresCleanup.sh (v1.1.0)
- `-c` doubly broken: custom config was sourced, then the default config was
  sourced ON TOP of it, silently overriding it. Now single source path.
- Fragile quoting `PGFUNCTIONTORUN="select * from aspa."\""IngresCleanup"\""();"`
  -> clean single-quoted string producing the same SQL.
- `source $SCRIPTPATH/pg_backup.config` unquoted + no readability check ->
  quoted + `[ -r ]` guard.
- Added SUCCESS logging and non-zero exit on failure (cron can now detect it).
- Naming note: file/function use "Ingres", the pg_agent job uses "Ingress".
  Kept as-is (function name is the live aspa object).

## 2. Deployment (manual to prod - no SSH access)

Package: `/tmp/opencode/prod-deploy/fixed-live-scripts.tar.gz`

```bash
# On prod, as root (scripts live in /mnt/data/aspadata/DB-Backup/)
tar -xzf fixed-live-scripts.tar.gz -C /mnt/data/aspadata/DB-Backup/
chmod +x /mnt/data/aspadata/DB-Backup/pg_backup_rotated.sh \
         /mnt/data/aspadata/DB-Backup/pg_maintenance.sh \
         /mnt/data/aspadata/DB-Backup/aspa_IngresCleanup.sh
# sanity check
bash -n /mnt/data/aspadata/DB-Backup/pg_backup_rotated.sh
```

Already deployed (verified) to both dev locations:
- `/mnt/db/IOTstack/DB_Backup/2026-08-11-manual/utilities/`
- `/mnt/data/aspadata/DB-Backup/2026-08-11-manual/utilities/`

## 3. Scheduler split recommendation (A4)

Current schedule (prod crontab + pg_agent):

| Job | Cron | pg_agent |
|-----|------|----------|
| pg_maintenance.sh | `8 2 * * *` | - |
| pg_backup_rotated.sh | `8 3 * 3-6 *` | - |
| pg_backup.sh | `6 4 * 2,6 *` | - |
| aspa_IngresCleanup.sh | `0,15,30,45 7-20 * 3-5 *` | Ingress Cleanup: minute 10, hourly, months Mar-Jun |
| Transfers -> Andrian/SAIT/Standl/Terlan | - | pg_agent (job 4 SAIT disabled) |
| Clear OP-115 Work order | - | pg_agent |
| Inventory Aging | - | pg_agent |

### The one real conflict: aspa_IngresCleanup is DOUBLE-SCHEDULED

Mar-May the function runs every 15 min (cron, 07-20h) AND every hour (pg_agent,
minute 10) -> overlapping executions. The function is idempotent (cleanup
process), so double-running is wasteful but not destructive - still, one
scheduler should own it.

**Recommendation (matches A4 split: DB maintenance on cron, APP functions in
pg_agent):**
1. **Keep** the pg_agent "Ingress Cleanup" job (APP-side aspa function -> pg_agent).
2. **Remove** the cron line `0,15,30,45 7-20 * 3-5 * aspa_IngresCleanup.sh`
   from prod's crontab.
3. Keep `pg_maintenance.sh` (DB maintenance) on cron as-is.
4. Keep backup jobs on cron (filesystem-level work -> cron).

Reasoning: pg_agent 12.13 has no cron-integration handover (reconsider when
the cluster moves to PG16, where pg_agent supports handover of cron jobs).
Until then, "DB-related maintenance on cron, aspaDB/APP functions in pg_agent"
is the clean split, with aspa_IngresCleanup belonging to pg_agent only.

### If you want to keep the cron line instead
Remove/disable the pg_agent "Ingress Cleanup" job (set `jstenabled=false` on
its jobstep or `jscenabled=false` on its schedule) to avoid double execution.

## 4. Verify after deployment

```bash
# maintenance now touches all 9 DBs
/mnt/data/aspadata/DB-Backup/pg_maintenance.sh            # expect all-DB SUCCESS lines
# rotated backup honours -c
/mnt/data/aspadata/DB-Backup/pg_backup_rotated.sh -c /mnt/data/aspadata/DB-Backup/pg_backup.config
# cleanup script logs SUCCESS and exits non-zero on failure
/mnt/data/aspadata/DB-Backup/aspa_IngresCleanup.sh
echo $?  # 0 on success
```
