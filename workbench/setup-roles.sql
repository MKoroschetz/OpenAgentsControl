-- ============================================================
-- setup-roles.sql - Create the read-only 'reporter' role
-- **Project**: aspaDB-workbench | **Path**: workbench/setup-roles.sql
-- **Version**: v1.1.0 | **Last Updated**: 2026-08-11
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.1.0 (2026-08-11): Standard header; reporter hardening (REVOKE CREATE)
-- - v1.0.0 (2026-08-06): Initial role setup script
--
-- HOW TO RUN (as a superuser - e.g. the postgres backup account):
--
--   Set the password first (never type it into the script):
--     export PGPASSWORD='your-strong-password'    # SUPERUSER password (auth)
--     export REPORTER_PW='reporter-password'      # reporter role password
--
--   Then run with psql:
--     psql -v dbname=yourdb -f setup-roles.sql
--
--   NOTE: PGPASSWORD is used BOTH for the psql connection AND (via \getenv)
--   to set the reporter password. If your superuser password differs from
--   the desired reporter password, set PGPASSWORD to the reporter password
--   and authenticate the superuser another way (e.g. a .pgpass entry, SSH
--   tunnel to a socket, or peer auth as the postgres OS user).
--
--   Alternatively, the remote variant used in the workbench reads the
--   reporter password from REPORTER_PW (see workbench/.env + README).
--
-- SAFETY: This script is idempotent - safe to re-run. It does not
-- drop or modify anything that already exists.

-- Load password from the PGPASSWORD environment variable.
-- Fails loudly if it is not set - prevents accidental blank passwords.
\getenv pw PGPASSWORD

-- Fail if the database name was not provided.
\if :{?dbname}
\else
  \echo 'ERROR: you must pass the database name: psql -v dbname=yourdb -f setup-roles.sql'
  \quit 1
\endif

-- 1. Create the role (skips if it already exists)
-- NOTE: psql does not interpolate variables inside dollar-quoted strings,
-- so use the \gexec pattern instead of a DO $$ block.
SELECT format('CREATE ROLE reporter LOGIN PASSWORD %L', :'pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reporter')
\gexec

-- 2. Optionally re-set the password (uncomment to rotate it)
-- ALTER ROLE reporter WITH PASSWORD :'pw';

-- 3. Database access
GRANT CONNECT ON DATABASE :dbname TO reporter;

-- 4. Schema usage - the app data lives in the 'aspa' schema (85 tables).
--    'public' holds a few scratch tables; reporter gets USAGE there too.
GRANT USAGE ON SCHEMA aspa TO reporter;
GRANT USAGE ON SCHEMA public TO reporter;

-- 5. Read access on current tables
GRANT SELECT ON ALL TABLES IN SCHEMA aspa TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporter;

-- 6. Read access on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA aspa GRANT SELECT ON TABLES TO reporter;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO reporter;

-- 7. Allow reading sequence values (needed if any report does nextval/currval)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA aspa TO reporter;
ALTER DEFAULT PRIVILEGES IN SCHEMA aspa GRANT SELECT ON SEQUENCES TO reporter;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO reporter;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO reporter;

-- 8. Harden: reporter must be READ-ONLY. By default PostgreSQL grants
--    CREATE on the public schema to PUBLIC; without this revoke, reporter
--    could create objects there. aspa has no PUBLIC CREATE grant (owner-only).
REVOKE CREATE ON SCHEMA public FROM reporter;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

\echo ''
\echo 'Reporter role is set up. Verify with:'
\echo '  SELECT rolname FROM pg_roles WHERE rolname = ''reporter'';'
\echo '  \du reporter'
