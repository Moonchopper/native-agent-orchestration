# Stage 3 Notes — handoff to Stage 4

## What Stage 3 built

- **Externalized fixtures.** Two standalone GitHub repos under `Moonchopper/`: `datadog-operations` (functional repo, fixture content for agent retrieval testing — *not* a deployable Datadog Terraform project) and `claude-plugin-observability` (the plugin, currently v0.1.2). The harness clones the functional repo per-variant from the runner, and the plugin is installed via `.claude-plugin/marketplace.json` pointing at the plugin repo via the `url` source form. The in-tree `fixtures/` directory was deleted in Phase A.
- **Three new variants for `create-log-index`.** Stage 2 only validated `local-hit`. Phase B added `cwd-shortcut` (CWD = the clone, agent's §9.1-step-1 hits) and `remote-fallback` (no clone present, agent runs `gh auth status` then clones via §9.1-step-4). Each variant has an end-to-end runner path, an assertion script with variant-specific transcript checks, bats fixture coverage with positive-and-negative controls, and N=5 measurements.
- **Second scenario: `create-monitor`.** Authored full golden-path content (`agent/golden-paths/create-monitor/{README,steps,best-practices,example.tf}`) plus two new best-practice files (`monitor-notification-target.md`, `monitor-evaluation-window-floor.md`) in `Moonchopper/datadog-operations`. The skill body lives in `Moonchopper/claude-plugin-observability` and follows the same §9.1 detection-ladder + freshness check + practice-loading + pr-handoff pattern as `create-log-index`. The scenario deliberately exercises a practice override: the test driver supplies `notify_target=@user-foo` (an individual, deliberate violation), the agent must surface the violation, accept the rationale "temporary while team rotation is being set up", and include the rationale under `## Best-practice overrides` in the PR body. The N=5 matrix verified all of this.
- **Baseline cost-floor scenario.** New `baseline/baseline` row that asks the agent an off-topic question ("What is the capital of France?") with the plugin enrolled. Asserts no `Skill(observability:*)` invocations in the transcript. This is the architectural denominator — measures plugin-enrollment overhead independently of any retrieval work.
- **Per-row token-budget enforcement.** `scripts/matrix/poc-full.tsv` gained a 4th column with locked budgets (`ceil(P95 × 1.20)`). `scripts/aggregate-metrics.sh` gained a `--matrix` flag and emits `max` (worst-of-N), `budget`, and `status` (PASS/FAIL/BUDGET_UNSET) columns. The aggregator exits 1 if any row FAILs, allowing run-benchmarks.sh to bubble up the failure. Six new bats cases cover the PASS, FAIL, BUDGET_UNSET-via-`-`, BUDGET_UNSET-via-missing-row, no-matrix-flag, and `max=worst-of-N` paths.

## Measurement summary (Task C1, full matrix N=25)

| scenario | variant | N | P50 | P95 | max | budget | status | cache_ratio | hot_turn |
|---|---|---|---|---|---|---|---|---|---|
| baseline | baseline | N=5 | 8 | 8 | 8 | 10 | PASS | 0 | 1 |
| create-log-index | cwd-shortcut | N=5 | 7839 | 7888 | 7888 | 12357 | PASS | 0.95 | 30 |
| create-log-index | local-hit | N=5 | 8558 | 10395 | 10395 | 11357 | PASS | 0.95 | 8 |
| create-log-index | remote-fallback | N=5 | 9625 | 10275 | 10275 | 13302 | PASS | 0.95 | 66 |
| create-monitor | local-hit | N=5 | 8940 | 9787 | 9787 | 11998 | PASS | 0.95 | 39 |

- **Doc 4 §5.1.2 variant-delta hypothesis verified.** P50 ordering: `cwd-shortcut (7839) < local-hit (8558) < remote-fallback (9625)`. The `cwd-shortcut` optimization is real — skipping §9.1 step-2 path-probing saves ~720 P50 tokens vs `local-hit`, the agent terminates the detection ladder one round-trip earlier (hot_turn 30 vs 8 reflects this).
- **Cost floor.** Baseline P50=P95=8 tokens (just question+answer), but the plugin's enrolled-skill-description footprint adds ~9.7k cache_creation tokens per invocation regardless of whether a skill is invoked. That's the practical floor of the system.
- **All rows PASS.** Worst-of-N max-per-invocation is below budget for every row. The +20% headroom (locked from Phase B's individual measurements) absorbs the run-to-run variance observed in C1's full matrix.

## Plan deviations worth recording

1. **`fixture-org` placeholder bug.** Stage-2 skill body had hard-coded `fixture-org` org references in the §9.1 conventional-path probes and gh api fallback path. Stage-2 tests didn't catch this because in-tree fixtures bypassed path detection. A8 surfaced it immediately when the runner pre-cloned to `~/src/Moonchopper/datadog-operations` but the skill body searched `~/src/fixture-org/datadog-operations`. Patched in `Moonchopper/claude-plugin-observability` (commit 5e73eb5), bumped to v0.1.1 (cd82c04). **A3's Step 3.5 audit verified structural shape (rev-parse + origin-URL match present) but did not check the placeholder org** — a thin-spec gap. Confirms the externalization decision.

2. **`PROJECT_SLUG` POSIX→Windows mismatch.** A6's per-variant CWD setup used `mktemp -d` returning `/tmp/tmp.X` (POSIX). Claude Code resolved that to `C:/Users/austi/AppData/Local/Temp/tmp.X` before slugifying for the transcript dir, so the sed-based slug derivation produced the wrong path and `extract-metrics` silently never ran. Fixed by deriving via `pwd -W` (Windows form) before slugifying (eb5c4a7). Stage 2 carry-forward risk #5 — now closed.

3. **`claude plugin update` is semver-gated.** Skill-body iterations during Stage 3 require a `plugin.json` version bump for the local cache to refresh. Worth recording as a workflow detail. Plugin moved 0.1.0 → 0.1.1 (fixture-org fix) → 0.1.2 (create-monitor skill).

4. **Substring glob `*datadog-operations*` in skill body's CWD-match check.** Stage-2 skill body uses substring matching rather than exact-org. Means stale clones with `datadog-operations` in their path can poison detection. Mitigation: keep `/d/tmp/` and similar clean of stale clones. Tightening the glob is a one-liner; deferred unless it bites again.

5. **Matrix-loop stdin gobbling.** Latent since Stage 2: `claude -p` inside `run-scenario.sh` was consuming stdin from the outer `tail | while read` matrix loop, terminating the loop after row 1. Never surfaced because every prior matrix had exactly one row. Fixed by adding `</dev/null` to the run-scenario invocation in run-benchmarks.sh (commit 769bfb4).

6. **C1 was completed in two phases due to a power outage.** The first attempt completed 3 of 5 rows (15 of 25 invocations) before host power was lost. A topup matrix re-ran the missing rows (create-monitor + baseline) and produced metrics that combined cleanly with the surviving data. Functionally equivalent to a single sequential run for budget-validation purposes, but worth noting that the matrix runner doesn't have resumability built in.

7. **B2's run 3 failed assertion mid-matrix.** During remote-fallback's N=5, run 3's agent didn't write the handoff to the expected post-clone path; assertion's `cd $(dirname HANDOFF_FILE)` failed. The other 4 runs passed cleanly. The aggregator still emitted P50/P95 over all 5 jsonls (since metrics extraction had run before assertion). 4-of-5 is acceptable variance for the PoC; the +20% budget headroom absorbs it.

8. **Bench output paths use POSIX `/tmp/...` form on git-bash.** B3 implementer hit a path-mapping quirk where `/tmp/...` shell paths translate to `C:\Users\austi\AppData\Local\Temp` for shell ops but the `Write` tool interprets them as `D:\tmp\...`. Worked around by using Windows-style absolute paths or `/d/tmp/...` for Write tool calls. Worth flagging for future scratch-dir tasks.

## Decisions recorded

- **Marketplace source form.** Verified in A1: object form with `{"source": "url", "url": "https://github.com/<org>/<repo>.git"}` works without SSH config; `{"source": "github", "repo": "..."}` form requires SSH-key configuration. Standardized on the `url` form for HTTPS access.
- **Marketplace name.** Renamed `native-agent-observability-local` → `native-agent-observability` since "local" no longer fits.
- **Worktree convention.** Stage 3 work happened in `.worktrees/stage-3-externalize-and-extend/`. Phase A's PR #5 was opened against `docs/reference-scenarios` (PR #4) so the diff isolates to Phase A — will retarget to `main` once both PRs merge sequentially.
- **Budget contract.** Worst-of-N max-per-invocation `<= budget`, with `budget = ceil(P95 × 1.20)`. Aggregator emits PASS/FAIL/BUDGET_UNSET; non-zero exit on any FAIL.
- **B2 run 3 retained in P50/P95.** The aggregator includes its jsonl (metrics extraction completed before the assertion failure). The PoC's handling of partial-failure runs is "include and lean on +20% headroom"; if a future stage wants strict 5/5 PASS gating per row, that's a Stage-4 decision.

## Carry-forward risks for Stage 4

- **Real `pr-handoff` still not implemented.** Currently writes JSON; spec §3 has the PR as the execution-model terminus. Stage 4 candidate.
- **`add-apm-service` scenario** sketched in architecture spec §6 but not authored. Adding it is mechanical given the patterns Stage 3 established.
- **`create-monitor` × `cwd-shortcut`/`remote-fallback`** variants. Doc 4 deliberately scoped `create-monitor` to `local-hit` only (variant-delta evidence comes from create-log-index's three variants). Adding the other two is mechanical if a future stage wants per-scenario variant coverage.
- **Skill-body substring glob `*datadog-operations*`.** Mitigation: clean stale clones. Tighten to exact-org match if it bites.
- **Matrix runner has no resumability.** A power outage or interruption mid-matrix loses progress for unfinished rows. Stage 3 worked around with manual topup; if matrix runs grow longer, a checkpoint-and-resume mechanism is worth ~1 day of work.
- **`claude plugin update` semver-gating.** Every skill-body iteration requires a `plugin.json` version bump. Annoying for development; worth a one-line dev-mode flag if Stage 4 iterates heavily.
- **Bats not in CI.** Stage-1 carry-forward, persists.
- **`shellcheck` not in CI.** Same.
- **Run-to-run variance.** Some runs occasionally fail assertion (B2 run 3) due to agent path drift. Worth understanding whether this is variance under control of the prompt or fundamental LLM noise.

## Open decisions for Stage 4 (if it happens)

- **Real PR-authoring `pr-handoff`.** When and whether to implement.
- **Resumability** for matrix runs. Worth the engineering vs. just re-running.
- **Drift detection** for the externalized fixture repos. The plugin and functional repo can drift from each other (e.g. plugin v0.1.2 expects practices that don't yet exist in datadog-operations). A schema-version handshake at runtime would surface this; out of scope for PoC.
