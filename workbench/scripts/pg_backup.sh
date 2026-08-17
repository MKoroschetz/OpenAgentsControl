#!/bin/bash

# pg_backup.sh - Full cluster backup for aspaDB
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/pg_backup.sh
# **Version**: v1.6.0 | **Last Updated**: 2026-08-16 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.6.0 (2026-08-16): aspa_restore wrapper copied into <backup>/IOTstack/ -
#   cp -fL resolves the host symlink so the backup carries a self-contained copy
#   (portable to other hosts, e.g. dev). Guarded: only copied when present.
# - v1.5.0 (2026-08-16): pgagent runtime table excluded from dumps - pga_jobagent
#   (one row per running daemon) is pure runtime state and is no longer backed up
#   (--exclude-table-data). Restoring it resurrected stale daemon registrations and
#   broke pga_job.jobagentid FK after restore (pg_restore.sh v2.2.0 reconciles the
#   runtime state + re-registers the daemon).
# - v1.4.0 (2026-08-16): Config capture is now VERSION-INDEPENDENT - detect_config_dir()
#   auto-resolves the live config dir when PG_CONFIG_DIR is blank: SHOW config_file via
#   the backup connection, then docker mount mapping for in-container paths (works for
#   PG12 old cluster AND PG17, anonymous volumes AND bind mounts). pg_hba.conf is
#   included in <backup>/config/ and ACTIVATED on restore (pg_restore.sh v2.0.4).
# - v1.3.1 (2026-08-16): Utilities copy no longer includes restore-cluster.sh —
#   merged into pg_restore.sh v2.0.0 (single restore tool).
# - v1.3.0 (2026-08-16): Config backup - copies the live postgresql.conf /
#   postgresql.auto.conf / pg_hba.conf into <backup>/config/ (PG_CONFIG_DIR),
#   so server tuning is part of the backup and can be staged on restore
#   (pg_restore.sh v2.0.0 -> PGDATA_TARGET as *.restored).
# - v1.2.0 (2026-08-11): Symlink auto-manual detection, --verify, restore-cluster.sh copy
# - v1.1.0 (2026-08-11): Improved 2026-08 (symlink resolution, config via resolved path)
# - v1.0.0 (2026-08-11): Initial standard header
#
# Usage:
#   pg_backup.sh [-c <config>] [-m <suffix>] [--verify]
#
#   -c <config>   Use an alternate config file (default: pg_backup.config)
#   -m <suffix>   Append a suffix to the backup directory name (e.g. -manual)
#   --verify      After each dump, verify integrity with pg_restore -l (custom) / gzip -t (plain)
#
# Manual backup: when invoked via the aspa_backup symlink, the backup
# directory is automatically labeled -manual (e.g. 2026-08-11-manual),
# distinguishing it from cron-triggered backups (2026-08-11).
#
# Produces per database:
#   <db>.custom   - custom format (restore-able with pg_restore) [if ENABLE_CUSTOM_BACKUPS=yes]
#   <db>.sql.gz   - gzipped plain SQL (portable, greppable)      [if ENABLE_PLAIN_BACKUPS=yes]
# Plus:
#   globals.sql.gz - roles/tablespaces (pg_dumpall -g)

# NOTE: modified to use UNIX Socket to execute. 02-10-2022 - MK!

## Change to script folder (resolve symlinks so the aspa_backup link works)
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
EXEDIR=$(dirname "$SCRIPT_PATH")
cd "$EXEDIR"

###########################
####### LOAD CONFIG #######
###########################
SUFFIX=""
CONFIG_FILE=""
VERIFY="no"

# When invoked via the aspa_backup link (manual backup), default to a
# clearly labeled backup directory (e.g. 2026-08-11-manual) so manual
# backups are distinguishable from cron-triggered ones.
INVOKED_AS=$(basename "$0")
if [ "$INVOKED_AS" = "aspa_backup" ]; then
        SUFFIX="-manual"
fi

while [ $# -gt 0 ]; do
        case $1 in
                -c)
                        if [ -r "$2" ]; then
                                CONFIG_FILE="$2"
                                shift 2
                        else
                                echo "Unreadable config file \"$2\"" 1>&2
                                exit 1
                        fi
                        ;;
                -m)
                        if [ -n "$2" ]; then
                                SUFFIX="-$2"
                                shift 2
                        else
                                SUFFIX="-manual"
                                shift 1
                        fi
                        ;;
                --verify)
                        VERIFY="yes"
                        shift 1
                        ;;
                *)
                        echo "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done

if [ -z "$CONFIG_FILE" ]; then
        SCRIPTPATH=$(dirname "$SCRIPT_PATH")
        CONFIG_FILE="$SCRIPTPATH/pg_backup.config"
