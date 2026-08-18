#!/usr/bin/env bash
#
# run-regression.sh - Execute the A.8/B.8 regression suite against a profile.
# **Project**: aspaDB-workbench | **Path**: workbench/regression/run-regression.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-17
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# Usage:
#   ./regression/run-regression.sh dev            # run suite -> reports/regression/
#   ./regression/run-regression.sh dev pg17-2026-08-17
#   ./regression/run-regression.sh prod
#
# Behavior:
#   - Loads the connection settings from workbench/.env.<profile> (via lib.sh)
#   - Runs regression-list.sql with ON_ERROR_STOP=0 (report ALL failures,
#     do not stop at the first one)
#   - Writes the unaligned, deterministic output to
#     reports/regression/regression-<profile>-<timestamp>.txt
#   - Prints a PASS/FAIL summary (counts ERROR lines)
#
# Diff protocol (README.md):
#   run on dev PG 17 -> baseline; run on prod -> compare with diff(1).
#   Zero ERROR lines = suite VALID on that environment.

set -euo pipefail

# NOTE: lib.sh redefines SCRIPT_DIR to its own location - capture the
# runner's directory under REGRESSION_DIR BEFORE sourcing it.
REGRESSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REGRESSION_DIR/../scripts/lib.sh"
WORKBENCH_DIR="$(dirname "$REGRESSION_DIR")"

PROFILE="${1:-}"
if [ -z "$PROFILE" ]; then
  echo "Usage: $0 dev|prod [report-name]" >&2
  exit 1
fi

load_env "$PROFILE"

REPORT_NAME="${2:-regression-${PROFILE}-$(date +%Y%m%d-%H%M%S)}"
REPORTS_DIR="$WORKBENCH_DIR/reports/regression"
mkdir -p "$REPORTS_DIR"
REPORT="$REPORTS_DIR/$REPORT_NAME.txt"

# Suppress NOTICE spam (EAR functions emit many) and bound runaway statements.
export PGOPTIONS="-c client_min_messages=warning -c statement_timeout=300000"

echo "==> Running regression suite against ${PGHOST}:${PGPORT}/${PGDATABASE} as ${PGUSER}"
if ! psql \
    -h "${PGHOST}" \
    -p "${PGPORT}" \
    -U "${PGUSER}" \
    -d "${PGDATABASE}" \
    --no-psqlrc \
    -A -t \
    --set ON_ERROR_STOP=0 \
    -f "$REGRESSION_DIR/regression-list.sql" > "$REPORT" 2>&1; then
  echo "!! psql exited non-zero (expected when checks fail - report still written)" >&2
fi

ERR_COUNT=$(grep -c '^ERROR' "$REPORT" || true)
echo "==> Report: $REPORT"
echo "==> ERROR lines: $ERR_COUNT"
if [ "$ERR_COUNT" -eq 0 ]; then
  echo "==> RESULT: PASS - suite valid on ${PROFILE}"
else
  echo "==> RESULT: FAIL - review errors above"
  grep -n '^ERROR' "$REPORT" || true
fi
