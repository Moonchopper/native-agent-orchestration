# Reference Scenario Walkthrough

**Status:** Specification, complete enough to drive Stage 3 planning.
**Precedents:** [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](superpowers/specs/2026-04-23-core-architecture-design.md), [`docs/problem-and-vision.md`](problem-and-vision.md), [`docs/stage-2-notes.md`](stage-2-notes.md).
**Successor:** Stage 3 implementation plan.

---

## 1. Purpose

The architecture spec defers two concrete questions to this document:

- **§11.5 Scenario matrix** — *which* scenarios and variants the measurement harness exercises.
- **§13.3 Passing criteria** — *what* "this scenario passed" means, per scenario.

This doc resolves both. It does not invent new architecture; it names the test surface the existing architecture is validated against.

It is a *soft* prerequisite for the implementation plan. Stage 2 already validated `create-log-index / local-hit` end-to-end with a placeholder matrix ([scripts/matrix/stage-2-initial.tsv](../scripts/matrix/stage-2-initial.tsv), single row, N=5). Stage 3's scenario list comes from §6 below.

## 2. Scenario shape

Every scenario in §5 fills the same schema. Reading these fields in the same order each time keeps the matrix legible.

| Field | What it captures |
|---|---|
| **Trigger** | The natural-language question the user asks. The skill-picker (runtime step 2) must match this against the topic skill's `description` frontmatter. |
| **Variant** | One of `local-hit`, `cwd-shortcut`, `remote-fallback`, or scenario-specific. Selects which branch of the detection ladder (§9 of the architecture spec) the run exercises. |
| **Pre-run fixture state** | What the working tree looks like before `claude -p` starts (clone present at `~/src/...`? CWD inside fixture repo? no clone at all?). The runner sets this up. |
| **Inputs the agent must elicit** | Step 6 of the runtime flow. Concrete values the test driver supplies. |
| **Expected drafted artifact** | Path + content shape the agent should produce in the working tree. The shape is a contract, not an exact string match. |
| **Practice checks expected to fire** | Which `agent/best-practices/*.md` files should be loaded and applied. Pre- and post-draft passes count separately. |
| **Override expectation** | Whether the inputs deliberately violate a practice. Drives the `## Best-practice overrides` PR-body assertion. |
| **Passing criteria** | The four-part contract from architecture spec §13.3, instantiated for this scenario. |

## 3. Variants — what each one tests

The three primary variants are not redundant runs of the same scenario. Each exercises a different branch of the detection ladder and produces a different cost profile.

| Variant | Pre-run state | Detection-ladder branch (§9.1) | What it tests |
|---|---|---|---|
| **`local-hit`** | Clone of the functional repo at a known conventional path; CWD elsewhere. | Step 2 (conventional paths) wins. | The happy path. Establishes the baseline P50/P95. The architecture's primary code path. |
| **`cwd-shortcut`** | CWD is *inside* a clone of the functional repo. | Step 1 (CWD match) wins. | The "user is already in the right repo" optimization. Validates the shortcut actually skips path-probing turns. Variant delta against `local-hit` is the headline efficiency claim. |
| **`remote-fallback`** | No clone present anywhere on disk. | Steps 1–3 miss; step 4 prompts; the test driver responds *"clone it for me"*. | The offer-to-clone path (§9.3). Validates that `gh auth status` runs, the clone happens, and the rest of the flow proceeds against the freshly cloned working tree. |

A scenario does not need to cover all three variants. Variants are picked per scenario based on what each one would teach.

## 4. Fixture state — what each variant needs

The runner's job is to put the working tree in the right state before `claude -p` starts. This is what the three variants require.

The functional repo `Moonchopper/datadog-operations` is a real GitHub-hosted repository; the agent retrieves content via clone or `gh api`. It is *not* a deployable Datadog Terraform project — see the repo's README for the fixture caveat.

| Variant | Fixture-setup work in the runner |
|---|---|
| `local-hit` | Clone `Moonchopper/datadog-operations` to `~/src/Moonchopper/datadog-operations`. The runner's CWD is a scratch directory, not the clone. |
| `cwd-shortcut` | Same clone setup as `local-hit`. Runner's CWD is the clone. |
| `remote-fallback` | No clone at any conventional path. The runner verifies absence; the agent's detection ladder must reach step 4 and offer to clone. |

`remote-fallback` introduces real network or `gh` mocking complexity. Stage 3 should not block on a perfect mock — a working `gh api` call against a public fork of the fixture repo is sufficient signal.

## 5. The scenarios

