# Findings
**Project**: aspaDB-workbench | **Path**: workbench/index-work/findings.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-11 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.0.0 (2026-08-11): Initial standard header

Record of query diagnoses and index changes. One entry per issue.

## Template

```markdown
### YYYY-MM-DD — <short description>

**Query / issue:** ...
**Root cause:** ...
**Change:** CREATE INDEX CONCURRENTLY ...
**Before:** <mean/total time from pg_stat_statements or EXPLAIN>
**After:** <mean/total time>
**Notes:** ...
```

---
