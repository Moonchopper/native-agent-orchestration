#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: run-scenario.sh <scenario> <variant>" >&2
  echo "  scenarios: create-log-index" >&2
  echo "  variants : local-hit, cwd-shortcut, remote-fallback" >&2
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
  local-hit|cwd-shortcut|remote-fallback) ;;
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
SESSION_DIR=$(mktemp -d)

# Conventional path the detection ladder will find for `local-hit`.
# (Per architecture spec §9.1 step 2: ~/src/<org>/<repo> is the first probed
# conventional path.)
CONVENTIONAL_CLONE_DIR="$HOME/src/Moonchopper/datadog-operations"

# Per-variant fixture-state setup. The runner's job is to put the working
# tree in the right state BEFORE claude -p starts. The agent's detection
# ladder then runs against that state.
case "$VARIANT" in
  local-hit)
    # Functional repo present at conventional path; CWD = run scratch dir
    # (NOT the clone). Agent's CWD-match check (§9.1 step 1) misses;
    # conventional-path check (§9.1 step 2) hits.
    if [ ! -d "$CONVENTIONAL_CLONE_DIR/.git" ]; then
      mkdir -p "$(dirname "$CONVENTIONAL_CLONE_DIR")"
      gh repo clone Moonchopper/datadog-operations "$CONVENTIONAL_CLONE_DIR"
    else
      # Refresh to a known-clean state for run reproducibility.
      git -C "$CONVENTIONAL_CLONE_DIR" fetch origin
      git -C "$CONVENTIONAL_CLONE_DIR" reset --hard origin/main
      git -C "$CONVENTIONAL_CLONE_DIR" clean -fd
    fi
    FIXTURE_REPO="$CONVENTIONAL_CLONE_DIR"
    INVOCATION_CWD="$SESSION_DIR"
    ;;

  cwd-shortcut)
    # Functional repo present at conventional path; CWD = the clone.
    # Agent's CWD-match check (§9.1 step 1) hits immediately.
    if [ ! -d "$CONVENTIONAL_CLONE_DIR/.git" ]; then
      mkdir -p "$(dirname "$CONVENTIONAL_CLONE_DIR")"
      gh repo clone Moonchopper/datadog-operations "$CONVENTIONAL_CLONE_DIR"
    else
      git -C "$CONVENTIONAL_CLONE_DIR" fetch origin
      git -C "$CONVENTIONAL_CLONE_DIR" reset --hard origin/main
      git -C "$CONVENTIONAL_CLONE_DIR" clean -fd
    fi
    FIXTURE_REPO="$CONVENTIONAL_CLONE_DIR"
    INVOCATION_CWD="$CONVENTIONAL_CLONE_DIR"
    ;;

  remote-fallback)
    # NO clone at any conventional path. Agent's detection ladder must
    # miss steps 1-3 and hit step 4 (ask user / offer to clone).
    # The test driver's prompt answers "yes, clone it."
    for dir in \
      "$HOME/src/Moonchopper/datadog-operations" \
      "$HOME/code/Moonchopper/datadog-operations" \
      "$HOME/git/Moonchopper/datadog-operations" \
      "$HOME/work/Moonchopper/datadog-operations"; do
      if [ -d "$dir/.git" ]; then
        echo "ERROR: remote-fallback requires NO clone at conventional paths." >&2
        echo "Found pre-existing clone at: $dir" >&2
        echo "Remove it (or rename) and re-run." >&2
        exit 1
      fi
    done
    # EXPECTED_CLONE_PATH is the single source of truth for "where the agent
    # is told to clone to" — referenced by both the PROMPT (clone authorization
    # text) and the assertion script (clone-existence check). One literal,
    # not two; prevents drift between prompt and assertion.
    FIXTURE_REPO="$HOME/src/Moonchopper/datadog-operations"
    INVOCATION_CWD="$SESSION_DIR"
    ;;
esac

# Single source of truth for where remote-fallback expects the clone to
# end up. local-hit/cwd-shortcut clone before claude -p so this is
# already-known; remote-fallback uses it in the PROMPT text.
export EXPECTED_CLONE_PATH="$FIXTURE_REPO"

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
# Only if FIXTURE_REPO exists (remote-fallback creates it during the run).
[ -d "$FIXTURE_REPO" ] && rm -f "$FIXTURE_REPO/terraform/logs/indexes/foobar.tf"

# Canned prompt — provides all inputs up front so the agent can proceed
# without an interactive confirmation loop. For remote-fallback, prefix
# with explicit clone-authorization so the agent doesn't get stuck at
# §9.1 step 4's user-prompt branch.
CLONE_AUTHORIZATION=""
if [ "$VARIANT" = "remote-fallback" ]; then
  CLONE_AUTHORIZATION="If you discover that the datadog-operations repo is not cloned locally, run gh auth status FIRST, then clone it to $EXPECTED_CLONE_PATH (do not invent a different path), and only then cd into the clone to draft files. Do not cd into the clone before the auth check.

"
fi

# NOTE: heredoc is unquoted (<<EOF, not <<'EOF') so ${CLONE_AUTHORIZATION}
# expands. The rest of the body has no $-references that would expand
# unintentionally.
PROMPT=$(cat <<EOF
${CLONE_AUTHORIZATION}Invoke the observability:create-log-index skill and execute its golden
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

# Invoke Claude Code headlessly from the per-variant CWD. local-hit and
# remote-fallback launch from SESSION_DIR (forcing the agent to walk the
# detection ladder); cwd-shortcut launches from the clone itself.
cd "$INVOCATION_CWD"

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
PROJECT_SLUG=$(echo "$INVOCATION_CWD" | sed -e 's/[\\:/.]/-/g' -e 's/^-*//')
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
