#!/usr/bin/env bash
set -euo pipefail

# Enroll the fixture plugin via the project-local marketplace at .claude-plugin/.
# Idempotent: re-running adds nothing if the marketplace is already registered
# and the plugin is already installed.
#
# NOTE: `claude plugin marketplace add` expects a directory that *contains*
# .claude-plugin/marketplace.json — so we pass REPO_ROOT, not REPO_ROOT/.claude-plugin.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_NAME="native-agent-observability"
PLUGIN_NAME="observability"

command -v claude >/dev/null 2>&1 || {
  echo "ERROR: 'claude' (Claude Code CLI) not found in PATH" >&2
  echo "Install Claude Code first: https://claude.com/claude-code" >&2
  exit 1
}

[ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ] || {
  echo "ERROR: marketplace file not found at $REPO_ROOT/.claude-plugin/marketplace.json" >&2
  exit 1
}

# `|| true` covers the benign "already registered / already installed" case for
# idempotent re-runs. Trade-off: this also swallows real errors from claude CLI.
# A post-install verification below catches the "nothing actually installed" outcome.
claude plugin marketplace add "$REPO_ROOT" --scope project || true
claude plugin install "$PLUGIN_NAME@$MARKETPLACE_NAME" --scope project || true

if ! claude plugin list 2>/dev/null | grep -q "$PLUGIN_NAME@$MARKETPLACE_NAME"; then
  echo "ERROR: plugin '$PLUGIN_NAME@$MARKETPLACE_NAME' not found in 'claude plugin list' after install" >&2
  echo "Diagnose: run 'claude plugin marketplace list' and 'claude plugin list' manually." >&2
  exit 1
fi

echo "Installed fixture plugin '$PLUGIN_NAME' from local marketplace '$MARKETPLACE_NAME'"
