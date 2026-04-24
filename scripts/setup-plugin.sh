#!/usr/bin/env bash
set -euo pipefail

# Copies the fixture plugin into the user's Claude Code plugin directory.
# Idempotent: re-running overwrites the existing installation.

REPO_ROOT=$(git rev-parse --show-toplevel)
SRC="$REPO_ROOT/fixtures/claude-plugin-observability"
DEST_BASE="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
DEST="$DEST_BASE/observability-fixture"

if [ ! -d "$SRC" ]; then
  echo "ERROR: fixture plugin not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST_BASE"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Installed fixture plugin to: $DEST"
echo "Verify Claude Code picks it up: claude /plugin list (or your local equivalent)"
