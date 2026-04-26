#!/usr/bin/env bash
set -euo pipefail

HANDOFF_FILE="${1:?handoff file path required}"
# Derive the fixture repo root from the handoff file location rather than
# git rev-parse, which would resolve to whatever repo CWD is currently inside
# (the runner cd's into the fixture repo before invoking this script).
FIXTURE_REPO=$(cd "$(dirname "$HANDOFF_FILE")" && pwd)

# TRANSCRIPT_PATH is exported by run-scenario.sh after extract-metrics runs.
# This assertion needs the transcript to verify the detection ladder shorted
# at §9.1 step 1 (CWD match) and never probed conventional paths.
TRANSCRIPT="${TRANSCRIPT_PATH:?TRANSCRIPT_PATH env var required for cwd-shortcut assertion}"

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

# 1. Handoff file exists
[ -f "$HANDOFF_FILE" ] || fail "handoff file '$HANDOFF_FILE' does not exist"

PAYLOAD=$(cat "$HANDOFF_FILE")

# 2. Payload has required top-level keys
for key in drafted_files pr_body override_rationale; do
  echo "$PAYLOAD" | jq -e "has(\"$key\")" >/dev/null 2>&1 \
    || fail "payload missing key '$key'"
done

# 3. Drafted file is referenced in the payload
DRAFTED_PATH=$(echo "$PAYLOAD" | jq -r '.drafted_files[0].path')
[ "$DRAFTED_PATH" = "terraform/logs/indexes/foobar.tf" ] \
  || fail "expected drafted path 'terraform/logs/indexes/foobar.tf', got '$DRAFTED_PATH'"

# 4. Drafted file actually exists on disk
[ -f "$FIXTURE_REPO/$DRAFTED_PATH" ] \
  || fail "drafted file '$FIXTURE_REPO/$DRAFTED_PATH' does not exist"

# 5. Drafted file contains the expected resource and values
DRAFTED_CONTENTS=$(cat "$FIXTURE_REPO/$DRAFTED_PATH")
for pattern in \
  'resource "datadog_logs_index"' \
  'foobar-prod' \
  'tier *= *"Flex"' \
  'days *= *30'
do
  echo "$DRAFTED_CONTENTS" | grep -qE "$pattern" \
    || fail "drafted file missing expected pattern: $pattern"
done

# 6. PR body mentions the index name
echo "$PAYLOAD" | jq -r '.pr_body' | grep -q "foobar-prod" \
  || fail "PR body does not mention 'foobar-prod'"

# 7. cwd-shortcut variant-specific: detection ladder must not have probed
# conventional paths. Per architecture spec §9.1 step 1, when the
# invocation CWD already matches the target repo (origin URL contains
# datadog-operations), the agent should immediately use the CWD and skip
# steps 2-4 (path probing, ask user, offer to clone).
#
# A "conventional-path probe" is a Bash command that names one of the
# skill-body's documented conventional locations *literally* — i.e. with
# `~` or `$HOME` (the unresolved forms a guessing agent would type). The
# resolved absolute form (e.g. /c/Users/austi/src/...) is NOT a probe
# when the agent's CWD already is that path: it's just the agent
# operating on its known CWD, which is the correct §9.1-step-1 behavior.
# So we match only the unresolved-tilde / $HOME forms; the resolved form
# of the CWD is expected and benign for cwd-shortcut.
[ -f "$TRANSCRIPT" ] \
  || fail "transcript not found at '$TRANSCRIPT' — cannot verify path probing"

PROBED=$(jq -r '.message.content[]?
                | select(.type=="tool_use" and .name=="Bash")
                | .input.command? // empty' "$TRANSCRIPT" 2>/dev/null \
  | grep -E "(~|\\\$HOME|\\\$\{HOME\})/(src|code|git|work)/[^/[:space:]]*/datadog-operations" \
  | head -5 || true)

if [ -n "$PROBED" ]; then
  fail "cwd-shortcut variant should skip §9.1 step 2 path-probing; found probes:
$PROBED"
fi

echo "All assertions passed (including cwd-shortcut variant-specific)."
