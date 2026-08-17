#!/usr/bin/env bash
#
# monitor.sh - Sample live query activity from the database.
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/monitor.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-14 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-14): Initial live activity monitor
#
# Usage:
#   ./scripts/monitor.sh [-e <profile>] [-i <interval>] [-d <duration>] [-o <name>]
#
# Options:
#   -e <profile>    Env profile (.env.<profile>); defaults to WORKBENCH_PROFILE or .env
#   -i <seconds>    Sample interval (default 2)
#   -d <seconds>    Stop after N seconds (default: run until Ctrl-C)
#   -o <name>       Output name (default: activity-<timestamp>)
#
# Behavior:
#   - Polls pg_stat_activity for running/active/idle-in-transaction queries
#   - Logs pid, user, duration, wait event, and query text to reports/<name>.log
#   - Excludes its own connection and idle connections
#
# Requirements: psql installed locally, reporter role (read-only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

INTERVAL=2
DURATION=0
OUTPUT=""

while getopts "e:i:d:o:h" opt; do
  case "$opt" in
    e) PROFILE="$OPTARG" ;;
    i) INTERVAL="$OPTARG" ;;
    d) DURATION="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    h) echo "Usage: $0 [-e profile] [-i interval] [-d duration] [-o name]"; exit 0 ;;
    *) echo "Usage: $0 [-e profile] [-i interval] [-d duration] [-o name]" >&2; exit 1 ;;
  esac
done

PROFILE="${PROFILE:-${WORKBENCH_PROFILE:-}}"
load_env "$PROFILE"

OUTPUT="${OUTPUT:-activity-$(date +%Y%m%d-%H%M%S)}"
REPORTS_DIR="$WORKBENCH_DIR/reports"
LOG="$REPORTS_DIR/$OUTPUT.log"
mkdir -p "$REPORTS_DIR"

SAMPLES=0
START_TS="$(date +%s)"
echo "# activity monitor - $(date -Is) - host $PGHOST:$PGPORT/$PGDATABASE" > "$LOG"

stop_loop() {
  echo "" >> "$LOG"
  echo "# monitor stopped after $SAMPLES samples - $(date -Is)" >> "$LOG"
  echo "Stopped. Log: reports/$OUTPUT.log ($SAMPLES samples)" >&2
  exit 0
}
trap stop_loop INT TERM

echo "Monitoring $PGHOST:$PGPORT/$PGDATABASE every ${INTERVAL}s (Ctrl-C to stop). Log: reports/$OUTPUT.log"

while true; do
  NOW_TS="$(date +%s)"
  if [ "$DURATION" -gt 0 ] && [ $((NOW_TS - START_TS)) -ge "$DURATION" ]; then
    stop_loop
  fi

  psql -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -d "${PGDATABASE:-postgres}" \
    -U "${PGUSER:-postgres}" --no-psqlrc --no-align --field-separator='|' \
    -c "
      SELECT now()::timestamp(0),
             pid,
             coalesce(usename,'') AS usr,
             round(extract(epoch FROM (now() - query_start))::numeric, 2) AS dur_s,
             coalesce(state,'') AS state,
             coalesce(wait_event_type,'') AS wait_type,
             coalesce(wait_event,'') AS wait_event,
             coalesce(left(query, 300),'') AS query
      FROM pg_stat_activity
      WHERE state IS NOT NULL
        AND state <> 'idle'
        AND pid <> pg_backend_pid()
        AND query NOT ILIKE '%pg_stat_activity%'
      ORDER BY query_start;" >> "$LOG" 2>&1 || true

  SAMPLES=$((SAMPLES + 1))
  sleep "$INTERVAL"
done
