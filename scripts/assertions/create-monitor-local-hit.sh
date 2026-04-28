#!/usr/bin/env bash
set -euo pipefail

HANDOFF_FILE="${1:?handoff file path required}"
# Derive the fixture repo root from the handoff file location rather than
# git rev-parse, which would resolve to whatever repo CWD is currently inside
# (the runner cd's into the fixture repo before invoking this script).
FIXTURE_REPO=$(cd "$(dirname "$HANDOFF_FILE")" && pwd)

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
[ "$DRAFTED_PATH" = "terraform/monitors/foobar-api-error-rate.tf" ] \
  || fail "expected drafted path 'terraform/monitors/foobar-api-error-rate.tf', got '$DRAFTED_PATH'"

# 4. Drafted file actually exists on disk
[ -f "$FIXTURE_REPO/$DRAFTED_PATH" ] \
  || fail "drafted file '$FIXTURE_REPO/$DRAFTED_PATH' does not exist"

# 5. Drafted file contains the expected resource and values. The notify_target
# (@user-foo) is the override target — it appears in the resource's `message`
# field per the create-monitor golden path.
DRAFTED_CONTENTS=$(cat "$FIXTURE_REPO/$DRAFTED_PATH")
for pattern in \
  'resource "datadog_monitor"' \
  'foobar-api-error-rate' \
  '@user-foo'
do
  echo "$DRAFTED_CONTENTS" | grep -qE "$pattern" \
    || fail "drafted file missing expected pattern: $pattern"
done

# 6. Override-specific assertions: the PR body must call out the override and
# include the supplied rationale. 'team rotation' is a sufficient unique
# substring of the rationale text to confirm propagation end-to-end.
PR_BODY=$(echo "$PAYLOAD" | jq -r '.pr_body')
echo "$PR_BODY" | grep -q "## Best-practice overrides" \
  || fail "PR body missing '## Best-practice overrides' heading"
echo "$PR_BODY" | grep -q "team rotation" \
  || fail "PR body missing override rationale (expected substring 'team rotation')"

echo "All assertions passed."
