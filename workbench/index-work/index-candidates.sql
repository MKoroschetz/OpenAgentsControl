-- ============================================================
-- index-candidates.sql - Find FK columns missing a supporting index
-- **Project**: aspaDB-workbench | **Path**: workbench/index-work/index-candidates.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-14): Initial missing-index candidate finder
--
-- For every foreign-key constraint in the `aspa` schema, check whether
-- the referencing column(s) are the leading column of any index.
-- Unindexed FK columns cause Seq Scans on JOINs and lock the referenced
-- table during DELETE/UPDATE. Top candidates for CREATE INDEX CONCURRENTLY.
--
-- NOTE: a composite index whose FIRST column matches the FK column still
-- counts as covered. This query ignores that nuance for simplicity.
--
-- Output: table, fk_column, constraint, has_index

SELECT c.conrelid::regclass::text            AS table,
       a.attname                              AS fk_column,
       c.conname                              AS constraint,
       EXISTS (
         SELECT 1
         FROM pg_index i
         JOIN pg_attribute ia ON ia.attrelid = i.indexrelid
         WHERE i.indrelid = c.conrelid
           AND i.indkey[0] = a.attnum
       )                                       AS has_index
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid
                  AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'f'
  AND c.connamespace = 'aspa'::regnamespace
  AND NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_attribute ia ON ia.attrelid = i.indexrelid
    WHERE i.indrelid = c.conrelid
      AND i.indkey[0] = a.attnum
  )
ORDER BY c.conrelid::regclass::text, a.attname;