Three scenarios. The first is the worked example from §6 of the architecture spec and is already partially fixtured. The second is the smallest credible second-scenario for proving generalization. The third is not a golden path at all — it is the cost floor.

### 5.1 `create-log-index`

The Team Foobar narrative from `problem-and-vision.md` §"Illustrative scenario." The skill, golden-path content, and best-practice files all exist in the repo already (Stage 1 + Stage 2).

#### 5.1.1 Variant: `local-hit` (already validated, Stage 2)

| Field | Value |
|---|---|
| Trigger | *"How do I create a log index in Datadog Prod for team Foobar?"* |
| Pre-run fixture state | Runner clones `Moonchopper/datadog-operations` to `~/src/Moonchopper/datadog-operations` (refreshed to a clean state on re-runs). CWD is the run's scratch directory, not the clone. |
| Inputs | `name=foobar-prod`, `filter=service:foobar-api env:prod`, `tier=Flex`, `days=30`, `quota=1000000000`. |
| Expected drafted artifact | `terraform/logs/indexes/foobar.tf` containing a single `datadog_logs_index` resource with the inputs above, formatted by `terraform fmt`. |
| Practice checks expected to fire | `index-naming` (no-op — name conforms), `query-cost-awareness` (no-op — Flex), `retention-tier-selection` (no-op — Flex). All three load both pre- and post-draft. |
| Override expectation | None. No rationale section in the PR body. |
| Passing criteria | (a) Skill body invoked; (b) `terraform/logs/indexes/foobar.tf` exists and `terraform validate` passes; (c) PR-handoff payload `drafted_files` contains exactly that file; (d) `## Best-practice overrides` heading absent from PR body; (e) tokens within budget (§7). |

This is the row already in [scripts/matrix/stage-2-initial.tsv](../scripts/matrix/stage-2-initial.tsv). N=5; 5/5 PASS in Stage 2.

#### 5.1.2 Variant: `cwd-shortcut`

Same trigger, same inputs, same expected artifact as 5.1.1. The single difference is fixture state: **Pre-run fixture state**: Same clone setup as 5.1.1. Runner's CWD is the clone. The detection ladder's step 1 (CWD match) should win.

**What this scenario must additionally prove:**

- The skill body's clone-detection turn skips path-probing entirely. Concretely: in the per-turn JSONL, the `cwd-shortcut` run's pre-content-load turns should be fewer than `local-hit`'s, because steps 2–4 of the ladder never execute.
- No regression in the artifact-drafting half of the flow.

