-- ============================================================
-- delivery-performance.sql - Delivery throughput by status/route
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/delivery-performance.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-14): Initial delivery performance report
--
-- Aggregates deliveries by status and the customer route they serve,
-- with total item lines and gross weight moved.
--
-- Output: route, status, deliveries, items, total_weight

SELECT COALESCE(r.name, 'unrouted')             AS route,
       d.status                                 AS status,
       count(DISTINCT d.id)                     AS deliveries,
       count(di.id)                             AS items,
       round(sum(di.net_weight), 2)             AS total_weight
FROM aspa.delivery d
JOIN aspa.delivery_items di ON di.delivery_id = d.id
LEFT JOIN aspa.customers c  ON c.id = d.customer_id
LEFT JOIN aspa.delivery_routes r ON r.id = c.route_id
WHERE d.deleted = false
GROUP BY r.name, d.status
ORDER BY deliveries DESC;
