-- ============================================================
-- sales-by-day.sql - Daily sales aggregation from orders
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/sales-by-day.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-14): Initial daily sales report
--
-- Daily revenue and order counts from the `orders`/`order_details`
-- sales pipeline. Joins customer for segmentation.
--
-- NOTE: relies on documented conventions - `creation_ts` timestamp,
-- `deleted` soft-delete flag, and `final_price` on order lines.
-- Adjust column names once validated against the live DB.
--
-- Output: sale_day, order_count, line_count, gross, net (after discounts)

SELECT date_trunc('day', o.creation_ts)          AS sale_day,
       count(DISTINCT o.id)                       AS order_count,
       count(od.id)                              AS line_count,
       round(sum(od.sales_price * od.quantity), 2) AS gross,
       round(sum(od.final_price * od.quantity), 2) AS net
FROM aspa.orders o
JOIN aspa.order_details od ON od.order_id = o.id
LEFT JOIN aspa.customers c ON c.id = o.customer_id
WHERE o.deleted = false
  AND od.deleted = false
GROUP BY date_trunc('day', o.creation_ts)
ORDER BY sale_day DESC;
