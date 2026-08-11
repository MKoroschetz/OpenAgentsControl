#!/bin/bash

# pg_restore.sh - Restore aspaDB databases from backup files
# Author: Manfred Koroschetz (original), improved 2026-08
#
# Usage:
#   pg_restore.sh -d <backupfile> [--drop] [--no-owner] [--no-privileges] [-c <config>]
#   pg_restore.sh -a <backupdir>  [--drop] [--no-owner] [--no-privileges] [-c <config>]
#
#   -d <backupfile>   Restore a single database from a backup file
#                     (e.g. aspadb.custom, aspadb.sql, aspadb.sql.gz)
#   -a <backupdir>    Restore ALL databases from a backup directory
#                     (globals first, then postgres, then every *.custom/*.sql.gz)
#   --drop            Drop the target database(s) first if they exist
#   --no-owner        Pass --no-owner to pg_restore (for cross-host restore)
#   --no-privileges   Pass --no-privileges to pg_restore (for cross-host restore)
#   --no-create       Restore INTO an existing database (no CREATE DATABASE).
#                     Required for the postgres system DB which always exists.
#   --maintenance-only  Skip restore; only run ANALYZE/VACUUM on all databases
#   -c <config>       Use an alternate config file (default: pg_backup.config)

## Change to script folder
EXEDIR=$(dirname "$0")
cd "$EXEDIR"

###########################
####### LOAD CONFIG #######
###########################
CONFIG_FILE=""
RESTOREALL="no"
DBNAME=""
DROP_FIRST="no"
NO_OWNER=""
NO_PRIVILEGES=""
NO_CREATE="no"
MAINTENANCE_ONLY="no"

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
                -a)
                        if [ -d "$2" ]; then
                                RESTOREALL="yes"
                                BACKUP_DIR_ARG="$2"
                                shift 2
                        else
                                echo -e "\n** Must provide a backup directory for -a!" 1>&2
                                echo -e "   Required: -a <backupdir>  (directory containing globals.sql.gz + database dumps)\n" 1>&2
                                exit 1
                        fi
                        ;;
                -d)
                        if [ -n "$2" ]; then
                                DB="$2"
                                RESTOREALL="no"
                                shift 2
                        else
                                echo -e "\n** Must provide DB backup filename!" 1>&2
                                echo -e "   Required: -d <dbname.ext> example: -d [<dbname>.custom|<dbname>.sql|<dbname>.sql.gz]" 1>&2
                                exit 1
                        fi
                        ;;
                --drop)
                        DROP_FIRST="yes"
                        shift 1
                        ;;
                --no-owner)
                        NO_OWNER="--no-owner"
                        shift 1
                        ;;
                --no-privileges)
                        NO_PRIVILEGES="--no-privileges"
                        shift 1
                        ;;
                --no-create)
                        NO_CREATE="yes"
                        shift 1
                        ;;
                --maintenance-only)
                        MAINTENANCE_ONLY="yes"
                        shift 1
                        ;;
                *)
                        echo "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done

# Load config if not provided via -c
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
#### PRE-RESTORE CHECKS ###
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
        LOG_FILE="${LOG_DIR}/pg_restore.log"
else
        LOG_FILE="${LOG_DIR}pg_restore.log"
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Host args: use -h when HOSTNAME is set (remote restore), else local socket
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "localhost" ]; then
        PGHOST_ARGS="-h $HOSTNAME"
else
        PGHOST_ARGS=""
fi

# PGPASSWORD env var overrides the passfile - unset it so the passfile is used
unset PGPASSWORD

# Export PGPASSFILE so both psql AND pg_restore use the passfile
# (pg_restore does not accept the passfile= conninfo parameter)
export PGPASSFILE="$PGPWDFILE"

echo -e "\n** PARAMS: HOST=$HOSTNAME, USER=$USERNAME, PGPWDFILE=$PGPWDFILE, LOG_FILE=$LOG_FILE, RESTOREALL=$RESTOREALL, DROP_FIRST=$DROP_FIRST, NO_CREATE=$NO_CREATE, NO_OWNER=$NO_OWNER, NO_PRIVILEGES=$NO_PRIVILEGES **\n"

###################################
#### HELPER FUNCTIONS #############
###################################

# drop_db <dbname> - drop a database if it exists
drop_db() {
        local db="$1"
        echo " >> Dropping existing database $db (if any) ..."
        psql $PGHOST_ARGS -U "$USERNAME" -d "passfile=$PGPWDFILE dbname=postgres" \
             -c "DROP DATABASE IF EXISTS \"$db\";" >/dev/null 2>&1
}

