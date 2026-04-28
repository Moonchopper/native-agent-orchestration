# Validating Stage 3 Personally

A short walkthrough for convincing yourself the architecture works end-to-end. Assumes you have `claude` CLI, `gh` CLI (authenticated), `git`, `jq`, `terraform` (optional — only used by the agent for `validate`), and bash.

Time: ~20 minutes total wall-clock.

## 1. Clone and bootstrap (~1 min)

```bash
git clone https://github.com/Moonchopper/native-agent-orchestration.git
cd native-agent-orchestration
git checkout stage-3-externalize-and-extend  # until PR #5 merges to main

# Vendored bats — gitignored, cloned on demand
[ -d .bats ] || git clone --depth 1 https://github.com/bats-core/bats-core.git .bats

# Install the fixture plugin from Moonchopper/claude-plugin-observability
bash scripts/setup-plugin.sh
```

Expected last line: `Installed fixture plugin 'observability' from local marketplace 'native-agent-observability'`.

## 2. Bats baseline (~5 sec)

```bash
.bats/bin/bats tests/
```

Expected: **44/44 passing.** Covers runner contract, extract-metrics, aggregate-metrics with budget enforcement, and per-variant assertion scripts.

## 3. Smoke a single scenario end-to-end (~2 min)

Pick the simplest scenario:

```bash
bash scripts/run-scenario.sh create-log-index local-hit
```

Watch what happens:
- Runner clones `Moonchopper/datadog-operations` to `~/src/Moonchopper/datadog-operations` (first run only; refreshes on re-runs).
- `claude -p` launches headlessly with the plugin enrolled, in a scratch CWD.
- Agent walks the §9.1 detection ladder, finds the clone, reads the golden-path content via real `Read` calls, drafts `terraform/logs/indexes/foobar.tf`, runs `terraform fmt`/`validate`, hands off to `pr-handoff`.
- Runner extracts metrics from the session transcript and runs the assertion script.

Expected last line: `All assertions passed.`

If you want to inspect the artifacts:
```bash
cat ~/src/Moonchopper/datadog-operations/terraform/logs/indexes/foobar.tf
cat ~/src/Moonchopper/datadog-operations/.stage-1-handoff.json | jq .
```

## 4. Verify the variant-delta claim (~3 min)

```bash
bash scripts/run-scenario.sh create-log-index cwd-shortcut
```

Same scenario, different fixture state — CWD is the clone, so the agent's §9.1-step-1 hits immediately and skips path-probing. Watch the assertion: it actively checks the transcript for absence of `~/src/...` Bash invocations.

```bash
# Optional: inspect the most recent transcript to see what the agent did
ls -t ~/.claude/projects/*/*.jsonl | head -1 | xargs jq -s '[.[] | select(.message.content[]?.type == "tool_use") | .message.content[]? | .name] | group_by(.) | map({name: .[0], count: length})'
```

`cwd-shortcut` should have far fewer Bash tool uses than `local-hit` because most of the path-probing turns are gone.

## 5. Verify `remote-fallback` (the auth+clone path) (~3 min)

```bash
# Make sure no clone exists
rm -rf ~/src/Moonchopper/datadog-operations ~/code/Moonchopper/datadog-operations \
       ~/git/Moonchopper/datadog-operations ~/work/Moonchopper/datadog-operations

bash scripts/run-scenario.sh create-log-index remote-fallback
```

The runner's preflight verifies no clone exists. The prompt explicitly authorizes the agent to clone after running `gh auth status` first. The assertion verifies (a) post-run clone exists, (b) `gh auth status` was invoked **before** any clone in transcript order.

## 6. Verify the second scenario (`create-monitor`) and override flow (~3 min)

```bash
bash scripts/run-scenario.sh create-monitor local-hit
```

The prompt deliberately supplies `notify_target=@user-foo` (an individual — violates the `monitor-notification-target` best practice) along with the override rationale. The assertion verifies the rationale appears under `## Best-practice overrides` in the PR body.

```bash
cat ~/src/Moonchopper/datadog-operations/.stage-1-handoff.json | jq .pr_body -r
```

You should see a `## Best-practice overrides` section with the rationale verbatim.

## 7. Verify the cost floor (~30 sec)

```bash
bash scripts/run-scenario.sh baseline baseline
```

Plugin enrolled, off-topic question. Assertion verifies no `Skill(observability:*)` invocation appears in the transcript. `session.out` will contain the agent's one-word answer.

## 8. Run the full matrix with budget enforcement (~60 min — skip if you've done 3-7)

The "everything works together" gate:

```bash
bash scripts/run-benchmarks.sh --matrix scripts/matrix/poc-full.tsv
```

Expected output (after ~60 min of `claude -p` invocations):

```
| scenario | variant | N | P50 | P95 | max | budget | status | cache_ratio | hot_turn |
|---|---|---|---|---|---|---|---|---|---|
| baseline | baseline | N=5 | ... | ... | ... | 10 | PASS | ... | ... |
| create-log-index | cwd-shortcut | N=5 | ... | ... | ... | 12357 | PASS | ... | ... |
| create-log-index | local-hit | N=5 | ... | ... | ... | 11357 | PASS | ... | ... |
| create-log-index | remote-fallback | N=5 | ... | ... | ... | 13302 | PASS | ... | ... |
| create-monitor | local-hit | N=5 | ... | ... | ... | 11998 | PASS | ... | ... |
```

Exit code 0 iff every row's worst-of-N max is under its locked budget. Test the FAIL gate by editing one of the budgets in `poc-full.tsv` to a value below the row's max — expect exit code 1 with `FAIL` in the status column.

## What you've validated

- The architecture's GitHub-API retrieval boundary is real (clone happens, `gh api` works, content moves between three real repos).
- The §9.1 detection ladder works for all three branches (CWD-match, conventional-paths, ask-and-clone).
- Two scenarios (`create-log-index`, `create-monitor`) prove the architecture generalizes — the second uses different practice files, a different drafted-artifact path, and exercises the deliberate-override flow.
- Token-budget assertions are enforced with worst-of-N semantics; the aggregator's exit code can gate CI.
- The cost floor (plugin-enrollment overhead) is measurable independently.

## Cleanup

```bash
rm -rf ~/src/Moonchopper/datadog-operations
claude plugin uninstall observability@native-agent-observability
claude plugin marketplace remove native-agent-observability
```

## Where to look when something feels off

- `docs/stage-3-notes.md` — what was built, plan deviations, carry-forward risks.
- `docs/reference-scenarios.md` — doc 4: the matrix and per-scenario passing criteria.
- `docs/superpowers/specs/2026-04-23-core-architecture-design.md` — the architecture spec (especially §9 detection ladder, §10 best-practice violations, §11 measurement).
- Per-run transcripts at `~/.claude/projects/<slug>/*.jsonl` — the ground truth for what the agent actually did.
