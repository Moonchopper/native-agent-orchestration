#!/usr/bin/env bats

# Coverage for scripts/assertions/create-log-index-remote-fallback.sh.
#
# Strategy: each test sets up a tmpdir-based fake $HOME containing the
# expected clone path ($HOME/src/Moonchopper/datadog-operations) with a
# stubbed .git/ dir, the handoff JSON, and the drafted Terraform file.
# Then runs the assertion against either the "clean" transcript fixture
# (gh auth status precedes clone — assertion should pass) or the
# "no-auth" fixture (clone happens with no preceding auth — should fail).

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  ASSERTION="$REPO_ROOT/scripts/assertions/create-log-index-remote-fallback.sh"
  CLEAN_FIXTURE="$REPO_ROOT/tests/fixtures/transcript-remote-fallback-clean.jsonl"
  NO_AUTH_FIXTURE="$REPO_ROOT/tests/fixtures/transcript-remote-fallback-no-auth.jsonl"

  # Build a fake HOME so the assertion's EXPECTED_CLONE path
  # ($HOME/src/Moonchopper/datadog-operations) resolves into our tmpdir.
  FAKE_HOME="$(mktemp -d)"
  export HOME="$FAKE_HOME"

  TMPDIR_REPO="$FAKE_HOME/src/Moonchopper/datadog-operations"
  HANDOFF_FILE="$TMPDIR_REPO/.stage-1-handoff.json"
  DRAFTED_DIR="$TMPDIR_REPO/terraform/logs/indexes"
  mkdir -p "$DRAFTED_DIR"
  # Stub .git/ so the post-run clone-existence check passes.
  mkdir -p "$TMPDIR_REPO/.git"

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
  rm -rf "$FAKE_HOME"
}

@test "remote-fallback assertion passes when auth precedes clone" {
  TRANSCRIPT_PATH="$CLEAN_FIXTURE" run "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All assertions passed"* ]]
}

@test "remote-fallback assertion FAILS when clone happens before auth" {
  TRANSCRIPT_PATH="$NO_AUTH_FIXTURE" run "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ASSERTION FAILED"* ]]
  # Either the auth-before-clone diagnostic mentions the ordering
  # explicitly, or it surfaces the offending CLONE-first event list.
  [[ "$output" == *"BEFORE any clone"* ]] || [[ "$output" == *"CLONE"* ]]
}

@test "remote-fallback assertion fails when TRANSCRIPT_PATH is unset" {
  run env -u TRANSCRIPT_PATH "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TRANSCRIPT_PATH"* ]]
}

@test "remote-fallback assertion fails when handoff file is missing" {
  TRANSCRIPT_PATH="$CLEAN_FIXTURE" run "$ASSERTION" "$FAKE_HOME/no-such-handoff.json"
  [ "$status" -ne 0 ]
}

@test "remote-fallback assertion fails when post-run clone is missing" {
  rm -rf "$TMPDIR_REPO/.git"
  TRANSCRIPT_PATH="$CLEAN_FIXTURE" run "$ASSERTION" "$HANDOFF_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"clone not found"* ]]
}

@test "remote-fallback assertion fails when drafted file path is wrong" {
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
