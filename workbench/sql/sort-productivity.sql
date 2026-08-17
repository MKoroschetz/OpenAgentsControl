-- ============================================================
-- sort-productivity.sql - Sorting productivity by worker
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/sort-productivity.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-14): Initial sort productivity report
--
-- Sums sorted net weight and item counts per worker (`person`)
-- over a date range, with an average minutes-per-kg proxy when
-- time punches are available.
--
-- Output: worker, processes, items, net_weight, avg_quality

SELECT p.full_name                              AS worker,
       count(DISTINCT sp.id)                    AS processes,
       count(si.id)                             AS items,
       round(sum(si.net_weight), 2)             AS net_weight,
       round(avg(si.quality_id), 2)             AS avg_quality
FROM aspa.sort_process sp
JOIN aspa.person p        ON p.id = sp.person_id
JOIN aspa.sort_items si   ON si.sort_process_id = sp.id
WHERE sp.deleted = false
GROUP BY p.full_name
ORDER BY net_weight DESC;
