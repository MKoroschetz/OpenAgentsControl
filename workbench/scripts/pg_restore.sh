#!/bin/bash

# pg_restore.sh - Restore aspaDB databases from backup files (single DB or full cluster)
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/pg_restore.sh
# **Version**: v2.4.1 | **Last Updated**: 2026-08-16 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v2.4.1 (2026-08-16): Config vars USERNAME/PGPWDFILE/HOSTNAME are now read
#   with ${VAR:-} guards - under `set -u` an absent config key (e.g. the minimal
#   temp config aspa_restore.sh passes, which sets HOSTNAME/PORT/PGPWDFILE but
#   not USERNAME) crashed with "unbound variable" before the defaults applied.
# - v2.4.0 (2026-08-16): Config PORT support - when HOSTNAME is set (host-side
#   TCP restore), an optional PORT from the config is appended to the connection
#   args (-p PORT). Needed for side-by-side containers whose published host port
#   differs from 5432 (e.g. dev postgres17 on 5434) - aspa_restore.sh v1.1.0
#   auto-detects the published port and passes it via its temp config.
# - v2.3.0 (2026-08-16): New --skip-pgagent-restart flag (skips the pgagent
#   daemon restart inside reconcile_pgagent for callers that manage the container
#   lifecycle themselves, e.g. aspa_restore.sh) + drop_db() now terminates
#   lingering connections (pg_terminate_backend) before DROP DATABASE so
#   reconnected app pools cannot block the restore.
# - v2.2.0 (2026-08-16): Post-restore pgagent reconciliation - the daemon keeps
#   running while the pgagent schema is dropped/recreated under it, leaving its
#   in-memory jagid and the joblog sequence out of sync with the restored data
#   (FK violations on pga_jobagent + duplicate pga_joblog keys). New step after
#   the postgres restore: unclaim all jobs, clear pga_jobagent, re-sync
#   pga_joblog_jlgid_seq, re-add the FK constraint if the restore could not
#   (pga_jobagent data is no longer backed up - pg_backup.sh v1.5.0), and
#   re-register the daemon (container restart; in-container runs warn).
# - v2.1.0 (2026-08-16): Post-restore collation normalization - old-cluster
#   dumps carry COLLATE "C.UTF-8" in index definitions (the old cluster was
#   init'd with C.UTF-8 default; those indexes were never rebuilt when the app
#   moved to en_US.utf8). The collation is registered temporarily during restore
#   (init-pgagent.sh) so the dump succeeds, then this step rebuilds every
#   C.UTF-8 index with en_US.utf8 and drops the now-unused collation - leaving
#   the cluster 100% en_US.utf8 (matching prod). No-op on clean dumps.
# - v2.0.5 (2026-08-16): postgresql.conf / postgresql.auto.conf are now
#   REFERENCE-ONLY - they stay in the backup's config/ for post-upgrade tuning
#   comparison and are NEVER written into PGDATA (fresh PG17 conf stays;
#   postgresql.auto.conf is auto-managed by ALTER SYSTEM, never hand-edited).
#   Only pg_hba.conf is activated (app-consistency critical, version-portable).
# - v2.0.4 (2026-08-16): Config staging: pg_hba.conf is now ACTIVATED directly
#   (copy to PGDATA_TARGET + chown/chmod + pg_reload_conf) - it is app-consistency
#   critical and version-portable. postgresql.conf/auto.conf stay *.restored
#   (version-specific, review first). In-container runs default PGDATA_TARGET to
#   $PGDATA (the host-side path from pg_backup.config does not exist in-container).
# - v2.0.3 (2026-08-16): Fixed NO_CREATE leak — it stayed "yes" after the
#   postgres DB restore, so every per-DB restore used --no-create and failed
#   with "database does not exist". Reset to "no" after step 2. Also: the
#   postgres restore now drops the container's fresh (empty) pgagent first when
#   the dump carries pgagent, so the old schedules restore without FK conflicts.
# - v2.0.2 (2026-08-16): Force unix-socket connection when running inside a
#   container (/.dockerenv) — TCP ports are host-side mappings (5434:5432); a
#   config HOSTNAME pointing at the host IP would hit the OLD container on 5432.
# - v2.0.1 (2026-08-16): Fixed unbound NO_OWNER/NO_PRIVILEGES (set -u crash on
#   --no-owner/--no-privileges); guarded PGDATA_TARGET for older configs.
#   Defaults tuned for the real-world same-host case — plain `pg_restore.sh
#   <backup-dir>` needs NO flags (drop-first + owners/privileges restored via
#   globals); --no-owner/--no-privileges are cross-host (prod->dev) only.
# - v2.0.0 (2026-08-16): Merged restore-cluster.sh into pg_restore.sh — ONE
#   restore tool, one name (the old pg_restore.sh + restore-cluster.sh pair was
#   contradictory/confusing). Cluster mode: <backup-dir> positional arg restores
#   globals -> postgres -> every DB in order, then ANALYZE/VACUUM, then stages
#   the backup's config/ into PGDATA_TARGET as *.restored. Single-DB mode: -d.
#   restore-cluster.sh removed.
# - v1.1.0 (2026-08-11): Improved 2026-08 (restore-all, maintenance-only, no-create)
# - v1.0.0 (2026-08-11): Initial standard header
#
# Usage:
#   pg_restore.sh <backup-dir> [--no-drop] [--no-owner] [--no-privileges] [--skip-maintenance] [--skip-pgagent-restart] [-c <config>]
#   pg_restore.sh -d <backupfile> [--drop] [--no-owner] [--no-privileges] [-c <config>]
#   pg_restore.sh --maintenance-only [-c <config>]
#
#   <backup-dir>      Directory containing globals.sql.gz + *.custom / *.sql.gz dumps
#                     (as produced by pg_backup.sh). Restores globals -> postgres ->
#                     every other DB in the correct order, then ANALYZE/VACUUM.
#   -d <backupfile>   Restore a single database from a backup file
#                     (e.g. aspadb.custom, aspadb.sql, aspadb.sql.gz)
#   --drop            Drop the target database(s) first if they exist (cluster default)
#   --no-drop         Do NOT drop existing databases before restoring
#   --no-owner        Restore without ownership (CROSS-HOST only: prod -> dev)
#   --no-privileges   Restore without privileges (CROSS-HOST only: prod -> dev)
#   --no-create       Restore INTO an existing database (no CREATE DATABASE).
#                     Required for the postgres system DB which always exists.
#   --skip-maintenance  Skip the ANALYZE/VACUUM pass at the end
#   --maintenance-only  Skip restore; only run ANALYZE/VACUUM on all databases
#   --skip-pgagent-restart  Skip the pgagent daemon restart in the post-restore
#                     reconciliation (for callers that manage the container
#                     lifecycle themselves, e.g. aspa_restore.sh).
#   -c <config>       Use an alternate config file (default: pg_backup.config)
#
# Defaults are tuned for the real-world same-host case — NO flags needed:
# existing DBs are dropped first (re-runnable) and owners/privileges are
# restored from the dump (roles come from the globals step). Only cross-host
# transfers (prod -> dev) need --no-owner --no-privileges.
#
# Examples:
#   # Same-host restore (the common case - no parameters needed)
#   ./pg_restore.sh /mnt/data/aspadata/DB-Backup/2026-06-30/
#   # Cross-host transfer to dev (no roles/owners from prod)
#   ./pg_restore.sh /mnt/data/aspadata/DB-Backup/2026-06-30/ --no-owner --no-privileges
#   # Single database
#   ./pg_restore.sh -d /mnt/data/aspadata/DB-Backup/2026-06-30/aspadb.custom --drop
#
# Exit codes: 0 = success, 1 = restore failure, 2 = usage error

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

