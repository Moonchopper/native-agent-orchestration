#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: run-scenario.sh <scenario> <variant>" >&2
  echo "  scenarios: create-log-index" >&2
  echo "  variants : local-hit" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

SCENARIO="$1"
VARIANT="$2"

case "$SCENARIO" in
  create-log-index) ;;
  *)
    echo "ERROR: unknown scenario '$SCENARIO'" >&2
    usage
    ;;
esac

case "$VARIANT" in
  local-hit) ;;
  *)
    echo "ERROR: unknown variant '$VARIANT'" >&2
    usage
    ;;
esac

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN: would run scenario=$SCENARIO variant=$VARIANT"
  exit 0
fi

# --- Real run ---

REPO_ROOT=$(git rev-parse --show-toplevel)
FIXTURE_REPO="$REPO_ROOT/fixtures/datadog-operations"
SESSION_DIR=$(mktemp -d)
HANDOFF_FILE="$FIXTURE_REPO/.stage-1-handoff.json"

# Clean any prior handoff artifact so the assertion reflects this run only.
rm -f "$HANDOFF_FILE"

# Canned prompt — provides all inputs up front so the agent can proceed
# without an interactive confirmation loop.
PROMPT=$(cat <<'EOF'
Create a Datadog log index with these parameters:
- team: foobar
- env: prod
- filter: service:foobar-api env:prod
- tier: Flex
- days: 30
- quota: 1000000

Accept best-practice suggestions as-is. When the PR payload is ready,
hand off to the _pr-handoff skill.
EOF
)

# Invoke Claude Code headlessly from the fixture repo's working tree so
# the CWD-detection ladder hits its first branch.
cd "$FIXTURE_REPO"

# `claude -p` runs non-interactively. Permission mode `bypassPermissions`
# is used because the scenario runs inside a fixture repo sandbox and there
# is no interactive approver; Stage 2 will pass a settings.json with the
# metric-capture hook and a narrower tool allowlist.
claude -p --permission-mode bypassPermissions "$PROMPT" > "$SESSION_DIR/session.out" 2> "$SESSION_DIR/session.err" || {
  echo "ERROR: claude invocation failed" >&2
  echo "--- stderr ---" >&2
  cat "$SESSION_DIR/session.err" >&2
  exit 1
}

echo "Scenario completed. Session artifacts in: $SESSION_DIR"
echo "Handoff file: $HANDOFF_FILE"

# Run scenario-specific assertions.
ASSERTION_SCRIPT="$REPO_ROOT/scripts/assertions/${SCENARIO}-${VARIANT}.sh"
if [ -x "$ASSERTION_SCRIPT" ]; then
  "$ASSERTION_SCRIPT" "$HANDOFF_FILE"
else
  echo "WARN: no assertion script at $ASSERTION_SCRIPT — skipping assertions" >&2
fi
