#!/bin/bash

# pg_backup_rotated.sh - Rotated cluster backup (daily/weekly/monthly) for aspaDB
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/pg_backup_rotated.sh
# **Version**: v1.1.0 | **Last Updated**: 2026-08-11
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.1.0 (2026-08-11): Fix -c config parsing, ${ECHO}, [ -z ] tests, mkdir -p,
#                        guard optional copies, symlink resolution, standard header
# - v1.0.0 (2023-01-17): Original rotated backup script (daily/weekly/monthly)
#
# Usage (cron):
#   8 3 * 3-6 * /mnt/data/aspadata/DB-Backup/pg_backup_rotated.sh
#
# Rotation logic (naming suffix is REQUIRED by the pruning rules - do not remove):
#   day-of-month == 1                  -> 2026-08-01-monthly  (prune all *-monthly)
#   day-of-week == DAY_OF_WEEK_TO_KEEP -> 2026-08-08-weekly   (prune > WEEKS_TO_KEEP*7 days)
#   otherwise                          -> 2026-08-09-daily    (prune > DAYS_TO_KEEP days)
#
# Produces the same directory layout as pg_backup.sh (globals.sql.gz,
# *.custom / *.sql.gz, utilities/, IOTstack/, crontabs/) so the restore
# tooling (restore-cluster.sh) works identically on either.

## Change to script folder (resolve symlinks so any link invocation works)
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
EXEDIR=$(dirname "$SCRIPT_PATH")
cd "$EXEDIR"

set -euo pipefail

###########################
####### LOAD CONFIG #######
###########################
CONFIG_FILE_PATH=""

while [ $# -gt 0 ]; do
        case $1 in
                -c)
                        CONFIG_FILE_PATH="$2"
                        shift 2
                        ;;
                *)
                        echo "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done

if [ -z "$CONFIG_FILE_PATH" ]; then
        CONFIG_FILE_PATH="${EXEDIR}/pg_backup.config"
fi

if [ ! -r "$CONFIG_FILE_PATH" ]; then
        echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
        exit 1
fi

source "$CONFIG_FILE_PATH"

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

# Host args: use -h when HOSTNAME is set (remote), else local socket
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "localhost" ]; then
        PGHOST_ARGS="-h $HOSTNAME"
else
        PGHOST_ARGS=""
fi

# PGPASSWORD env var overrides the passfile - unset it so the passfile is used
unset PGPASSWORD
export PGPASSFILE="$PGPWDFILE"

echo -e "\n** PARAMS: $HOSTNAME, $USERNAME, $PGPWDFILE, $LOG_DIR, $LOG_FILE **\n"

###########################
#### START THE BACKUPS ####
###########################