BACKUP_DIR_ARG=""
DB=""
EXTRA_ARGS=()
CONFIG_ARG=""
SKIP_MAINTENANCE="no"
DROP_FIRST="yes"   # cluster default: overwrite existing databases (disaster recovery / dev transfer)
NO_CREATE="no"
NO_OWNER=""
NO_PRIVILEGES=""
MAINTENANCE_ONLY="no"
SKIP_PGAGENT_RESTART="no"

# Parse args in any order: the first non-flag argument is the backup directory
while [ $# -gt 0 ]; do
        case $1 in
                -d)
                        if [ -n "$2" ]; then
                                DB="$2"
                                shift 2
                        else
                                echo "Usage: -d <backupfile>" 1>&2
                                exit 2
                        fi
                        ;;
                --drop)
                        DROP_FIRST="yes"
                        shift
                        ;;
                --no-drop)
                        DROP_FIRST="no"
                        shift
                        ;;
                --no-owner)
                        NO_OWNER="--no-owner"
                        EXTRA_ARGS+=("$1")
                        shift
                        ;;
                --no-privileges)
                        NO_PRIVILEGES="--no-privileges"
                        EXTRA_ARGS+=("$1")
                        shift
                        ;;
                --no-create)
                        NO_CREATE="yes"
                        shift
                        ;;
                --skip-maintenance)
                        SKIP_MAINTENANCE="yes"
                        shift
                        ;;
                --maintenance-only)
                        MAINTENANCE_ONLY="yes"
                        shift
                        ;;
                --skip-pgagent-restart)
                        SKIP_PGAGENT_RESTART="yes"
                        shift
                        ;;
                -c)
                        CONFIG_ARG="-c $2"
                        shift 2
                        ;;
                -*)
                        echo "Unknown option: $1" 1>&2
                        exit 2
                        ;;
                *)
                        if [ -z "$BACKUP_DIR_ARG" ]; then
                                BACKUP_DIR_ARG="$1"
                        else
                                echo "Error: unexpected argument: $1" 1>&2
                                exit 2
                        fi
                        shift
                        ;;
        esac
