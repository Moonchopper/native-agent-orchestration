#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  FIXTURE="$REPO_ROOT/tests/fixtures/transcript-sample.jsonl"
  METRICS_FILE="$(mktemp)"
  export AGENT_ORCH_METRICS_FILE="$METRICS_FILE"
  export AGENT_ORCH_SCENARIO="create-log-index"
  export AGENT_ORCH_VARIANT="local-hit"
  export AGENT_ORCH_RUN_IX="3"
}

teardown() {
  rm -f "$METRICS_FILE"
}

@test "extract-metrics emits one JSONL line per assistant usage entry" {
  USAGE_COUNT=$(jq -s 'map(select(.message.usage)) | length' "$FIXTURE")
  "$REPO_ROOT/scripts/extract-metrics.sh" "$FIXTURE"
  LINE_COUNT=$(wc -l < "$METRICS_FILE")
  [ "$LINE_COUNT" = "$USAGE_COUNT" ]
}

@test "extract-metrics tags each line with scenario/variant/run_ix from env" {
  "$REPO_ROOT/scripts/extract-metrics.sh" "$FIXTURE"
  while IFS= read -r line; do
    [ "$line" = "create-log-index" ] || return 1
  done < <(jq -r '.scenario' "$METRICS_FILE")
  while IFS= read -r line; do
    [ "$line" = "3" ] || return 1
  done < <(jq -r '.run_ix' "$METRICS_FILE")
}

@test "extract-metrics carries token fields verbatim from .message.usage" {
  "$REPO_ROOT/scripts/extract-metrics.sh" "$FIXTURE"
  EXPECTED_FIRST_IN=$(jq -s 'map(select(.message.usage)) | .[0].message.usage.input_tokens' "$FIXTURE")
  ACTUAL_FIRST_IN=$(jq -s '.[0].tokens_in' "$METRICS_FILE")
  [ "$EXPECTED_FIRST_IN" = "$ACTUAL_FIRST_IN" ]
}

@test "extract-metrics turn field is 1-indexed and monotonically increasing" {
  "$REPO_ROOT/scripts/extract-metrics.sh" "$FIXTURE"
  PREV=0
  while IFS= read -r t; do
    [ "$t" -gt "$PREV" ] || return 1
    PREV="$t"
  done < <(jq -r '.turn' "$METRICS_FILE")
}

@test "extract-metrics writes to stdout when AGENT_ORCH_METRICS_FILE is unset" {
  unset AGENT_ORCH_METRICS_FILE
  run "$REPO_ROOT/scripts/extract-metrics.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "extract-metrics fails on missing transcript file" {
  run "$REPO_ROOT/scripts/extract-metrics.sh" "/nonexistent/path.jsonl"
  [ "$status" -ne 0 ]
}
