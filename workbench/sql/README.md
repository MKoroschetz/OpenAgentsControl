# SQL Reports Index
**Project**: aspaDB-workbench | **Path**: workbench/sql/README.md
**Version**: v1.0.0 | **Last Updated**: 2026-08-14 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.0.0 (2026-08-14): Initial index of reusable report queries

Reusable business-report queries against the `aspa` schema. Run with
`./scripts/run.sh sql/<file>.sql` (see `../README.md`).

Each query follows the standard SQL header and filters soft-deleted rows
(`deleted = false`) where applicable. Column names are based on the
documented conventions in `../.opencode/context/development/data/aspa/aspa-schema.md`
and should be validated against the live DB before production use.

| File | Purpose | Output |
|------|---------|--------|
| `sales-by-day.sql` | Daily revenue/order counts from `orders`/`order_details` | sale_day, order_count, line_count, gross, net |
| `customer-revenue.sql` | Top 50 customers by net revenue | customer, type, orders, lines, net_revenue |
| `inventory-by-warehouse.sql` | Stock position by warehouse + class | warehouse, class, sku_count, total_quantity, avg_aging |
| `delivery-performance.sql` | Delivery throughput by route/status | route, status, deliveries, items, total_weight |
| `sort-productivity.sql` | Sort net weight & items per worker | worker, processes, items, net_weight, avg_quality |

## Adding a report
1. Copy `../sql/_template.sql` to a kebab-case name.
2. Fill the standard header (Project/Path/Version/Author/License).
3. Filter `deleted = false` on base tables.
4. Document output columns in the header comment.
5. Add a row to the table above.
