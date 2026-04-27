#!/usr/bin/env bash
set -euo pipefail

# baseline/baseline assertion: the agent must NOT invoke any
# observability:* skill in response to an off-topic prompt. The plugin is
# enrolled (skill descriptions are present in context), but no skill body
# should be loaded — that's the architectural cost floor.

TRANSCRIPT="${1:?transcript path required}"

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

[ -f "$TRANSCRIPT" ] || fail "transcript not found: $TRANSCRIPT"

# Count Skill(observability:*) tool_use entries anywhere in the transcript.
# The Skill tool's input shape is .input.skill (e.g. "observability:create-log-index").
SKILL_USES=$(jq -r '
  .message.content[]?
  | select(.type == "tool_use" and .name == "Skill")
  | .input.skill // empty
' "$TRANSCRIPT" 2>/dev/null | grep -c "^observability:" || true)

[ "$SKILL_USES" -eq 0 ] || fail "expected no Skill(observability:*) invocations; found $SKILL_USES"

echo "Baseline assertion passed: no observability skill invoked."
