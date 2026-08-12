#!/bin/bash

# aspa_IngresCleanup.sh - Run the aspa "IngresCleanup" function (harvest-season cleanup)
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/aspa_IngresCleanup.sh
# **Version**: v1.1.0 | **Last Updated**: 2026-08-11
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.1.0 (2026-08-11): Fix -c parsing (was double-sourced: custom config then
#                        default overrode it), simplify PGFUNCTIONTORUN quoting,
#                        ${ECHO}, [ -z ] tests, quoted source, add SUCCESS logging
#                        and non-zero exit on failure; symlink resolution;
#                        mkdir -p log dir; standard header
# - v1.0.0 (2022-10-02): Modified to use UNIX Socket (MK)
#
# Usage (cron - see A4: recommend keeping APP functions in pg_agent, not cron):
#   0,15,30,45 7-20 * 3-5 * /mnt/data/aspadata/DB-Backup/aspa_IngresCleanup.sh
#
# Executes: select * from aspa."IngresCleanup"();
# NOTE: File/function name "Ingres" vs pg_agent job name "Ingress" - see workbench
#       findings; kept as-is because the function is the live aspa object name.

## Change to script folder (resolve symlinks so any link invocation works)
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
EXEDIR=$(dirname "$SCRIPT_PATH")
cd "$EXEDIR"

set -euo pipefail

################################################
####### Run aspa-Ingress Cleanup process #######
################################################

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
        LOG_FILE="${LOG_DIR}/pg_IngresCleanup.log"
else
        LOG_FILE="${LOG_DIR}pg_IngresCleanup.log"
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

# Ensure the log directory exists (first run on a fresh host)
mkdir -p "$LOG_DIR"

echo -e "\n** PARAMS: $HOSTNAME, $USERNAME, $PGPWDFILE, $LOG_DIR, $LOG_FILE **\n"

###############################################
#### Run pg Function aspa."IngresCleanup"  ####
###############################################

PGFUNCTIONTORUN='select * from aspa."IngresCleanup"();'
echo -e "\n** PG_FUNCTION: $PGFUNCTIONTORUN **\n"

if ! psql $PGHOST_ARGS -U "$USERNAME" -At -c "$PGFUNCTIONTORUN" -d "passfile=$PGPWDFILE dbname=aspadb" >> "$LOG_FILE"; then
        echo "[!!ERROR!!] Unable to execute $PGFUNCTIONTORUN" 1>&2
        echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Unable to execute $PGFUNCTIONTORUN" >> "$LOG_FILE"
        exit 1
else
        echo "$(date +%Y-%m-%d_%H:%M:%S);SUCCESS - executed $PGFUNCTIONTORUN" >> "$LOG_FILE"
        echo " >> SUCCESS - executed $PGFUNCTIONTORUN"
fi
