-- ============================================================
-- sort-productivity.sql - Sorting productivity by worker
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/sort-productivity.sql
-- **Version**: v1.0.1 | **Last Updated**: 2026-08-17
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.1 (2026-08-17): Fixed against live schema - `person`/`sort_process`/
--   `sort_items` PKs are *_id (not `id`); `person.full_name` does not exist
--   (use first/middle/last_name); quality joined via `quality.quality_id`
--   for a readable label instead of averaging FK ids.
-- - v1.0.0 (2026-08-14): Initial sort productivity report
--
-- Sums sorted net weight and item counts per worker (`person`)
-- over completed, non-deleted sort processes.
--
-- Output: worker, processes, items, net_weight, top_quality

SELECT concat_ws(' ', p.first_name, p.middle_name, p.last_name) AS worker,
       count(DISTINCT sp.sort_process_id)                       AS processes,
       count(si.sort_items_id)                                  AS items,
       round(sum(si.net_weight)::numeric, 2)                    AS net_weight,
       min(q.name)                                              AS top_quality
FROM aspa.sort_process sp
JOIN aspa.person p        ON p.person_id = sp.person_id
JOIN aspa.sort_items si   ON si.sort_process_id = sp.sort_process_id
LEFT JOIN aspa.quality q  ON q.quality_id = si.quality_id
WHERE sp.deleted = false
  AND sp.status = 'COMPLETE'
  AND si.deleted = false
GROUP BY concat_ws(' ', p.first_name, p.middle_name, p.last_name)
ORDER BY net_weight DESC;
