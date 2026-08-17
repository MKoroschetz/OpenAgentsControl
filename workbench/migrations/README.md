# Migrations
**Project**: aspaDB-workbench | **Path**: workbench/migrations/README.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-14 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.0.0 (2026-08-14): Initial migrations scaffold

Schema-evolution scripts for the `aspaDB` database. This folder complements
`../index-work/` (runtime index diagnosis) by holding versioned, repeatable
schema changes.

## Rules
- One logical change per file, named `NNNN-kebab-case.sql` (e.g. `0001-add-foo-index.sql`).
- **Idempotent**: use `CREATE INDEX CONCURRENTLY IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `DO $$ ...`.
- **Production**: never block writes — prefer `CREATE INDEX CONCURRENTLY`.
- Record performance-impacting changes (esp. indexes) in `../index-work/findings.md`
  with before/after `EXPLAIN (ANALYZE, BUFFERS)` timings.
- Carry the standard SQL header + an in-object header (see `_template.sql`).
- Always run as a role with the needed privileges, not the read-only `reporter`.

## Running
Migrations are plain SQL; apply with psql:
```bash
psql -v dbname=aspadb -f migrations/0001-add-foo-index.sql
```
Use the workbench `reporter`-capable admin connection (not the reporting role).