done

# Load config (host/user/passfile) - default: pg_backup.config next to this script
CONFIG_FILE=""
if [ -n "$CONFIG_ARG" ]; then
        CONFIG_FILE="${CONFIG_ARG#-c }"
else
        CONFIG_FILE="$SCRIPT_DIR/pg_backup.config"
fi
if [ -r "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
else
        echo "Error: config file not found: $CONFIG_FILE" 1>&2
        exit 2
fi
[ -z "${USERNAME:-}" ] && USERNAME="postgres"
[ -z "${PGPWDFILE:-}" ] && PGPWDFILE="$SCRIPT_DIR/.pgpass"
# Config-sourced vars may be absent in older pg_backup.config files
PGDATA_TARGET="${PGDATA_TARGET:-}"
unset PGPASSWORD
export PGPASSFILE="$PGPWDFILE"
if [ -n "${HOSTNAME:-}" ] && [ "${HOSTNAME:-}" != "localhost" ]; then
        PGHOST_ARGS="-h $HOSTNAME"
        # Optional PORT from config (side-by-side containers publish non-5432
        # host ports, e.g. dev postgres17 on 5434). Default stays 5432.
        if [ -n "${PORT:-}" ] && [ "$PORT" != "5432" ]; then
                PGHOST_ARGS="$PGHOST_ARGS -p $PORT"
        fi
else
        PGHOST_ARGS=""
fi
# Inside a container, ALWAYS connect over the unix socket (peer auth as the
# postgres OS user). TCP ports are host-side mappings (5434:5432) — a config
# HOSTNAME pointing at the host IP would hit the OLD container on 5432.
if [ -f /.dockerenv ]; then
        PGHOST_ARGS=""
        unset PGHOST
        # In-container: default the config staging target to the container's PGDATA
        # (the host-side PGDATA_TARGET path from pg_backup.config does not exist here).
        PGDATA_TARGET="${PGDATA_TARGET:-$PGDATA}"
fi

# Log file (non-fatal if unwritable)
LOG_DIR="${BACKUP_DIR:-./}log"
LOG_FILE="${LOG_DIR}/pg_restore.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

echo "=============================================="
echo " PG RESTORE"
echo "=============================================="
echo " Backup dir : ${BACKUP_DIR_ARG:-<single-db>}"
echo " DB file    : ${DB:-<cluster>}"
echo " Extra args : ${EXTRA_ARGS[*]:-none}"
echo " Config     : $CONFIG_FILE"
echo "=============================================="

###########################
#### HELPER FUNCTIONS #####
###########################

# drop_db <dbname> - drop a database if it exists. Terminates lingering
# connections first (pg_terminate_backend) so reconnected app pools cannot
# block the DROP.
drop_db() {
        local db="$1"
        echo " >> Dropping existing database $db (if any) ..."
        psql $PGHOST_ARGS -U "$USERNAME" -d postgres -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS "$db";
SQL
}

# restore_custom <file> <dbname> - restore a custom-format dump
restore_custom() {
        local file="$1" db="$2"
        echo -e " >> using <pg_restore> on $file\n"
        if [ "$NO_CREATE" = "yes" ]; then
                # Restore INTO an existing database (e.g. the postgres system DB).
                # Tolerant: existing objects (schemas, extensions) are expected and skipped.
                # SEQUENTIAL (no -j): the dump's pgagent data (extension member tables)
                # has no FK dependency entries, so parallel restore can load pga_jobstep
                # before pga_job and trip FK violations. Sequential keeps dump order.
                if ! pg_restore $PGHOST_ARGS -U "$USERNAME" -d "$db" \
                                $NO_OWNER $NO_PRIVILEGES "$file"; then
                        echo -e "\n** [!!ERROR!!] Restoring INTO existing $db. Check messages above **\n" 1>&2
                        return 1
                fi
        else
                # --create -d postgres: pg_restore creates the DB named in the dump
                # The DB MUST NOT EXIST (or --drop was used)
                if ! pg_restore $PGHOST_ARGS -U "$USERNAME" -j 4 --create -d postgres --exit-on-error \
                                $NO_OWNER $NO_PRIVILEGES "$file"; then
                        echo -e "\n** [!!ERROR!!] Restoring $db. Make sure the DB does NOT EXIST (or use --drop) **\n" 1>&2
                        return 1
                fi
        fi
        echo -e "\n** [SUCCESS] $db restored successfully\n"
        return 0
}

# restore_plain <file> <dbname> - restore a plain SQL dump (optionally gzipped)
restore_plain() {
        local file="$1" db="$2"
        echo -e " >> using <psql>\n"
        if [[ "$file" == *.gz ]]; then
                if ! gunzip < "$file" | psql $PGHOST_ARGS -U "$USERNAME" --set ON_ERROR_STOP=on -d "$db" -o "/tmp/restore_${db}.log"; then
                        echo -e "\n** [!!ERROR!!] Restoring $db. Check /tmp/restore_${db}.log **\n" 1>&2
                        return 1
                fi
        else
                if ! psql $PGHOST_ARGS -U "$USERNAME" --set ON_ERROR_STOP=on -d "$db" -o "/tmp/restore_${db}.log" -f "$file"; then
                        echo -e "\n** [!!ERROR!!] Restoring $db. Check /tmp/restore_${db}.log **\n" 1>&2
                        return 1
                fi
        fi
        echo -e "\n** [SUCCESS] $db restored successfully. Check LOG at /tmp/restore_${db}.log\n"
        return 0
}

# restore_one <file> <dbname> - dispatch to the right restore function
restore_one() {
        local file="$1" db="$2"
        local ext="${file##*.}"

        if [ "$DROP_FIRST" = "yes" ]; then
                drop_db "$db"
        fi

        case "$ext" in
                custom)
                        restore_custom "$file" "$db"
                        ;;
                gz)
                        restore_plain "$file" "$db"
                        ;;
                sql)
                        restore_plain "$file" "$db"
                        ;;
                *)
                        echo -e "\n** [!!ERROR!!] Invalid backup file format: $ext **\n" 1>&2
                        return 1
                        ;;
        esac
}

