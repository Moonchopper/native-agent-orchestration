#!/usr/bin/env bash
set -euo pipefail

HANDOFF_FILE="${1:?handoff file path required}"
# Derive the fixture repo root from the handoff file location rather than
# git rev-parse, which would resolve to whatever repo CWD is currently inside
# (the runner cd's into the fixture repo before invoking this script).
FIXTURE_REPO=$(cd "$(dirname "$HANDOFF_FILE")" && pwd)

# TRANSCRIPT_PATH is exported by run-scenario.sh after extract-metrics runs.
# This assertion needs the transcript to verify gh auth status was invoked
# before any clone command (per architecture spec §9.4 — auth preflight is
# the FIRST thing the runtime flow does after the detection ladder begins).
TRANSCRIPT="${TRANSCRIPT_PATH:?TRANSCRIPT_PATH env var required for remote-fallback assertion}"

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

# 4. Drafted file actually exists on disk under the (cloned) fixture repo
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

# 7. remote-fallback variant-specific: clone exists post-run at the
# EXPECTED_CLONE_PATH the agent was told to use.
EXPECTED_CLONE="$HOME/src/Moonchopper/datadog-operations"
[ -d "$EXPECTED_CLONE/.git" ] \
  || fail "clone not found at $EXPECTED_CLONE post-run (remote-fallback should produce one)"

# 8. remote-fallback variant-specific: gh auth status was invoked before
# any clone command in the transcript. Per architecture spec §9.4, auth
# preflight is the first thing the runtime flow does. We scan tool_use
# Bash invocations in transcript order and require an AUTH event before
# the first CLONE event.
[ -f "$TRANSCRIPT" ] \
  || fail "transcript not found at '$TRANSCRIPT' — cannot verify auth-before-clone"

# Build an ordered list of relevant Bash invocations (auth and clone events)
# in transcript order. Output: tab-separated "<event>\t<command_excerpt>".
EVENTS=$(jq -r '
  select(.type == "assistant")
  | .message.content[]?
  | select(.type == "tool_use" and .name == "Bash")
  | .input.command
  | select(. != null)
  | if test("gh auth status") then "AUTH\t" + .[0:120]
    elif test("gh repo clone|git clone.*datadog-operations") then "CLONE\t" + .[0:120]
    else empty
    end
' "$TRANSCRIPT" 2>/dev/null || true)

if [ -z "$EVENTS" ]; then
  fail "no gh auth status or clone invocations found in transcript"
fi

# First relevant event must be AUTH (auth precedes clone).
FIRST_EVENT=$(echo "$EVENTS" | head -1 | cut -f1)
if [ "$FIRST_EVENT" != "AUTH" ]; then
  fail "expected gh auth status BEFORE any clone, but first event was: $FIRST_EVENT
Events:
$EVENTS"
fi

# At least one CLONE must follow AUTH.
echo "$EVENTS" | grep -q "^CLONE" \
  || fail "no clone event observed in transcript (expected gh repo clone or git clone of datadog-operations)"

echo "All assertions passed (including remote-fallback variant-specific)."
