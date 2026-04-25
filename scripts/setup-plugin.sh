#!/usr/bin/env bash
set -euo pipefail

# Enroll the fixture plugin via the project-local marketplace at .claude-plugin/.
# Idempotent: re-running adds nothing if the marketplace is already registered
# and the plugin is already installed.
#
# NOTE: `claude plugin marketplace add` expects a directory that *contains*
# .claude-plugin/marketplace.json — so we pass REPO_ROOT, not REPO_ROOT/.claude-plugin.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_NAME="native-agent-observability-local"
PLUGIN_NAME="observability"

[ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ] || {
  echo "ERROR: marketplace file not found at $REPO_ROOT/.claude-plugin/marketplace.json" >&2
  exit 1
}

claude plugin marketplace add "$REPO_ROOT" --scope project || true
claude plugin install "$PLUGIN_NAME@$MARKETPLACE_NAME" --scope project || true

echo "Installed fixture plugin '$PLUGIN_NAME' from local marketplace '$MARKETPLACE_NAME'"
echo "Verify: claude plugin list"