# run_maintenance <dbs> - ANALYZE + VACUUM on the given databases
run_maintenance() {
        local dbs="$1"
        echo -e "\nPerforming routine maintenance (ANALYZE + VACUUM) on: $dbs"
        echo -e "--------------------------------------------\n"
        for db in $dbs; do
                echo -e " Executing ANALYZE on DB $db ...\n"
                psql $PGHOST_ARGS -U "$USERNAME" -b -c "ANALYZE;" -d "$db" >/dev/null 2>&1 \
                        && echo " >> SUCCESS for ANALYZE $db" \
                        || echo "[!!ERROR!!] Failed while executing ANALYZE $db" 1>&2
                echo -e "\n Executing VACUUM on DB $db ...\n"
                psql $PGHOST_ARGS -U "$USERNAME" -b -c "VACUUM;" -d "$db" >/dev/null 2>&1 \
                        && echo " >> SUCCESS for VACUUM $db" \
                        || echo "[ERROR] Failed while executing VACUUM on DB $db" 1>&2
        done
}

# normalize_collations <dbs> - rebuild legacy C.UTF-8 indexes with en_US.utf8,
# then drop the now-unused C.UTF-8 collation. Old-cluster dumps pin COLLATE
# "C.UTF-8" in index definitions; the collation is registered temporarily during
# restore (init-pgagent.sh) so the dump succeeds. This step removes the
# dependency for good: the cluster ends up 100% en_US.utf8 (matching prod).
# No-op on clean dumps (no C.UTF-8 references, no collation to drop).
normalize_collations() {
        local dbs="$1"
        echo ""
        echo "[4/5] Normalizing legacy C.UTF-8 collation usage ..."
        for db in $dbs; do
                local idx_count
                idx_count=$(psql $PGHOST_ARGS -U "$USERNAME" -d "$db" -tAc \
                        "SELECT count(*) FROM pg_indexes WHERE indexdef LIKE '%COLLATE \"C.UTF-8\"%';" 2>/dev/null || echo 0)
                if [ "$idx_count" -gt 0 ]; then
                        echo "      $db: rebuilding $idx_count index(es) with en_US.utf8 ..."
                        # Drop each C.UTF-8 index and recreate it with the collation
                        # swapped to en_US.utf8 (definition otherwise identical).
                        psql $PGHOST_ARGS -U "$USERNAME" -d "$db" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
DO $$
DECLARE
        r record;
        newdef text;
BEGIN
        FOR r IN
                SELECT schemaname, tablename, indexname, indexdef
                FROM pg_indexes
                WHERE indexdef LIKE '%COLLATE "C.UTF-8"%'
        LOOP
                newdef := replace(r.indexdef, 'COLLATE "C.UTF-8"', 'COLLATE "en_US.utf8"');
                EXECUTE format('DROP INDEX %I.%I', r.schemaname, r.indexname);
                EXECUTE newdef;
                RAISE NOTICE 'rebuilt %', r.indexname;
        END LOOP;
END $$;
SQL
                        echo "      $db: indexes rebuilt"
                fi
                # Drop the now-unused collation (if present) - safe no-op otherwise
                psql $PGHOST_ARGS -U "$USERNAME" -d "$db" -c \
                        "DROP COLLATION IF EXISTS pg_catalog.\"C.UTF-8\";" >/dev/null 2>&1 \
                        && echo "      $db: dropped C.UTF-8 collation"
        done
        # Templates too (temporarily allow connections so the collation is gone
        # from future CREATE DATABASE defaults as well)
        psql $PGHOST_ARGS -U "$USERNAME" -d postgres \
                -c "UPDATE pg_database SET datallowconn=true WHERE datname IN ('template0','template1');" >/dev/null 2>&1
        for t in template0 template1; do
                psql $PGHOST_ARGS -U "$USERNAME" -d "$t" \
                        -c "DROP COLLATION IF EXISTS pg_catalog.\"C.UTF-8\";" >/dev/null 2>&1
        done
        psql $PGHOST_ARGS -U "$USERNAME" -d postgres \
                -c "UPDATE pg_database SET datallowconn=false WHERE datname IN ('template0','template1');" >/dev/null 2>&1
        echo "      Collation normalization complete."
}

