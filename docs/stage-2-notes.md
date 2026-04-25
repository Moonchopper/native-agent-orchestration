# Stage 2 Notes — handoff to Stage 3

## What Stage 2 built

- **Hardened `create-log-index` scenario.** Renamed `_pr-handoff` to `pr-handoff`; rewrote Step 9 of the create-log-index skill to use an explicit `Skill` tool invocation with forbidden fallbacks; replaced `--permission-mode bypassPermissions` with an explicit `--allowedTools` allowlist via `settings/benchmark.settings.json`; added a `--append-system-prompt` directive to suppress brainstorming/design-review modes.
- **Fixed plugin enrollment.** The previous `setup-plugin.sh` did `cp -R` into `~/.claude/plugins/`, which doesn't actually enroll a plugin. Replaced with a project-root `.claude-plugin/marketplace.json` plus `claude plugin marketplace add` + `claude plugin install` (both `--scope project`). See "Plan deviation A4.5" below — this was a Stage-1-era latent bug that surfaced during A4 hardening.
- **Stability gate (Task A5).** 5 consecutive end-to-end runs of `create-log-index / local-hit` after hardening: **5/5 PASS**, all confirmed plugin-driven via session-transcript inspection (each run invoked `Skill(observability:create-log-index)` and `Skill(observability:pr-handoff)`).
- **Per-turn metric extraction.** `scripts/extract-metrics.sh` reads a Claude Code session transcript JSONL and emits one summary line per assistant LLM call with `{ts, session_id, scenario, variant, run_ix, turn, model, tokens_in, tokens_out, cache_read, cache_creation, duration_ms, skill_active}`. **No hook layer** — the original plan called for a Stop hook, but B1's payload-capture step found that the actual `claude -p` Stop payload carries no token data; runner post-processing of the transcript is simpler and equivalent.
- **Aggregator.** `scripts/aggregate-metrics.sh` produces a markdown table per `(scenario, variant)` with `N`, P50, P95, cache_ratio, and hot_turn (the assistant LLM call that consumed the most tokens). Per spec §11.6 analysis dimensions.
- **Matrix driver.** `scripts/run-benchmarks.sh --matrix <tsv>` iterates `(scenario, variant, n)` rows, invokes `run-scenario.sh` n times in fresh sessions per row, collects per-run metrics files, and pipes them to the aggregator.
- **Stage-2 calibration matrix:** [scripts/matrix/stage-2-initial.tsv](../scripts/matrix/stage-2-initial.tsv) — single row, `create-log-index / local-hit`, N=5. Stage 3 extends this file with additional rows once doc 4 lands.

## Measurement summary (Task D1, N=5)

| scenario | variant | N | P50 | P95 | cache_ratio | hot_turn |
|---|---|---|---|---|---|---|
| create-log-index | local-hit | N=5 | 8755 | 9356 | 0.96 | 32 |

- **N=5 pass rate:** 5/5 (zero `RUN FAILED` markers in the bench log).
- **P50 (8755 tokens):** typical per-invocation total of `tokens_in + tokens_out` across all assistant LLM calls in one scenario run.
- **P95 (9356 tokens):** worst-of-5 per-invocation total. Spread between P50 and P95 is ~7% — small enough to suggest the hardened scenario is reasonably deterministic on the cost dimension.
- **cache_ratio 0.96:** 96% of total input tokens came from prompt cache. The architecture re-uses the skill body across many tool-use cycles and Claude Code's caching is doing most of the heavy lifting.
- **hot_turn 32:** the 32nd assistant LLM call in a typical run consumed the most tokens. Worth investigating in Stage 3 whether this corresponds to step 5 of the skill body (load golden-path content) as the spec hypothesized.

**Proposed token-budget tolerance for Stage 3 assertions:** `ceil(9356 * 1.20) = 11228` tokens per scenario invocation. The 20% headroom accounts for run-to-run LLM variability while not blowing the budget out for legitimately heavy runs. Stage 3 should re-derive this number per-scenario as new scenarios land.

## Plan deviations worth recording

1. **Task A1 over-edited historical docs.** The first attempt to grep-replace `_pr-handoff` → `pr-handoff` touched `docs/stage-1-notes.md` and the two plan documents. Spec reviewer caught it; the docs-only edits were reverted via `git checkout HEAD~1 -- <files>` and the commit was amended to include only active-source changes.

