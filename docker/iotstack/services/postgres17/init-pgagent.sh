#!/bin/sh
#
# init-pgagent.sh - idempotently create the pgagent extension in the postgres DB.
# **Project**: aspaDB-workbench | **Path**: docker/iotstack/services/postgres17/init-pgagent.sh
# **Version**: v1.5.0 | **Last Updated**: 2026-08-16
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.5.0 (2026-08-16): Silence informational NOTICEs (client_min_messages =
#   warning) - the idempotent IF NOT EXISTS / IF EXISTS statements emit
#   "already exists, skipping" NOTICEs at every boot, which look like errors to
#   normal users. WARNING/ERROR and the verification SELECT output are kept.
# - v1.4.0 (2026-08-16): Create the "C.UTF-8" collation in pg_catalog (NOT
#   public) - pg_restore workers run with search_path=pg_catalog, so a public
#   collation is invisible to the dump's COLLATE "C.UTF-8" indexes. Also drop
#   the stale public-schema copy from v1.2.0/v1.3.0.
# - v1.3.0 (2026-08-16): Create the "C.UTF-8" collation in template1 (NOT just
#   postgres) - pg_collation is per-database, so new DBs only inherit it from
#   template1. Without it the dump's COLLATE "C.UTF-8" indexes fail in restored
#   DBs ("collation does not exist").
# - v1.2.0 (2026-08-16): Also create the "C.UTF-8" named collation (safety net
#   for the localedef in the Dockerfile - the dump's COLLATE "C.UTF-8" indexes
#   need it; pg_collation is a shared catalog so one CREATE covers all DBs).
# - v1.1.0 (2026-08-16): Also create pg_stat_statements extension (library is
#   preloaded via entrypoint -c flags; the extension object is created here).
# - v1.0.0 (2026-08-16): Initial version (idempotent CREATE EXTENSION pgagent).
#
# Runs as the postgres OS user via the unix socket (peer auth), so no password
# is needed. The pgagent daemon also connects as postgres over the socket.
# A dedicated least-privilege role can be enabled instead by following
# services/postgres/pgagent.sql (see docker/iotstack capture).

set -e

psql -v ON_ERROR_STOP=1 -d postgres <<'SQL'
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pgagent;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE COLLATION IF NOT EXISTS pg_catalog."C.UTF-8" (provider = libc, locale = 'C.UTF-8');
DROP COLLATION IF EXISTS public."C.UTF-8";
SELECT extname || ' ' || extversion AS installed FROM pg_extension WHERE extname IN ('pgagent', 'pg_stat_statements') ORDER BY extname;
SQL

# pg_collation is per-database: new DBs inherit collations from their template.
# pg_dump's CREATE DATABASE uses TEMPLATE = template0, so the collation must
# exist in template0 (and template1 for good measure) - in pg_catalog, because
# pg_restore workers resolve unqualified collation names via search_path=pg_catalog.
for db in template0 template1; do
  psql -v ON_ERROR_STOP=1 -d postgres -c "UPDATE pg_database SET datallowconn = true WHERE datname = '$db';" >/dev/null
  psql -v ON_ERROR_STOP=1 -d "$db" <<SQL
SET client_min_messages = warning;
CREATE COLLATION IF NOT EXISTS pg_catalog."C.UTF-8" (provider = libc, locale = 'C.UTF-8');
DROP COLLATION IF EXISTS public."C.UTF-8";
SQL
  psql -v ON_ERROR_STOP=1 -d postgres -c "UPDATE pg_database SET datallowconn = false WHERE datname = '$db';" >/dev/null
done