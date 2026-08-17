#!/bin/bash

# aspa_restore.sh - host-level restore wrapper for the aspaDB postgres container.
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/aspa_restore.sh
# **Version**: v1.2.0 | **Last Updated**: 2026-08-17 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.2.0 (2026-08-17): Fixed the backup pg_restore.sh version check - it
#   required the -x (executable) bit, so a v2.3.0+ copy that lost its exec bit
#   during a prod->dev transfer (scp/zip/rsync without -a) was falsely rejected
#   as "too old". The check now parses the **Version**: header and compares
#   against v2.3.0 (grep for --skip-pgagent-restart kept as fallback for
#   non-standard copies), chmod +x's a usable copy, and reports the found
#   version in the warning. Also: .pgpass lookup now also checks $HOME/.pgpass
#   and ASPA_RESTORE_PGPASS, and generates a temp .pgpass from PGPASSWORD when
#   set (the backup's utilities/.pgpass is a hidden file that transfers often
#   drop). Cleaner no-args usage message (was the cryptic "${1:?}" "1:" output).
# - v1.1.1 (2026-08-16): Fixed the failure exit-code capture - `if ! cmd; then
#   rc=$?` records the NEGATED status (always 0), so a failed restore was
#   reported as "exit 0" and the wrapper exited 0 (success). Now uses
#   `cmd || rc=$?` which captures the real status.
# - v1.1.0 (2026-08-16): Two fixes found during the dev-host test setup:
#   (1) the backup's utilities/pg_restore.sh must support --skip-pgagent-restart
#   (v2.3.0+), not just reconcile_pgagent (v2.2.0) - the wrapper always passes
#   the flag, so a v2.2.0 copy would fail on the unknown option; the fallback
#   check now greps for the flag. (2) PORT resolution - side-by-side containers
#   publish non-5432 host ports (dev postgres17 on 5434); the wrapper now
#   auto-detects the published port via `docker port` (ASPA_RESTORE_PORT
#   overrides), passes it in the temp config (pg_restore.sh v2.4.0 honors it)
#   and rewrites the passfile's port field to match.
# - v1.0.0 (2026-08-16): Initial version - host-level wrapper (like aspa_backup
#   for backups): stops the postgres container, starts it, runs pg_restore.sh
#   from the backup's utilities/ against it (host pg-client over TCP), then
#   restarts the container so the pgagent daemon re-registers fresh.
#
# Usage:
#   aspa_restore.sh <backup-dir> [pg_restore args...]
#
#   <backup-dir>   Backup directory (as produced by pg_backup.sh) containing
#                  globals.sql.gz + *.custom dumps + utilities/pg_restore.sh
#   [args...]      Extra pg_restore.sh args (e.g. --no-owner --no-privileges)
#
# Flow:
#   1. docker stop <container>  - postgres + pgagent stop cleanly (pgagent stop
#      is implicit: it runs inside the container, the entrypoint trap stops it)
#   2. docker start <container> - postgres + pgagent up (pg_restore needs a live
#      server; the container's entrypoint always starts both)
#   3. Run utilities/pg_restore.sh against it (host pg-client, TCP 127.0.0.1)
#   4. docker restart <container> - pgagent re-registers with a fresh jagid
#
# Requirements: docker + host pg-client (psql/pg_restore). The backup's
# utilities/.pgpass must hold the postgres password for localhost:5432 (the
# wrapper rewrites localhost -> 127.0.0.1 for the TCP connection). If the
# backup's .pgpass is missing (transfers often drop hidden files), the wrapper
# also checks $HOME/.pgpass, ASPA_RESTORE_PGPASS, or generates one from the
# PGPASSWORD env var.
#
# NOTE: app containers that reconnect to postgres after step 2 may briefly hold
# connections; pg_restore.sh v2.3.0 terminates them (pg_terminate_backend)
# before DROP DATABASE, so they cannot block the restore.
#
# Install: symlink on the host like aspa_backup, e.g.
#   ln -s /path/to/workbench/scripts/aspa_restore.sh /root/IOTstack/aspa_restore

