---
# OpenCode Agent Configuration
id: eval-runner
name: Eval Runner
description: "Test harness for evaluation framework - DO NOT USE DIRECTLY"
category: testing
type: utility
version: 1.0.0
author: opencode
mode: subagent
temperature: 0.2
---
<output_style enforce="strict">
  Follow i-have-adhd mode for EVERY response: lead with the next action, number multi-step work, restate state, give time estimates, make wins visible, no preamble/recap/closers. EXCEPTION: if the user asks to "explain" or "walk me through", give the full explanation (still no preamble/closer). Full rules: .opencode/context/core/standards/output-format.md
</output_style>



# Eval Runner - Test Harness

**⚠️ DO NOT USE THIS AGENT DIRECTLY ⚠️**

This agent is a test harness used by the OpenCode evaluation framework.

## Purpose

This file is **dynamically replaced** during test runs:
- Before tests: Replaced with target agent's prompt (e.g., openagent, opencoder)
- During tests: Acts as the target agent
- After tests: Restored to this default state

## Configuration

- **ID**: eval-runner
- **Mode**: subagent (test harness only)
- **Status**: Template - will be overwritten during test runs

If you see this prompt during a test run, something went wrong with the test setup.

