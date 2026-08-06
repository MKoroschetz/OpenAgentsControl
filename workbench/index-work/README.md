# Index Work

This folder is where failing/slow query diagnosis and index changes live.

## Workflow

1. **Identify** the failing query (see `../slow-queries/`).
2. **Explain** it: paste the query into psql with
   `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) <query>;`
   and save the output here as `explain-<issue>.txt` so before/after
   comparisons are possible.
3. **Diagnose** what's missing (see checklist below).
4. **Create** the index with `CREATE INDEX CONCURRENTLY ...` (avoids
   locking the table during writes).
5. **Re-run** the EXPLAIN, then re-check `pg_stat_statements` after a
   few hours of production traffic.
6. **Record** findings in `findings.md`.

## What to look for in an EXPLAIN

| Pattern                    | Implication                                |
|----------------------------|--------------------------------------------|
| `Seq Scan` on big table    | Index on WHERE/JOIN/ORDER BY column        |
| `Bitmap Heap Scan`         | Index exists but low selectivity; composite index may help |
| `Sort`                     | Index matching ORDER BY                    |
| `Nested Loop` w/ many rows | Missing index on inner table's join column |

## Rules

- Always use `CREATE INDEX CONCURRENTLY` in production.
- One index per issue, verified before adding the next.
- Never drop an index without checking `unused-indexes.sql` AND knowing
  it's not used by a reporting/analytics path.
- Record every change in `findings.md` with before/after timings.