set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Container: ASPA_RESTORE_CONTAINER env override, else aspadb (final name),
# else aspaDB (compose historical name).
CONTAINER="${ASPA_RESTORE_CONTAINER:-aspadb}"
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        if docker inspect "aspaDB" >/dev/null 2>&1; then
                CONTAINER="aspaDB"
        else
                echo "ERROR: container '$CONTAINER' not found (set ASPA_RESTORE_CONTAINER)" 1>&2
                exit 1
        fi
fi


if [ $# -lt 1 ]; then
        echo "Usage: aspa_restore.sh <backup-dir> [pg_restore args...]" 1>&2
        exit 2
fi
BACKUP_DIR="$1"
BACKUP_DIR="$(readlink -f "$BACKUP_DIR")"
shift

[[ -d "$BACKUP_DIR" ]] || {
  echo "ERROR: backup directory not found: $BACKUP_DIR"
  exit 1
}

# version_ge <ver> <min> - true if ver >= min (dotted numeric comparison)
version_ge() {
        local v="$1" min="$2" i a b
        IFS='.' read -ra va <<< "$v"
        IFS='.' read -ra mb <<< "$min"
        for i in 0 1 2; do
                a="${va[$i]:-0}"
                b="${mb[$i]:-0}"
                if [ "$a" -gt "$b" ]; then return 0; fi
                if [ "$a" -lt "$b" ]; then return 1; fi
        done
        return 0
}

# Locate pg_restore.sh: prefer the backup's utilities copy (v2.3.0+ carries the
# pgagent reconciliation AND the --skip-pgagent-restart flag this wrapper always
# passes), else fall back to the script next to this wrapper.
RESTORE_SCRIPT="$BACKUP_DIR/utilities/pg_restore.sh"
BACKUP_RESTORE_VERSION=""
if [ -f "$RESTORE_SCRIPT" ]; then
        BACKUP_RESTORE_VERSION=$(sed -n 's/.*\*\*Version\*\*: v\([0-9][0-9.]*\).*/\1/p' "$RESTORE_SCRIPT" 2>/dev/null | head -1)
fi
if [ -n "$BACKUP_RESTORE_VERSION" ] && version_ge "$BACKUP_RESTORE_VERSION" "2.3.0"; then
        # v2.3.0+ carries --skip-pgagent-restart. Transfers can drop the exec
        # bit, so ensure it's executable before invoking it directly.
        chmod +x "$RESTORE_SCRIPT" 2>/dev/null || true
        if [ ! -x "$RESTORE_SCRIPT" ]; then
                echo "WARNING: $BACKUP_DIR/utilities/pg_restore.sh is v$BACKUP_RESTORE_VERSION but not executable (chmod failed)." 1>&2
                echo "         Using $SCRIPT_DIR/pg_restore.sh instead." 1>&2
                RESTORE_SCRIPT="$SCRIPT_DIR/pg_restore.sh"
        fi
elif [ -f "$RESTORE_SCRIPT" ] && grep -q "skip-pgagent-restart" "$RESTORE_SCRIPT" 2>/dev/null; then
        # No version header (non-standard copy) but the flag is present - usable.
        chmod +x "$RESTORE_SCRIPT" 2>/dev/null || true
        if [ ! -x "$RESTORE_SCRIPT" ]; then
                echo "WARNING: $BACKUP_DIR/utilities/pg_restore.sh not executable (chmod failed)." 1>&2
                echo "         Using $SCRIPT_DIR/pg_restore.sh instead." 1>&2
                RESTORE_SCRIPT="$SCRIPT_DIR/pg_restore.sh"
        fi
else
        echo "WARNING: $BACKUP_DIR/utilities/pg_restore.sh missing or too old (needs v2.3.0+, found ${BACKUP_RESTORE_VERSION:-none})." 1>&2
        echo "         Using $SCRIPT_DIR/pg_restore.sh instead." 1>&2
        RESTORE_SCRIPT="$SCRIPT_DIR/pg_restore.sh"
fi

# Resolve the host port the container publishes for 5432/tcp. Side-by-side
# containers use non-5432 host ports (dev postgres17 on 5434); the final
# cutover container publishes 5432. ASPA_RESTORE_PORT overrides auto-detection.
PORT="${ASPA_RESTORE_PORT:-}"
if [ -z "$PORT" ]; then
        PORT=$(docker port "$CONTAINER" 5432/tcp 2>/dev/null | head -1 | sed 's/.*://')
fi
[ -z "$PORT" ] && PORT="5432"

# Restore config + passfile: connect over TCP to the container's published port.
# The utilities config defaults to the unix socket (not present on the host) and
# "localhost" would also select the socket path in pg_restore.sh, so use
# 127.0.0.1 and rewrite the passfile's localhost entries (host AND port) to match.
PGPASS="${ASPA_RESTORE_PGPASS:-}"
if [ -z "$PGPASS" ] || [ ! -f "$PGPASS" ]; then
        PGPASS="$BACKUP_DIR/utilities/.pgpass"
fi
[ -f "$PGPASS" ] || PGPASS="$SCRIPT_DIR/.pgpass"
[ -f "$PGPASS" ] || PGPASS="$HOME/.pgpass"
TMP_CONFIG=$(mktemp)
TMP_PGPASS=$(mktemp)
if [ -f "$PGPASS" ]; then
        sed -E "s/^localhost:([0-9]+|\*):/127.0.0.1:$PORT:/" "$PGPASS" > "$TMP_PGPASS"
elif [ -n "${PGPASSWORD:-}" ]; then
        # No passfile anywhere - generate one from PGPASSWORD (host:port:db:user:pass)
        echo "127.0.0.1:$PORT:*:postgres:$PGPASSWORD" > "$TMP_PGPASS"
        echo "WARNING: no .pgpass found - using PGPASSWORD env var (generated temp passfile)." 1>&2
else
        echo "ERROR: no .pgpass found (looked in $BACKUP_DIR/utilities/, $SCRIPT_DIR/, $HOME/;" 1>&2
        echo "       set ASPA_RESTORE_PGPASS or PGPASSWORD to provide credentials)." 1>&2
        rm -f "$TMP_CONFIG" "$TMP_PGPASS"
        exit 1
fi
chmod 600 "$TMP_PGPASS"
echo "HOSTNAME=127.0.0.1" > "$TMP_CONFIG"
echo "PORT=$PORT" >> "$TMP_CONFIG"
echo "PGPWDFILE=$TMP_PGPASS" >> "$TMP_CONFIG"

# Never leave the container stopped - restart it on any exit path.
cleanup() {
        rm -f "$TMP_CONFIG" "$TMP_PGPASS"
        if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "false" ]; then
                docker start "$CONTAINER" >/dev/null 2>&1 || true
        fi
}
trap cleanup EXIT

