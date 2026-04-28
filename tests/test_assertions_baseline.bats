#!/usr/bin/env bats

# Coverage for scripts/assertions/baseline-baseline.sh.
#
# The baseline assertion checks that NO Skill(observability:*) tool_use
# appears anywhere in the run's transcript — the off-topic-cost-floor
# guarantee. We exercise both the negative (no skill) and positive
# (skill present) controls plus the missing-file edge case.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ASSERTION="$REPO_ROOT/scripts/assertions/baseline-baseline.sh"
  NO_SKILL_FIXTURE="$REPO_ROOT/tests/fixtures/transcript-no-skill.jsonl"
  WITH_SKILL_FIXTURE="$REPO_ROOT/tests/fixtures/transcript-with-skill.jsonl"
}

@test "baseline assertion passes when no observability skill is invoked" {
  run "$ASSERTION" "$NO_SKILL_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Baseline assertion passed"* ]]
}

@test "baseline assertion FAILS when observability skill is invoked (positive control)" {
  run "$ASSERTION" "$WITH_SKILL_FIXTURE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ASSERTION FAILED"* ]]
}

@test "baseline assertion fails on missing transcript file" {
  run "$ASSERTION" /tmp/nonexistent-baseline-transcript.jsonl
  [ "$status" -ne 0 ]
  [[ "$output" == *"ASSERTION FAILED"* ]]
}
