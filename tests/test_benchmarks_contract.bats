#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "run-benchmarks shows usage on zero args" {
  run "$REPO_ROOT/scripts/run-benchmarks.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "run-benchmarks DRY_RUN echoes each planned invocation" {
  DRY_RUN=1 run "$REPO_ROOT/scripts/run-benchmarks.sh" \
    --matrix "$REPO_ROOT/scripts/matrix/stage-2-initial.tsv"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'scenario=create-log-index')" -eq 5 ]
}

@test "run-benchmarks honors --n override" {
  DRY_RUN=1 run "$REPO_ROOT/scripts/run-benchmarks.sh" \
    --matrix "$REPO_ROOT/scripts/matrix/stage-2-initial.tsv" \
    --n 2
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'scenario=create-log-index')" -eq 2 ]
}
