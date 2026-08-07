<!-- Context: development/data/aspa-schema | Priority: high | Version: 1.0 | Updated: 2026-08-07 -->

# aspaDB Schema Reference

> The `aspa` schema is the core application schema of the aspadb database — 85 tables + ~110 views covering inventory, sorting, delivery, sales, and CRM for a produce/fruit business (South Tyrol, Italy).

## Quick Facts

| Fact | Value |
|------|-------|
| Database | `aspadb` (PostgreSQL 12.13) |
| Main schema | `aspa` (85 tables, ~110 views) |
| Other schemas | `public` (11 scratch), `tax_reports` (7 tables + 7 views), `winery` (10 tables) |
| Largest tables | `inventory` (74k rows, 88 MB), `inventory_log` (338k, 60 MB), `log_raw` (191k, 45 MB) |
| Key entities | `person` (members/workers), `customers`, `products`, `inventory`, `orders`, `delivery` |
| Conventions | `*_id` PKs with `aspa.*_seq` sequences; `creation_ts`/`last_modification_ts` timestamptz; soft-delete via `deleted` boolean; `active` boolean on reference tables |

## Domain Map

Tables grouped by business area (all in `aspa` unless noted):

### Inventory & Stock
| Table | Rows | Notes |
|-------|------|-------|
| `inventory` | 73,783 | Current stock items; `status`, `class_id`, `warehouse_id`, `aging`, `log` json |
| `inventory_log` | 338,034 | Movement history (scans in/out, transfers); `type`, `origin_wh`, `destination_wh` |
| `inventory_audit` | 35 | Stock-count audits |
| `inventory_audit_details` | 16,376 | Per-class/case audit lines |
| `inventory_check` | 1,336 | Check records |
| `inventory_orders` | 831 | Stock transfer orders |
| `inventory_order_details` | 2,997 | Lines of transfer orders |
| `warehouses` | 9 | Locations; `type`, `ipaddress` |
| `waste` | 109 | Waste/discard records |

### Sorting & Processing
| Table | Rows | Notes |
|-------|------|-------|
| `sort_process` | 4,102 | Sort runs; `person_id` (worker) |
| `sort_items` | 94,441 | Items sorted per process; `gross_weight`, `net_weight`, `quality_id` |
| `admin_sort_summary` | 7,463 | Aggregated sort stats |
| `admin_sort_taxi` | 6,871 | Taxi/transport sort records |
| `quality` | 11 | Quality grades |
| `classes` | 17 | Product classes (linked to `cases`) |
| `cases` | 9 | Case/crate types (tare, min/max weight) |
| `classes_product_rel` | 19 | Class ↔ product mapping |

### Delivery & Shipping
| Table | Rows | Notes |
|-------|------|-------|
| `delivery` | 14,346 | Deliveries; `status`, `person_id` |
| `delivery_items` | 32,380 | Items per delivery; `code`, weights, `sort_process_id` |
| `delivery_routes` | 5 | Route definitions |
| `comments` | 413 | Comments on deliveries/sorts |
| `temp_egress` / `temp_egress_staging` | 334/127 | Egress staging tables |

### Sales & Orders
| Table | Rows | Notes |
|-------|------|-------|
| `orders` | 7,181 | Sales orders; `type`, `status`, `origin_wh_id`, `dest_wh_id` |
| `order_details` | 11,474 | Order lines; `product_id`, `quantity`, `sales_price`, `final_price` |
| `shop_sale` | 53,714 | POS/shop sales (imported); `transid`, `saledate` |
| `shop_products` | 71 | Shop product catalog |
| `shop_temp` | 0 | Staging for shop imports |
| `pricelists` | 174 | Prices per product/customer/type; `price`, `tax`, `discount_1/2` |
| `pricelists_history` | 255 | Price change history |
| `promotions` / `promotion_types` | 0/0 | Promotions (empty) |
| `product_options` | 19 | Product option flags |

### Customers & CRM
| Table | Rows | Notes |
|-------|------|-------|
| `customers` | 365 | Customers; `corp_name`, `type_id`, `driver_id`, `route_id` |
| `customer_types` | 11 | Customer categories |
| `customers_authorized_users` | 240 | Authorized users per customer |
| `customer_log` | 72 | Customer activity log |
| `customer_routes` | 0 | Customer ↔ route links |
| `phones` | 242 | Customer phone numbers |
| `partners` | 5 | Partner companies |

