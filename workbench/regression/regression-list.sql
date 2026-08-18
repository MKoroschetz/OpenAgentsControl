-- ============================================================
-- regression-list.sql - A.8/B.8 regression suite (PG 12 -> PG 17)
-- **Project**: aspaDB-workbench | **Path**: workbench/regression/regression-list.sql
-- **Version**: v1.0.0 | **Last Updated**: 2026-08-17
-- **Author**: Manfred Koroschetz/AI
-- **License**: SPDX-License-Identifier: MIT
--
-- PURPOSE
--   Validate the app's REAL query layer against the migrated cluster.
--   Built from LIVE schema introspection on dev PG 17.11 (2026-08-17),
--   not from the unvalidated workbench/sql/ report queries (those had
--   never been run and reference non-existent columns - see README).
--
-- TIERS
--   0  Server identity + locale (informational; version differs dev/prod by design)
--   1  EAR_export_* functions - the app's production reporting/export layer
--      (row counts are the diffable signal; LIMIT samples check real data)
--   2  All aspa views - existence + row count (109; identical = same dataset)
--   3  Structure: tables/schemas/roles/extensions/inventory counts
--   4  Catalog: index counts + FK missing-index candidates (schema-derived)
--
-- RUN (from workbench/):  ./regression/run-regression.sh dev|prod
-- PASS = zero ERROR lines in the report. See README.md for diff protocol.
-- ============================================================

-- ============ TIER 0 - SERVER IDENTITY ============
\echo '=== T0 server ==='
SELECT version();
\echo '=== T0 locale (pg_database.datcollate/datctype) ==='
SELECT datname||'|'||datcollate||'|'||datctype FROM pg_database ORDER BY 1;
\echo '=== T0 lc_monetary / server_encoding ==='
SELECT current_setting('lc_monetary')||'|'||current_setting('server_encoding');
\echo '=== T0 databases (non-template) ==='
SELECT count(*) FROM pg_database WHERE datistemplate = false;

