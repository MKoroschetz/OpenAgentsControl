#!/usr/bin/env bash
#
# run.sh - Execute a .sql file against the remote PostgreSQL database.
# **Project**: aspaDB-workbench | **Path**: workbench/scripts/run.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-11 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-11): Initial standard header
#
# Usage:
#   ./scripts/run.sh [-e <profile>] <query-file.sql> [output-name]
#
# Examples:
#   ./scripts/run.sh schema-analysis/tables-overview.sql
#   ./scripts/run.sh -e dev schema-analysis/tables-overview.sql
#   ./scripts/run.sh -e prod slow-queries/top-slow.sql top-slow-2026-08-06
#
# Profile (-e):
#   -e prod  -> uses .env.prod (production host)
#   -e dev   -> uses .env.dev  (dev host)
#   (no -e)  -> uses .env (default)
#   Also honored: WORKBENCH_PROFILE env var.
#
# Behavior:
#   - Loads connection settings from the selected .env file
#   - Runs the file with psql, writing results to reports/<output-name>.txt
#   - If no output-name given, uses the sql filename with a timestamp
#
# Requirements: psql installed locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Parse arguments
PROFILE="${WORKBENCH_PROFILE:-}"
while getopts "e:h" opt; do
  case "$opt" in
    e) PROFILE="$OPTARG" ;;
    h) echo "Usage: $0 [-e <profile>] <query-file.sql> [output-name]"; exit 0 ;;
    *) echo "Usage: $0 [-e <profile>] <query-file.sql> [output-name]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Load environment (profile-aware)
load_env "$PROFILE"

# Validate arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 [-e <profile>] <query-file.sql> [output-name]" >&2
  exit 1
fi

QUERY_FILE="$1"
if [ ! -f "$QUERY_FILE" ]; then
  echo "Error: file not found: $QUERY_FILE" >&2
  exit 1
fi

# Determine output name and ensure reports dir exists
OUTPUT_NAME="${2:-$(basename "$QUERY_FILE" .sql)-$(date +%Y%m%d-%H%M%S)}"
REPORTS_DIR="$WORKBENCH_DIR/reports"
mkdir -p "$REPORTS_DIR"

# Honor SSH tunnel preference
if [ "${PG_USE_SSH_TUNNEL:-0}" = "1" ]; then
  export PGHOST="${PGHOST:-localhost}"
  export PGPORT="${PGPORT:-5432}"
fi

# Execute
echo "Running $QUERY_FILE against $PGHOST:$PGPORT/$PGDATABASE ..."
if psql \
    -h "${PGHOST:-localhost}" \
    -p "${PGPORT:-5432}" \
    -d "${PGDATABASE:-postgres}" \
    -U "${PGUSER:-postgres}" \
    --no-psqlrc \
    --set ON_ERROR_STOP=1 \
    --file "$QUERY_FILE" > "$REPORTS_DIR/$OUTPUT_NAME.txt" 2>&1; then
  echo "Done. Output: reports/$OUTPUT_NAME.txt"
else
  echo "Query failed. See reports/$OUTPUT_NAME.txt for details." >&2
  exit 1
fi
