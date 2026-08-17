#!/bin/bash
#
# setup-postgres17.sh - scaffold the postgres17 service (build files + credential templates + data dir)
# **Project**: aspaDB-workbench | **Path**: docker/iotstack/setup-postgres17.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-16
# **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-16): Initial scaffold for the PG 17.11 upgrade
#   (docs/CORE-PLATFORM-UPGRADE.md Part A). Idempotent - existing files are
#   never overwritten.
#
# Usage:
#   ./setup-postgres17.sh [TARGET_DIR]
#
#   TARGET_DIR  IOTstack root to scaffold into (default: current directory).
#               Creates <TARGET>/services/postgres17/ + <TARGET>/volumes/postgres17/data/.
#
# What it does:
#   1. Copies BUILD files (Dockerfile, entrypoint.sh, init-pgagent.sh) from this
#      script's sibling dir services/postgres17/.
#   2. Copies TEMPLATE credential files from the existing services/postgres/
#      (postgres.env, pgagent.env, pgagent.pgpass) - REDACTED placeholders, the
#      user must edit them before first start. Never overwrites existing files.
#   3. Ends with a CHECKPOINT validation (all 6 files + data dir) and next steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(pwd)}"

SERVICE_DIR="$TARGET_DIR/services/postgres17"
DATA_DIR="$TARGET_DIR/volumes/postgres17/data"
TEMPLATE_DIR="$TARGET_DIR/services/postgres"

BUILD_FILES=(Dockerfile entrypoint.sh init-pgagent.sh)
TEMPLATE_FILES=(postgres.env pgagent.env pgagent.pgpass)

echo "==> Scaffolding postgres17 service into: $TARGET_DIR"

# --- preconditions -----------------------------------------------------------
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "ERROR: template source dir not found: $TEMPLATE_DIR" >&2
  echo "       Expected the existing PG12 service (services/postgres/) under the target dir." >&2
  exit 1
fi

mkdir -p "$SERVICE_DIR" "$DATA_DIR"

# --- copy build files (from this script's sibling dir) ------------------------
for f in "${BUILD_FILES[@]}"; do
  src="$SCRIPT_DIR/services/postgres17/$f"
  dst="$SERVICE_DIR/$f"
  if [ -e "$dst" ]; then
    echo "SKIP  $dst (already present)"
  elif [ ! -f "$src" ]; then
    echo "ERROR: build file missing next to this script: $src" >&2
    exit 1
  else
    cp "$src" "$dst"
    case "$f" in
      *.sh) chmod +x "$dst" ;;
    esac
    echo "COPY  $src -> $dst"
  fi
done

# --- copy credential TEMPLATES (never overwrite) ------------------------------
for f in "${TEMPLATE_FILES[@]}"; do
  src="$TEMPLATE_DIR/$f"
  dst="$SERVICE_DIR/$f"
  if [ -e "$dst" ]; then
    echo "SKIP  $dst (already present)"
  elif [ ! -f "$src" ]; then
    echo "ERROR: template file missing: $src" >&2
    exit 1
  else
    cp "$src" "$dst"
    echo "COPY  $src -> $dst (TEMPLATE - edit before first start)"
  fi
done

# --- CHECKPOINT validation -----------------------------------------------------
echo ""
echo "==> CHECKPOINT: verifying scaffold"
missing=0
for f in "${BUILD_FILES[@]}" "${TEMPLATE_FILES[@]}"; do
  if [ -f "$SERVICE_DIR/$f" ]; then
    echo "  OK   $SERVICE_DIR/$f"
  else
    echo "  MISS $SERVICE_DIR/$f"
    missing=1
  fi
done
if [ -d "$DATA_DIR" ]; then
  echo "  OK   $DATA_DIR (data dir)"
else
  echo "  MISS $DATA_DIR (data dir)"
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  echo "ERROR: scaffold incomplete - fix the MISS lines above." >&2
  exit 1
fi

echo ""
echo "==> postgres17 scaffold complete."
echo ""
echo "Next steps:"
echo "  1. Edit credentials in $SERVICE_DIR/postgres.env and $SERVICE_DIR/pgagent.pgpass"
echo "     (templates carry REDACTED placeholders - real passwords live on the host)."
echo "  2. chmod 600 $SERVICE_DIR/pgagent.pgpass"
echo "  3. Start the side-by-side container:  docker compose up -d postgres17"
echo "     (compose: docker/iotstack/docker-compose.target-postgres.yml; cutover: runbook A.9)"