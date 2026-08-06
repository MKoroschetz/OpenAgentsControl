#!/usr/bin/env bash
#
# lib.sh - Shared helpers for workbench scripts.
#
# Usage (in run.sh / snapshot.sh):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Provides:
#   load_env [profile] - source the correct .env file for a profile.
#
# Profile resolution:
#   load_env prod   -> sources .env.prod
#   load_env dev    -> sources .env.dev
#   load_env        -> sources .env (default, backward compatible)
#   WORKBENCH_PROFILE env var can also be used (see scripts).

# Resolve the workbench root from this file's own location, so it works
# regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKBENCH_DIR="$(dirname "$SCRIPT_DIR")"

# load_env [profile]
#   Sourced from the workbench .env files. Exports variables to the
#   current shell (set -a / set +a), never hardcoded in scripts.
load_env() {
  local profile="${1:-}"
  local env_file="$WORKBENCH_DIR/.env"

  if [ -n "$profile" ]; then
    env_file="$WORKBENCH_DIR/.env.$profile"
  fi

  if [ ! -f "$env_file" ]; then
    echo "Error: environment file not found: $env_file" >&2
    echo "       Create it from .env.example, e.g.:" >&2
    echo "         cp .env.example .env.$profile" >&2
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}