# restore_custom <file> <dbname> - restore a custom-format dump
restore_custom() {
  local file="$1" db="$2"
  echo -e " >> using <pg_restore> on $file\n"
  if [ "$NO_CREATE" = "yes" ]; then
    # Restore INTO an existing database (e.g. the postgres system DB).
    # Tolerant: existing objects (schemas, extensions) are expected and skipped.
    if ! pg_restore $PGHOST_ARGS -U "$USERNAME" -j 4 -d "$db" \
                    $NO_OWNER $NO_PRIVILEGES "$file"; then
      echo -e "\n** [!!ERROR!!] Restoring INTO existing $db. Check messages above **\n" 1>&2
      echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Restoring INTO existing $db" >> "$LOG_FILE"
      return 1
    fi
  else
    # --create -d postgres: pg_restore creates the DB named in the dump
    # The DB MUST NOT EXIST (or --drop was used)
    if ! pg_restore $PGHOST_ARGS -U "$USERNAME" -j 4 --create -d postgres --exit-on-error \
                    $NO_OWNER $NO_PRIVILEGES "$file"; then
      echo -e "\n** [!!ERROR!!] Restoring $db. Make sure the DB does NOT EXIST (or use --drop) **\n" 1>&2
      echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Restoring $db" >> "$LOG_FILE"
      return 1
    fi
  fi
  echo -e "\n** [SUCCESS] $db restored successfully\n" 1>&2
  echo "$(date +%Y-%m-%d_%H:%M:%S);[SUCCESS] Successfully restored $db" >> "$LOG_FILE"
  return 0
}

# restore_plain <file> <dbname> - restore a plain SQL dump (optionally gzipped)
restore_plain() {
  local file="$1" db="$2"
  echo -e " >> using <psql>\n"
  if [[ "$file" == *.gz ]]; then
    if ! gunzip < "$file" | psql $PGHOST_ARGS -U "$USERNAME" --set ON_ERROR_STOP=on -d "$db" -o "$LOG_DIR/restore_${db}.log"; then
      echo -e "\n** [!!ERROR!!] Restoring $db. Check $LOG_DIR/restore_${db}.log **\n" 1>&2
      echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Restoring $db" >> "$LOG_FILE"
      return 1
    fi
  else
    if ! psql $PGHOST_ARGS -U "$USERNAME" --set ON_ERROR_STOP=on -d "$db" -o "$LOG_DIR/restore_${db}.log" -f "$file"; then
      echo -e "\n** [!!ERROR!!] Restoring $db. Check $LOG_DIR/restore_${db}.log **\n" 1>&2
      echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Restoring $db" >> "$LOG_FILE"
      return 1
    fi
  fi
  echo -e "\n** [SUCCESS] $db restored successfully. Check LOG at $LOG_DIR/restore_${db}.log\n" 1>&2
  echo "$(date +%Y-%m-%d_%H:%M:%S);[SUCCESS] Successfully restored $db" >> "$LOG_FILE"
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
      echo "$(date +%Y-%m-%d_%H:%M:%S);[!!ERROR!!] Invalid backup file format: $ext" >> "$LOG_FILE"
      return 1
      ;;
  esac
}

################################
#### START ANALYZE & VACUUM ####
################################

run_maintenance_only() {
  local dbs="$1"
  echo -e "\nPerforming routine maintenance (ANALYZE + VACUUM) on: $dbs"
  echo -e "--------------------------------------------\n"

  for db in $dbs; do
    echo -e " Executing ANALYZE on DB $db ...\n"
    if ! psql $PGHOST_ARGS -U "$USERNAME" -b -c "ANALYZE;" -d "passfile=$PGPWDFILE dbname=$db"; then
          echo "[!!ERROR!!] Failed while executing ANALYZE $db" 1>&2
          echo "$(date +%Y-%m-%d_%H:%M:%S);ERROR with ANALYZE $db" >> "$LOG_FILE"
    else
          echo "$(date +%Y-%m-%d_%H:%M:%S);SUCCESS for ANALYZE $db" >> "$LOG_FILE"
          echo " >> SUCCESS for ANALYZE $db"
    fi

    echo -e "\n Executing VACUUM on DB $db ...\n"
    if ! psql $PGHOST_ARGS -U "$USERNAME" -b -c "VACUUM;" -d "passfile=$PGPWDFILE dbname=$db"; then
      echo "[ERROR] Failed while executing VACUUM on DB $db" 1>&2
      echo "$(date +%Y-%m-%d_%H:%M:%S);ERROR with VACUUM on DB $db" >> "$LOG_FILE"
    else
      echo "$(date +%Y-%m-%d_%H:%M:%S);SUCCESS for VACUUM on DB $db" >> "$LOG_FILE"
      echo " >> SUCCESS for VACUUM on DB $db"
    fi
  done
}

