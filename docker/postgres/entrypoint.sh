#!/bin/sh
#
# entrypoint.sh - start PostgreSQL 17, ensure pgagent schema, run pgagent daemon.
# **Project**: aspaDB-workbench | **Path**: docker/postgres/entrypoint.sh
# **Version**: v2.3.0 | **Last Updated**: 2026-08-15 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# Architecture C: postgres server + pgagent daemon run in the SAME container.
# The postgres cluster (17/main) is managed in the background; /usr/bin/pgagent
# runs in the FOREGROUND so it keeps the container alive (like the original
# `CMD ["/usr/bin/pgagent","-f",...]` intent).
#
# A data dir mounted into /var/lib/postgresql/17/main that is EMPTY (fresh
# deploy / restore target) is initialized automatically via pg_createcluster
# (Debian initdb), mirroring the official postgres image behaviour.

set -e
exec 2>&1

PGDATA=/var/lib/postgresql/17/main
PGCONF=/etc/postgresql/17/main/postgresql.conf

# Ensure the data dir (possibly a bind mount) is owned by the postgres OS user.
# NOTE: install -d defaults NEW/existing dirs to 0755 (invalid for postgres);
# force 0700 to match postgres' data-dir requirement on every boot.
install -d -o postgres -g postgres -m 0700 "$PGDATA"
owner="$(stat -c '%U' "$PGDATA")"
[ "$owner" != "postgres" ] && chown -R postgres:postgres "$PGDATA"

# Initialize a fresh (empty) data dir like the official image does.
# The /etc/postgresql/17/main config is baked into the image; a Debian cluster
# config exists even when the mounted data dir is empty.
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "==> PG_VERSION not found - initdb into $PGDATA"
  su -s /bin/sh postgres -c \
    '/usr/lib/postgresql/17/bin/initdb -D /var/lib/postgresql/17/main --auth-local=peer --auth-host=scram-sha-256'
fi

# Ensure the server listens beyond 127.0.0.1 (pgadmin / service clients reach
# it via the published port) and load pg_stat_statements (runbook S.A.7).
# Guard on ACTIVE (uncommented) options; Debian ships commented defaults.
if ! grep -Eq '^[[:space:]]*[^#]*listen_addresses[[:space:]]*=' "$PGCONF"; then
  sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PGCONF"
  grep -Eq '^[[:space:]]*[^#]*listen_addresses[[:space:]]*=' "$PGCONF" \
    || echo "listen_addresses = '*'" >> "$PGCONF"
fi
if ! grep -Eq '^[[:space:]]*[^#]*shared_preload_libraries[[:space:]]*=' "$PGCONF"; then
  echo "shared_preload_libraries = 'pg_stat_statements'" >> "$PGCONF"
fi

# Allow TCP clients (pgadmin + application clients over the published port /
# Docker network) to connect with SCRAM password auth - matches the official
# postgres image behaviour and the original aspaDB setup (env password).
PGHBA=/etc/postgresql/17/main/pg_hba.conf
if ! grep -Eq '^[[:space:]]*host[[:space:]]+all[[:space:]]+all[[:space:]]+0\.0\.0\.0/0' "$PGHBA"; then
  echo "host  all  all  0.0.0.0/0  scram-sha-256" >> "$PGHBA"
fi

echo "==> starting PostgreSQL cluster 17/main (PGDATA=$PGDATA)"
# Skip if already online (unclean docker stop leaves the server running and
# would otherwise fail the start on the next boot).
if ! pg_lsclusters -h 2>/dev/null | \
     awk '$1 ~ /^17/ && $2 ~ /^main/ { if ($4 ~ /^online/) online=1 } END { exit online ? 0 : 1 }'
then
  pg_ctlcluster 17 main start
fi

i=0
until pg_isready -q -h /var/run/postgresql -U postgres; do
  i=$((i + 1))
  [ "$i" -gt 30 ] && { echo "ERROR: postgres did not become ready"; pg_lsclusters; exit 1; }
  sleep 1
done
echo "==> postgres is ready"

echo "==> ensuring pgagent schema (idempotent)"
su -s /bin/sh postgres -c /usr/local/bin/init-pgagent.sh

# Graceful shutdown on `docker stop` (SIGTERM/SIGINT to PID 1 -> this shell).
# We do NOT exec pgagent: keeping this shell as PID 1 lets the trap stop the
# cluster cleanly so a restart never trips over a still-running server.
shutdown() {
  echo "==> received TERM/INT - stopping pgagent and cluster"
  pkill -f '/usr/bin/pgagent' 2>/dev/null || true
  pg_ctlcluster 17 main stop -m fast || true
  exit 0
}
trap shutdown TERM INT

echo "==> starting pgagent (foreground child, host=/var/run/postgresql)"
su -s /bin/sh postgres -c '/usr/bin/pgagent -f -l 2 host=/var/run/postgresql dbname=postgres user=postgres' &
wait