2. **Task A2 was missing `Skill` from the skill's `allowed-tools` frontmatter.** Code-quality reviewer flagged that Step 9 directs the agent to invoke the `Skill` tool but the file's `allowed-tools` line listed `Bash, Read, Glob, Grep, Edit, Write` — no `Skill`. Folded into a follow-up commit that also tightened the halt-on-error wording and added a literal `args` example to remove double-encoding ambiguity.

3. **Task A1 audit-trail gap (`scripts/setup-plugin.sh`).** The plan's Step 1 grep + Step 5 verify-no-stragglers grep were supposed to confirm `setup-plugin.sh` had no `_pr-handoff` references. They were run, but the implementer's report didn't surface the result. Confirmed during code-quality review: the script uses a directory-level `cp -R` with no skill-specific paths, so no edit was required. Recording here to close the audit trail.

4. **Task A4.5 — fix local-plugin enrollment (added mid-execution).** A4's `--append-system-prompt` ("halt if a referenced skill is unavailable") surfaced a Stage-1-era latent bug: the fixture plugin was never actually loaded by `claude -p`. The previous `setup-plugin.sh` did `cp -R fixtures/claude-plugin-observability ~/.claude/plugins/observability-fixture/`, but Claude Code only loads plugins enrolled via `claude plugin marketplace add` + `claude plugin install`. **A3's "successful" smoke and Stage-1's "1/3 pass" were both the agent improvising — `cd`'d into the fixture repo, it could read `agent/golden-paths/...` directly off disk and follow the prose without invoking the plugin.** Fix: project-root `.claude-plugin/marketplace.json` + a rewritten `setup-plugin.sh` using the canonical CLI commands. **First true plugin-driven end-to-end pass on record:** verified via session JSONL showing `Skill(observability:create-log-index)` and `Skill(observability:pr-handoff)` invocations.

5. **Task A4.5 sub-deviation: `enabledPlugins` in `benchmark.settings.json`.** `--scope project` plugin enrollment activates only when `cwd` matches the project path. The runner does `cd "$FIXTURE_REPO"` (a subdirectory) before `claude -p`, which broke activation. Workaround: added `"enabledPlugins": {"observability@native-agent-observability-local": true}` to `settings/benchmark.settings.json`. The harness explicitly controls its own plugin set via `--settings`. Risk: a future `claude plugin disable` in the project scope flips the project-scope binding to false but leaves the benchmark binding intact. This is arguably correct (the harness is sovereign over its environment) but non-obvious.

6. **Part B redesigned (drop the hook).** The original plan called for a Stop hook to capture per-turn token metadata. B1's payload-capture step found that the actual `claude -p` Stop payload carries only `{session_id, transcript_path, cwd, permission_mode, hook_event_name, stop_hook_active, last_assistant_message}` — no token data. All token data lives in the session transcript JSONL at `transcript_path` under `.message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`. Replaced the hook-centric design with `scripts/extract-metrics.sh` invoked by the runner after `claude -p` exits. Eliminated 3 tasks of work and removed hook-payload-shape drift risk across Claude Code versions. Spec §11 was descriptive of intent, not prescriptive of mechanism — all §11.6 analysis dimensions work identically.

7. **Task B4 simplification: skipped `AGENT_ORCH_HANDOFF_FILE`.** The original B5 wanted to route the handoff JSON through `$SESSION_DIR/handoff.json` to enable parallel benchmark runs without clobbering. Per spec §11.4 the matrix runs in fresh **serial** sessions, so the single fixture-repo handoff path remains adequate. Skipped the corresponding `pr-handoff/SKILL.md` env-var-honoring update.

8. **Task C2 cache_ratio bug, fixed during C5 smoke.** Initial formula was `cache_read_sum / tokens_in_sum`, which produced nonsensical values >>1 on real Claude Code data (C5 smoke produced `cache_ratio=20051.82`). Conceptually correct formula is `cache_read / (cache_read + tokens_in + cache_creation)` — the share of total input that came from cache. On real data this gives ~0.95, a meaningful diagnostic.

