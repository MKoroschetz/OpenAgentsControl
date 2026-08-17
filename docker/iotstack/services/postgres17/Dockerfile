# **Project**: aspaDB-workbench | **Path**: docker/iotstack/services/postgres17/Dockerfile
# **Version**: v1.0.0 | **Last Updated**: 2026-08-16 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-16): Initial postgres17 service image - official
#   postgres:17.11 + pgagent daemon in the SAME container (architecture C, per
#   docs/CORE-PLATFORM-UPGRADE.md §A.3). PGDATA is versioned
#   (/var/lib/postgresql/17/data) so a future PG 18 upgrade keeps the mount
#   path stable and rollback stays possible.
#
# postgres+pgagent COMBINED image. One container runs the PostgreSQL 17 server
# AND the pgagent scheduling daemon. Mirrors the old services/postgres/Dockerfile
# intent but on the OFFICIAL postgres:17.11 base (Debian bookworm) instead of a
# hand-rolled Debian 13 image (docker/postgres/Dockerfile is superseded).

FROM postgres:17.11

# Versioned PGDATA - survives future PG 18 upgrade, enables rollback.
# The compose bind-mounts ./volumes/postgres17/data onto this path.
ENV PGDATA=/var/lib/postgresql/17/data

# postgres:17 images are Debian bookworm-based. The official image already
# configures the PGDG repo; the guard keeps the bookworm-pgdg entry present
# (idempotent) so postgresql-17-pgagent always resolves.
RUN if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then \
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
      && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
    fi \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-17-pgagent \
    && rm -rf /var/lib/apt/lists/*

# Generate the C.UTF-8 locale at the OS level so initdb/PG collation discovery
# registers it as "C.UTF-8" (uppercase). The official image only ships "C.utf8"
# (lowercase); the old dev cluster's dump uses COLLATE "C.UTF-8" and the named
# collation must exist or index creation fails ("collation does not exist").
RUN localedef -i C -c -f UTF-8 -A /usr/share/locale/locale.alias C.UTF-8

# pgagent schema init (idempotent) + wrapper entrypoint (starts the official
# entrypoint in the background, then the pgagent daemon).
COPY init-pgagent.sh /usr/local/bin/init-pgagent.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/init-pgagent.sh /usr/local/bin/entrypoint.sh

# The official postgres image ends with `USER postgres`. Run as root so the
# wrapper can let the official entrypoint chown the bind-mounted PGDATA and
# su to the postgres OS user for schema init + the pgagent daemon (peer auth).
USER root

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]