perform_backups()
{
        SUFFIX=$1
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

        if [[ $ENABLE_GLOBALS_BACKUPS == "yes" ]]; then
                echo "Globals backup"
                echo "$(date +%Y-%m-%d_%H:%M:%S);Globals backup" >> "$LOG_FILE"

                if ! pg_dumpall -g $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE" | gzip > "$FINAL_BACKUP_DIR/globals.sql.gz.in_progress"; then
                        echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
                        echo "$(date +%Y-%m-%d_%H:%M:%S);Failed to produce globals backup" >> "$LOG_FILE"
                else
                        mv "$FINAL_BACKUP_DIR/globals.sql.gz.in_progress" "$FINAL_BACKUP_DIR/globals.sql.gz"
                fi
        else
                echo "None"
        fi

        ###########################
        ### SCHEMA-ONLY BACKUPS ###
        ###########################

        SCHEMA_ONLY_CLAUSE=
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

        EXCLUDE_SCHEMA_ONLY_CLAUSE=
        for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }; do
                EXCLUDE_SCHEMA_ONLY_CLAUSE="$EXCLUDE_SCHEMA_ONLY_CLAUSE and datname !~ '$SCHEMA_ONLY_DB'"
        done

        FULL_BACKUP_QUERY="select datname from pg_database where not datistemplate and datallowconn $EXCLUDE_SCHEMA_ONLY_CLAUSE order by datname;"

        echo -e "\n\nPerforming full backups"
        echo -e "--------------------------------------------\n"

        for DATABASE in $(psql $PGHOST_ARGS -U "$USERNAME" -At -c "$FULL_BACKUP_QUERY" -d "passfile=$PGPWDFILE dbname=postgres"); do
                if [[ $ENABLE_PLAIN_BACKUPS == "yes" ]]; then
                        echo -e " Performing backup of $DATABASE in PLAIN sql format ..."
                        echo "$(date +%Y-%m-%d_%H:%M:%S);Plain backup of $DATABASE" >> "$LOG_FILE"

                        if ! pg_dump -Fp $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" | gzip > "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz.in_progress"; then
                                echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
                                echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Failed to produce plain backup database $DATABASE" >> "$LOG_FILE"
                        else
                                mv "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz.in_progress" "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz"
                        fi
                fi

                if [[ $ENABLE_CUSTOM_BACKUPS == "yes" ]]; then
                        echo -e " Performing backup of $DATABASE in CUSTOM format. Use pg_restore to recover data! ..."
                        echo "$(date +%Y-%m-%d_%H:%M:%S);Custom backup of $DATABASE in CUSTOM format. Use pg_restore to recover data!" >> "$LOG_FILE"

                        if ! pg_dump -Fc $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" -f "$FINAL_BACKUP_DIR/${DATABASE}.custom.in_progress"; then
                                echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE"
                                echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Failed to produce custom backup database $DATABASE" >> "$LOG_FILE"
                        else
                                mv "$FINAL_BACKUP_DIR/${DATABASE}.custom.in_progress" "$FINAL_BACKUP_DIR/${DATABASE}.custom"
                        fi
                fi
        done

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
        cp -af "${BACKUP_DIR}restore-cluster.sh" "${FINAL_BACKUP_DIR}utilities/restore-cluster.sh"
        cp -af "${BACKUP_DIR}aspa_IngresCleanup.sh" "${FINAL_BACKUP_DIR}utilities/aspa_IngresCleanup.sh"
        cp -af "${BACKUP_DIR}.pgpass" "${FINAL_BACKUP_DIR}utilities/.pgpass"
        chmod 600 "${FINAL_BACKUP_DIR}utilities/.pgpass"

        cp -a "${DOCKER_COMPOSE_DIR}aspa_backup" "${FINAL_BACKUP_DIR}IOTstack/aspa_backup" 2>/dev/null || true
        cp -a /var/spool/cron/crontabs/root "${FINAL_BACKUP_DIR}crontabs/root" 2>/dev/null || true

        echo -e "\nAll database backups complete!"
        echo "$(date +%Y-%m-%d);All database backups complete!" >> "$LOG_FILE"
}

###########################################
# CLEANUP MONTHLY BACKUPS
###########################################

DAY_OF_MONTH=$(date +%d)

if [ "$DAY_OF_MONTH" -eq 1 ]; then
        # Delete all expired monthly directories
        find "$BACKUP_DIR" -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'

        perform_backups "-monthly"

        exit 0
fi

###########################################
# CLEANUP WEEKLY BACKUPS
###########################################

DAY_OF_WEEK=$(date +%u) #1-7 (Monday-Sunday)
EXPIRED_DAYS=$(((WEEKS_TO_KEEP * 7) + 1))

if [ "$DAY_OF_WEEK" = "$DAY_OF_WEEK_TO_KEEP" ]; then
        # Delete all expired weekly directories
        find "$BACKUP_DIR" -maxdepth 1 -mtime "+$EXPIRED_DAYS" -name "*-weekly" -exec rm -rf '{}' ';'

        perform_backups "-weekly"

        exit 0
fi

###########################################
# CLEANUP DAILY BACKUPS
###########################################

# Delete daily backups older than DAYS_TO_KEEP days
find "$BACKUP_DIR" -maxdepth 1 -mtime "+$DAYS_TO_KEEP" -name "*-daily" -exec rm -rf '{}' ';'

perform_backups "-daily"
