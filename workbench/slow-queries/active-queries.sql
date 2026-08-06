-- active-queries.sql
-- Show queries currently running on the server.
-- Use this to spot long-running / stuck queries in real time.

SELECT pid,
       state,
       now() - query_start                      AS duration,
       coalesce(wait_event_type, '')            AS wait_type,
       left(query, 150)                         AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY query_start;