fi
if [ -r "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
else
        echo "Config file not found: $CONFIG_FILE" 1>&2
        exit 1
fi

###########################
#### PRE-BACKUP CHECKS ####
###########################

# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" ] && [ "$(id -un)" != "$BACKUP_USER" ]; then
        echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
        exit 1
fi

###########################
### INITIALISE DEFAULTS ###
###########################

if [ -z "$HOSTNAME" ]; then
        HOSTNAME="localhost"
fi

if [ -z "$USERNAME" ]; then
        USERNAME="postgres"
fi

if [ -z "$PGPWDFILE" ]; then
        PGPWDFILE="./.pgpass"
fi

if [ -z "$LOG_DIR" ]; then
        LOG_DIR="${BACKUP_DIR}log"
        LOG_FILE="${LOG_DIR}/pg_backup.log"
else
        LOG_FILE="${LOG_DIR}pg_backup.log"
fi

# Host args: use -h when HOSTNAME is set (remote backup), else local socket
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "localhost" ]; then
        PGHOST_ARGS="-h $HOSTNAME"
else
        PGHOST_ARGS=""
fi

# PGPASSWORD env var overrides the passfile - unset it so the passfile is used
unset PGPASSWORD

# Export PGPASSFILE so psql, pg_dump and pg_dumpall all use the passfile
export PGPASSFILE="$PGPWDFILE"

echo -e "\n** PARAMS: $HOSTNAME, $USERNAME, $PGPWDFILE, $LOG_DIR, $LOG_FILE **\n"

###########################
#### START THE BACKUPS ####
###########################

FINAL_BACKUP_DIR="${BACKUP_DIR}$(date +%Y-%m-%d)${SUFFIX}/"

echo "Making backup directory in $FINAL_BACKUP_DIR"

if ! mkdir -p "$FINAL_BACKUP_DIR"; then
        echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
        exit 1
fi

echo "Making log directory $LOG_DIR"

if ! mkdir -p "$LOG_DIR"; then
        echo "Cannot create LOG directory $LOG_DIR. Go and fix it!" 1>&2
        exit 1
fi

#######################
### GLOBALS BACKUPS ###
#######################

echo -e "\n\nPerforming globals backup"
echo -e "--------------------------------------------\n"

if [ "$ENABLE_GLOBALS_BACKUPS" = "yes" ]; then
        echo "Globals backup"
        echo "$(date +%Y-%m-%d_%H:%M:%S);Globals backup" >> "$LOG_FILE"

        if ! pg_dumpall -g $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE" | gzip > "$FINAL_BACKUP_DIR/globals.sql.gz.in_progress"; then
                echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
                echo "$(date +%Y-%m-%d_%H:%M:%S);Failed to produce globals backup" >> "$LOG_FILE"
        else
                mv "$FINAL_BACKUP_DIR/globals.sql.gz.in_progress" "$FINAL_BACKUP_DIR/globals.sql.gz"
                if [ "$VERIFY" = "yes" ]; then
                        gzip -t "$FINAL_BACKUP_DIR/globals.sql.gz" && echo " >> globals.sql.gz verified OK"
                fi
        fi
else
        echo "None"
fi

###########################
### SCHEMA-ONLY BACKUPS ###
###########################

SCHEMA_ONLY_CLAUSE=""
for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }; do
        SCHEMA_ONLY_CLAUSE="$SCHEMA_ONLY_CLAUSE or datname ~ '$SCHEMA_ONLY_DB'"
done

SCHEMA_ONLY_QUERY="select datname from pg_database where false $SCHEMA_ONLY_CLAUSE order by datname;"

echo -e "\n\nPerforming schema-only backups"
echo -e "--------------------------------------------\n"

SCHEMA_ONLY_DB_LIST=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "$SCHEMA_ONLY_QUERY" -d "passfile=$PGPWDFILE dbname=postgres")

echo -e "The following databases were matched for schema-only backup:\n${SCHEMA_ONLY_DB_LIST}\n"

for DATABASE in $SCHEMA_ONLY_DB_LIST; do
        echo "Schema-only backup of $DATABASE"
        echo "$(date +%Y-%m-%d_%H:%M:%S);Schema-only backup of $DATABASE" >> "$LOG_FILE"

        if ! pg_dump -Fp -s $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" | gzip > "$FINAL_BACKUP_DIR/${DATABASE}_SCHEMA.sql.gz.in_progress"; then
                echo "[!!ERROR!!] Failed to backup database schema of $DATABASE" 1>&2
                echo "$(date +%Y-%m-%d_%H:%M:%S);Failed to backup database schema of $DATABASE" >> "$LOG_FILE"
        else
                mv "$FINAL_BACKUP_DIR/${DATABASE}_SCHEMA.sql.gz.in_progress" "$FINAL_BACKUP_DIR/${DATABASE}_SCHEMA.sql.gz"
        fi
