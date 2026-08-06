-- top-slow.sql
-- Top 20 queries by total execution time (from pg_stat_statements).
-- Requires the pg_stat_statements extension to be installed (see README).
--
-- pct = share of total server time; high pct + high mean_ms = top candidate
-- for index work.

SELECT calls,
       round(total_exec_time / 1000, 2) AS total_s,
       round(mean_exec_time, 2)          AS mean_ms,
       round(max_exec_time, 2)           AS max_ms,
       round((100 * total_exec_time / NULLIF(sum(total_exec_time) OVER (), 0))::numeric, 2) AS pct,
       rows,
       left(query, 200)                  AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
