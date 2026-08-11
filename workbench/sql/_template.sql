-- ============================================================
-- _template.sql - SQL script template with standard header
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/_template.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-11
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-11): Initial template
--
-- ## Usage
-- Copy this file to a kebab-case name (e.g. my-feature.sql), fill in the
-- header fields, and replace the example objects below with real ones.
--
-- ## Header rules
-- - Version: MAJOR.MINOR.PATCH (breaking.feature.fix)
-- - Author: "Manfred Koroschetz" (human) | "Manfred Koroschetz, AI" (collaborative)
--          | "Manfred Koroschetz/AI" (AI-assisted with review)
-- - License: exact string MIT (SPDX identifier)
-- - Every object gets its own in-DB header (see examples below)
-- ============================================================

-- ============================================================
-- EXAMPLE 1: FUNCTION (header inside $$ body - survives in pg_proc.prosrc)
-- ============================================================
CREATE OR REPLACE FUNCTION aspa.example_function()
RETURNS integer
LANGUAGE plpgsql
AS $$
-- **Object**: aspa.example_function | **Version**: v1.0.0 | **Last Updated**: 2026-08-11
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
BEGIN
    RETURN 1;
END;
$$;

-- ============================================================
-- EXAMPLE 2: VIEW (header via COMMENT ON - comments in SELECT are stripped)
-- ============================================================
CREATE OR REPLACE VIEW aspa.example_view AS
SELECT 1 AS col;

COMMENT ON VIEW aspa.example_view IS
'**Project**: aspaDB-workbench | **Object**: aspa.example_view
**Version**: v1.0.0 | **Last Updated**: 2026-08-11
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT';

-- ============================================================
-- EXAMPLE 3: TRIGGER FUNCTION (header inside $$ body)
-- ============================================================
CREATE OR REPLACE FUNCTION aspa.example_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
-- **Object**: aspa.example_trigger_fn | **Version**: v1.0.0 | **Last Updated**: 2026-08-11
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
BEGIN
    RETURN NEW;
END;
$$;

-- ============================================================
-- EXAMPLE 4: TRIGGER (header via COMMENT ON TRIGGER)
-- ============================================================
CREATE TRIGGER example_trigger
AFTER INSERT ON aspa.example_view
FOR EACH ROW EXECUTE FUNCTION aspa.example_trigger_fn();

COMMENT ON TRIGGER example_trigger ON aspa.example_view IS
'**Project**: aspaDB-workbench | **Object**: aspa.example_trigger
**Version**: v1.0.0 | **Last Updated**: 2026-08-11
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT';

-- ============================================================
-- EXAMPLE 5: PROCEDURE (header inside $$ body)
-- ============================================================
CREATE OR REPLACE PROCEDURE aspa.example_procedure()
LANGUAGE plpgsql
AS $$
-- **Object**: aspa.example_procedure | **Version**: v1.0.0 | **Last Updated**: 2026-08-11
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
BEGIN
    NULL;
END;
$$;

-- ============================================================
-- VERIFICATION QUERY (optional - find all objects with version headers)
-- ============================================================
-- SELECT c.relname, d.description
-- FROM pg_description d
-- JOIN pg_class c ON c.oid = d.objoid
-- WHERE d.objsubid = 0 AND d.description LIKE '**Version**:%';