# reconcile_pgagent - post-restore reconciliation of pgagent runtime state.
# The pgagent daemon runs in the same container as the server and registers
# itself in pga_jobagent at startup (jagid). The restore drops/recreates the
# pgagent schema out from under the running daemon, so:
#   - pga_job.jobagentid may reference jagid values that no longer exist (FK
#     violations when the daemon claims jobs), and
#   - pga_joblog_jlgid_seq can drift behind the restored rows (duplicate jlgid).
# This step unclaims all jobs, clears the runtime table, re-syncs the sequence,
# re-adds the FK constraint if the restore could not (pga_jobagent data is no
# longer backed up - pg_backup.sh v1.5.0), and re-registers the daemon.
reconcile_pgagent() {
        echo ""
        echo "      Reconciling pgagent runtime state (daemon re-registration) ..."
        if ! psql $PGHOST_ARGS -U "$USERNAME" -d postgres -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
-- Unclaim every job: the restored jobagentid values reference daemon
-- registrations that no longer exist after the restore.
UPDATE pgagent.pga_job SET jobagentid = NULL WHERE jobagentid IS NOT NULL;
-- Clear the runtime registration table (one row per running daemon).
DELETE FROM pgagent.pga_jobagent;
-- Re-sync the joblog sequence with the restored history rows.
SELECT setval('pgagent.pga_joblog_jlgid_seq',
              (SELECT COALESCE(max(jlgid), 1) FROM pgagent.pga_joblog));
-- Re-add the FK constraint if the restore could not: pga_jobagent data is no
-- longer backed up, so ALTER TABLE ... ADD CONSTRAINT may have failed validation
-- against the restored pga_job rows (all jobagentid are NULL now, so it passes).
DO $$
BEGIN
        IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                JOIN pg_namespace n ON n.oid = c.connamespace
                WHERE c.conname = 'pga_job_jobagentid_fkey' AND n.nspname = 'pgagent'
        ) THEN
                ALTER TABLE pgagent.pga_job
                        ADD CONSTRAINT pga_job_jobagentid_fkey
                        FOREIGN KEY (jobagentid) REFERENCES pgagent.pga_jobagent(jagid);
        END IF;
