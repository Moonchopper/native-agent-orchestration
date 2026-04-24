#!/usr/bin/env bats

@test "runner rejects unknown scenario with exit code 2" {
  run scripts/run-scenario.sh bogus-scenario local-hit
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown scenario"* ]]
}

@test "runner rejects unknown variant with exit code 2" {
  run scripts/run-scenario.sh create-log-index bogus-variant
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown variant"* ]]
}

@test "runner rejects missing arguments with exit code 2" {
  run scripts/run-scenario.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "runner in DRY_RUN accepts create-log-index local-hit" {
  DRY_RUN=1 run scripts/run-scenario.sh create-log-index local-hit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN"* ]]
  [[ "$output" == *"create-log-index"* ]]
  [[ "$output" == *"local-hit"* ]]
}