### People (Members & Workers)
| Table | Rows | Notes |
|-------|------|-------|
| `person` | 178 | Members/workers; `person_type_id`, `bar_code`, `email`, `language` |
| `person_type` | 4 | Person categories |
| `time_punches` | 6 | Work time punches |
| `weekly_average` / `weekly_sum` | 66/66 | Weekly productivity stats |

### Barcodes & Tracking
| Table | Rows | Notes |
|-------|------|-------|
| `barcodes` | 3,825 | Barcode registry; `code`, `member_id`, `fields_id`, `status` |
| `barcode_template` | 3 | Barcode templates |
| `tracking_barcodes` | 111,951 | Barcode tracking; `sort_class`, `case_number`, `lot_number`, `status` |
| `track_bolibo` | 8,462 | Bolibo tracking |
| `track_case_inventory` | 58,482 | Case-level inventory tracking |
| `track_case_sort` | 44,112 | Case-level sort tracking |
| `track_case_delivery` | 14,732 | Case-level delivery tracking |

### Fields (Agriculture)
| Table | Rows | Notes |
|-------|------|-------|
| `fields` | 68 | Fields; `latitude`, `longitude`, `plant_variety`, `area` |
| `field_rows` | 109 | Field rows |
| `fields_history` | 27 | Field change history |

### Logging & System
| Table | Rows | Notes |
|-------|------|-------|
| `log_raw` | 191,286 | Raw scanner log; `source`, `barcode`, `gross`, `net`, `buffer` jsonb |
| `log_raw2` | 355 | Secondary raw log |
| `log_mscanner` | 71,532 | Mobile scanner log |
| `audit` | 0 | Audit trail |
| `api_control` | 113 | API access control |
| `process_control` | 2 | Process control flags |
| `settings` | 5 | App settings (json) |
| `email_config` / `email_notification_setup` | 1 / 1 | Email config |
| `languages` | 10 | Language list |
| `infobox` | 11 | Info boxes |
| `operation_hours` / `holiday_schedule` / `schedule` | 1 / 3 / 7 | Scheduling |
| `whitelisted_ips` | 16 | IP whitelist |
| `ear_params` | 7 | EAR parameters |
| `dropdown_helper` | 10 | Dropdown values |
| `bio_categories` | 2 | Bio categories |
| `reports` / `report_parameters` / `reports_report_parameters` | 45 / 25 / 128 | Report definitions |
| `actionable_report_columns` | 0 | Report column config |

### Legacy / Scratch (do not rely on)
`oldtable`, `oldtable1`, `oldtable2`, `prova`, `sequenza_giorni`, `temp_log`, `audit`, `shop_temp`

---

## Key Relationships (Foreign Keys)

```
person ──┬── addresses (person_id)
         ├── barcodes (member_id / person_id)
         ├── delivery (person_id)
         ├── fields (person_id)
         ├── sort_process (person_id)
         ├── inventory_log (user_id)
         ├── inventory_audit (user_id)
         └── time_punches (person_id)

customers ──┬── addresses (customer_id)
            ├── orders (customer_id)
            ├── pricelists (customer_id)
            ├── phones (customer_id)
            ├── partners (customer_id)
            └── customers_authorized_users (customer_id)

products ──┬── order_details (product_id)
           ├── pricelists (product_id)
           ├── classes_product_rel (product_id)
           └── promotions (product_id)

cases ──┬── classes (cases_id)
        ├── delivery_items (cases_id)
        ├── inventory (cases_id)
        ├── person (cases_id)
        ├── products (cases_id)
        └── sort_items (cases_id)

warehouses ──┬── inventory (warehouse_id)
             ├── inventory_audit (warehouse_id)
             ├── orders (origin_wh_id / dest_wh_id)
             └── waste (origin_id)

delivery ──┬── delivery_items (delivery_id)
           └── comments (delivery_id)

sort_process ──┬── sort_items (sort_process_id)
               ├── delivery_items (sort_process_id)
               ├── inventory (sort_process_id)
               └── comments (sort_id)
```

---

## Views (~110)

Views are heavily used for reporting and consolidation. Notable groups:

