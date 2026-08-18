# SQL Reports Index
**Project**: aspaDB-workbench | **Path**: workbench/sql/README.md
**Version**: v1.1.0 | **Last Updated**: 2026-08-17 | **Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.1.0 (2026-08-17): All 5 reports rewritten against the **live schema**
  and validated on dev PG17 + prod PG12 (identical row counts). The earlier
  "compiles but unvalidated" note is retired.
- v1.0.0 (2026-08-14): Initial index of reusable report queries

Reusable business-report queries against the `aspa` schema. Run with
`./scripts/run.sh sql/<file>.sql` (see `../README.md`).

> **Validation status (2026-08-17):** Every query in this directory was
> compile-checked (`ON_ERROR_STOP=1`) and executed against both dev PG 17.11
> and prod PG 12.13. All return rows; counts match between the two.
> These are business-report queries only — the migration regression suite
> lives in `../regression/` and is the authoritative upgrade validator.

| File | Purpose | Output | Row counts (dev=prod) |
|------|---------|--------|------------------------|
| `sales-by-day.sql` | Daily revenue/order counts from `orders`/`order_details` (status = DONE) | sale_day, order_count, line_count, gross, net | 313 |
| `customer-revenue.sql` | Top 50 active customers by net revenue | customer, type, orders, lines, net_revenue | 54 |
| `inventory-by-warehouse.sql` | Stock position by warehouse + class | warehouse, class, sku_count, total_quantity, avg_aging | 58 |
| `delivery-performance.sql` | Delivery throughput by status/driver route | route, status, deliveries, items, total_weight | 13 |
| `sort-productivity.sql` | Sort net weight & items per worker (COMPLETE processes) | worker, processes, items, net_weight, top_quality | 25 |

## Schema facts learned (2026-08-17)
- `orders`, `order_details`, `customers` have **no `deleted` flag**; filter
  sales by `orders.status = 'DONE'` and customers by `customers.active`.
- `person`, `sort_process`, `sort_items`, `delivery`, `delivery_items`,
  `quality`, `classes` use `*_id` primary keys (e.g. `person_id`,
  `delivery_id`, `delivery_item_id`, `classes_id`), **not** `id`.
- `person.full_name` does not exist → `concat_ws(' ', first_name,
  middle_name, last_name)`.
- `delivery_routes` has no `name` column; the route label lives in the
  `destination` jsonb (`destination->>'city'`). Deliveries link to routes
  via driver: `delivery.person_id = delivery_routes.driver_id`.
- `inventory.log` is jsonb; quantities need `(log->>'quantity')::numeric`.

## Adding a report
1. Copy `../sql/_template.sql` to a kebab-case name.
2. Fill the standard header (Project/Path/Version/Author/License).
3. Check the live schema first (see facts above) — don't assume `deleted`
   or `id` exist.
4. Compile-check: `psql -v ON_ERROR_STOP=1 -f <file>.sql`.
5. Document output columns in the header comment.
6. Add a row to the table above with observed row counts.
