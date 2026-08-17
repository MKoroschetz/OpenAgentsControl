#!/usr/bin/env bash
#
# sum-token-usage.sh - OpenCode token usage + cost aggregator.
# **Project**: aspaDB-workbench | **Path**: scripts/check-context-logs/sum-token-usage.sh
# **Version**: v1.1.0 | **Last Updated**: 2026-08-17
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.1.0 (2026-08-17): Read from opencode.db (SQLite) when present - current
#   opencode writes message/session data to the DB, not the legacy JSON storage
#   (which stopped updating 2026-03-13). DB rows are extracted into the legacy
#   layout in a temp dir and the existing jq pipeline is reused unchanged.
#   Added --db flag; --storage still works for legacy-only installs.
# - v1.0.0 (2026-08-15): Initial aggregator (legacy JSON storage only)
#
# Tracks real token usage + cost across all OpenCode sessions for this project.
# Reads local OpenCode storage (message-level tokens/cost) and writes a gitignored
# snapshot + append-only history for cost analysis.
#
# Usage:
#   ./sum-token-usage.sh               # summarize this project's sessions
#   ./sum-token-usage.sh --all         # include sessions outside this repo
#   ./sum-token-usage.sh --storage DIR # custom OpenCode storage root (legacy JSON)
#   ./sum-token-usage.sh --db PATH     # explicit opencode.db (SQLite) path
#   ./sum-token-usage.sh --history     # print the history table
#   ./sum-token-usage.sh --json        # emit latest snapshot as JSON
#
# Source priority: --db > $OPENCODE_DB > <storage>/../opencode.db > legacy JSON.
# Requires: jq, python3 (SQLite extraction). Output lives in .tmp/token-usage/.

set -euo pipefail

# Colors
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STORAGE="${OPENCODE_STORAGE:-$HOME/.local/share/opencode/storage}"
DATA_DIR="$WORKSPACE_ROOT/.tmp/token-usage"
LATEST_JSON="$DATA_DIR/latest.json"
HISTORY_CSV="$DATA_DIR/history.csv"

DB_PATH=""
DB_TMP=""
trap 'rm -rf "$DB_TMP"' EXIT

INCLUDE_ALL=""
MODE="summary"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) INCLUDE_ALL="1" ;;
        --storage) STORAGE="$2"; shift ;;
        --db) DB_PATH="$2"; shift ;;
        --history) MODE="history" ;;
        --json) MODE="json" ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
    esac
    shift
done

# --- Source detection: SQLite DB (current) vs legacy JSON storage ---
SOURCE_LABEL="$STORAGE"
DB_PATH="${DB_PATH:-${OPENCODE_DB:-}}"
if [[ -z "$DB_PATH" && -f "$STORAGE/../opencode.db" ]]; then
    DB_PATH="$STORAGE/../opencode.db"
fi

if [[ -n "$DB_PATH" && -f "$DB_PATH" ]]; then
    # Extract DB rows into the legacy layout in a temp dir, then reuse the
    # existing jq pipeline below unchanged. Messages are written as JSONL
    # (one message per line) so `jq -s` slurps them into one array.
    DB_TMP=$(mktemp -d)
    if ! python3 - "$DB_PATH" "$DB_TMP" <<'PY'
import json, os, sqlite3, sys

db_path, out_root = sys.argv[1], sys.argv[2]
session_dir = os.path.join(out_root, "session")
msg_root = os.path.join(out_root, "message")
os.makedirs(session_dir, exist_ok=True)
os.makedirs(msg_root, exist_ok=True)

con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
cur = con.cursor()

for sid, directory, created in cur.execute(
    "SELECT id, directory, time_created FROM session"
):
    meta = {"id": sid, "directory": directory or "?", "time": {"created": created or 0}}
    with open(os.path.join(session_dir, f"{sid}.json"), "w") as f:
        json.dump(meta, f)

for sid, data in cur.execute("SELECT session_id, data FROM message"):
    try:
        d = json.loads(data)
    except Exception:
        continue
    if not isinstance(d, dict):
        continue
    mdir = os.path.join(msg_root, sid)
    os.makedirs(mdir, exist_ok=True)
    with open(os.path.join(mdir, "messages.json"), "a") as f:
        f.write(json.dumps(d) + "\n")
PY
    then
        echo -e "${RED}✗ Failed to read opencode.db: $DB_PATH${NC}" >&2
        exit 1
    fi
    STORAGE="$DB_TMP"
    SOURCE_LABEL="$DB_PATH"
elif [[ ! -d "$STORAGE/message" ]]; then
    echo -e "${RED}✗ OpenCode storage not found: $STORAGE${NC}" >&2
    echo "  Set OPENCODE_STORAGE, pass --storage (legacy JSON), or --db (SQLite)." >&2
    exit 1
