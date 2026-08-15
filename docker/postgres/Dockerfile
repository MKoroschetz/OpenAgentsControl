# **Project**: aspaDB-workbench | **Path**: docker/postgres/Dockerfile
# **Version**: v2.0.0 | **Last Updated**: 2026-08-15 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# postgres+pgagent COMBINED image (architecture C, per docs/CORE-PLATFORM-UPGRADE.md §A.3).
# One container runs the PostgreSQL 17 server AND the pgagent scheduling daemon.
# Mirrors IOTstack folder: services/postgres/Dockerfile.
#
# Rationale: the runbook targets Debian 13 + PG 17 (Bullseye EOL 2026-08-31, PG 12 EOL).
# Postgres 17 ships as Debian 13's default package; postgresql-17-pgagent comes from PGDG.
# Data migration is logical dump/restore into a FRESH data dir (see docker/iotstack/README.md).

# Use Debian slim as the base image
FROM debian:13-slim

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Helper tools (minimal — no Recommends)
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    curl \
    nano \
    cron \
    openssh-client \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# PGDG repo (only for postgresql-17-pgagent; postgresql-17 itself is Debian 13 native)
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
    && sh -c 'echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN apt-get update

# PostgreSQL 17 server + pgagent (extension + daemon). Debian 13 bundles
# contrib (pg_stat_statements, hstore, cube, ...) inside postgresql-17 itself.
# Do NOT add postgresql-contrib: PGDG's metapackage resolves to default major
# 18 and would drag in postgresql-18 + PG-18 client tools.
RUN apt-get install -y --no-install-recommends \
      postgresql-17 \
      postgresql-17-pgagent \
    && rm -rf /var/lib/apt/lists/* \
    && /usr/lib/postgresql/17/bin/pg_config --version \
    # Postgresql postinst auto-creates + inits a default cluster during build.
    # Keep /etc/postgresql/17/main (config) but drop the throwaway DATA dir so
    # every container starts clean (entrypoint initdb's an empty PGDATA).
    && rm -rf /var/lib/postgresql/17/main /var/log/postgresql

# pgagent schema init (idempotent) + container entrypoint (starts PG, then runs pgagent)
COPY init-pgagent.sh /usr/local/bin/init-pgagent.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/init-pgagent.sh /usr/local/bin/entrypoint.sh

# The default cluster 17/main is created by the postgresql-17 package on /var/lib/postgresql/17/main
CMD ["/usr/local/bin/entrypoint.sh"]