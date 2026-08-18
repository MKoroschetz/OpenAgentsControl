-- ============================================================
-- customer-revenue.sql - Top customers by net revenue
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/customer-revenue.sql
-- **Version**: v1.0.1 | **Last Updated**: 2026-08-17
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.1 (2026-08-17): Fixed against live schema - no `deleted` column on
--   customers/orders/order_details; filters use `customers.active` and
--   `orders.status = 'DONE'`.
-- - v1.0.0 (2026-08-14): Initial customer revenue report
--
-- Ranks active customers by total net revenue from `order_details`,
-- with order and line counts for context.
--
-- Output: customer, type, orders, lines, net_revenue

SELECT c.corp_name                             AS customer,
       ct.name                                 AS type,
       count(DISTINCT o.id)                    AS orders,
       count(od.id)                            AS lines,
       round(sum(od.final_price * od.quantity)::numeric, 2) AS net_revenue
FROM aspa.customers c
JOIN aspa.orders o          ON o.customer_id = c.id AND o.status = 'DONE'
JOIN aspa.order_details od  ON od.order_id = o.id
LEFT JOIN aspa.customer_types ct ON ct.id = c.type_id
WHERE c.active = true
GROUP BY c.corp_name, ct.name
ORDER BY net_revenue DESC
LIMIT 50;