fi

export SOURCE_LABEL
mkdir -p "$DATA_DIR"

# History mode works regardless of whether sessions exist yet
if [[ "$MODE" == "history" ]]; then
    if [[ ! -f "$HISTORY_CSV" ]]; then
        echo -e "${YELLOW}No history yet. Run the script once to create it.${NC}"
        exit 0
    fi
    echo -e "${BOLD}${CYAN}Token usage history${NC} ($HISTORY_CSV)"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    awk -F, 'NR==1 {print; next} {
        printf "%-22s %-8s %-12s %-12s %-12s %-12s %-10s $%.4f\n",
            $1, $2, $3, $4, $5, $6, $7, $8 }' "$HISTORY_CSV"
    exit 0
fi

# Collect session metadata (id + directory + timing)
SESSIONS_TSV=$(mktemp)
while IFS= read -r -d '' sfile; do
    id=$(basename "$sfile" .json)
    dir=$(jq -r '.directory // "?"' "$sfile" 2>/dev/null)
    created=$(jq -r '.time.created // 0' "$sfile" 2>/dev/null)
    printf '%s\t%s\t%s\n' "$id" "$dir" "$created" >> "$SESSIONS_TSV"
done < <(find "$STORAGE/session" -name '*.json' -print0 2>/dev/null)

# Filter to this project unless --all
FILTERED_TSV=$(mktemp)
if [[ -n "$INCLUDE_ALL" ]]; then
    cp "$SESSIONS_TSV" "$FILTERED_TSV"
else
    awk -F'\t' -v root="$WORKSPACE_ROOT" '$2 == root' "$SESSIONS_TSV" > "$FILTERED_TSV"
fi

session_count=$(wc -l < "$FILTERED_TSV" | tr -d ' ')

if [[ "$session_count" == "0" ]]; then
    echo -e "${YELLOW}No sessions found$([ -n "$INCLUDE_ALL" ] && echo ' (--all)' || echo ' for this project yet').${NC}"
    [[ -z "$INCLUDE_ALL" ]] && echo "  Open sessions are keyed by directory; none match: $WORKSPACE_ROOT"
    echo "  Tip: use --all to scan every session, or --storage for a different install."
    rm -f "$SESSIONS_TSV" "$FILTERED_TSV"
    exit 0
fi

# Aggregate per session: tokens + cost, keyed by model
TOTALS=$(mktemp -d)