**Variant-delta hypothesis (testable):** `cwd-shortcut` P50 is at least one full LLM call lower than `local-hit` P50, and the cost difference is concentrated in the early "where is the repo?" turns, not the content-load hot turn (turn 32 in Stage 2's run).

**Passing criteria:** identical to 5.1.1, with one addition — *no Glob/Bash invocation against `~/src/...`, `~/code/...`, etc., appears in the transcript*. Detection step 1 is sufficient on its own.

#### 5.1.3 Variant: `remote-fallback`

Same trigger and inputs as 5.1.1. **Pre-run fixture state**: No clone at any conventional path. Runner verifies absence pre-flight (errors if any conventional path has a `.git`). The test driver answers the agent's *"shall I clone it for you?"* prompt with *"yes, clone it"* (default path or any pre-configured one).

**What this scenario must additionally prove:**

- `gh auth status` is invoked early (auth preflight, §9.4 of the architecture spec).
- A clone happens, ending up at the offered path.
- The flow then proceeds normally against the just-cloned working tree.
- Token cost is meaningfully higher than `local-hit` — quantifying *how much* higher is the headline result.

**Passing criteria:** identical to 5.1.1, plus — (a) clone exists on disk after the run; (b) transcript contains a `gh auth status` Bash invocation before any clone; (c) PR-handoff payload's `drafted_files` paths are relative to the freshly cloned working tree.

### 5.2 `create-monitor`

A second golden path, deliberately distinct from `create-log-index` along architectural axes that matter:

- **Different referenced practices.** Monitor thresholds, alert routing, on-call ownership — not retention or query cost. Forces a fresh set of `agent/best-practices/*.md` files; tests that practice loading is not accidentally hardcoded for the log-index case.
- **A practice the user is expected to override.** *"Monitors must page a team channel, not an individual."* The test driver supplies an individual user as the alert recipient; the agent surfaces the violation, the driver supplies a rationale (*"temporary while team rotation is being set up"*), and the agent must record it under `## Best-practice overrides` in the PR body.
- **A second resource type in the same functional repo.** Drafts `terraform/monitors/<team>.tf`, not `terraform/logs/...`. Confirms the architecture is not implicitly coupled to one Terraform sub-tree.

#### 5.2.1 Variant: `local-hit`

| Field | Value |
|---|---|
| Trigger | *"Set up a Datadog monitor that alerts when foobar-api error rate goes over 2% for 5 minutes."* |
| Pre-run fixture state | Same clone setup as 5.1.1. |
| Inputs | `name=foobar-api-error-rate`, `query=sum:foobar.api.errors{*}.as_rate() > 0.02`, `window=5m`, `notify_target=@user-foo` *(individual — the override case)*. |
| Expected drafted artifact | `terraform/monitors/foobar-api-error-rate.tf` containing a `datadog_monitor` resource, `terraform fmt`'d and `terraform validate`'d. |
| Practice checks expected to fire | `monitor-notification-target` (fires; raises violation), plus 1–2 others to be authored alongside the fixture (e.g. `monitor-evaluation-window-floor`). |
| Override expectation | Yes — for `monitor-notification-target`. Rationale text supplied by the test driver and asserted to appear in the PR body. |
| Passing criteria | (a)–(c) same as 5.1.1 against the new path/resource; (d) PR body **contains** `## Best-practice overrides` with the supplied rationale; (e) tokens within a per-scenario budget re-derived from this scenario's first measurement pass. |

`create-monitor` requires fixture content that does not yet exist: a new SKILL.md in the plugin, a new golden-path directory, a new best-practice file (`monitor-notification-target.md`), and an `example.tf` for monitors. Authoring it is part of Stage 3 scope, not this doc.

`create-monitor` is intentionally exercised on `local-hit` only in the PoC. The variant-delta evidence we need (`cwd-shortcut`, `remote-fallback`) is already collected via 5.1.2 and 5.1.3 — those branches of the detection ladder are scenario-agnostic. Re-running every variant for every scenario is the kind of growth that should wait for an actual N-of-topics > 2 problem.

### 5.3 `baseline`

Not a golden path. The cost floor.

| Field | Value |
|---|---|
| Trigger | *"What's the capital of France?"* — or any clearly off-topic question. |
| Pre-run fixture state | Plugin enrolled, but the question matches no skill description. |
| Variant | Single variant, named `baseline`. |
| Expected drafted artifact | None. |
| Practice checks expected to fire | None. |
| Override expectation | None. |
| Passing criteria | (a) No skill body is loaded (verifiable in the transcript: no `Skill(observability:*)` tool use); (b) the agent answers the off-topic question normally; (c) the per-invocation token total is logged so it can be subtracted from in-scope scenarios as overhead. |

The point of `baseline` is **not** correctness. It is the denominator. *"How much does the plugin cost when it isn't being used?"* — if that number is large, the plugin is too expensive to install widely; if it is small, the plugin's overhead is amortized away the first time it routes a real question. This is the analysis dimension §11.6 of the architecture spec calls *baseline cost*.

## 6. The matrix

This is the table the implementation plan installs in [scripts/matrix/](../scripts/matrix/) and feeds to `run-benchmarks.sh`. Stage 3 should land it as something like `scripts/matrix/poc-full.tsv`, alongside the existing Stage-2 row.

| Scenario | Variant | N | In Stage 2? | Stage 3 status |
|---|---|---|---|---|
| `create-log-index` | `local-hit` | 5 | Yes (validated) | Re-runs as part of full matrix; no fixture work |
| `create-log-index` | `cwd-shortcut` | 5 | No | Runner gains a CWD-controlling flag; no fixture work |
| `create-log-index` | `remote-fallback` | 5 | No | Runner gains no-clone setup + `gh` reachability; no new content fixture |
| `create-monitor` | `local-hit` | 5 | No | Requires new SKILL, golden-path dir, ≥2 best-practice files, `example.tf` for monitors |
| `baseline` | `baseline` | 5 | No | Trivial setup; no fixture work beyond a triggering off-topic prompt |

`N=5` for every row, mirroring Stage 2. Whether to grow N for tighter P95 confidence is one of the open Stage 3 decisions in [stage-2-notes.md](stage-2-notes.md) §"Open decisions for Stage 3."

`baseline` is listed as a single variant for clarity; in the TSV it occupies one row. The "all in N=5" choice is deliberate — if a scenario shows wide P50/P95 spread at N=5, that is a finding worth surfacing rather than papering over with a larger N.

## 7. Token-budget assertions

Stage 2 proposed `ceil(P95 * 1.20) = 11228` tokens/invocation as the tolerance for `create-log-index / local-hit`. That number stands and becomes the row's budget in `scripts/matrix/poc-full.tsv`.

For the new rows, the budget cannot be guessed in advance. The procedure (matching architecture spec §15's *"set after the first end-to-end measurement pass"*):

1. Stage 3 lands the matrix row with **no budget assertion** (or a permissive sentinel like `99999`).
2. The first end-to-end pass produces real P50/P95 numbers for that row.
3. The implementer applies `ceil(P95 * 1.20)` and updates the matrix row.
4. Subsequent runs assert against the locked-in number.

This is mechanical, not interpretive. The 1.20 headroom factor is the same across rows unless a specific scenario surfaces a reason to widen it.

**`cwd-shortcut`'s budget should land lower than `local-hit`'s.** If it does not, the variant-delta hypothesis in §5.1.2 is wrong and the architecture's "skip detection ladder steps 2–4" optimization is not actually paying off — that is itself a finding worth surfacing in Stage 3's results write-up.

**`remote-fallback`'s budget should land higher than `local-hit`'s.** *How much* higher is the answer to whether local-first retrieval is worth its complexity (an analysis dimension already named in architecture spec §11.6).

## 8. What's deliberately not covered

Aligned with `problem-and-vision.md` non-goals and architecture spec §14 (out of scope), the following are **not** scenarios in the PoC:

- **`add-apm-service`** is sketched in the architecture-spec diagram (§6) but not enumerated here. A *third* in-scope golden path is not required to validate the architecture. It is also a natural Stage 4 candidate if the project continues past PoC.
- **A scenario where the agent halts on a missing best-practice file.** The architecture spec §12 prescribes the response, but exercising it in the matrix is a unit-test concern, not a measurement-harness concern.
- **A scenario where `gh auth status` fails.** Same reasoning. The error path is specified; benchmarking it consumes budget without producing meaningful cost data.
- **Multi-clone disambiguation.** Architecture spec §12 prescribes "prefer CWD; otherwise first-found." Real-world rare; not worth a matrix row.
- **A scenario where `terraform validate` fails on the drafted file.** This is a fixture-correctness test, not an architecture test. If `example.tf` is right and the substitutions are right, validation passes by construction.

If any of these become load-bearing later, they can be promoted into the matrix without redesigning the harness — adding a row is mechanical.

## 9. Open decisions for Stage 3

Resolved when the implementation plan is written, not here. Doc 4 names them so they aren't lost.

- **Where the `create-monitor` fixture content lives.** Same `Moonchopper/datadog-operations` repo (consistent with the colocate-with-function principle), or a separate fixture repo to demonstrate cross-functional-repo routing? Inclination: same repo. The cross-repo case is a future concern, and the PoC's premise is one functional repo per topic *cluster*, not per topic.
- **Whether `remote-fallback` runs against a real public GitHub fork or a `gh`-CLI mock.** Real fork is simpler to set up but couples the matrix run to network availability. A `gh` mock is more hermetic but real engineering work. Inclination: real public fork; flag the network dependency in the matrix runner's preamble.
- **Whether `baseline` runs *with* or *without* the plugin enrolled.** Architecture spec §11.5 frames it as "plugin installed, off-topic question." That is the right call. A second variant (`baseline-no-plugin`) might surface plugin overhead more starkly, but it tests Claude Code's behavior rather than this PoC's, and is out of scope.
- **Whether to re-derive the `local-hit` budget after Stage 3's broader changes.** Stage 2's number was measured against a single matrix row in isolation. If Stage 3 changes anything that touches the `create-log-index/local-hit` flow (e.g. a generic-ified skill body extracted for reuse with `create-monitor`), the budget should be re-derived. If not, the existing 11228 stands.

## 10. Glossary

Quick reference for terms used above.

- **Detection ladder** — the four-step sequence (CWD match → conventional paths → plugin-configured prefix → ask user) the agent uses to find a local clone. Architecture spec §9.1.
- **Hot turn** — the assistant LLM call that consumes the most tokens in a run. Stage 2 found turn 32 to be hot for `create-log-index/local-hit`, corresponding to step 5 of the runtime flow (load golden-path content).
- **Variant delta** — the cost difference between two variants of the same scenario. The headline output of running multiple variants.
- **Override rationale** — non-empty user-supplied text justifying a deliberate best-practice violation. Recorded in the PR body under `## Best-practice overrides`.
- **PR-handoff payload** — `{drafted_files, pr_body, override_rationale[]}` passed from a topic skill to the orthogonal `pr-handoff` skill. Currently a JSON-stub; see `stage-2-notes.md` carry-forward risk.
