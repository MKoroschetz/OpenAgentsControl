-- ============================================================
-- customer-revenue.sql - Top customers by net revenue
-- **Project**: aspaDB-workbench | **Path**: workbench/sql/customer-revenue.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-14
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- ## Changelog
-- - v1.0.0 (2026-08-14): Initial customer revenue report
--
-- Ranks customers by total net revenue from `order_details`,
-- with order and line counts for context.
--
-- Output: customer, type, orders, lines, net_revenue

SELECT c.corp_name                             AS customer,
       ct.name                                 AS type,
       count(DISTINCT o.id)                    AS orders,
       count(od.id)                            AS lines,
       round(sum(od.final_price * od.quantity), 2) AS net_revenue
FROM aspa.customers c
JOIN aspa.orders o          ON o.customer_id = c.id AND o.deleted = false
JOIN aspa.order_details od  ON od.order_id = o.id AND od.deleted = false
LEFT JOIN aspa.customer_types ct ON ct.id = c.type_id
WHERE c.deleted = false
GROUP BY c.corp_name, ct.name
ORDER BY net_revenue DESC
LIMIT 50;