END $$;
SQL
        then
                echo "      WARNING: pgagent reconciliation SQL failed - check the messages above" 1>&2
        else
                echo "      pgagent data reconciled (jobs unclaimed, runtime table cleared, sequence synced)"
        fi

        # Re-register the daemon so its in-memory jagid matches the clean table.
        # In-container: pkill would stop the container (entrypoint.sh waits on the
        # daemon), so warn instead. Host-side: restart the postgres container.
        # --skip-pgagent-restart: the caller (aspa_restore) manages the container
        # lifecycle and restarts it after the restore.
        if [ "$SKIP_PGAGENT_RESTART" = "yes" ]; then
                echo "      Skipping daemon restart (--skip-pgagent-restart) - the caller"
                echo "      (aspa_restore) restarts the container after the restore."
        elif [ -f /.dockerenv ]; then
                echo "      WARNING: running inside the container - restart the container"
                echo "      (docker restart <name>) to re-register the pgagent daemon."
                echo "      Until then, job launches may fail with FK errors on pga_jobagent."
        else
                local cid=""
                if [ -n "$PGDATA_TARGET" ] && [ -d "$PGDATA_TARGET" ]; then
                        cid=$(docker ps -q 2>/dev/null | while read -r c; do
                                docker inspect "$c" --format '{{range .Mounts}}{{if eq .Source "'"$PGDATA_TARGET"'"}}{{.Destination}}{{end}}{{end}}' 2>/dev/null | grep -q . && echo "$c" && break
                        done)
                fi
                if [ -n "$cid" ]; then
                        echo "      Restarting container $cid to re-register pgagent ..."
                        if docker restart "$cid" >/dev/null 2>&1; then
                                echo "      Container restarted - pgagent re-registered."
                        else
                                echo "      WARNING: docker restart failed - restart the container manually." 1>&2
                        fi
                else
                        echo "      WARNING: could not locate the postgres container (set PGDATA_TARGET"
                        echo "      in pg_backup.config). Restart the container manually to re-register pgagent."
                fi
        fi
}

# stage_config <backup-dir> - activate pg_hba.conf from the backup.
# postgresql.conf / postgresql.auto.conf are REFERENCE-ONLY: they stay in the
# backup's config/ for post-upgrade tuning comparison and are NEVER written into
# the target PGDATA (the fresh PG17 conf must remain untouched; postgresql.auto.conf
# is auto-managed by ALTER SYSTEM and must not be manually edited).
stage_config() {
        local backup_dir="$1"
        echo ""
        echo "[5/5] Staging server config from backup ..."
        if [ -d "$backup_dir/config" ]; then
                if [ -n "$PGDATA_TARGET" ] && [ -d "$PGDATA_TARGET" ]; then
                        # pg_hba.conf is app-consistency critical (auth rules) and
                        # version-portable: ACTIVATE it directly + reload.
                        if [ -f "$backup_dir/config/pg_hba.conf" ]; then
                                cp -af "$backup_dir/config/pg_hba.conf" "$PGDATA_TARGET/pg_hba.conf"
                                chown postgres:postgres "$PGDATA_TARGET/pg_hba.conf" 2>/dev/null || true
                                chmod 600 "$PGDATA_TARGET/pg_hba.conf" 2>/dev/null || true
                                echo "      ACTIVATED pg_hba.conf -> $PGDATA_TARGET/pg_hba.conf"
                                if psql $PGHOST_ARGS -U "$USERNAME" -d postgres \
                                        -c "SELECT pg_reload_conf();" >/dev/null 2>&1; then
                                        echo "      pg_hba.conf reloaded (pg_reload_conf)"
                                else
                                        echo "      WARNING: pg_reload_conf failed - restart the container to apply pg_hba.conf" 1>&2
                                fi
                        fi
                        echo ""
                        echo "      postgresql.conf / postgresql.auto.conf are REFERENCE-ONLY:"
                        echo "        kept in $backup_dir/config/ for post-upgrade tuning comparison."
                        echo "        NOT written into PGDATA - the fresh PG17 conf stays in place and"
                        echo "        postgresql.auto.conf is auto-managed by ALTER SYSTEM (never edit it manually)."
                else
                        echo "      config/ found in backup but PGDATA_TARGET not set or missing -"
                        echo "      pg_hba.conf NOT activated. Files left in: $backup_dir/config/"
                        echo "      (set PGDATA_TARGET in pg_backup.config to auto-activate into the target cluster)"
                fi
        else
                echo "      No config/ dir in backup - skipping"
        fi
}

