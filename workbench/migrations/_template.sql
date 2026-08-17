-- ============================================================
-- _template.sql - Migration template (copy to NNNN-kebab-case.sql)
-- **Project**: aspaDB-workbench | **Path**: workbench/migrations/_template.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-14): Initial migration template
--
-- RULES: idempotent, CONCURRENTLY in prod, in-object headers, record
-- index changes in ../index-work/findings.md. See README.md.

-- Example: add a missing index safely (idempotent + non-blocking)
CREATE INDEX CONCURRENTLY IF NOT EXISTS aspa.idx_example
    ON aspa.example_table (example_column);

-- Example: add a column only if it does not exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'aspa'
          AND table_name = 'example_table'
          AND column_name = 'example_column'
    ) THEN
        ALTER TABLE aspa.example_table ADD COLUMN example_column text;
    END IF;
END $$;
