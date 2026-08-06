-- indexes.sql
-- List every index in the database with its definition.
-- Useful before creating new indexes to avoid duplicates/redundancy.
--
-- Tip: replace 'your_table' with a specific table name to focus output.

SELECT schemaname,
       tablename,
       indexname,
       indexdef
FROM pg_indexes
-- WHERE tablename = 'your_table'   -- uncomment to filter
ORDER BY schemaname, tablename, indexname;
