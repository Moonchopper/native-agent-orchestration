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

@test "runner DRY_RUN echoes run_ix=0 by default" {
  DRY_RUN=1 run scripts/run-scenario.sh create-log-index local-hit
  [ "$status" -eq 0 ]
  [[ "$output" == *"run_ix=0"* ]]
}

@test "runner DRY_RUN honors RUN_IX env override" {
  DRY_RUN=1 RUN_IX=7 run scripts/run-scenario.sh create-log-index local-hit
  [ "$status" -eq 0 ]
  [[ "$output" == *"run_ix=7"* ]]
}

@test "DRY_RUN reports cwd-shortcut variant" {
  run env DRY_RUN=1 RUN_IX=2 ./scripts/run-scenario.sh create-log-index cwd-shortcut
  [ "$status" -eq 0 ]
  [[ "$output" == *"scenario=create-log-index"* ]]
  [[ "$output" == *"variant=cwd-shortcut"* ]]
  [[ "$output" == *"run_ix=2"* ]]
}

@test "DRY_RUN reports remote-fallback variant" {
  run env DRY_RUN=1 RUN_IX=0 ./scripts/run-scenario.sh create-log-index remote-fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"variant=remote-fallback"* ]]
}

@test "runner rejects unknown variant" {
  run ./scripts/run-scenario.sh create-log-index banana-split
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown variant"* ]]
}