echo "=============================================="
echo " ASPA RESTORE"
echo "=============================================="
echo " Container : $CONTAINER (host port $PORT)"
echo " Backup    : $BACKUP_DIR"
echo " Restore   : $RESTORE_SCRIPT"
echo "=============================================="

echo ""
echo "[1/4] Stopping $CONTAINER (postgres + pgagent) ..."
docker stop "$CONTAINER" >/dev/null

echo "[2/4] Starting $CONTAINER (pg_restore needs a live server) ..."
docker start "$CONTAINER" >/dev/null

echo "      Waiting for postgres readiness ..."
i=0
until docker exec "$CONTAINER" pg_isready -q -U postgres -h /var/run/postgresql 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -gt 60 ]; then
                echo "ERROR: postgres did not become ready within 60s" 1>&2
                exit 1
        fi
        sleep 1
done
echo "      postgres ready."

echo ""
echo "[3/4] Running pg_restore.sh ..."
rc=0
"$RESTORE_SCRIPT" "$BACKUP_DIR" -c "$TMP_CONFIG" --skip-pgagent-restart "$@" || rc=$?
if [ "$rc" -ne 0 ]; then
        echo ""
        echo "** [!!ERROR!!] Restore FAILED (exit $rc) - see messages above **" 1>&2
        echo "** Restarting $CONTAINER anyway (data may be partial). **" 1>&2
        docker restart "$CONTAINER" >/dev/null 2>&1 || true
        exit $rc
fi

echo ""
echo "[4/4] Restarting $CONTAINER so pgagent re-registers fresh ..."
docker restart "$CONTAINER" >/dev/null
echo ""
echo "** [SUCCESS] Restore complete - $CONTAINER running with the restored data **"
exit 0