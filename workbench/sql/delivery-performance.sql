-- ============================================================
-- delivery-performance.sql - Delivery throughput by status/route
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/delivery-performance.sql
-- **Version**: v1.0.1 | **Last Updated**: 2026-08-17
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.1 (2026-08-17): Fixed against live schema - `delivery` PK is
--   `delivery_id` (no `id`/`customer_id`); route joined via driver
--   (`delivery.person_id = delivery_routes.driver_id`); route label from
--   `destination->>'city'` jsonb (no `name` column).
-- - v1.0.0 (2026-08-14): Initial delivery performance report
--
-- Aggregates non-deleted deliveries by status and the driver route they
-- serve, with total item lines and net weight moved.
--
-- Output: route, status, deliveries, items, total_weight

SELECT COALESCE(r.destination ->> 'city', 'unrouted') AS route,
       d.status                                       AS status,
       count(DISTINCT d.delivery_id)                  AS deliveries,
       count(di.delivery_item_id)                     AS items,
       round(sum(di.net_weight)::numeric, 2)          AS total_weight
FROM aspa.delivery d
JOIN aspa.delivery_items di ON di.delivery_id = d.delivery_id
LEFT JOIN aspa.delivery_routes r ON r.driver_id = d.person_id
WHERE d.deleted = false
GROUP BY r.destination ->> 'city', d.status
ORDER BY deliveries DESC;