done

###########################
###### FULL BACKUPS #######
###########################

# pgagent's pga_jobagent table is RUNTIME state (one row per running daemon) -
# never back it up: restoring it resurrects stale daemon registrations and breaks
# pga_job.jobagentid -> pga_jobagent.jagid after restore. The daemon re-registers
# on restart; pg_restore.sh v2.2.0 reconciles the runtime state post-restore.
PGAGENT_EXCLUDE="--exclude-table-data=pgagent.pga_jobagent"

EXCLUDE_SCHEMA_ONLY_CLAUSE=""
for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }; do
        EXCLUDE_SCHEMA_ONLY_CLAUSE="$EXCLUDE_SCHEMA_ONLY_CLAUSE and datname !~ '$SCHEMA_ONLY_DB'"
done

FULL_BACKUP_QUERY="select datname from pg_database where not datistemplate and datallowconn $EXCLUDE_SCHEMA_ONLY_CLAUSE order by datname;"

echo -e "\nPerforming full backups"
echo -e "--------------------------------------------\n"

for DATABASE in $(psql $PGHOST_ARGS -U "$USERNAME" -At -c "$FULL_BACKUP_QUERY" -d "passfile=$PGPWDFILE dbname=postgres"); do
        if [ "$ENABLE_PLAIN_BACKUPS" = "yes" ]; then
                echo -e " Performing backup of $DATABASE in PLAIN sql format ..."
                echo "$(date +%Y-%m-%d_%H:%M:%S);Plain backup of $DATABASE" >> "$LOG_FILE"

                if ! pg_dump -Fp $PGAGENT_EXCLUDE $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" | gzip > "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz.in_progress"; then
                        echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
                        echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Failed to produce plain backup database $DATABASE" >> "$LOG_FILE"
                else
                        mv "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz.in_progress" "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz"
                        if [ "$VERIFY" = "yes" ]; then
                                gzip -t "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz" && echo "   ${DATABASE}.sql.gz verified OK"
                        fi
                fi
        fi

        if [ "$ENABLE_CUSTOM_BACKUPS" = "yes" ]; then
                echo -e " Performing backup of $DATABASE in CUSTOM format. Use pg_restore to recover data! ..."
                echo "$(date +%Y-%m-%d_%H:%M:%S);Custom backup of $DATABASE" >> "$LOG_FILE"

                if ! pg_dump -Fc $PGAGENT_EXCLUDE $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" -f "$FINAL_BACKUP_DIR/${DATABASE}.custom.in_progress"; then
                        echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE" 1>&2
                        echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Failed to produce custom backup database $DATABASE" >> "$LOG_FILE"
                else
                        mv "$FINAL_BACKUP_DIR/${DATABASE}.custom.in_progress" "$FINAL_BACKUP_DIR/${DATABASE}.custom"
                        if [ "$VERIFY" = "yes" ]; then
                                pg_restore -l "$FINAL_BACKUP_DIR/${DATABASE}.custom" >/dev/null 2>&1 \
                                        && echo "   ${DATABASE}.custom verified OK" \
                                        || echo "   [!!WARN!!] ${DATABASE}.custom FAILED verification" 1>&2
                        fi
                fi
        fi
done

###########################
#### CONFIG BACKUPS #######
###########################

# detect_config_dir - resolve the LIVE postgresql.conf dir, version-independent.
# Priority: 1) PG_CONFIG_DIR from config (if valid), 2) SHOW config_file via the
# backup connection (bare-metal: path exists locally), 3) docker mount mapping
# (in-container path -> host source; works for anonymous volumes AND bind mounts,
# so it is agnostic to the PG version / container layout).
detect_config_dir() {
        if [ -n "$PG_CONFIG_DIR" ] && [ -d "$PG_CONFIG_DIR" ]; then
                echo "$PG_CONFIG_DIR"
                return 0
        fi
        local cfg_file cfg_dir cid src
        cfg_file="$(psql $PGHOST_ARGS -U "$USERNAME" -d postgres -tAc "SHOW config_file;" 2>/dev/null | tr -d '[:space:]')"
        [ -z "$cfg_file" ] && return 1
        cfg_dir="$(dirname "$cfg_file")"
        if [ -d "$cfg_dir" ]; then
                echo "$cfg_dir"
                return 0
        fi
        # In-container path (e.g. /var/lib/postgresql/data): find the docker
        # container mounting it and map to the host-side source dir. Only accept
        # a source that actually holds postgresql.conf - other containers may
        # mount the same path with an empty/decoy volume (e.g. the new cluster's
        # anonymous volume while its real PGDATA is a bind mount).
        for cid in $(docker ps -q 2>/dev/null); do
                src="$(docker inspect "$cid" --format '{{range .Mounts}}{{if eq .Destination "'"$cfg_dir"'"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)"
                if [ -n "$src" ] && [ -d "$src" ] && [ -f "$src/postgresql.conf" ]; then
                        echo "$src"
                        return 0
                fi
        done
        return 1
}