###################################
#### MAINTENANCE-ONLY MODE #######
###################################

if [ "$MAINTENANCE_ONLY" = "yes" ]; then
        echo -e "\n=== MAINTENANCE ONLY (no restore) ===\n"
        MAINT_DBS=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "select datname from pg_database where not datistemplate and datallowconn order by datname;" -d postgres)
        run_maintenance "$MAINT_DBS"
        exit 0
fi

###################################
#### SINGLE-DATABASE MODE ########
###################################

if [ -n "$DB" ]; then
        echo -e "\n=== RESTORE SINGLE DATABASE ===\n"
        FULLNAME="${DB##*/}"
        FPATH="${DB%/*}"
        [ "$FPATH" = "$DB" ] && FPATH="."
        DBNAME="${FULLNAME%.*}"
        FEXT="${FULLNAME##*.}"
        if [[ "$FEXT" == "gz" ]]; then
                DBNAME="${DBNAME%.*}"
        fi
        echo -e "\n Restoring $DBNAME from $FPATH/$FULLNAME ...\n"
        restore_one "$FPATH/$FULLNAME" "$DBNAME"
        rc=$?
        if [ $rc -ne 0 ]; then
                echo -e "\n** [!!ERROR!!] Restore of $DBNAME FAILED **\n" 1>&2
                exit 1
        fi
        # pgagent lives in the postgres DB - reconcile its runtime state after restore
        if [ "$DBNAME" = "postgres" ]; then
                reconcile_pgagent
        fi
        if [ "$SKIP_MAINTENANCE" = "no" ]; then
                run_maintenance "$DBNAME"
        fi
        normalize_collations "$DBNAME"
        echo -e "\nRestore complete. Log: $LOG_FILE"
        exit 0
fi

###################################
#### CLUSTER MODE ################
###################################

if [ -z "$BACKUP_DIR_ARG" ]; then
        echo "Usage: pg_restore.sh <backup-dir> [--no-drop] [--no-owner] [--no-privileges] [--skip-maintenance] [-c <config>]" 1>&2
        echo "       pg_restore.sh -d <backupfile> [--drop] [--no-owner] [--no-privileges] [-c <config>]" 1>&2
        echo "       pg_restore.sh --maintenance-only [-c <config>]" 1>&2
        exit 2
fi

if [ ! -d "$BACKUP_DIR_ARG" ]; then
        echo "Error: backup directory not found: $BACKUP_DIR_ARG" 1>&2
        exit 2
fi

if [ ! -f "$BACKUP_DIR_ARG/globals.sql.gz" ]; then
        echo "Error: $BACKUP_DIR_ARG/globals.sql.gz not found - not a valid backup directory" 1>&2
        exit 2
fi

if [ "$DROP_FIRST" = "yes" ]; then
        EXTRA_ARGS+=("--drop")
fi

echo "=============================================="
echo " RESTORE CLUSTER"
echo "=============================================="
echo " Backup dir : $BACKUP_DIR_ARG"
echo " Extra args : ${EXTRA_ARGS[*]:-none}"
echo " Config     : $CONFIG_FILE"
echo "=============================================="

# Step 1: Restore globals (roles) - "already exists" errors are expected and ignored
echo ""
echo "[1/5] Restoring globals (roles, tablespaces) ..."
if ! gunzip < "$BACKUP_DIR_ARG/globals.sql.gz" | psql $PGHOST_ARGS -U "$USERNAME" --set ON_ERROR_STOP=off -d postgres >/dev/null 2>&1; then
        echo "WARNING: globals restore had errors (already-exists is normal). Continuing." 1>&2
fi
echo "      Globals done."