###################################
#### START THE RESTORE PROCESS ####
###################################

if [ "$MAINTENANCE_ONLY" = "yes" ]; then
  echo -e "\n=== MAINTENANCE ONLY (no restore) ===\n"
  MAINT_DBS=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "select datname from pg_database where not datistemplate and datallowconn order by datname;" -d "passfile=$PGPWDFILE dbname=postgres")
  run_maintenance_only "$MAINT_DBS"
  exit 0
fi

if [ "$RESTOREALL" = "yes" ]; then
  # ---------------- RESTORE ALL DATABASES ----------------
  echo -e "\n=== RESTORE ALL from $BACKUP_DIR_ARG ===\n"

  # 1. Restore globals (roles, tablespaces) - ignore "already exists" errors
  if [ -f "$BACKUP_DIR_ARG/globals.sql.gz" ]; then
    echo -e "\n[1/3] Restoring globals (roles) ..."
    gunzip < "$BACKUP_DIR_ARG/globals.sql.gz" | psql -U "$USERNAME" --set ON_ERROR_STOP=off -d postgres >/dev/null 2>&1
    echo "Globals restored (already-exists errors ignored)."
  else
    echo "WARNING: globals.sql.gz not found in $BACKUP_DIR_ARG - skipping roles restore" 1>&2
  fi

  # 2. Restore postgres database (system DB - must exist)
  if [ -f "$BACKUP_DIR_ARG/postgres.custom" ]; then
    echo -e "\n[2/3] Restoring postgres database ...\n"
    restore_custom "$BACKUP_DIR_ARG/postgres.custom" "postgres"
  elif [ -f "$BACKUP_DIR_ARG/postgres.sql.gz" ]; then
    echo -e "\n[2/3] Restoring postgres database ...\n"
    restore_plain "$BACKUP_DIR_ARG/postgres.sql.gz" "postgres"
  else
    echo "WARNING: postgres backup not found - skipping" 1>&2
  fi

  # 3. Restore every other database (skip postgres, template*, globals)
  echo -e "\n[3/3] Restoring remaining databases ...\n"
  for file in "$BACKUP_DIR_ARG"/*.custom; do
    [ -e "$file" ] || continue
    db=$(basename "$file" .custom)
    case "$db" in
      postgres|template0|template1) continue ;;
    esac
    echo -e "\n--- Restoring $db ---\n"
    restore_one "$file" "$db"
  done

  echo -e "\n=== RESTORE ALL COMPLETE ===\n"
  echo "$(date +%Y-%m-%d_%H:%M:%S);Restore ALL complete from $BACKUP_DIR_ARG" >> "$LOG_FILE"

else
  # ---------------- RESTORE SINGLE DATABASE ----------------
  if [ -z "$DB" ]; then
    echo -e "\n** Must provide a database backup file!" 1>&2
    echo -e "   Required: -d <dbname.ext>  [<dbname>.custom|<dbname>.sql|<dbname>.sql.gz]" 1>&2
    exit 1
  fi

  # Parse the file path
  FULLNAME="${DB##*/}"
  FPATH="${DB%/*}"
  [ "$FPATH" = "$DB" ] && FPATH="."
  DBNAME="${FULLNAME%.*}"
  FEXT="${FULLNAME##*.}"

  if [[ "$FEXT" == "gz" ]]; then
    DBNAME="${DBNAME%.*}"
  fi

  echo -e "\n Restoring $DBNAME from $FPATH/$FULLNAME ...\n"
  echo "$(date +%Y-%m-%d_%H:%M:%S);Restoring $DBNAME" >> "$LOG_FILE"

  restore_one "$FPATH/$FULLNAME" "$DBNAME"
  rc=$?

  if [ $rc -ne 0 ]; then
    echo -e "\n** [!!ERROR!!] Restore of $DBNAME FAILED **\n" 1>&2
    exit 1
  fi
fi

################################
#### START ANALYZE & VACUUM ####
################################

# Only run maintenance on the restored database(s)
if [ "$RESTOREALL" = "yes" ]; then
  MAINT_DBS=$(psql $PGHOST_ARGS -U "$USERNAME" -At -c "select datname from pg_database where not datistemplate and datallowconn order by datname;" -d "passfile=$PGPWDFILE dbname=postgres")
else
  MAINT_DBS="$DBNAME"
fi

run_maintenance_only "$MAINT_DBS"

echo -e "\n"
echo "Restore complete. Log: $LOG_FILE"

#######################
#### END of script ####
#######################