#!/usr/bin/env bash
#
# snapshot.sh - Capture a pg_stat_statements snapshot to track query
#               performance over time.
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/snapshot.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-11 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-11): Initial standard header
#
# Usage:
#   ./scripts/snapshot.sh [-e <profile>] [label]
#
# Examples:
#   ./scripts/snapshot.sh                # default profile, timestamp label
#   ./scripts/snapshot.sh -e prod before-index
#   ./scripts/snapshot.sh -e dev after-index
#
# Profile (-e):
#   -e prod  -> uses .env.prod (production host)
#   -e dev   -> uses .env.dev  (dev host)
#   (no -e)  -> uses .env (default)
#   Also honored: WORKBENCH_PROFILE env var.
#
# Output:
#   reports/snapshots/<label>.txt   - full top-50 slow query listing
#   reports/snapshots/<label>.csv   - machine-readable summary for diffing
#
# Tip: run periodically (e.g. cron every hour) and diff CSVs to see
# which queries regress or improve after index changes.
#
# Requires: psql + read-only access to pg_stat_statements.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Parse arguments
PROFILE="${WORKBENCH_PROFILE:-}"
while getopts "e:h" opt; do
  case "$opt" in
    e) PROFILE="$OPTARG" ;;
    h) echo "Usage: $0 [-e <profile>] [label]"; exit 0 ;;
    *) echo "Usage: $0 [-e <profile>] [label]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Load environment (profile-aware)
load_env "$PROFILE"

LABEL="${1:-$(date +%Y%m%d-%H%M%S)}"
SNAPSHOT_DIR="$WORKBENCH_DIR/reports/snapshots"
mkdir -p "$SNAPSHOT_DIR"

PSQL_CMD=(psql -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}"
  -d "${PGDATABASE:-postgres}" -U "${PGUSER:-postgres}" --no-psqlrc)

# Full listing (top 50 by total time)
"${PSQL_CMD[@]}" --file - > "$SNAPSHOT_DIR/$LABEL.txt" <<'SQL'
SELECT calls,
       round(total_exec_time / 1000, 2) AS total_s,
       round(mean_exec_time, 2)          AS mean_ms,
       round(max_exec_time, 2)           AS max_ms,
       round((100 * total_exec_time / NULLIF(sum(total_exec_time) OVER (), 0))::numeric, 2) AS pct,
       left(query, 120)                  AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 50;
SQL

# CSV summary (queryid + perf metrics, ideal for diffing snapshots)
"${PSQL_CMD[@]}" --no-align --field-separator=',' --file - > "$SNAPSHOT_DIR/$LABEL.csv" <<'SQL'
SELECT queryid, calls, total_exec_time, mean_exec_time, max_exec_time, rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC;
SQL

echo "Snapshot '$LABEL' saved:"
echo "  $SNAPSHOT_DIR/$LABEL.txt"
echo "  $SNAPSHOT_DIR/$LABEL.csv"
