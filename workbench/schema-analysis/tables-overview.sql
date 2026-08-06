-- tables-overview.sql
-- Full DB picture: table sizes, estimated rows, and index counts.
-- Run first to identify the big tables worth focusing index work on.
--
-- Output columns: schema, table, total_size, table_size, index_size, est_rows, index_count

SELECT t.schemaname,
       t.relname                                                        AS table,
       pg_size_pretty(pg_total_relation_size(c.oid))                    AS total_size,
       pg_size_pretty(pg_relation_size(c.oid))                          AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid))                           AS index_size,
       t.n_live_tup                                                     AS est_rows,
       (SELECT count(*)
        FROM pg_indexes i
        WHERE i.schemaname = t.schemaname AND i.tablename = t.relname)  AS index_count
FROM pg_stat_user_tables t
JOIN pg_class c
  ON c.relname = t.relname
 AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = t.schemaname)
ORDER BY pg_total_relation_size(c.oid) DESC;