-- ============ TIER 1 - EAR_export_* FUNCTIONS ============
\echo '=== T1 EAR_export_APAYMENT (2025 legacy) ==='
SELECT count(*) FROM aspa."EAR_export_APAYMENT"('2025');
\echo '=== T1 EAR_export_APAYMENT (2026 -> 2026 branch) ==='
SELECT count(*) FROM aspa."EAR_export_APAYMENT"('2026');
\echo '=== T1 EAR_export_APAYMENT (default = current year) ==='
SELECT count(*) FROM aspa."EAR_export_APAYMENT"();
\echo '=== T1 EAR_export_APAYMENT_2026 (2026) ==='
SELECT count(*) FROM aspa."EAR_export_APAYMENT_2026"('2026');
\echo '=== T1 EAR_export_APAYMENT_2026 sample ==='
SELECT * FROM aspa."EAR_export_APAYMENT_2026"('2026') LIMIT 2;
\echo '=== T1 EAR_export_APAYMENT_LEGACY (2025) ==='
SELECT count(*) FROM aspa."EAR_export_APAYMENT_LEGACY"('2025');
\echo '=== T1 EAR_export_AUX_DATA (2026) ==='
SELECT count(*) FROM aspa."EAR_export_AUX_DATA"('2026');
\echo '=== T1 EAR_export_AUX_DATA (2025) ==='
SELECT count(*) FROM aspa."EAR_export_AUX_DATA"('2025');
\echo '=== T1 EAR_export_DELIVERY (2026) ==='
SELECT count(*) FROM aspa."EAR_export_DELIVERY"('2026');
\echo '=== T1 EAR_export_DELIVERY (2026 wildcard) ==='
SELECT count(*) FROM aspa."EAR_export_DELIVERY"('2026','*');
\echo '=== T1 EAR_export_DELIVERY sample ==='
SELECT * FROM aspa."EAR_export_DELIVERY"('2026') LIMIT 2;
\echo '=== T1 EAR_export_MEMBERS () ==='
SELECT count(*) FROM aspa."EAR_export_MEMBERS"();
\echo '=== T1 EAR_export_MEMBERS (1,1) ==='
SELECT count(*) FROM aspa."EAR_export_MEMBERS"('1',1);
\echo '=== T1 EAR_export_MEMBERS (2,1) ==='
SELECT count(*) FROM aspa."EAR_export_MEMBERS"('2',1);
\echo '=== T1 EAR_export_MEMBERS (4,1) ==='
SELECT count(*) FROM aspa."EAR_export_MEMBERS"('4',1);
\echo '=== T1 EAR_export_MEMBERS (active 1, itype 10) ==='
SELECT count(*) FROM aspa."EAR_export_MEMBERS"(active=>'1',itype=>10);
\echo '=== T1 EAR_export_MEMBERS (syear 2026) ==='
SELECT count(*) FROM aspa."EAR_export_MEMBERS"(syear=>'2026');
\echo '=== T1 EAR_export_PARAMS (2026) ==='
SELECT count(*) FROM aspa."EAR_export_PARAMS"('2026');
\echo '=== T1 EAR_export_PARAMS (default) ==='
SELECT count(*) FROM aspa."EAR_export_PARAMS"();
\echo '=== T1 EAR_export_PRICELISTS (2026,1) ==='
SELECT count(*) FROM aspa."EAR_export_PRICELISTS"('2026',1);
\echo '=== T1 EAR_export_PRICELISTS (2026,1,history) ==='
SELECT count(*) FROM aspa."EAR_export_PRICELISTS"('2026',1,true);
\echo '=== T1 EAR_export_PRICELISTS (default) ==='
SELECT count(*) FROM aspa."EAR_export_PRICELISTS"();
\echo '=== T1 EAR_export_SORT (2025) ==='
SELECT count(*) FROM aspa."EAR_export_SORT"('2025');
\echo '=== T1 EAR_export_SORT (2025 summary) ==='
SELECT count(*) FROM aspa."EAR_export_SORT"('2025',summary:=true);
\echo '=== T1 EAR_export_SORT sample ==='
SELECT * FROM aspa."EAR_export_SORT"('2025') LIMIT 2;
\echo '=== T1 EAR_export_SORT_2026 (2026) ==='
SELECT count(*) FROM aspa."EAR_export_SORT_2026"('2026');
\echo '=== T1 EAR_export_SORT_2026 (2026 summary) ==='
SELECT count(*) FROM aspa."EAR_export_SORT_2026"('2026',summary:=true);
\echo '=== T1 EAR_export_SORT_2026 sample ==='
SELECT * FROM aspa."EAR_export_SORT_2026"('2026') LIMIT 2;
\echo '=== T1 EAR_export_SORT_n (2025 - 2026 data breaks SORT_n: known app bug, see README) ==='
SELECT count(*) FROM aspa."EAR_export_SORT_n"('2025');