9. **Plan arithmetic error in C1 fixture math.** Plan claimed `tokens_in_sum=16500` for the aggregator test fixture; actual sum was 17000. Test expectation updated; aggregator implementation was correct.

## Carry-forward risks for Stage 3

- **Single scenario, single variant.** The `remote-fallback` and `cwd-shortcut` variants need new fixture states (no local clone; in an unrelated repo); additional scenarios (`create-monitor`, etc.) need doc 4. Stage 2 deliberately validated only `create-log-index / local-hit`.
- **`skill_active` is emitted as `null`.** The transcript schema doesn't tag each assistant turn with which skill is active. Deriving it would require scanning backward through `Skill` tool-use entries to find the most recent invocation. Useful for "which skill consumed what tokens" cross-cuts in Stage 3+.
- **`duration_ms` is emitted as 0.** Not present in the transcript schema. Not in scope per spec §11.8 ("wall-clock from the user's perspective" is deliberately not measured), but flagged here in case Stage 3 wants per-turn latency.
- **Percentile formula is rank-based, not interpolated.** Fine for N=5; revisit if Stage 3 grows N significantly.
- **`PROJECT_SLUG` derivation in `run-scenario.sh` is heuristic.** Currently `sed -e 's/[\\:/.]/-/g'` to mimic Claude Code's path-munging convention. Verified correct on Windows-style paths in this worktree, but if Claude Code's convention changes (e.g., to handle UTF-8 or other special chars), this breaks silently — the runner falls back to "no transcript found, skipping metric extraction" with a warning. Consider a more robust derivation if Stage 3 hits new path edge cases.
- **`pr-handoff` is still a stub.** It writes a JSON file rather than opening a real PR. A real PR-authoring skill is a Stage 3 or separate "orthogonal skills" track concern.
- **`shellcheck` not yet in CI.** Stage-1 carry-forward risk persists into Stage 2.
- **`setup-plugin.sh` swallows real errors via `|| true` on `claude plugin marketplace add` and `claude plugin install`.** Mitigant: the post-install verification (`claude plugin list | grep -q ...`) at the bottom catches the "nothing actually installed" outcome. But if the `claude` CLI is upgraded and either subcommand changes its error-on-duplicate behavior, the verification check is the only guard. Worth revisiting if errors land in `claude` CLI semantics.
- **`enabledPlugins` / project-scope dual-knob drift.** Documented in A4.5 above. A future `claude plugin disable` in the project scope does not affect benchmark runs because `--settings` overrides it. This is intentional but non-obvious; reading order matters.

## Decisions recorded

- **Hook event:** none — runner post-processes the transcript JSONL after `claude -p` exits.
- **Transcript schema observed (claude opus 4.6, 2026-04-25):** `.message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}` per assistant LLM call. Lines also include `.message.model`, `.timestamp`, `.uuid`, and `.parentUuid`.
- **Percentile definition:** rank-based — for N runs, P50 = sorted[floor(N/2)], P95 = sorted[N-1].
- **Cache ratio definition:** `cache_read / (cache_read + tokens_in + cache_creation)` — share of total input from cache.
- **Tolerance heuristic:** `ceil(P95 * 1.20)` for §13.3 token-budget assertions in Stage 3.

## Open decisions for Stage 3

- **Scenario list (from doc 4):** which additional scenarios land first.
- **Whether to grow N beyond 5** for tighter P95 confidence intervals.
- **Failed-run handling.** Currently `run-benchmarks.sh` continues past a failed `run-scenario.sh` and prints "RUN FAILED" without aborting. The aggregator treats failed runs as missing data, which understates P95. Consider whether Stage 3 wants a strict mode that fails the whole matrix on any run failure.
- **Real `pr-handoff` implementation.** Currently writes a JSON file; spec §3 has the PR as the execution-model terminus, but Stage 1-2 deferred actual PR creation. Stage 3 timing depends on whether real CI/CD integration is in scope.
- **Cross-machine reproducibility of `setup-plugin.sh`.** Currently writes machine-specific absolute paths into `.claude/settings.json` (gitignored). Each developer must run `setup-plugin.sh` once on a fresh clone. Consider whether a smoother onboarding pattern is needed before sharing the repo more widely.
