-- ============================================================
-- sales-by-day.sql - Daily sales aggregation from orders
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/sales-by-day.sql
-- **Version**: v1.0.1 | **Last Updated**: 2026-08-17
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.1 (2026-08-17): Fixed against live schema - no `deleted` column on
--   orders/order_details; filter uses `orders.status = 'DONE'` (DELETED/NEW/
--   UNCONFIRMED/IN PROGRESS excluded).
-- - v1.0.0 (2026-08-14): Initial daily sales report
--
-- Daily revenue and order counts from the `orders`/`order_details`
-- sales pipeline.
--
-- Output: sale_day, order_count, line_count, gross, net (after discounts)

SELECT date_trunc('day', o.creation_ts)          AS sale_day,
       count(DISTINCT o.id)                       AS order_count,
       count(od.id)                              AS line_count,
       round(sum(od.sales_price * od.quantity)::numeric, 2) AS gross,
       round(sum(od.final_price * od.quantity)::numeric, 2) AS net
FROM aspa.orders o
JOIN aspa.order_details od ON od.order_id = o.id
WHERE o.status = 'DONE'
GROUP BY date_trunc('day', o.creation_ts)
ORDER BY sale_day DESC;
