-- ============================================================
-- inventory-by-warehouse.sql - Stock position by warehouse/class
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/inventory-by-warehouse.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.1 (2026-08-17): Fixed against live schema - `classes` PK is
--   `classes_id` (not `id`); `inventory.log` jsonb quantity cast to numeric.
-- - v1.0.0 (2026-08-14): Initial inventory position report

-- Current stock counts and summed `log` json weights per warehouse
-- and product class. Useful to spot overstock / dead stock.
--
-- Output: warehouse, class, sku_count, total_quantity, avg_aging

SELECT w.name                                   AS warehouse,
       cl.name                                  AS class,
       count(i.id)                              AS sku_count,
       round(sum((i.log->>'quantity')::numeric), 2) AS total_quantity,
       round(avg(i.aging), 1)                   AS avg_aging
FROM aspa.inventory i
JOIN aspa.warehouses w  ON w.id = i.warehouse_id
JOIN aspa.classes cl    ON cl.classes_id = i.class_id
WHERE i.deleted = false
GROUP BY w.name, cl.name
ORDER BY w.name, sku_count DESC;