# Step 2: Restore postgres database (INTO the existing system DB - never drop/create it)
echo ""
echo "[2/5] Restoring postgres database (into existing DB) ..."
PGAGENT_RESTORED="no"
if [ -f "$BACKUP_DIR_ARG/postgres.custom" ] || [ -f "$BACKUP_DIR_ARG/postgres.sql.gz" ]; then
        # The container's init-pgagent.sh already created a fresh (empty) pgagent.
        # If the dump carries pgagent (old schedules), drop the fresh one first so
        # the dump's pgagent + schedule data restore cleanly (no FK conflicts).
        if [ -f "$BACKUP_DIR_ARG/postgres.custom" ]; then
                pg_restore -l "$BACKUP_DIR_ARG/postgres.custom" 2>/dev/null | grep -q "pgagent" && PGAGENT_RESTORED="yes"
        elif [ -f "$BACKUP_DIR_ARG/postgres.sql.gz" ]; then
                gunzip -c "$BACKUP_DIR_ARG/postgres.sql.gz" 2>/dev/null | grep -q "pgagent" && PGAGENT_RESTORED="yes"
        fi
        if [ "$PGAGENT_RESTORED" = "yes" ]; then
                echo "      Dropping fresh pgagent so the dump's pgagent (schedules) restores ..."
                # Drop the extension AND the schema: the fresh extension's tables
                # would otherwise make the dump's CREATE TABLE fail, which skips
                # the data COPY and causes FK violations (pga_jobstep/pga_schedule).
                psql $PGHOST_ARGS -U "$USERNAME" -d postgres \
                        -c "DROP EXTENSION IF EXISTS pgagent CASCADE;" \
                        -c "DROP SCHEMA IF EXISTS pgagent CASCADE;" >/dev/null 2>&1
        fi
        NO_CREATE="yes"
        if [ -f "$BACKUP_DIR_ARG/postgres.custom" ]; then
                restore_custom "$BACKUP_DIR_ARG/postgres.custom" "postgres"
        else
                restore_plain "$BACKUP_DIR_ARG/postgres.sql.gz" "postgres"
        fi
else
        echo "WARNING: postgres backup not found - skipping" 1>&2
fi
# Post-restore: reconcile pgagent runtime state. The daemon keeps running while
# the schema is dropped/recreated under it, so its in-memory jagid and the joblog
# sequence drift out of sync with the restored data (FK + duplicate-key errors).
if [ "$PGAGENT_RESTORED" = "yes" ]; then
        reconcile_pgagent
fi
# Reset for the per-DB restores below (they CREATE their databases from the dump)
NO_CREATE="no"

# Step 3: Restore every other database
echo ""
echo "[3/5] Restoring remaining databases ..."
RESTORED=0
for file in "$BACKUP_DIR_ARG"/*.custom; do
        [ -e "$file" ] || continue
        db=$(basename "$file" .custom)
        case "$db" in
                postgres|template0|template1) continue ;;
        esac
        echo ""
        echo "--- Restoring $db ---"
        restore_one "$file" "$db"
        RESTORED=$((RESTORED + 1))
done

# Also handle .sql.gz dumps for DBs without a .custom counterpart
for file in "$BACKUP_DIR_ARG"/*.sql.gz; do
        [ -e "$file" ] || continue
        db=$(basename "$file" .sql.gz)
        case "$db" in
                postgres|globals|*_SCHEMA) continue ;;
        esac
        # Skip if a .custom for this DB was already restored
        if [ -f "$BACKUP_DIR_ARG/${db}.custom" ]; then
                continue
        fi
        echo ""
        echo "--- Restoring $db (from sql.gz) ---"
        restore_one "$file" "$db"
        RESTORED=$((RESTORED + 1))
done

echo ""
echo "=============================================="
echo " RESTORE COMPLETE - $RESTORED databases restored"
echo "=============================================="

if [ "$SKIP_MAINTENANCE" = "no" ]; then
        echo ""
        echo "Running ANALYZE/VACUUM maintenance ..."
        MAINT_DBS=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "select datname from pg_database where not datistemplate and datallowconn order by datname;" -d postgres)
        run_maintenance "$MAINT_DBS"
else
        MAINT_DBS=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "select datname from pg_database where not datistemplate and datallowconn order by datname;" -d postgres)
fi

# Step 4: Normalize legacy C.UTF-8 collation usage (rebuild indexes + drop collation)
normalize_collations "$MAINT_DBS"

# Step 5: Stage server config from the backup (postgresql.conf etc.)
stage_config "$BACKUP_DIR_ARG"

exit 0