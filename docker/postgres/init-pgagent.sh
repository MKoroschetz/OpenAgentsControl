#!/bin/sh
#
# init-pgagent.sh - idempotently create the pgagent extension in the postgres DB.
# **Project**: aspaDB-workbench | **Path**: docker/postgres/init-pgagent.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-15 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# Runs as the postgres OS user via the unix socket (peer auth), so no password
# is needed. The pgagent daemon also connects as postgres over the socket.
# A dedicated least-privilege role can be enabled instead by following
# services/postgres/pgagent.sql (see docker/iotstack capture).

set -e

psql -v ON_ERROR_STOP=1 -d postgres <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgagent;
SELECT extname || ' ' || extversion AS installed FROM pg_extension WHERE extname = 'pgagent';
SQL