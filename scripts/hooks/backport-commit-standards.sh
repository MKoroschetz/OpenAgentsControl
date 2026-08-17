#!/bin/bash

# backport-commit-standards.sh - Copy commit standards into other projects.
# **Project**: aspaDB-workbench | **Path**: scripts/hooks/backport-commit-standards.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-15
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-15): Initial standard header; backport hook + CI + docs to target repos
#
# Usage: ./scripts/hooks/backport-commit-standards.sh /path/to/project1 [/path/to/project2 ...]
#
# Per project, installs:
#   1. .githooks/commit-msg                 - version-controlled hook (share with teammates)
#   2. copy into the active hooks dir       - immediate local enforcement
#   3. .github/workflows/pr-title-check.yml - CI PR title validation (idempotent)
#   4. commit guidelines section            - appended to CONTRIBUTING.md (idempotent)
#
# No external dependencies. Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/commit-msg"
WORKFLOW_SRC="$(cd "$SCRIPT_DIR/../ci" && pwd)/pr-title-check.yml"
DOCS_SRC="$(cd "$SCRIPT_DIR/../../docs/contributing" && pwd)/CONTRIBUTING.md"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 /path/to/project1 [/path/to/project2 ...]"
  exit 1
fi

for PROJ in "$@"; do
  PROJ="$(cd "$PROJ" && pwd)"
  echo "==> Backporting to: $PROJ"

  if [ ! -d "$PROJ/.git" ]; then
    echo "    SKIP: not a git repository (no .git)"
    continue
  fi

  # 1. Version-controlled copy for the team
  mkdir -p "$PROJ/.githooks"
  cp "$HOOK_SRC" "$PROJ/.githooks/commit-msg"
  chmod +x "$PROJ/.githooks/commit-msg"
  echo "    Installed .githooks/commit-msg"

  # 2. Direct install where git actually looks for hooks (respects core.hooksPath)
  HOOKS_DIR="$(git -C "$PROJ" rev-parse --path-format=absolute --git-path hooks)"
  mkdir -p "$HOOKS_DIR"
  cp "$HOOK_SRC" "$HOOKS_DIR/commit-msg"
  chmod +x "$HOOKS_DIR/commit-msg"
  echo "    Enabled locally: $HOOKS_DIR/commit-msg"

  # 3. CI PR title validation (never overwrite existing)
  if [ ! -f "$PROJ/.github/workflows/pr-title-check.yml" ]; then
    mkdir -p "$PROJ/.github/workflows"
    cp "$WORKFLOW_SRC" "$PROJ/.github/workflows/pr-title-check.yml"
    echo "    Added .github/workflows/pr-title-check.yml"
  else
    echo "    Existing pr-title-check.yml left unchanged (merge patterns manually)"
  fi

  # 4. Commit guidelines docs section (never duplicate)
  if [ -f "$PROJ/docs/contributing/CONTRIBUTING.md" ]; then
    DOCS="$PROJ/docs/contributing/CONTRIBUTING.md"
  elif [ -f "$PROJ/CONTRIBUTING.md" ]; then
    DOCS="$PROJ/CONTRIBUTING.md"
  else
    DOCS="$PROJ/docs/contributing/CONTRIBUTING.md"
  fi
  mkdir -p "$(dirname "$DOCS")"
  [ -f "$DOCS" ] || touch "$DOCS"

  if grep -q '^## Commit Message Guidelines$' "$DOCS"; then
    echo "    Existing commit guidelines section left unchanged"
  else
    printf '\n\n' >> "$DOCS"
    awk '/^## Commit Message Guidelines$/{f=1} f{print} /^## Pull Request Guidelines$/{exit}' "$DOCS_SRC" >> "$DOCS"
    printf '\n' >> "$DOCS"
    echo "    Appended Commit Message Guidelines to $DOCS"
  fi
done

echo ""
echo "Done. In each project, commit these files: .githooks/, .github/workflows/pr-title-check.yml, and the CONTRIBUTING.md change."
echo "Teammates only need to run: git config core.hooksPath .githooks"