echo -e "\n\nPerforming postgresql.conf backup"
echo -e "--------------------------------------------\n"

CONFIG_DIR="$(detect_config_dir)"
if [ -n "$CONFIG_DIR" ]; then
        CONFIG_BACKUP_DIR="${FINAL_BACKUP_DIR}config"
        mkdir -p "$CONFIG_BACKUP_DIR"
        for CFG in postgresql.conf postgresql.auto.conf pg_hba.conf; do
                if [ -f "$CONFIG_DIR/$CFG" ]; then
                        cp -af "$CONFIG_DIR/$CFG" "$CONFIG_BACKUP_DIR/$CFG"
                        echo "   $CFG backed up"
                        echo "$(date +%Y-%m-%d_%H:%M:%S);Config backup of $CFG" >> "$LOG_FILE"
                fi
        done
else
        echo "Could not resolve the live config dir - skipping postgresql.conf backup"
        echo "  (set PG_CONFIG_DIR in pg_backup.config to the host dir holding the live postgresql.conf)"
fi

#############################################################
###### BACKUP DOCKER COMPOSE SCRIPT and OTHER SCRIPTS #######
#############################################################

echo -e "\n\nSaving Docker compose script: $DOCKER_COMPOSE_FILE -> from: $DOCKER_COMPOSE_DIR"
echo -e "----------------------------------------------------\n"

# copy backup/restore utilities
mkdir -p "${FINAL_BACKUP_DIR}utilities"
mkdir -p "${FINAL_BACKUP_DIR}IOTstack"
mkdir -p "${FINAL_BACKUP_DIR}crontabs"

cp -af "${DOCKER_COMPOSE_DIR}${DOCKER_COMPOSE_FILE}" "${FINAL_BACKUP_DIR}IOTstack/${DOCKER_COMPOSE_FILE}"

cp -af "${BACKUP_DIR}pg_backup.sh" "${FINAL_BACKUP_DIR}utilities/pg_backup.sh"
cp -af "${BACKUP_DIR}pg_backup_rotated.sh" "${FINAL_BACKUP_DIR}utilities/pg_backup_rotated.sh"
cp -af "${BACKUP_DIR}pg_backup.config" "${FINAL_BACKUP_DIR}utilities/pg_backup.config"
cp -af "${BACKUP_DIR}pg_maintenance.sh" "${FINAL_BACKUP_DIR}utilities/pg_maintenance.sh"
cp -af "${BACKUP_DIR}pg_restore.sh" "${FINAL_BACKUP_DIR}utilities/pg_restore.sh"
cp -af "${BACKUP_DIR}aspa_IngresCleanup.sh" "${FINAL_BACKUP_DIR}utilities/aspa_IngresCleanup.sh"
cp -af "${BACKUP_DIR}.pgpass" "${FINAL_BACKUP_DIR}utilities/.pgpass"
chmod 600 "${FINAL_BACKUP_DIR}utilities/.pgpass"

cp -a "${DOCKER_COMPOSE_DIR}aspa_backup" "${FINAL_BACKUP_DIR}IOTstack/aspa_backup" 2>/dev/null || true
# aspa_restore wrapper: cp -fL resolves the host symlink -> self-contained copy
# (portable to other hosts). Guarded: only copied when present on the host.
if [ -f "${DOCKER_COMPOSE_DIR}aspa_restore" ]; then
        cp -fL "${DOCKER_COMPOSE_DIR}aspa_restore" "${FINAL_BACKUP_DIR}IOTstack/aspa_restore"
        chmod +x "${FINAL_BACKUP_DIR}IOTstack/aspa_restore"
        echo "   aspa_restore wrapper copied to IOTstack/"
fi
cp -a /var/spool/cron/crontabs/root "${FINAL_BACKUP_DIR}crontabs/root" 2>/dev/null || true

echo -e "\nAll database backups complete!"
echo "$(date +%Y-%m-%d);All database backups complete!" >> "$LOG_FILE"

#######################
#### END of script ####
#######################