while IFS=$'\t' read -r sid dir created; do
    msgdir="$STORAGE/message/$sid"
    [[ -d "$msgdir" ]] || continue

    jq -s --arg sid "$sid" --arg created "$created" '
        [.[] | select(.role == "assistant" and .tokens != null)] as $msgs |
        if ($msgs | length) == 0 then empty else
        {
            session: $sid,
            created: ($created | tonumber),
            msgs: ($msgs | length),
            input:   ($msgs | map(.tokens.input   // 0 | tonumber) | add),
            output:  ($msgs | map(.tokens.output  // 0 | tonumber) | add),
            reasoning: ($msgs | map(.tokens.reasoning // 0 | tonumber) | add),
            cache_read:  ($msgs | map(.tokens.cache.read  // 0 | tonumber) | add),
            cache_write: ($msgs | map(.tokens.cache.write // 0 | tonumber) | add),
            cost: ($msgs | map(.cost // 0 | tonumber) | add),
            models: ($msgs
                | map(. as $m |
                    { key: ($m.modelID // "unknown"),
                      input:   ($m.tokens.input   // 0 | tonumber),
                      output:  ($m.tokens.output  // 0 | tonumber),
                      reasoning: ($m.tokens.reasoning // 0 | tonumber),
                      cache_read:  ($m.tokens.cache.read  // 0 | tonumber),
                      cache_write: ($m.tokens.cache.write // 0 | tonumber),
                      cost: ($m.cost // 0 | tonumber),
                      msgs: 1 })
                | group_by(.key)
                | map({ model: .[0].key,
                        input:   (map(.input)   | add),
                        output:  (map(.output)  | add),
                        reasoning: (map(.reasoning) | add),
                        cache_read:  (map(.cache_read)  | add),
                        cache_write: (map(.cache_write) | add),
                        cost: (map(.cost) | add),
                        msgs: (map(.msgs) | add) }) )
        } end' "$msgdir"/*.json 2>/dev/null \
        > "$TOTALS/$sid.json" || true
done < "$FILTERED_TSV"

if [[ "$(ls "$TOTALS" 2>/dev/null | wc -l | tr -d ' ')" == "0" ]]; then
    echo -e "${YELLOW}No measurable sessions (no assistant messages with token data).${NC}"
    rm -f "$SESSIONS_TSV" "$FILTERED_TSV"; rm -rf "$TOTALS"
    exit 0
fi

# Merge everything
jq -s '
    (map(.models) | add | group_by(.model) | map({ model: .[0].model,
        input:   (map(.input)   | add),
        output:  (map(.output)  | add),
        reasoning: (map(.reasoning) | add),
        cache_read:  (map(.cache_read)  | add),
        cache_write: (map(.cache_write) | add),
        cost: (map(.cost) | add),
        msgs: (map(.msgs) | add),
        sessions: length })) as $modelRows |
    {
        generated: (now * 1000 | floor),
        project: (env.WORKSPACE_ROOT // ""),
        source: (env.SOURCE_LABEL // ""),
        sessions: length,
        totals: {
            input:     (map(.input)     | add),
            output:    (map(.output)    | add),
            reasoning: (map(.reasoning) | add),
            cache_read:  (map(.cache_read)  | add),
            cache_write: (map(.cache_write) | add),
            cost: (map(.cost) | add)
        },
        by_session: sort_by(.cost) | reverse,
        by_model: ($modelRows | sort_by(.cost) | reverse)
    }' "$TOTALS"/*.json > "$LATEST_JSON" 2>/dev/null || { echo -e "${RED}Aggregation failed${NC}" >&2; exit 1; }

# Append to append-only history (one row per run for cost trending)
if [[ -f "$LATEST_JSON" ]]; then
    row=$(jq -r '[.sessions, .totals.input, .totals.output, .totals.reasoning, .totals.cache_read, .totals.cache_write, (.totals.cost * 100 | round / 100)] | @csv' "$LATEST_JSON")
    if [[ ! -f "$HISTORY_CSV" ]]; then
        echo "timestamp,sessions,input,output,reasoning,cache_read,cache_write,cost_usd" > "$HISTORY_CSV"
    fi
    stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s,%s\n' "$stamp" "$row" >> "$HISTORY_CSV"
fi

if [[ "$MODE" == "json" ]]; then
    cat "$LATEST_JSON"
    rm -f "$SESSIONS_TSV" "$FILTERED_TSV"; rm -rf "$TOTALS"
    exit 0
fi

# Summary output
jq -r '.totals' "$LATEST_JSON" > /dev/null 2>&1
T=$(jq '.totals' "$LATEST_JSON")
IN=$(jq -r '.totals.input' "$LATEST_JSON")
OUT=$(jq -r '.totals.output' "$LATEST_JSON")
REAS=$(jq -r '.totals.reasoning' "$LATEST_JSON")
CR=$(jq -r '.totals.cache_read' "$LATEST_JSON")
CW=$(jq -r '.totals.cache_write' "$LATEST_JSON")
COST=$(jq -r '.totals.cost' "$LATEST_JSON")
MSGS=$(jq -r '[.by_session[].msgs] | add' "$LATEST_JSON")
SESS=$(jq -r '.sessions' "$LATEST_JSON")

fmt() { printf "%'d\n" "$1" 2>/dev/null || echo "$1"; }

echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  OpenCode Token Usage — ${BOLD}${GREEN}$SESS${CYAN} sessions${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BLUE}Project:${NC}    $WORKSPACE_ROOT"
echo -e "  ${BLUE}Source:${NC}     $SOURCE_LABEL"
echo -e "  ${BLUE}Snapshot:${NC}   $LATEST_JSON"
echo ""
echo -e "${BOLD}Tokens${NC}"
printf "  %-14s %s\n" "Input:"    "$(fmt "$IN")"
printf "  %-14s %s\n" "Output:"   "$(fmt "$OUT")"
printf "  %-14s %s\n" "Reasoning:" "$(fmt "$REAS")"
printf "  %-14s %s\n" "Cache read:" "$(fmt "$CR")"
printf "  %-14s %s\n" "Cache write:" "$(fmt "$CW")"
printf "  %-14s %s\n" "Messages:" "$(fmt "$MSGS")"
printf "  %-14s \$%.4f\n" "Cost:" "$COST"
echo ""
echo -e "${BOLD}By model${NC}"
jq -r '.by_model[] | [.model, .msgs, .input, .output, .cache_read, .cost] | @tsv' "$LATEST_JSON" 2>/dev/null | \
    awk -F'\t' '{ printf "  %-42s %6s msgs  in=%-12s out=%-10s cache=%-12s $%.4f\n", $1, $2, $3, $4, $5, $6 }'
echo ""
echo -e "History: $HISTORY_CSV"

rm -f "$SESSIONS_TSV" "$FILTERED_TSV"; rm -rf "$TOTALS"