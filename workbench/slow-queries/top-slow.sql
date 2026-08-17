-- top-slow.sql
-- Top 20 queries by total execution time (from pg_stat_statements).
-- Requires the pg_stat_statements extension to be installed (see README).
--
-- pct = share of total server time; high pct + high mean_ms = top candidate
-- for index work.
--
-- PostgreSQL version compatibility:
--   PG 13+ : planning time is tracked separately; columns are
--            total_exec_time / mean_exec_time / max_exec_time.
--   PG 12- : only execution time is tracked; columns are
--            total_time / mean_time / max_time.
--
-- Column names are resolved at parse time by the server, so a plain CASE
-- cannot switch between them (PG 12 would fail to parse the PG 13 names
-- even if the branch is never taken). This script builds the query with
-- format() + \gexec (same pattern as setup-roles.sql), so only the correct
-- statement is ever sent to the server. Works on PG 12 and PG 13+.

SELECT format(
'SELECT calls,
       round(%1$s / 1000, 2)                         AS total_s,
       round(%2$s, 2)                                AS mean_ms,
       round(%3$s, 2)                                AS max_ms,
       round((100 * %1$s / NULLIF(SUM(%1$s) OVER (), 0))::numeric, 2) AS pct,
       rows,
       left(query, 200)                              AS query
FROM pg_stat_statements
ORDER BY %1$s DESC
LIMIT 20;',
CASE WHEN current_setting('server_version_num')::int >= 130000
     THEN 'total_exec_time' ELSE 'total_time' END,
CASE WHEN current_setting('server_version_num')::int >= 130000
     THEN 'mean_exec_time' ELSE 'mean_time' END,
CASE WHEN current_setting('server_version_num')::int >= 130000
     THEN 'max_exec_time' ELSE 'max_time' END
)
\gexec
