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

echo "All assertions passed."
