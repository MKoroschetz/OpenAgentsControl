#!/bin/bash

# restore-cluster.sh - One-shot disaster recovery / dev transfer for aspaDB
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/restore-cluster.sh
# **Version**: v1.1.0 | **Last Updated**: 2026-08-11 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.1.0 (2026-08-11): Overwrite-by-default, order-independent args
# - v1.0.0 (2026-08-11): Initial standard header
#
# Restores a full cluster backup directory (as produced by pg_backup.sh) in the
# correct order:
#   1. globals.sql.gz   (roles, tablespaces - "already exists" errors ignored)
#   2. postgres DB      (system database)
#   3. every other DB   (aspadb, aspadb-temp, ...)
#
# Usage:
#   restore-cluster.sh <backup-dir> [--no-drop] [--no-owner] [--no-privileges] [--skip-maintenance] [-c <config>]
#
#   <backup-dir>      Directory containing globals.sql.gz + *.custom / *.sql.gz dumps
#   --no-drop         Do NOT drop existing databases before restoring (default: drop/overwrite)
#   --no-owner        Restore without ownership (cross-host: prod -> dev)
#   --no-privileges   Restore without privileges (cross-host: prod -> dev)
#   --skip-maintenance  Skip the ANALYZE/VACUUM pass at the end
#   -c <config>       Config file for pg_restore.sh (host/user/passfile). Default: pg_backup.config
#
# Examples:
#   # Disaster recovery on the same host (roles + all DBs, overwrites existing)
#   ./restore-cluster.sh /mnt/data/aspadata/DB-Backup/2026-06-30/
#
#   # Transfer to dev (no roles/owners from prod, overwrites existing)
#   ./restore-cluster.sh /mnt/data/aspadata/DB-Backup/2026-06-30/ --no-owner --no-privileges
#
# Exit codes: 0 = success, 1 = restore failure, 2 = usage error

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
RESTORE_SCRIPT="$SCRIPT_DIR/pg_restore.sh"

BACKUP_DIR_ARG=""
EXTRA_ARGS=()
CONFIG_ARG=""

if [ $# -lt 1 ]; then
        echo "Usage: $0 <backup-dir> [--no-drop] [--no-owner] [--no-privileges] [--skip-maintenance] [-c <config>]" 1>&2
        exit 2
fi

SKIP_MAINTENANCE="no"
DROP_FIRST="yes"   # default: overwrite existing databases (disaster recovery / dev transfer)

# Parse args in any order: the first non-flag argument is the backup directory
while [ $# -gt 0 ]; do
        case $1 in
                --drop)
                        DROP_FIRST="yes"
                        shift
                        ;;
                --no-drop)
                        DROP_FIRST="no"
                        shift
                        ;;
                --no-owner|--no-privileges)
                        EXTRA_ARGS+=("$1")
                        shift
                        ;;
                -c)
                        CONFIG_ARG="-c $2"
                        shift 2
                        ;;
                --skip-maintenance)
                        SKIP_MAINTENANCE="yes"
                        shift
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

if [ -z "$BACKUP_DIR_ARG" ]; then
        echo "Error: no backup directory provided" 1>&2
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

# Load config for the globals step (host/user/passfile)
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
[ -z "$USERNAME" ] && USERNAME="postgres"
[ -z "$PGPWDFILE" ] && PGPWDFILE="$SCRIPT_DIR/.pgpass"
unset PGPASSWORD
export PGPASSFILE="$PGPWDFILE"
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "localhost" ]; then
        PGHOST_ARGS="-h $HOSTNAME"
else
        PGHOST_ARGS=""
fi

echo "=============================================="
echo " RESTORE CLUSTER"
echo "=============================================="
echo " Backup dir : $BACKUP_DIR_ARG"
echo " Extra args : ${EXTRA_ARGS[*]:-none}"
echo " Config    : $CONFIG_FILE"
echo "=============================================="

# Step 1: Restore globals (roles) - "already exists" errors are expected and ignored
echo ""
echo "[1/3] Restoring globals (roles, tablespaces) ..."
if ! gunzip < "$BACKUP_DIR_ARG/globals.sql.gz" | psql $PGHOST_ARGS -U "$USERNAME" --set ON_ERROR_STOP=off -d postgres >/dev/null 2>&1; then
        echo "WARNING: globals restore had errors (already-exists is normal). Continuing." 1>&2
fi
echo "      Globals done."

# Step 2: Restore postgres database (INTO the existing system DB - never drop/create it)
echo ""
echo "[2/3] Restoring postgres database (into existing DB) ..."
if [ -f "$BACKUP_DIR_ARG/postgres.custom" ]; then
        "$RESTORE_SCRIPT" -d "$BACKUP_DIR_ARG/postgres.custom" --no-create $CONFIG_ARG "${EXTRA_ARGS[@]}"
elif [ -f "$BACKUP_DIR_ARG/postgres.sql.gz" ]; then
        "$RESTORE_SCRIPT" -d "$BACKUP_DIR_ARG/postgres.sql.gz" --no-create $CONFIG_ARG "${EXTRA_ARGS[@]}"
else
        echo "WARNING: postgres backup not found - skipping" 1>&2
fi

# Step 3: Restore every other database
echo ""
echo "[3/3] Restoring remaining databases ..."
RESTORED=0
for file in "$BACKUP_DIR_ARG"/*.custom; do
        [ -e "$file" ] || continue
        db=$(basename "$file" .custom)
        case "$db" in
                postgres|template0|template1) continue ;;
        esac
        echo ""
        echo "--- Restoring $db ---"
        "$RESTORE_SCRIPT" -d "$file" $CONFIG_ARG "${EXTRA_ARGS[@]}"
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
        "$RESTORE_SCRIPT" -d "$file" $CONFIG_ARG "${EXTRA_ARGS[@]}"
        RESTORED=$((RESTORED + 1))
done

echo ""
echo "=============================================="
echo " RESTORE COMPLETE - $RESTORED databases restored"
echo "=============================================="

if [ "$SKIP_MAINTENANCE" = "no" ]; then
        echo ""
        echo "Running ANALYZE/VACUUM maintenance ..."
        "$RESTORE_SCRIPT" --maintenance-only $CONFIG_ARG "${EXTRA_ARGS[@]}" 2>/dev/null || true
fi

exit 0