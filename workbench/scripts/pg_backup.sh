#!/bin/bash

# pg_backup.sh - Full cluster backup for aspaDB
# Author: Manfred Koroschetz (original), improved 2026-08
#
# Usage:
#   pg_backup.sh [-c <config>] [-m <suffix>] [--verify]
#
#   -c <config>   Use an alternate config file (default: pg_backup.config)
#   -m <suffix>   Append a suffix to the backup directory name (e.g. -manual)
#   --verify      After each dump, verify integrity with pg_restore -l (custom) / gzip -t (plain)
#
# Produces per database:
#   <db>.custom   - custom format (restore-able with pg_restore) [if ENABLE_CUSTOM_BACKUPS=yes]
#   <db>.sql.gz   - gzipped plain SQL (portable, greppable)      [if ENABLE_PLAIN_BACKUPS=yes]
# Plus:
#   globals.sql.gz - roles/tablespaces (pg_dumpall -g)

# NOTE: modified to use UNIX Socket to execute. 02-10-2022 - MK!

## Change to script folder
EXEDIR=$(dirname "$0")
cd "$EXEDIR"

###########################
####### LOAD CONFIG #######
###########################
SUFFIX=""
CONFIG_FILE=""
VERIFY="no"

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
        SCRIPTPATH=$(cd "${0%/*}" && pwd -P)
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

                if ! pg_dump -Fp $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" | gzip > "$FINAL_BACKUP_DIR/${DATABASE}.sql.gz.in_progress"; then
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

                if ! pg_dump -Fc $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=$DATABASE" -f "$FINAL_BACKUP_DIR/${DATABASE}.custom.in_progress"; then
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
cp -a /var/spool/cron/crontabs/root "${FINAL_BACKUP_DIR}crontabs/root" 2>/dev/null || true

echo -e "\nAll database backups complete!"
echo "$(date +%Y-%m-%d);All database backups complete!" >> "$LOG_FILE"

#######################
#### END of script ####
#######################