- **Sales**: `SalesOrderView`, `SalesOrderDetailView`, `SalesOrderValueView`, `SalesOrderRequirementView`, `SalesOrderDeliveries`, `SalesOrderShort`, `SalesFulfillmentView`, `SalesFulfillmentProd`, `SalesConsistency`, `SalesStatus`, `ShopSalesByDay`
- **Inventory**: `InventoryView`, `InventoryProductView`, `InventoryState`, `InventoryConsistency`, `InventoryIngres`, `InventoryOrders`, `InventoryShortDetailByAge`, `ConsolidatedStock`, `ConsolidatedProducts`, `PendingStockIngress`, `StockIngress`
- **Sorting**: `SortProcesses`, `SortProcesses_c`, `SortDetails`, `SortDetails1`, `SortDetailShort`, `SortPending`, `SortPendingSum`, `SortConsistency`, `daily_sort_process`, `current_sort_process`, `list_daily_sort_process`, `sort_last_day`, `OrphanedSortProcesses`
- **Delivery**: `Deliveries`, `Deliveries1`, `DeliveryDetails`, `DeliveryConsistency`, `FieldDeliveryView`, `NextDeliveryDate`, `WarehouseTransit`
- **Tracking**: `Tracking`, `Tracking_crates`, `CrateCodes`, `CrateCodesSummary`, `ActiveFieldCrateLabels`
- **People**: `Members`, `MemberDetails`, `Workers`, `ActiveWorkers`, `ActiveMembers`, `ActiveDrivers`, `Drivers`, `Admins`, `AMembers`, `Helfer`, `ActiveProdWorkers`, `ActivePartnersAll`, `TaxiDrivers`, `ActiveStatus`
- **Products/Classes**: `ActiveProducts`, `ActiveClasses`, `ActiveFields`, `ActiveWarehouses`, `ActiveShopProducts`, `ClassProdRelation`, `ProdCategories`
- **Misc**: `Weekly`, `weekly_totals`, `Minutes per kg`, `Minutes kg`, `AVG Minutes per kg`, `PrintBarcodes`, `PrintBarcodesManual`, `Extract_JSON_Code`, `ReportConfigHelper`, `CustNames`, `CustomerTypes`, `CustomerReport`, `CRM_Contact`, `Orders_Customers`, `TransferOrderView`, `TransferAndrian2Terlan`, `OP115_TempExitView`, `Produzione campi 2021`, `admin_taxi_deliveries`, `admin_sort_processing`, `daily_ingress_process`, `list_daily_ingress_process`, `list_daily_ingress_groupby_member`, `IngressPending`, `IngressPending_Old`, `sort_delivery`, `sort_delivery_id`, `ShopTempSummary`, `SalesSatusSelector`, `SalesOrderDetailViewJson`, `Forecast`, `InventoryCheck`, `BioInventory`, `PriceLists`, `Base_Languages`, `InvOrderShort`, `ActiveSortDetail`, `ActiveFields`, `ActiveFieldCrateLabels`

---

## Other Schemas

### `public` (scratch/legacy)
`contatore`, `dropdown_helper`, `emptied`, `flyway_schema_history`, `ntotal_in`, `office_days`, `office_hworked`, `p_id`, `processed`, `transit` + view `dd_helper`

### `tax_reports` (7 tables + 7 views)
`ae_certificates`, `corrispettivi`, `corrispettivi_iva`, `corrispettivi_signatures`, `device_connectivity_log`, `processing_log`, `rt_devices` + views `v_cert_expiry`, `v_daily_summary`, `v_device_status`, `v_iva_breakdown`, `v_missing_receipt`, `v_monthly_iva_breakdown`, `v_monthly_totals`

### `winery` (10 tables)
`bottled_by`, `bottled_for`, `clients`, `delivery`, `distributors`, `imported_by`, `produced_by`, `transporters`, `warehouses`, `wine_type`

---

## Querying Tips

- **Always filter by `deleted = false`** — most tables soft-delete.
- **`inventory_log` is the audit trail** — use it to reconstruct stock movements; `type` distinguishes scan-in/out/transfer.
- **`log_raw` is the raw scanner feed** — `buffer` jsonb holds the full payload; `duplicate` flags re-scans.
- **`shop_sale` is imported POS data** — `transid` + `saledate` are unique; `invupdate_status` tracks inventory sync.
- **`tracking_barcodes` is the barcode lifecycle** — `status` moves PENDING → (sorted/delivered); `lot_number`/`year` identify batches.
- **`person` is the hub for people** — members, workers, drivers all live here, distinguished by `person_type_id`.
- **`pricelists` is per-customer/year** — always filter by `year` and `customer_id`/`type_id`.
- **Views are the reporting layer** — prefer views over raw joins for sales/inventory/delivery reports.

---

## Related Context

- **Postgres patterns** → `../sql-patterns/postgres-patterns.md`
- **Data navigation** → `../navigation.md`
- **Technical domain** → `../../../project-intelligence/technical-domain.md`