-- ============ TIER 2 - ALL aspa VIEWS (row counts) ============
\echo '=== T2 views ==='
SELECT 'AMembers' AS view, count(*) FROM aspa."AMembers";
SELECT 'AVG Minutes per kg' AS view, count(*) FROM aspa."AVG Minutes per kg";
SELECT 'ActiveClasses' AS view, count(*) FROM aspa."ActiveClasses";
SELECT 'ActiveCustomers' AS view, count(*) FROM aspa."ActiveCustomers";
SELECT 'ActiveDrivers' AS view, count(*) FROM aspa."ActiveDrivers";
SELECT 'ActiveFieldCrateLabels' AS view, count(*) FROM aspa."ActiveFieldCrateLabels";
SELECT 'ActiveFields' AS view, count(*) FROM aspa."ActiveFields";
SELECT 'ActiveMembers' AS view, count(*) FROM aspa."ActiveMembers";
SELECT 'ActivePartnersAll' AS view, count(*) FROM aspa."ActivePartnersAll";
SELECT 'ActiveProdWorkers' AS view, count(*) FROM aspa."ActiveProdWorkers";
SELECT 'ActiveProducts' AS view, count(*) FROM aspa."ActiveProducts";
SELECT 'ActiveShopProducts' AS view, count(*) FROM aspa."ActiveShopProducts";
SELECT 'ActiveSortDetail' AS view, count(*) FROM aspa."ActiveSortDetail";
SELECT 'ActiveStatus' AS view, count(*) FROM aspa."ActiveStatus";
SELECT 'ActiveWarehouses' AS view, count(*) FROM aspa."ActiveWarehouses";
SELECT 'ActiveWorkers' AS view, count(*) FROM aspa."ActiveWorkers";
SELECT 'Admins' AS view, count(*) FROM aspa."Admins";
SELECT 'Base_Languages' AS view, count(*) FROM aspa."Base_Languages";
SELECT 'BioInventory' AS view, count(*) FROM aspa."BioInventory";
SELECT 'CRM_Contact' AS view, count(*) FROM aspa."CRM_Contact";
SELECT 'ClassProdRelation' AS view, count(*) FROM aspa."ClassProdRelation";
SELECT 'ConsolidatedProducts' AS view, count(*) FROM aspa."ConsolidatedProducts";
SELECT 'ConsolidatedStock' AS view, count(*) FROM aspa."ConsolidatedStock";
SELECT 'CrateCodes' AS view, count(*) FROM aspa."CrateCodes";
SELECT 'CrateCodesSummary' AS view, count(*) FROM aspa."CrateCodesSummary";
SELECT 'CustNames' AS view, count(*) FROM aspa."CustNames";
SELECT 'CustomerReport' AS view, count(*) FROM aspa."CustomerReport";
SELECT 'CustomerTypes' AS view, count(*) FROM aspa."CustomerTypes";
SELECT 'Deliveries' AS view, count(*) FROM aspa."Deliveries";
SELECT 'Deliveries1' AS view, count(*) FROM aspa."Deliveries1";
SELECT 'DeliveryConsistency' AS view, count(*) FROM aspa."DeliveryConsistency";
SELECT 'DeliveryDetails' AS view, count(*) FROM aspa."DeliveryDetails";
SELECT 'Drivers' AS view, count(*) FROM aspa."Drivers";
SELECT 'Extract_JSON_Code' AS view, count(*) FROM aspa."Extract_JSON_Code";
SELECT 'FieldDeliveryView' AS view, count(*) FROM aspa."FieldDeliveryView";
SELECT 'Forecast' AS view, count(*) FROM aspa."Forecast";
SELECT 'Helfer' AS view, count(*) FROM aspa."Helfer";
SELECT 'InfoboxActive' AS view, count(*) FROM aspa."InfoboxActive";
SELECT 'IngressPending' AS view, count(*) FROM aspa."IngressPending";
SELECT 'IngressPending_Old' AS view, count(*) FROM aspa."IngressPending_Old";
SELECT 'InvOrderShort' AS view, count(*) FROM aspa."InvOrderShort";
SELECT 'InventoryCheck' AS view, count(*) FROM aspa."InventoryCheck";
SELECT 'InventoryConsistency' AS view, count(*) FROM aspa."InventoryConsistency";
SELECT 'InventoryIngres' AS view, count(*) FROM aspa."InventoryIngres";
SELECT 'InventoryOrders' AS view, count(*) FROM aspa."InventoryOrders";
SELECT 'InventoryProductView' AS view, count(*) FROM aspa."InventoryProductView";
SELECT 'InventoryShortDetailByAge' AS view, count(*) FROM aspa."InventoryShortDetailByAge";
SELECT 'InventoryState' AS view, count(*) FROM aspa."InventoryState";
SELECT 'InventoryView' AS view, count(*) FROM aspa."InventoryView";
SELECT 'MemberDetails' AS view, count(*) FROM aspa."MemberDetails";
SELECT 'Members' AS view, count(*) FROM aspa."Members";
SELECT 'Minutes kg' AS view, count(*) FROM aspa."Minutes kg";
SELECT 'Minutes per kg' AS view, count(*) FROM aspa."Minutes per kg";
SELECT 'NextDeliveryDate' AS view, count(*) FROM aspa."NextDeliveryDate";
SELECT 'OP115_TempExitView' AS view, count(*) FROM aspa."OP115_TempExitView";
SELECT 'Orders_Customers' AS view, count(*) FROM aspa."Orders_Customers";
SELECT 'OrphanedSortProcesses' AS view, count(*) FROM aspa."OrphanedSortProcesses";
SELECT 'PendingStockIngress' AS view, count(*) FROM aspa."PendingStockIngress";
SELECT 'PriceLists' AS view, count(*) FROM aspa."PriceLists";
SELECT 'PrintBarcodes' AS view, count(*) FROM aspa."PrintBarcodes";
SELECT 'PrintBarcodesManual' AS view, count(*) FROM aspa."PrintBarcodesManual";
SELECT 'ProdCategories' AS view, count(*) FROM aspa."ProdCategories";
SELECT 'Produzione campi 2021' AS view, count(*) FROM aspa."Produzione campi 2021";
SELECT 'ReportConfigHelper' AS view, count(*) FROM aspa."ReportConfigHelper";
SELECT 'SalesConsistency' AS view, count(*) FROM aspa."SalesConsistency";
SELECT 'SalesFulfillmentProd' AS view, count(*) FROM aspa."SalesFulfillmentProd";
SELECT 'SalesFulfillmentView' AS view, count(*) FROM aspa."SalesFulfillmentView";
SELECT 'SalesOrderDeliveries' AS view, count(*) FROM aspa."SalesOrderDeliveries";
SELECT 'SalesOrderDetailView' AS view, count(*) FROM aspa."SalesOrderDetailView";
SELECT 'SalesOrderDetailViewJson' AS view, count(*) FROM aspa."SalesOrderDetailViewJson";
SELECT 'SalesOrderRequirementView' AS view, count(*) FROM aspa."SalesOrderRequirementView";
SELECT 'SalesOrderShort' AS view, count(*) FROM aspa."SalesOrderShort";
SELECT 'SalesOrderValueView' AS view, count(*) FROM aspa."SalesOrderValueView";
SELECT 'SalesOrderView' AS view, count(*) FROM aspa."SalesOrderView";
SELECT 'SalesSatusSelector' AS view, count(*) FROM aspa."SalesSatusSelector";
SELECT 'SalesStatus' AS view, count(*) FROM aspa."SalesStatus";
SELECT 'ShopSalesByDay' AS view, count(*) FROM aspa."ShopSalesByDay";
SELECT 'ShopTempSummary' AS view, count(*) FROM aspa."ShopTempSummary";
SELECT 'SortConsistency' AS view, count(*) FROM aspa."SortConsistency";
SELECT 'SortDetailShort' AS view, count(*) FROM aspa."SortDetailShort";
SELECT 'SortDetails' AS view, count(*) FROM aspa."SortDetails";
SELECT 'SortDetails1' AS view, count(*) FROM aspa."SortDetails1";
SELECT 'SortPending' AS view, count(*) FROM aspa."SortPending";
SELECT 'SortPendingSum' AS view, count(*) FROM aspa."SortPendingSum";
SELECT 'SortProcesses' AS view, count(*) FROM aspa."SortProcesses";
SELECT 'SortProcesses_c' AS view, count(*) FROM aspa."SortProcesses_c";
SELECT 'StockIngress' AS view, count(*) FROM aspa."StockIngress";
SELECT 'TaxiDrivers' AS view, count(*) FROM aspa."TaxiDrivers";
SELECT 'Tracking' AS view, count(*) FROM aspa."Tracking";
SELECT 'Tracking_crates' AS view, count(*) FROM aspa."Tracking_crates";
SELECT 'TransferAndrian2Terlan' AS view, count(*) FROM aspa."TransferAndrian2Terlan";
SELECT 'TransferOrderView' AS view, count(*) FROM aspa."TransferOrderView";
SELECT 'WarehouseTransit' AS view, count(*) FROM aspa."WarehouseTransit";
SELECT 'Weekly' AS view, count(*) FROM aspa."Weekly";
SELECT 'Workers' AS view, count(*) FROM aspa."Workers";
SELECT 'admin_cost_base' AS view, count(*) FROM aspa."admin_cost_base";
SELECT 'admin_sort_processing' AS view, count(*) FROM aspa."admin_sort_processing";
SELECT 'admin_taxi_deliveries' AS view, count(*) FROM aspa."admin_taxi_deliveries";
SELECT 'current_ingress_process' AS view, count(*) FROM aspa."current_ingress_process";
SELECT 'current_sort_process' AS view, count(*) FROM aspa."current_sort_process";
SELECT 'daily_ingress_process' AS view, count(*) FROM aspa."daily_ingress_process";
SELECT 'daily_sort_process' AS view, count(*) FROM aspa."daily_sort_process";
SELECT 'list_daily_ingress_groupby_member' AS view, count(*) FROM aspa."list_daily_ingress_groupby_member";
SELECT 'list_daily_ingress_process' AS view, count(*) FROM aspa."list_daily_ingress_process";
SELECT 'list_daily_sort_process' AS view, count(*) FROM aspa."list_daily_sort_process";
SELECT 'sort_delivery' AS view, count(*) FROM aspa."sort_delivery";
SELECT 'sort_delivery_id' AS view, count(*) FROM aspa."sort_delivery_id";
SELECT 'sort_last_day' AS view, count(*) FROM aspa."sort_last_day";
SELECT 'weekly_totals' AS view, count(*) FROM aspa."weekly_totals";

