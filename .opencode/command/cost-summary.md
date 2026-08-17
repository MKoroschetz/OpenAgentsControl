---
description: Aggregate OpenCode token usage and cost across sessions - totals, per-model profiling, and history
tags:
  - cost
  - tokens
  - usage
  - analysis
---

# Cost Summary

You are a cost analysis specialist. Run the OpenCode token usage aggregator and present a clear summary of LLM token consumption and spend.

## Execution

Run the aggregator script:

```bash
bash scripts/check-context-logs/sum-token-usage.sh
```

## Arguments

- **`/cost-summary all`** → include sessions from **all** projects on this machine:
  ```bash
  bash scripts/check-context-logs/sum-token-usage.sh --all
  ```
- **`/cost-summary history`** → show append-only cost history (cost trending over time):
  ```bash
  bash scripts/check-context-logs/sum-token-usage.sh --history
  ```
- **`/cost-summary <custom-storage-path>`** → point at a non-default OpenCode storage dir:
  ```bash
  bash scripts/check-context-logs/sum-token-usage.sh --storage <path>
  ```
- **`/cost-summary json`** → dump full structured snapshot as JSON (`--json`)

## Presentation

Present the results as a concise markdown report:

1. **Totals** - session count, input/output/reasoning/cache tokens, total cost
2. **By model** - ranked table of models with messages, input, output, cache, cost
3. **Insights** - call out:
   - Top cost drivers (highest $ models)
   - Free vs paid models usage share
   - Per-message cost outliers (cost ÷ messages)
   - Any models worth switching away from for cost savings

If any command fails (e.g. storage not found), check `~/.local/share/opencode/storage`, offer `--storage` guidance, and report the error clearly.

## Notes

- Data is aggregated from real per-message token/cost records in OpenCode local storage (not estimates).
- Snapshot and history are written to `.tmp/token-usage/` (gitignored).
- Default scope is sessions matching this project directory; use `all` for machine-wide totals.