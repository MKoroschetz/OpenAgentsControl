-- unused-indexes.sql
-- Find indexes that are never (or rarely) used for scans.
-- idx_scan = 0 since last stats reset => likely dead weight.
-- Dropping these speeds up writes (INSERT/UPDATE/DELETE).
--
-- NOTE: numbers reset when stats are reset (pg_stat_reset() or restart).
-- A value of 0 right after restart means "unknown", not "unused".

SELECT s.schemaname,
       s.relname              AS table,
       s.indexrelname         AS index,
       s.idx_scan,
       s.idx_tup_read,
       s.idx_tup_fetch
FROM pg_stat_user_indexes s
ORDER BY s.idx_scan ASC, s.relname;
