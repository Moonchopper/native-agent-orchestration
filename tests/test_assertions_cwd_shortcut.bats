#!/usr/bin/env bats

# Coverage for scripts/assertions/create-log-index-cwd-shortcut.sh.
#
# Strategy: each test sets up a tmpdir-based fake fixture repo containing
# the handoff JSON + the drafted Terraform file with the expected shape,
# then runs the assertion against either the "clean" transcript fixture
# (no path probing — assertion should pass) or the "probed" fixture
# (assertion should fail with a path-probing-specific message).

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  ASSERTION="$REPO_ROOT/scripts/assertions/create-log-index-cwd-shortcut.sh"
  CLEAN_FIXTURE="$REPO_ROOT/tests/fixtures/transcript-cwd-shortcut-clean.jsonl"
  PROBED_FIXTURE="$REPO_ROOT/tests/fixtures/transcript-cwd-shortcut-probed.jsonl"

  TMPDIR_REPO="$(mktemp -d)"
  HANDOFF_FILE="$TMPDIR_REPO/.stage-1-handoff.json"
  DRAFTED_DIR="$TMPDIR_REPO/terraform/logs/indexes"
  mkdir -p "$DRAFTED_DIR"

  cat > "$DRAFTED_DIR/foobar.tf" <<'TF'
resource "datadog_logs_index" "foobar-prod" {
  name = "foobar-prod"
  filter { query = "service:foobar-api env:prod" }
  exclusion_filter {}
  daily_limit = 1000000
  retention {
    tier = "Flex"
    days = 30
  }
}
TF

  cat > "$HANDOFF_FILE" <<'JSON'
{
  "drafted_files": [{"path": "terraform/logs/indexes/foobar.tf"}],
  "pr_body": "Adds foobar-prod log index.\nFilter: service:foobar-api env:prod",
  "override_rationale": null
}
JSON
}

teardown() {
  rm -rf "$TMPDIR_REPO"
}

@test "cwd-shortcut assertion passes on clean transcript (no path probing)" {
  TRANSCRIPT_PATH="$CLEAN_FIXTURE" run "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All assertions passed"* ]]
}

@test "cwd-shortcut assertion fails on probed transcript (positive control)" {
  TRANSCRIPT_PATH="$PROBED_FIXTURE" run "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"path-probing"* ]] || [[ "$output" == *"step 2"* ]]
  [[ "$output" == *"datadog-operations"* ]]
}

@test "cwd-shortcut assertion fails when TRANSCRIPT_PATH is unset" {
  run env -u TRANSCRIPT_PATH "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TRANSCRIPT_PATH"* ]]
}

@test "cwd-shortcut assertion fails when handoff file is missing" {
  TRANSCRIPT_PATH="$CLEAN_FIXTURE" run "$ASSERTION" "/nonexistent/handoff.json"
  [ "$status" -ne 0 ]
}

@test "cwd-shortcut assertion fails when drafted file path is wrong" {
  cat > "$HANDOFF_FILE" <<'JSON'
{
  "drafted_files": [{"path": "wrong/path/foobar.tf"}],
  "pr_body": "Adds foobar-prod.",
  "override_rationale": null
}
JSON
  TRANSCRIPT_PATH="$CLEAN_FIXTURE" run "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected"* ]] || [[ "$output" == *"ASSERTION FAILED"* ]]
}
