<!-- Context: standards/file-headers | Priority: critical | Version: 1.0 | Updated: 2026-08-11 -->

# File Header Standards

**Purpose**: Every file created or touched in this project carries a standard version header. Applies to ALL document types (`.md`, `.sh`, `.sql`, `.psql`, `.py`, `.js`, `.ts`, config files, etc.). For undefined document types, apply the header using the same field structure, adapted to the file's comment syntax.

**Source of truth**: This standard is derived from the header convention in `/CLAUDE.md` (gtc-uFC project, v1.6.0) and adapted for aspaDB-workbench.

---

## Markdown Header (`.md` files)

```markdown
# Title
**Project**: aspaDB-workbench | **Path**: /path/to/file
**Version**: vX.Y.Z | **Last Updated**: YYYY-MM-DD
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- vX.Y.Z (date): Description
```

## Shell Script Header (`.sh` files)

```bash
#!/bin/bash

# script_name.sh - Brief description
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/script_name.sh
# **Version**: vX.Y.Z | **Last Updated**: YYYY-MM-DD
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - vX.Y.Z (date): Description
```

## SQL / PSQL Header (`.sql`, `.psql` files)

### File header (top of file)

```sql
-- ============================================================
-- script_name.sql - Brief description
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/script_name.sql
-- **Version**: vX.Y.Z | **Last Updated**: YYYY-MM-DD
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - vX.Y.Z (date): Description
-- ============================================================
```

### In-DB object headers (survive inside PostgreSQL)

PostgreSQL stores objects differently, so two mechanisms are required (verified 2026-08-11 on dev):

**Functions / Procedures / Trigger functions** — header inside the `$$` body (survives in `pg_proc.prosrc`):

```sql
CREATE OR REPLACE FUNCTION aspa.my_func()
RETURNS void
LANGUAGE plpgsql
AS $$
-- **Object**: aspa.my_func | **Version**: vX.Y.Z | **Last Updated**: YYYY-MM-DD
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
BEGIN
  ...
END;
$$;
```

**Views** — header via `COMMENT ON VIEW` (comments inside the SELECT are STRIPPED by the query tree parser — verified; only `COMMENT ON` survives in `pg_description`):

```sql
CREATE OR REPLACE VIEW aspa.my_view AS
SELECT ...

COMMENT ON VIEW aspa.my_view IS
'**Project**: aspaDB-workbench | **Object**: aspa.my_view
**Version**: vX.Y.Z | **Last Updated**: YYYY-MM-DD
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT';
```

**Triggers** — header via `COMMENT ON TRIGGER`:

```sql
CREATE TRIGGER my_trigger
AFTER INSERT ON aspa.my_table
FOR EACH ROW EXECUTE FUNCTION aspa.my_trigger_fn();

COMMENT ON TRIGGER my_trigger ON aspa.my_table IS
'**Project**: aspaDB-workbench | **Object**: aspa.my_trigger
**Version**: vX.Y.Z | **Last Updated**: YYYY-MM-DD
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT';
```

**Verification query** (find all DB objects with version headers):

```sql
SELECT c.relname, d.description
FROM pg_description d
JOIN pg_class c ON c.oid = d.objoid
WHERE d.objsubid = 0 AND d.description LIKE '**Version**:%';
```

---

## Rules

1. **Versioning**: MAJOR.MINOR.PATCH (breaking.feature.fix)
2. **License line**: exact string `MIT` (SPDX identifier, matches `/LICENSE`)
3. **Author field**:
   - `Manfred Koroschetz` — human only
   - `Manfred Koroschetz, AI` — collaborative
   - `Manfred Koroschetz/AI` — AI-assisted with review
4. **Author on its own line** (not combined with Version/Last Updated)
5. **Retrofitting (MANDATORY)**: any file touched for any reason gets its header brought current as part of that edit — including adding a missing `SPDX-License-Identifier` line or fixing stale fields. Do NOT bulk-edit untouched files solely to backfill; let the standard catch up file-by-file as work naturally touches them.
6. **Undefined document types**: apply the same field structure (`Project`, `Path`, `Version`, `Last Updated`, `Author`, `License`, `Changelog`) using the file's native comment syntax (`#`, `--`, `//`, `/* */`, `<!-- -->`, etc.).
7. **SQL in-DB objects**: `Path` field is replaced by `Object` (e.g. `aspa.my_func`) since the path is meaningless once inside the database.

---

## Template File

A ready-to-copy template with all examples lives at `workbench/sql/_template.sql`.