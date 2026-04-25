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
  echo "DRY_RUN: would run scenario=$SCENARIO variant=$VARIANT run_ix=${RUN_IX:-0}"
  exit 0
fi

# --- Real run ---

REPO_ROOT=$(git rev-parse --show-toplevel)
FIXTURE_REPO="$REPO_ROOT/fixtures/datadog-operations"
SESSION_DIR=$(mktemp -d)
HANDOFF_FILE="$FIXTURE_REPO/.stage-1-handoff.json"

# Tag this run's metrics with scenario/variant/run_ix so the aggregator
# can group across runs. RUN_IX is set by the benchmark driver in Part C;
# defaults to 0 for standalone runs.
export AGENT_ORCH_SCENARIO="$SCENARIO"
export AGENT_ORCH_VARIANT="$VARIANT"
export AGENT_ORCH_RUN_IX="${RUN_IX:-0}"
export AGENT_ORCH_SESSION_DIR="$SESSION_DIR"
export AGENT_ORCH_METRICS_FILE="${AGENT_ORCH_METRICS_FILE:-$SESSION_DIR/metrics.jsonl}"

# Clean any prior handoff artifact so the assertion reflects this run only.
rm -f "$HANDOFF_FILE"

# Also clean any drafted Terraform from a prior run so re-runs are
# self-contained and the agent's Step-8 diff reflects this run only.
rm -f "$FIXTURE_REPO/terraform/logs/indexes/foobar.tf"

# Canned prompt — provides all inputs up front so the agent can proceed
# without an interactive confirmation loop.
PROMPT=$(cat <<'EOF'
Invoke the observability:create-log-index skill and execute its golden
path end-to-end. Do NOT enter brainstorming or planning mode. Do NOT ask
for design approval — the golden path IS the approved design. Write
files, run the checks, and hand off to pr-handoff directly.

Parameters (already confirmed by the operator):
- team: foobar
- env: prod
- filter: service:foobar-api env:prod
- tier: Flex
- days: 30
- quota: 1000000

Accept best-practice suggestions as-is.
EOF
)

# System-level directive to prevent design-discussion mode.
BENCH_SYSTEM_PROMPT='You are running inside an automated benchmark harness. Do not enter brainstorming, design-review, or planning modes. Do not ask the operator for approval on design decisions — the skill body IS the approved design. Execute golden paths end-to-end. If a referenced skill or tool is unavailable, halt with a clear error; do not substitute an alternative.'

# Invoke Claude Code headlessly from the fixture repo's working tree so
# the CWD-detection ladder hits its first branch.
cd "$FIXTURE_REPO"

# `claude -p` runs non-interactively. We pass --settings pointing at
# settings/benchmark.settings.json which provides an explicit
# permissions.allow allowlist scoped to the tools create-log-index
# exercises (git, gh auth, terraform fmt/validate, file ops, Skill).
# Hook wiring lands in Task B4.
claude -p \
  --settings "$REPO_ROOT/settings/benchmark.settings.json" \
  --append-system-prompt "$BENCH_SYSTEM_PROMPT" \
  "$PROMPT" > "$SESSION_DIR/session.out" 2> "$SESSION_DIR/session.err" || {
  echo "ERROR: claude invocation failed" >&2
  echo "--- stderr ---" >&2
  cat "$SESSION_DIR/session.err" >&2
  exit 1
}

echo "Scenario completed. Session artifacts in: $SESSION_DIR"
echo "Handoff file: $HANDOFF_FILE"

# Extract per-turn token metrics from Claude Code's session transcript.
# The transcript path is derived from the cwd at claude -p invocation time:
# Claude Code munges path separators (\ : /) to '-' to form the project slug.
PROJECT_SLUG=$(echo "$FIXTURE_REPO" | sed -e 's/[\\:/.]/-/g' -e 's/^-*//')
TRANSCRIPT_DIR="$HOME/.claude/projects/$PROJECT_SLUG"
TRANSCRIPT=$(ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | head -1)

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "WARN: no transcript found under $TRANSCRIPT_DIR; skipping metric extraction" >&2
else
  "$REPO_ROOT/scripts/extract-metrics.sh" "$TRANSCRIPT"
  TURNS=$(wc -l < "$AGENT_ORCH_METRICS_FILE" 2>/dev/null || echo 0)
  echo "Metrics: $AGENT_ORCH_METRICS_FILE ($TURNS turns)"
fi

# Run scenario-specific assertions.
ASSERTION_SCRIPT="$REPO_ROOT/scripts/assertions/${SCENARIO}-${VARIANT}.sh"
if [ -x "$ASSERTION_SCRIPT" ]; then
  "$ASSERTION_SCRIPT" "$HANDOFF_FILE"
else
  echo "ERROR: no assertion script at $ASSERTION_SCRIPT" >&2
  echo "A scenario/variant pair that passes the runner's allowlist must have a matching assertion script." >&2
  exit 1
fi
