# Stage 1 Notes — handoff to Stage 2

## What Stage 1 built

- One end-to-end scenario working: `create-log-index / local-hit`.
- Fixture plugin (`fixtures/claude-plugin-observability/`) with one α-style orchestration skill (`create-log-index`) and one stub handoff skill (`_pr-handoff`).
- Fixture functional repo (`fixtures/datadog-operations/`) with one golden path and three best-practice files.
- Runner (`scripts/run-scenario.sh`) with a bats-tested CLI contract, a `DRY_RUN` escape hatch, and the real-run invocation of `claude -p`.
- Scenario-specific assertion script (`scripts/assertions/create-log-index-local-hit.sh`) verifying handoff payload shape and drafted Terraform content.
- Plugin-install helper (`scripts/setup-plugin.sh`) for copying the fixture plugin into Claude Code's plugin directory.

## Plan deviations worth recording

1. **Task 7 (shared assertion library) was dropped.** The `scripts/lib/assert.sh` + paired bats tests wrapped trivial bash primitives (`[ ]`, `grep`, `jq`) with exactly one consumer. The end-to-end scenario would surface any misbehavior, making the wrapper tests redundant defense. Task 11 inlines the 4 checks directly.

2. **`bats-core` is vendored, not installed.** The plan's original prerequisite list said `npm install -g bats`; during execution we cloned bats-core to `.bats/` (gitignored) instead. Avoids user-system side effects and matches the plan's file-structure hint.

3. **Runner added `--permission-mode bypassPermissions` to `claude -p`.** Discovered during end-to-end: headless mode blocked on the `Write` permission prompt for `terraform/logs/indexes/foobar.tf`. Skill-level `allowed-tools` frontmatter does not bypass global permission prompts. Stage 2 should tighten this via a settings.json allowlist.

4. **Assertion script derives `FIXTURE_REPO` from the handoff path, not `git rev-parse`.** The runner `cd`s into the fixture repo before invoking assertions, so `git rev-parse --show-toplevel` resolved to the fixture repo itself, producing a doubled path on disk. Using `dirname($HANDOFF_FILE)` is self-contained and correct.

5. **Plugin-dir gitlink trap.** `git add fixtures/claude-plugin-observability/` auto-created a submodule gitlink (mode 160000) because the nested `.git/` exists. Fixed via a hide-the-nested-.git-during-add workaround; Task 1's `.gitkeep` in `fixtures/datadog-operations/` had accidentally inoculated that subtree, so the plugin was the only victim. See memory `nested_fixture_repos_gitlink_trap.md`.

## What Stage 2 needs from Stage 1

- **Runner is the integration point** for the measurement hook. Stage 2 will set `AGENT_ORCH_SCENARIO` and `AGENT_ORCH_VARIANT` env vars from inside the runner before invoking `claude -p`, and pass `--settings <path>` to configure the metric-capture hook.
- **Scenario/variant tuples** need to become an iterable table so Stage 2 can benchmark the matrix. Currently hardcoded in one `case` statement.
- **`.stage-1-handoff.json`** is a per-run artifact; Stage 2 will capture it per run iteration (not overwrite) when measuring P50/P95 across N runs.
- **Permission mode** should move from `bypassPermissions` to an explicit `--allowedTools` allowlist once we know precisely which Bash patterns the skill exercises (`Bash(git:*)`, `Bash(gh:*)`, `Bash(terraform:*)`).

## Decisions deferred

- Exact Claude Code hook event name for per-turn token capture (`Stop` is the candidate; confirm in Stage 2).
- Token-budget tolerance for scenario assertions (calibrate after the first measurement pass).

## Carry-forward risks

- **`_pr-handoff` is a stub.** It serializes the payload to a local JSON file rather than opening a real PR. A real PR-authoring skill is a Stage 3 or separate "orthogonal skills" track concern.
- **Detection ladder only exercised on the CWD-match branch.** The `remote-fallback` and `cwd-shortcut` variants need fixtures for "no local clone" and "in an unrelated repo" scenarios — Stage 2 or 3.
- **Fixture repo origins are fictional.** `git fetch` against `github.com/fixture-org/...` will fail. The skill body tolerates fetch failure gracefully, but the freshness-check prompt path has not been exercised end-to-end.
- **`bash -n` is the only static check.** No shellcheck, no CI. A Stage 2 TODO.
