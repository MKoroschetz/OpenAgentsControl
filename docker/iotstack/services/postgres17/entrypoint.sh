#!/bin/bash
#
# entrypoint.sh - wrapper: official postgres entrypoint + pgagent daemon.
# **Project**: aspaDB-workbench | **Path**: docker/iotstack/services/postgres17/entrypoint.sh
# **Version**: v1.2.0 | **Last Updated**: 2026-08-16
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.2.0 (2026-08-16): Fast shutdown on TERM/INT - postgres SIGTERM is a
#   SMART shutdown (waits for all connections to end); with active connections
#   (e.g. during/after a restore, or pgagent's own connection) it hangs past
#   docker stop's 10s grace, docker escalates to SIGKILL and the next start
#   runs crash recovery ("database system was not properly shut down"). The
#   official image uses pg_ctl stop -m fast; SIGINT is the equivalent here.
# - v1.1.0 (2026-08-16): Pass pg_stat_statements config via -c flags at server
#   start (shared_preload_libraries, max=10000, track=all) - the official image
#   does not set shared_preload_libraries by default (old Debian entrypoint did).
# - v1.0.0 (2026-08-16): Initial wrapper - runs the official
#   /usr/local/bin/docker-entrypoint.sh postgres in the background (handles
#   initdb, POSTGRES_* env, PGDATA chown), waits for readiness, ensures the
#   pgagent schema, then starts the pgagent daemon. TERM/INT trap for graceful
#   shutdown; the container stays alive via `wait` on the postgres PID.
#
# Architecture C: postgres server + pgagent daemon in ONE container
# (docs/CORE-PLATFORM-UPGRADE.md §A.3). Runs as root (USER root in Dockerfile)
# so the official entrypoint can chown the bind-mounted PGDATA; postgres and
# pgagent run as the postgres OS user (peer auth on the unix socket).

set -euo pipefail
exec 2>&1

POSTGRES_PID=""
PGAGENT_PID=""

shutdown() {
  echo "==> received TERM/INT - stopping pgagent and postgres"
  [ -n "$PGAGENT_PID" ] && kill -TERM "$PGAGENT_PID" 2>/dev/null || true
  # Fast shutdown (SIGINT): SIGTERM is a SMART shutdown that waits for ALL
  # connections to end - with active connections it hangs past docker stop's
  # 10s grace, docker escalates to SIGKILL, and the next start does crash
  # recovery. SIGINT terminates connections + checkpoints, like pg_ctl -m fast.
  [ -n "$POSTGRES_PID" ] && kill -INT "$POSTGRES_PID" 2>/dev/null || true
  [ -n "$POSTGRES_PID" ] && wait "$POSTGRES_PID" 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

echo "==> starting official postgres entrypoint in background (PGDATA=$PGDATA)"
# pg_stat_statements: the official image does NOT set shared_preload_libraries
# by default (the old Debian entrypoint did). Pass the library + tuning vars
# via -c so they load from first boot (no restart needed). The .so ships in
# postgres:17.11 (postgresql-contrib-17) - no Dockerfile change required.
/usr/local/bin/docker-entrypoint.sh postgres \
  -c shared_preload_libraries=pg_stat_statements \
  -c pg_stat_statements.max=10000 \
  -c pg_stat_statements.track=all &
POSTGRES_PID=$!

echo "==> waiting for postgres to become ready"
i=0
until pg_isready -q -h /var/run/postgresql -U postgres 2>/dev/null \
      || pg_isready -q -h localhost -U postgres 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "ERROR: postgres did not become ready within 60s" >&2
    exit 1
  fi
  sleep 1
done
echo "==> postgres is ready"

echo "==> ensuring pgagent schema (idempotent)"
su -s /bin/sh postgres -c /usr/local/bin/init-pgagent.sh

echo "==> starting pgagent daemon (background, host=/var/run/postgresql)"
su -s /bin/sh postgres -c '/usr/bin/pgagent -f -l 2 host=/var/run/postgresql dbname=postgres user=postgres' &
PGAGENT_PID=$!

echo "==> postgres17 up (postgres PID $POSTGRES_PID, pgagent PID $PGAGENT_PID)"
wait "$POSTGRES_PID"