-- ============ TIER 3 - STRUCTURE ============
\echo '=== T3 aspa base tables ==='
SELECT count(*) FROM information_schema.tables WHERE table_schema='aspa' AND table_type='BASE TABLE';
\echo '=== T3 aspa views ==='
SELECT count(*) FROM pg_views WHERE schemaname='aspa';
\echo '=== T3 aspa functions ==='
SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='aspa' AND p.prokind='f';
\echo '=== T3 aspa EAR functions ==='
SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='aspa' AND p.prokind='f' AND p.proname ILIKE 'ear%';
\echo '=== T3 schemas ==='
SELECT nspname FROM pg_namespace WHERE nspname IN ('aspa','public','tax_reports','winery') ORDER BY 1;
\echo '=== T3 roles ==='
SELECT rolname FROM pg_roles WHERE rolname IN ('mkoroschetz','reporter','grafana_user') ORDER BY 1;
\echo '=== T3 inventory (deleted=false) ==='
SELECT count(*) FROM aspa.inventory WHERE deleted = false;
\echo '=== T3 inventory (all) ==='
SELECT count(*) FROM aspa.inventory;
\echo '=== T3 extensions in aspadb ==='
SELECT extname||' '||extversion FROM pg_extension ORDER BY 1;
\echo '=== T3 core base-table counts ==='
SELECT 'sort_items' AS t, count(*) FROM aspa.sort_items
UNION ALL SELECT 'inventory_log', count(*) FROM aspa.inventory_log
UNION ALL SELECT 'log_raw', count(*) FROM aspa.log_raw
UNION ALL SELECT 'orders', count(*) FROM aspa.orders
UNION ALL SELECT 'order_details', count(*) FROM aspa.order_details
UNION ALL SELECT 'customers', count(*) FROM aspa.customers
UNION ALL SELECT 'person', count(*) FROM aspa.person
UNION ALL SELECT 'delivery', count(*) FROM aspa.delivery
UNION ALL SELECT 'delivery_items', count(*) FROM aspa.delivery_items
UNION ALL SELECT 'sort_process', count(*) FROM aspa.sort_process
UNION ALL SELECT 'shop_sale', count(*) FROM aspa.shop_sale
UNION ALL SELECT 'tracking_barcodes', count(*) FROM aspa.tracking_barcodes
UNION ALL SELECT 'warehouses', count(*) FROM aspa.warehouses
UNION ALL SELECT 'classes', count(*) FROM aspa.classes
UNION ALL SELECT 'pricelists', count(*) FROM aspa.pricelists;

-- ============ TIER 4 - CATALOG (diffable) ============
\echo '=== T4 aspa index count ==='
SELECT count(*) FROM pg_indexes WHERE schemaname='aspa';
\echo '=== T4 FK columns missing a leading index (aspa) ==='
SELECT c.conrelid::regclass::text AS table, a.attname AS fk_column, c.conname AS constraint
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'f'
  AND c.connamespace = 'aspa'::regnamespace
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND i.indkey[0] = a.attnum
  )
ORDER BY c.conrelid::regclass::text, a.attname;
