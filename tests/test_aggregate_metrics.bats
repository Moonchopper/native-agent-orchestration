#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  FIXTURE="$REPO_ROOT/tests/fixtures/aggregate-sample.jsonl"
}

@test "aggregate prints one row per (scenario, variant)" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'create-log-index.*local-hit')" -eq 1 ]
}

@test "aggregate reports P50 = 3940 for the sample fixture" {
  # Per-run totals (tokens_in + tokens_out) sorted: 3500, 3720, 3940, 4160, 4380.
  # Rank-based P50 for N=5 is sorted[floor(5/2)] = sorted[2] = 3940.
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"3940"* ]]
}

@test "aggregate reports N=5 runs for the sample fixture" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"N=5"* ]] || [[ "$output" == *"| 5 "* ]]
}

@test "aggregate reports cache_ratio ~= 0.43 for the sample fixture" {
  # Fixture sums: cache_read=13000, tokens_in=17000, cache_creation=0.
  # Ratio = cache_read / (cache_read + tokens_in + cache_creation) = 13000 / 30000 = 0.4333.
  # Aggregator truncates to 2 decimal places. (Earlier formula was
  # cache_read/tokens_in which gave nonsensical >>1 values on real Claude Code
  # data where cache_read can be 1000x tokens_in.)
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"0.43"* ]]
}

@test "aggregate reports hot turn = 2 for the sample fixture" {
  # Turn 2 is always larger than turn 1 within each run.
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"hot_turn"* ]]
  HOT_LINE=$(echo "$output" | grep 'create-log-index.*local-hit')
  [[ "$HOT_LINE" == *"| 2 |"* ]] || [[ "$HOT_LINE" == *"turn=2"* ]]
}

@test "aggregate fails on empty input" {
  EMPTY="$(mktemp)"
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$EMPTY"
  [ "$status" -ne 0 ]
  rm -f "$EMPTY"
}

# --- C2: per-row token-budget enforcement -----------------------------------
#
# Sample fixture per-run totals (sorted): 3500, 3720, 3940, 4160, 4380.
# So `max` (worst-of-N) = 4380.

@test "aggregate PASS when max <= budget (--matrix)" {
  MATRIX="$(mktemp)"
  printf 'scenario\tvariant\tn\tbudget\ncreate-log-index\tlocal-hit\t5\t5000\n' > "$MATRIX"
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" --matrix "$MATRIX" "$FIXTURE"
  rm -f "$MATRIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" != *"FAIL"* ]]
  [[ "$output" != *"BUDGET_UNSET"* ]]
}

@test "aggregate FAIL when max > budget (--matrix), exits 1" {
  MATRIX="$(mktemp)"
  printf 'scenario\tvariant\tn\tbudget\ncreate-log-index\tlocal-hit\t5\t4000\n' > "$MATRIX"
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" --matrix "$MATRIX" "$FIXTURE"
  rm -f "$MATRIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "aggregate BUDGET_UNSET when budget is '-' (--matrix), exits 0" {
  MATRIX="$(mktemp)"
  printf 'scenario\tvariant\tn\tbudget\ncreate-log-index\tlocal-hit\t5\t-\n' > "$MATRIX"
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" --matrix "$MATRIX" "$FIXTURE"
  rm -f "$MATRIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BUDGET_UNSET"* ]]
  [[ "$output" != *"FAIL"* ]]
}

@test "aggregate BUDGET_UNSET when row not present in matrix" {
  MATRIX="$(mktemp)"
  printf 'scenario\tvariant\tn\tbudget\nother-scenario\tother-variant\t5\t9999\n' > "$MATRIX"
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" --matrix "$MATRIX" "$FIXTURE"
  rm -f "$MATRIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BUDGET_UNSET"* ]]
}

@test "aggregate without --matrix leaves every row BUDGET_UNSET" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BUDGET_UNSET"* ]]
}

@test "aggregate emits max column equal to worst-of-N (4380)" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4380"* ]]
}
