#!/bin/bash

# pg_maintenance.sh - Daily routine maintenance (ANALYZE + VACUUM) for all databases
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/pg_maintenance.sh
# **Version**: v1.2.0 | **Last Updated**: 2026-08-16
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.2.0 (2026-08-16): Force unix-socket connection when running inside a
#   container (/.dockerenv) — the postgres17 container has NO host socket
#   mount, so host-side cron must invoke via `docker exec -u postgres`.
# - v1.1.0 (2026-08-11): Fix -c config parsing, ${ECHO}, [ -z ] tests, symlink
#                        resolution; loop ALL databases (was hardcoded aspadb);
#                        mkdir -p log dir; standard header
# - v1.0.0 (2023-01-17): Original routine maintenance script (aspadb only)
#
# Usage (cron):
#   # PG12 era (host socket mount): run directly on the DB host
#   8 2 * * * /mnt/data/aspadata/DB-Backup/pg_maintenance.sh
#   # PG17 era (postgres17 container, no host socket): run INSIDE the container
#   8 2 * * * docker exec -u postgres postgres17 /mnt/DB-Backup/pg_maintenance.sh
#
# Runs ANALYZE then VACUUM on every non-template, connectable database
# (same DB list as pg_restore.sh --maintenance-only). Invoke daily before
# the backup to optimize tables.

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

# Inside a container, ALWAYS connect over the unix socket (peer auth as the
# postgres OS user). TCP ports are host-side mappings (5434:5432) — a config
# HOSTNAME pointing at the host IP would hit the OLD container on 5432.
if [ -f /.dockerenv ]; then
        PGHOST_ARGS=""
        unset PGHOST
fi

# PGPASSWORD env var overrides the passfile - unset it so the passfile is used
unset PGPASSWORD
export PGPASSFILE="$PGPWDFILE"

# Ensure the log directory exists (first run on a fresh host)
mkdir -p "$LOG_DIR"

echo -e "\n** PARAMS: $HOSTNAME, $USERNAME, $PGPWDFILE, $LOG_DIR, $LOG_FILE **\n"

################################
#### START ANALYZE & VACUUM ####
################################

# All non-template, connectable databases (same list as pg_restore.sh --maintenance-only)
MAINT_DBS=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "select datname from pg_database where not datistemplate and datallowconn order by datname;" -d "passfile=$PGPWDFILE dbname=postgres")

echo -e "\nPerforming daily routine maintenance (ANALYZE + VACUUM) on: $MAINT_DBS"
echo -e "--------------------------------------------\n"

for DBNAME in $MAINT_DBS; do
        echo -e " Executing ANALYZE on DB $DBNAME ...\n"
        if ! psql $PGHOST_ARGS -U "$USERNAME" -b -c "ANALYZE;" -d "passfile=$PGPWDFILE dbname=$DBNAME"; then
                echo "[!!ERROR!!] Failed while executing ANALYZE $DBNAME" 1>&2
                echo "$(date +%Y-%m-%d_%H:%M:%S);ERROR with ANALYZE $DBNAME" >> "$LOG_FILE"
        else
                echo "$(date +%Y-%m-%d_%H:%M:%S);SUCCESS for ANALYZE $DBNAME" >> "$LOG_FILE"
                echo " >> SUCCESS for ANALYZE $DBNAME"
        fi

        echo -e "\n Executing VACUUM on DB $DBNAME ...\n"
        if ! psql $PGHOST_ARGS -U "$USERNAME" -b -c "VACUUM;" -d "passfile=$PGPWDFILE dbname=$DBNAME"; then
                echo "[!!ERROR!!] Failed while executing VACUUM on DB $DBNAME" 1>&2
                echo "$(date +%Y-%m-%d_%H:%M:%S);ERROR with VACUUM on DB $DBNAME" >> "$LOG_FILE"
        else
                echo "$(date +%Y-%m-%d_%H:%M:%S);SUCCESS for VACUUM on DB $DBNAME" >> "$LOG_FILE"
                echo " >> SUCCESS for VACUUM on DB $DBNAME"
        fi

        echo -e "\n"
done

#######################
#### END of script ####
#######################