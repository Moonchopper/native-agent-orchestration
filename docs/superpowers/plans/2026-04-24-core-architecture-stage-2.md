# Stage 2: Scenario Hardening + Measurement Harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the Stage-1 scenario so re-runs succeed deterministically, then ship the §11 measurement harness (hook + runner extensions + benchmark driver + aggregator), and perform a single-cell calibration pass to seed the Stage-3 token-budget tolerance.

**Architecture:** A Claude Code `Stop` hook (or equivalent, confirmed during Task B1) writes one JSONL line per turn to `~/.local/share/agent-orch/metrics/<session_id>.jsonl`, tagged via env vars that the runner injects before `claude -p`. A benchmark driver wraps `run-scenario.sh` to iterate a matrix in fresh sessions; an aggregator reads the JSONL and emits P50/P95 per scenario/variant.

**Tech Stack:** bash (POSIX-ish, `set -euo pipefail`), `jq`, bats-core (vendored in `.bats/`), Claude Code `claude -p` headless, Claude Code `settings.json` hooks.

**Precedents:**
- Spec: [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](../specs/2026-04-23-core-architecture-design.md) — §11 defines the measurement system; §15 flags `Stop` as the candidate hook event.
- Stage-1 handoff: [`docs/stage-1-notes.md`](../../stage-1-notes.md) — §Plan deviations #6 lists the hardening work that must land before the measurement matrix is believable.

**Out of scope (deferred):**
- Additional scenarios (`create-monitor`, `remote-fallback`, `cwd-shortcut` variants). Those need doc 4 and belong in Stage 3.
- `shellcheck` in CI (stage-1-notes carry-forward risk; nice-to-have, not on the Stage-2 critical path).
- Real PR authoring from `pr-handoff` (still a stub that writes JSON).
- Semantic/cost optimization passes (spec §14).

---

## File Structure

### Modify

- `fixtures/claude-plugin-observability/skills/_pr-handoff/` — rename directory to `pr-handoff/` (drop leading underscore); update the `name:` frontmatter line inside its `SKILL.md`.
- `fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md` — rewrite **Step 9** to use an explicit `Skill` tool invocation (name `observability:pr-handoff`), forbid `git commit` / `gh pr create` fallbacks, and surface a halt instruction if the handoff skill is unreachable.
- `scripts/run-scenario.sh` — three changes:
  1. Replace `--permission-mode bypassPermissions` with `--allowedTools` allowlist + `--settings <path>` pointing at `settings/benchmark.settings.json`.
  2. Add `--append-system-prompt` injecting "scenario run; do not enter brainstorming; do not ask for design approval."
  3. Set `AGENT_ORCH_SCENARIO`, `AGENT_ORCH_VARIANT`, `AGENT_ORCH_RUN_IX`, `AGENT_ORCH_METRICS_FILE`, `AGENT_ORCH_SESSION_DIR` env vars before invoking `claude -p`. Route the per-run handoff artifact to a run-scoped path so consecutive runs don't clobber each other.
- `scripts/assertions/create-log-index-local-hit.sh` — accept the run-scoped handoff path from the runner; no behavior change beyond pathing.
- `scripts/setup-plugin.sh` — update any path references that mention `_pr-handoff` to `pr-handoff`.
- `tests/test_runner_contract.bats` — extend with: new env-var contract (scenario/variant/run-ix surface in `DRY_RUN` output), new CLI flag surface.
- `docs/superpowers/specs/2026-04-23-core-architecture-design.md` — **no edits** (spec is locked); any decisions recorded against it go to `docs/stage-2-notes.md`.

### Create

- `hooks/metric-capture.sh` — bash hook. Reads Claude Code hook payload from stdin, extracts token-usage fields, appends one JSONL line per turn to `$AGENT_ORCH_METRICS_FILE` (or a default derived from session id).
- `settings/benchmark.settings.json` — the `--settings` file the runner passes: hook registration + narrow `permissions.allow` allowlist (replaces `bypassPermissions`).
- `scripts/run-benchmarks.sh` — matrix driver. Iterates `(scenario, variant)` tuples N times, invokes `run-scenario.sh` per iteration in a fresh session, collects per-run metrics paths.
- `scripts/aggregate-metrics.sh` — reads one or more JSONL metric files, groups by `(scenario, variant)`, computes P50/P95 for `tokens_in + tokens_out`, cache-read ratio, and hot-spot turn. Emits a markdown summary table to stdout.
- `scripts/matrix/stage-2-initial.tsv` — TSV of the Stage-2 matrix (single row for now: `create-log-index\tlocal-hit\t5`). Stage 3 extends this file.
- `tests/test_metric_hook.bats` — fixture-driven tests for the metric-capture hook: given a canned hook payload, assert the JSONL line shape and fields.
- `tests/test_aggregate_metrics.bats` — fixture-JSONL-driven tests for the aggregator's P50/P95 math and table shape.
- `tests/fixtures/metric-hook-payload.json` — canned Claude Code hook payload (one turn) for the hook test.
- `tests/fixtures/metric-hook-payload-missing-tokens.json` — canned payload with missing/null token fields for the hook's graceful-degradation test.
- `tests/fixtures/aggregate-sample.jsonl` — 10 fixture lines (two scenarios, two variants, varied token counts) for the aggregator test.
- `docs/stage-2-notes.md` — handoff to Stage 3 (mirrors `docs/stage-1-notes.md`): what Stage 2 built, plan deviations, decisions deferred, carry-forward risks, and the first P50/P95 measurement with a proposed tolerance for Stage-3 assertions.

### Do not create

- Shared `scripts/lib/*.sh` helper files. Per prior feedback, inline trivial primitives at the call site; only extract when ≥2 real consumers exist. This rule especially applies to any "assert-json-field" or "read-metric" helpers.
- A settings.local.json variant. One committed settings file for benchmark runs is enough.

---

## Why this ordering

Part A hardens the scenario **before** measurement. Rationale: Stage-1 verification showed three different outcomes across three runs (pass, brainstorming stall, handoff-skill-not-found). Measuring a scenario with >0% catastrophic-failure rate produces a P95 that reflects LLM mode-confusion, not architecture cost. Harden first so the measurement signal is about the architecture.

Part B builds the instrumentation end-to-end on the hardened scenario (one cell only). Part C generalizes the driver to a matrix. Part D runs the calibration pass that Stage 3 needs to set its token-budget tolerance. Each part ends at a natural checkpoint where the plan could be paused and revisited.

---

# Part A — Harden the scenario

### Task A1: Rename `_pr-handoff` → `pr-handoff`

**Why:** Leading-underscore skill names may be interpreted as "private/hidden" by some matching heuristics. Stage-1 run 3 reported `_pr-handoff` as "not registered" and fell back to a git commit. Removing the underscore is a cheap mitigation.

**Files:**
- Rename: `fixtures/claude-plugin-observability/skills/_pr-handoff/` → `fixtures/claude-plugin-observability/skills/pr-handoff/`
- Modify: `fixtures/claude-plugin-observability/skills/pr-handoff/SKILL.md` (update `name:` frontmatter)
- Modify: `fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md:151` (reference to `/observability:_pr-handoff`)
- Modify: `scripts/setup-plugin.sh` (any hard-coded path references — verify via grep first)
- Modify: `scripts/assertions/create-log-index-local-hit.sh` (handoff-file path if hard-coded)

- [ ] **Step 1: Grep all references to `_pr-handoff`**

```bash
grep -rn "_pr-handoff" --include="*.md" --include="*.sh" --include="*.json" .
```

Expected: list of sites that need updating. Capture the list before editing to avoid missing one.

- [ ] **Step 2: Rename the directory**

Use `git mv` (not `mv` + `git add`) so git preserves the rename:

```bash
git mv fixtures/claude-plugin-observability/skills/_pr-handoff \
       fixtures/claude-plugin-observability/skills/pr-handoff
```

Expected: `git status` shows one rename.

- [ ] **Step 3: Update the skill's own frontmatter**

Edit `fixtures/claude-plugin-observability/skills/pr-handoff/SKILL.md` — change `name: _pr-handoff` to `name: pr-handoff`.

- [ ] **Step 4: Update every other reference identified in Step 1**

For each hit from Step 1 (excluding the file renamed in Step 2), replace `_pr-handoff` with `pr-handoff`. Common spots: Step 9 reference in `create-log-index/SKILL.md`, any path strings in assertion or setup scripts.

- [ ] **Step 5: Verify no stragglers**

```bash
grep -rn "_pr-handoff" --include="*.md" --include="*.sh" --include="*.json" .
```

Expected: no matches. If any remain, repeat Step 4 on those files.

- [ ] **Step 6: Run existing bats suite**

```bash
.bats/bin/bats tests/
```

Expected: 4/4 pass. If any tests reference the old name, update them as part of this task.

- [ ] **Step 7: Reinstall the plugin**

```bash
./scripts/setup-plugin.sh
```

Expected: plugin directory under `~/.claude/plugins/` now contains `skills/pr-handoff/`, not `skills/_pr-handoff/`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: rename _pr-handoff skill to pr-handoff

Leading underscore was interpreted as 'hidden' during Stage 1 run 3,
causing the agent to fall back to a git commit. Per stage-1-notes.md
§Plan deviations #6."
```

---

### Task A2: Rewrite Step 9 of `create-log-index` SKILL.md — explicit Skill invocation, forbid fallbacks

**Why:** Stage-1 run 3 had Claude execute the golden path then invent its own handoff mechanism (git commit). The skill body said *"Invoke the `_pr-handoff` skill (`/observability:_pr-handoff`)"* — a slash-command reference, not a directive to use the Skill tool. Rewriting to name the tool explicitly and forbid alternatives closes the gap.

**Files:**
- Modify: `fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md:144-153` (Step 9 body)

- [ ] **Step 1: Read the current Step 9 body**

```bash
sed -n '144,160p' fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md
```

Confirm the current prose matches what's quoted in the stage-1 notes. Any divergence is a hint that someone already touched this; resolve before proceeding.

- [ ] **Step 2: Replace Step 9 body with the hardened version**

New Step 9 body (complete, replaces the existing ~10 lines):

```markdown
## Step 9 — Hand off to `pr-handoff`

Assemble the payload:
- `drafted_files`: `[{path: "terraform/logs/indexes/$team.tf", contents: <contents>}]`
- `pr_body`: fill the PR body template from `steps.md` with the confirmed values
- `override_rationale`: `overrides[]` collected above

Invoke the `pr-handoff` skill by calling the `Skill` tool with:
- `skill: "observability:pr-handoff"`
- `args: <the assembled payload, JSON-encoded>`

Do NOT substitute any alternative. Specifically:
- Do NOT run `git commit` or `gh pr create` from this skill. Those are
  `pr-handoff`'s job — not yours.
- Do NOT write the handoff JSON directly with the `Write` tool. The
  `pr-handoff` skill owns the artifact path and schema.
- Do NOT ask the user "should I commit this instead?" The answer is no.

If the `Skill` tool reports that `observability:pr-handoff` is not
available, halt and surface the error verbatim. Do not fall back.
```

- [ ] **Step 3: Run the bats suite**

```bash
.bats/bin/bats tests/
```

Expected: 4/4 pass. This is a prose-only edit, so bats shouldn't notice — it's a sanity check that nothing else broke.

- [ ] **Step 4: Reinstall the plugin**

```bash
./scripts/setup-plugin.sh
```

- [ ] **Step 5: Commit**

```bash
git add fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md
git commit -m "fix(skill): make Step 9 handoff explicit and forbid fallbacks

Stage-1 run 3 had the agent invent a git-commit handoff when it couldn't
resolve the old slash-command reference. Rewrite Step 9 to name the Skill
tool invocation directly and list the alternatives that are forbidden."
```

---

### Task A3: Narrow `claude -p` permissions via `--settings`

**Why:** `--permission-mode bypassPermissions` disables every safety prompt, which is broader than the scenario needs and makes the agent's behavior less predictable. Replacing it with an explicit allowlist (via `settings.json` + `--settings <path>`) tightens the scope to what `create-log-index` actually exercises.

**Files:**
- Create: `settings/benchmark.settings.json`
- Modify: `scripts/run-scenario.sh:79` (the `claude -p` invocation)

- [ ] **Step 1: Enumerate the tool calls the skill actually makes**

Walk `fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md` and list the tools + concrete patterns used:
- `Bash(git:*)` — `git rev-parse`, `git config`, `git fetch`, `git rev-list`, `git diff`
- `Bash(gh:*)` — `gh auth status` (preflight only; no mutation in Stage 1)
- `Bash(terraform:*)` — `terraform fmt`, `terraform validate`
- `Read` — best-practices files, golden-path files
- `Glob`, `Grep` — for detection ladder
- `Write` — the drafted `.tf` file
- `Edit` — not currently needed, but safe to include for future iteration
- `Skill` — the `pr-handoff` invocation added in A2

- [ ] **Step 2: Create `settings/benchmark.settings.json`**

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(gh auth status)",
      "Bash(terraform fmt:*)",
      "Bash(terraform validate)",
      "Bash(terraform validate:*)",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "Skill"
    ]
  },
  "hooks": {}
}
```

The `hooks` block is left empty on purpose — Task B6 fills it in.

- [ ] **Step 3: Update the runner's `claude -p` invocation**

In `scripts/run-scenario.sh`, replace the `--permission-mode bypassPermissions` argument with `--settings "$REPO_ROOT/settings/benchmark.settings.json"`. Surrounding lines stay as-is.

- [ ] **Step 4: Smoke-run the scenario once**

```bash
./scripts/run-scenario.sh create-log-index local-hit
```

Expected: scenario completes, assertion script passes, no permission-prompt stall.

**Failure mode to watch for:** the agent hits a prompt for a tool you forgot to allow. Symptom: headless run hangs or exits with a `requires user approval` error. Fix: add the specific pattern to `settings/benchmark.settings.json` and re-run. If you hit this for a pattern not in the Step-1 inventory, that's information — note it in `docs/stage-2-notes.md` plan-deviations when you write that file later.

- [ ] **Step 5: Commit**

```bash
git add settings/benchmark.settings.json scripts/run-scenario.sh
git commit -m "feat: replace bypassPermissions with explicit allowlist

Narrow headless claude -p to the tools create-log-index actually uses.
Hook wiring lands in Task B6."
```

---

### Task A4: Inject a "no brainstorming" directive via `--append-system-prompt`

**Why:** Stage-1 run 2 had Claude enter a design-discussion mode and ask for approval before acting — something the canned prompt already tried to forbid in user-turn prose ("Do NOT enter brainstorming mode..."), but user prompts don't carry the same weight as system prompts. Moving the directive into `--append-system-prompt` puts it in the right layer of the context hierarchy.

**Files:**
- Modify: `scripts/run-scenario.sh` — add `--append-system-prompt "<directive>"` to the `claude -p` invocation.

- [ ] **Step 1: Choose the directive text**

Keep it short and declarative:

```
You are running inside an automated benchmark harness. Do not enter brainstorming, design-review, or planning modes. Do not ask the operator for approval on design decisions — the skill body IS the approved design. Execute golden paths end-to-end. If a referenced skill or tool is unavailable, halt with a clear error; do not substitute an alternative.
```

- [ ] **Step 2: Add the flag to the runner**

Add a shell variable near the top of the real-run section and pass it via `--append-system-prompt`:

```bash
BENCH_SYSTEM_PROMPT='You are running inside an automated benchmark harness. Do not enter brainstorming, design-review, or planning modes. Do not ask the operator for approval on design decisions — the skill body IS the approved design. Execute golden paths end-to-end. If a referenced skill or tool is unavailable, halt with a clear error; do not substitute an alternative.'

# ... in the claude invocation:
claude -p \
  --settings "$REPO_ROOT/settings/benchmark.settings.json" \
  --append-system-prompt "$BENCH_SYSTEM_PROMPT" \
  "$PROMPT" > "$SESSION_DIR/session.out" 2> "$SESSION_DIR/session.err" || { ... }
```

- [ ] **Step 3: Smoke-run once**

```bash
./scripts/run-scenario.sh create-log-index local-hit
```

Expected: pass. No behavior change from A3 baseline except the system prompt is richer.

- [ ] **Step 4: Commit**

```bash
git add scripts/run-scenario.sh
git commit -m "feat: append no-brainstorming directive to system prompt

Move the 'execute end-to-end, do not ask for approval' directive from
the user prompt into --append-system-prompt so it carries system-level
weight. Addresses stage-1 run 2 mode-confusion."
```

---

### Task A4.5: Fix local-plugin enrollment (added mid-execution)

**Why this task exists (plan deviation):** A4's stricter system prompt ("If a referenced skill or tool is unavailable, halt") surfaced a Stage-1-era latent bug: the fixture plugin is not actually loaded by `claude -p`. The previous `scripts/setup-plugin.sh` did `cp -R fixtures/claude-plugin-observability ~/.claude/plugins/observability-fixture/` — but Claude Code does not auto-discover plugins from arbitrary directories. It loads only plugins enrolled in `~/.claude/plugins/installed_plugins.json` (or in a project's `.claude/settings.json`), with `installPath` typically under `~/.claude/plugins/cache/<marketplace>/<name>/<version>/`. The result: A3's "successful" smoke run was actually the agent improvising — `cd`'d into the fixture repo, it read `agent/golden-paths/create-log-index/steps.md` directly off disk and followed the prose, never invoking the plugin. The assertion script (which checks artifacts, not invocation path) couldn't tell the difference. Stage 1's "one successful end-to-end run on record" was very likely the same improvisation. **Until this is fixed, the entire architecture validation is compromised** — Stage 2's measurement matrix would benchmark improvisation cost, not architecture cost.

**Canonical fix (per Claude Code docs):** Add a project-root local marketplace and use `claude plugin marketplace add` + `claude plugin install` with `--scope project`.

**Files:**
- Create: `.claude-plugin/marketplace.json` at project root (committed to repo).
- Rewrite: `scripts/setup-plugin.sh` to use the marketplace + install commands instead of `cp -R`.
- Possibly create or modify: `.claude/settings.json` at project root (the `--scope project` flag writes here; if so, decide whether to commit or gitignore).

- [ ] **Step 1: Create the marketplace file**

`/.claude-plugin/marketplace.json` (project root, NOT inside the fixture):

```json
{
  "name": "native-agent-observability-local",
  "owner": { "name": "native-agent-orchestration" },
  "plugins": [
    {
      "name": "observability",
      "source": "./fixtures/claude-plugin-observability",
      "description": "PoC fixture plugin: skills for Datadog observability golden paths"
    }
  ]
}
```

The `source` path is relative to the marketplace root (project root). Marketplace name is arbitrary but must be unique on the user's machine.

- [ ] **Step 2: Rewrite `scripts/setup-plugin.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Enroll the fixture plugin via the project-local marketplace at .claude-plugin/.
# Idempotent: re-running adds nothing if the marketplace is already registered
# and the plugin is already installed.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_DIR="$REPO_ROOT/.claude-plugin"
MARKETPLACE_NAME="native-agent-observability-local"
PLUGIN_NAME="observability"

[ -f "$MARKETPLACE_DIR/marketplace.json" ] || {
  echo "ERROR: marketplace file not found at $MARKETPLACE_DIR/marketplace.json" >&2
  exit 1
}

claude plugin marketplace add "$MARKETPLACE_DIR" --scope project
claude plugin install "$PLUGIN_NAME@$MARKETPLACE_NAME" --scope project

echo "Installed fixture plugin '$PLUGIN_NAME' from local marketplace '$MARKETPLACE_NAME'"
echo "Verify: claude plugin list"
```

If either `claude plugin marketplace add` or `claude plugin install` is non-idempotent (errors when already-registered/installed), wrap each call in an idempotency check (e.g., `claude plugin list | grep -q ...` first, or `... || true` if errors are benign duplicates).

- [ ] **Step 3: Run setup-plugin.sh and verify**

```bash
./scripts/setup-plugin.sh
claude plugin list
```

Expected: `claude plugin list` shows `observability@native-agent-observability-local` enabled. If it doesn't, inspect the project's `.claude/settings.json` (which `--scope project` writes to) and the user's `~/.claude/plugins/installed_plugins.json` to see what landed where.

- [ ] **Step 4: Decide on `.claude/settings.json` git-tracking**

If `--scope project` created `.claude/settings.json` in the worktree, decide:
- **Commit it** — if its content is just the marketplace + plugin enrollment (no user secrets, no machine-specific paths). This makes the plugin auto-load for any developer who clones the repo and runs `setup-plugin.sh` (they only need to run setup once).
- **Gitignore it** — if it picked up local paths or settings that shouldn't be shared.

Inspect `cat .claude/settings.json` and choose. Add to `.gitignore` if needed; otherwise add to commit.

- [ ] **Step 5: Smoke-run the scenario**

```bash
./scripts/run-scenario.sh create-log-index local-hit
```

Expected: scenario passes WITHOUT the agent improvising. Verify by inspecting the session output:

```bash
# The session dir is printed by the runner; look at session.out
cat <session_dir>/session.out
```

Expected language in the output: explicit reference to invoking the `observability:create-log-index` skill (NOT just "I read steps.md and followed it"). If the agent says anything like "the skill isn't available, but I followed the golden path content directly," that's still improvisation — STOP and report BLOCKED.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/marketplace.json scripts/setup-plugin.sh
# Optionally: git add .claude/settings.json    (if Step 4 chose to commit)
# OR:        git add .gitignore                (if Step 4 chose to gitignore)
git commit -m "fix: enroll fixture plugin via local marketplace

A3's smoke and Stage-1's '1/3 pass' were both improvisation, not
plugin-driven discovery. Claude Code only loads plugins registered
via marketplace + install commands; cp -R into ~/.claude/plugins/
is not enough. Add a project-root marketplace.json and rewrite
setup-plugin.sh to use claude plugin marketplace add + install."
```

**Risk to flag for Task D2 (stage-2-notes):** The original Stage-1 "validation" was on a false premise. The architecture's plugin-driven discovery has never been end-to-end-verified in this repo until Task A4.5 lands. This raises the priority of A5's stability run as the FIRST true validation.

---

### Task A5: Stability verification — 5 consecutive runs

**Why:** A1–A4 are each individually cheap, but the *combined* claim — "hardening fixed the non-determinism" — is only answerable by running the scenario multiple times and counting failures. This is the Part-A exit criterion.

**Files:** none (verification only).

- [ ] **Step 1: Run the scenario 5 times back-to-back (exit-code-tracked)**

```bash
PASSES=0
FAILS=0
for i in 1 2 3 4 5; do
  echo "=== run $i ==="
  if ./scripts/run-scenario.sh create-log-index local-hit; then
    PASSES=$((PASSES + 1))
    echo "=== run $i: PASS ==="
  else
    FAILS=$((FAILS + 1))
    echo "=== run $i: FAIL ==="
  fi
done 2>&1 | tee /tmp/stage-2-a5.log
echo "Summary: passes=$PASSES fails=$FAILS"
```

Exit-code-based tracking avoids depending on any particular success-string in the runner's stdout.

- [ ] **Step 2: Read the summary line**

The last line printed in Step 1 is `Summary: passes=<N> fails=<M>`. Record both numbers for the Stage-2 notes in Task D2.

**Exit criterion: at least 4 of 5 pass.** Ideally 5/5, but LLM non-determinism is acknowledged in the spec; 4/5 is the minimum bar for "hardening worked." If 3 or fewer pass, the hardening is insufficient — do NOT proceed to Part B. Instead:
1. Inspect the failing-run session output under `/tmp`.
2. Identify which of A1–A4 didn't land or needs more pressure (e.g. the append-system-prompt wasn't strong enough; the allowlist was missing a pattern).
3. Add a targeted fix as Task A6 and re-run Step 1.

- [ ] **Step 3: If passing, record the run count in the upcoming `docs/stage-2-notes.md`**

No commit for this task (no file changes). Just capture the pass rate for the Stage-2 handoff notes that you'll write in Task E1.

---

# Part B — Metric-capture hook

### Task B1: Confirm the Claude Code hook event

**Why:** Spec §15 flagged `Stop` as the candidate. `Stop` fires once per user-turn completion, which is per-turn cadence. But per-turn *token metadata* may land in a different event (e.g., `PostToolUse`, `SessionEnd`). We need to confirm the event that actually carries `tokens_in`, `tokens_out`, `cache_read`, `cache_creation`, and `duration_ms` before implementing the hook body.

**Files:** none yet — research task. Output is a written decision recorded inline in the next task's hook file.

- [ ] **Step 1: Query the Claude Code hook reference**

Dispatch the `claude-code-guide` agent (or consult the Claude Code docs directly) with:

> "I need to write a Claude Code hook that captures per-turn token usage. Specifically: tokens_in, tokens_out, cache_read, cache_creation, duration_ms, and the currently active skill name. Which hook event delivers this data in its payload? Prefer events that fire once per turn without firing per-tool-call. Confirm the JSON path to each field in the hook stdin payload."

- [ ] **Step 2: Record the decision**

Write a one-paragraph decision note at the top of `hooks/metric-capture.sh` (the file you'll create in Task B3). Include:
- The hook event name (e.g., `Stop`, `PostToolUse`).
- Why that event was chosen over alternatives.
- The JSON path to each token field (`.response.usage.input_tokens`, etc.).
- Any gotchas (e.g., "`cache_read` is 0 on uncached turns rather than absent").

- [ ] **Step 3: Capture a real payload for the fixture**

Temporarily wire a stub hook that writes `$INPUT` to a file, run one scenario invocation, then inspect the captured payload:

```bash
cat > /tmp/hook-capture.sh <<'EOF'
#!/usr/bin/env bash
cat > "/tmp/hook-payload-$(date +%s%N).json"
EOF
chmod +x /tmp/hook-capture.sh
```

Add a temporary hook entry to `settings/benchmark.settings.json` pointing at `/tmp/hook-capture.sh` for the event chosen in Step 1, run the scenario once, then `cat /tmp/hook-payload-*.json | jq .` to inspect. Pick one representative payload and save it as `tests/fixtures/metric-hook-payload.json`.

- [ ] **Step 4: Revert the temporary hook wiring and verify**

```bash
git diff settings/benchmark.settings.json
```

Expected: no diff (or only the already-intended A3/B4 edits — no `/tmp/hook-capture.sh` reference). If the temp entry is still there, remove it now. Verifying via `git diff` rather than relying on manual revert prevents the "forgot to undo the stub" bug.

(No commit yet — this task's output is the recorded decision and the saved fixture, both consumed by B2/B3.)

---

### Task B2: Write failing test for `hooks/metric-capture.sh`

**Files:**
- Create: `tests/test_metric_hook.bats`
- Use: `tests/fixtures/metric-hook-payload.json` (from B1), and a second fixture you'll create below

- [ ] **Step 1: Create the second fixture (missing-tokens payload)**

Copy `tests/fixtures/metric-hook-payload.json` to `tests/fixtures/metric-hook-payload-missing-tokens.json` and zero-out or null-out the usage fields. This drives the hook's graceful-degradation path.

- [ ] **Step 2: Write the bats test**

Create `tests/test_metric_hook.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  METRICS_FILE="$(mktemp)"
  export AGENT_ORCH_METRICS_FILE="$METRICS_FILE"
  export AGENT_ORCH_SCENARIO="create-log-index"
  export AGENT_ORCH_VARIANT="local-hit"
  export AGENT_ORCH_RUN_IX="3"
}

teardown() {
  rm -f "$METRICS_FILE"
}

@test "hook appends one JSONL line with token fields from a valid payload" {
  "$REPO_ROOT/hooks/metric-capture.sh" < "$REPO_ROOT/tests/fixtures/metric-hook-payload.json"
  run wc -l < "$METRICS_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run jq -r '.scenario' "$METRICS_FILE"
  [ "$output" = "create-log-index" ]
  run jq -r '.variant' "$METRICS_FILE"
  [ "$output" = "local-hit" ]
  run jq -r '.run_ix' "$METRICS_FILE"
  [ "$output" = "3" ]
  run jq -r '.tokens_in' "$METRICS_FILE"
  [ "$output" != "null" ]
  [ "$output" != "" ]
}

@test "hook tolerates missing token fields without erroring" {
  run "$REPO_ROOT/hooks/metric-capture.sh" < "$REPO_ROOT/tests/fixtures/metric-hook-payload-missing-tokens.json"
  [ "$status" -eq 0 ]
  run jq -r '.tokens_in' "$METRICS_FILE"
  [ "$output" = "0" ] || [ "$output" = "null" ]
}

@test "hook appends; does not overwrite" {
  "$REPO_ROOT/hooks/metric-capture.sh" < "$REPO_ROOT/tests/fixtures/metric-hook-payload.json"
  "$REPO_ROOT/hooks/metric-capture.sh" < "$REPO_ROOT/tests/fixtures/metric-hook-payload.json"
  run wc -l < "$METRICS_FILE"
  [ "$output" = "2" ]
}
```

- [ ] **Step 3: Run the test and confirm it fails**

```bash
.bats/bin/bats tests/test_metric_hook.bats
```

Expected: 3 failures, all with "hooks/metric-capture.sh: No such file or directory" or similar. If any test *passes*, something is wrong — investigate before proceeding.

- [ ] **Step 4: Commit the failing test**

```bash
git add tests/test_metric_hook.bats tests/fixtures/metric-hook-payload*.json
git commit -m "test: failing bats for metric-capture hook

Fixtures captured from a real claude -p run (see B1 decision note);
hook implementation follows in next commit."
```

---

### Task B3: Implement `hooks/metric-capture.sh`

**Files:**
- Create: `hooks/metric-capture.sh`

- [ ] **Step 1: Create the file with the decision note from B1 at the top**

Minimal implementation (adjust the `jq` paths to match the event you confirmed in B1):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Hook: metric-capture
#
# Event: <fill in from B1>
# Why this event: <fill in from B1>
# Payload fields consumed (jq paths):
#   - tokens_in:       .<path>
#   - tokens_out:      .<path>
#   - cache_read:      .<path>
#   - cache_creation:  .<path>
#   - duration_ms:     .<path>
#   - session_id:      .<path>
#   - turn_index:      .<path>
#   - skill_active:    .<path> (may be absent on turns with no active skill)
#
# Output: one JSONL line appended to $AGENT_ORCH_METRICS_FILE (or a derived
# default). Fields not present in the payload are emitted as 0 or null as
# appropriate; the hook must never fail a turn just because a field is missing.

PAYLOAD="$(cat)"

SCENARIO="${AGENT_ORCH_SCENARIO:-untagged}"
VARIANT="${AGENT_ORCH_VARIANT:-untagged}"
RUN_IX="${AGENT_ORCH_RUN_IX:-0}"

# Derive a default metrics file if the runner didn't set one.
if [ -z "${AGENT_ORCH_METRICS_FILE:-}" ]; then
  SID="$(echo "$PAYLOAD" | jq -r '.<session_id_path> // "unknown"')"
  DEFAULT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agent-orch/metrics"
  mkdir -p "$DEFAULT_DIR"
  AGENT_ORCH_METRICS_FILE="$DEFAULT_DIR/$SID.jsonl"
fi

mkdir -p "$(dirname "$AGENT_ORCH_METRICS_FILE")"

echo "$PAYLOAD" | jq -c \
  --arg scenario "$SCENARIO" \
  --arg variant "$VARIANT" \
  --argjson run_ix "$RUN_IX" \
  '{
    ts:             (now | todateiso8601),
    session_id:     (.<session_id_path> // "unknown"),
    scenario:       $scenario,
    variant:        $variant,
    run_ix:         $run_ix,
    turn:           (.<turn_index_path> // 0),
    model:          (.<model_path> // "unknown"),
    tokens_in:      (.<tokens_in_path> // 0),
    tokens_out:     (.<tokens_out_path> // 0),
    cache_read:     (.<cache_read_path> // 0),
    cache_creation: (.<cache_creation_path> // 0),
    duration_ms:    (.<duration_ms_path> // 0),
    skill_active:   (.<skill_active_path> // null)
  }' >> "$AGENT_ORCH_METRICS_FILE"
```

Replace each `<...>_path` placeholder with the concrete `jq` path from B1.

- [ ] **Step 2: Make it executable**

```bash
chmod +x hooks/metric-capture.sh
```

- [ ] **Step 3: Run the test**

```bash
.bats/bin/bats tests/test_metric_hook.bats
```

Expected: 3/3 pass. If a test fails, do NOT mark the task complete — fix the hook (common issues: wrong `jq` path; forgot to `chmod +x`; `jq` output not compact-mode).

- [ ] **Step 4: Commit**

```bash
git add hooks/metric-capture.sh
git commit -m "feat: metric-capture hook emits one JSONL line per turn"
```

---

### Task B4: Register the hook in `settings/benchmark.settings.json`

**Why:** The hook from B3 only runs if Claude Code knows about it. That wiring is configured in the settings file we introduced in A3.

**Files:**
- Modify: `settings/benchmark.settings.json`

- [ ] **Step 1: Add the hook block**

Replace the empty `"hooks": {}` with a registration for the event confirmed in B1. Example for `Stop`:

```json
"hooks": {
  "Stop": [
    { "command": "${CLAUDE_PROJECT_DIR}/hooks/metric-capture.sh" }
  ]
}
```

Use the event key that matches B1's decision. If `${CLAUDE_PROJECT_DIR}` substitution is not supported in the Claude Code version we target, fall back to an absolute path constructed by the runner — but confirm support first via B1.

- [ ] **Step 2: Smoke-run the scenario**

```bash
# Ensure no stale metrics
rm -rf ~/.local/share/agent-orch/metrics/

./scripts/run-scenario.sh create-log-index local-hit
```

Expected: scenario passes AND one JSONL file appears under `~/.local/share/agent-orch/metrics/` with ≥1 line.

- [ ] **Step 3: Inspect the captured metrics**

```bash
ls -la ~/.local/share/agent-orch/metrics/
jq . ~/.local/share/agent-orch/metrics/*.jsonl | head -100
```

Sanity-check: `scenario` field says `untagged` (because the runner doesn't set env vars yet — that's Task B5's job) and `tokens_in` is > 0 for at least some turns.

- [ ] **Step 4: Commit**

```bash
git add settings/benchmark.settings.json
git commit -m "feat: register metric-capture hook in benchmark settings"
```

---

### Task B5: Wire runner env vars + per-run metrics file

**Why:** The hook currently stamps every line as `untagged`. Runner must set scenario/variant/run_ix and point `AGENT_ORCH_METRICS_FILE` at a per-run path so multiple invocations don't all pile into one file.

**Files:**
- Modify: `scripts/run-scenario.sh`
- Modify: `tests/test_runner_contract.bats`

- [ ] **Step 1: Add env-var setup to the runner**

Near the top of the real-run section in `run-scenario.sh`, after `SESSION_DIR=$(mktemp -d)`:

```bash
export AGENT_ORCH_SCENARIO="$SCENARIO"
export AGENT_ORCH_VARIANT="$VARIANT"
export AGENT_ORCH_RUN_IX="${RUN_IX:-0}"
export AGENT_ORCH_SESSION_DIR="$SESSION_DIR"
export AGENT_ORCH_METRICS_FILE="$SESSION_DIR/metrics.jsonl"
```

The runner accepts `RUN_IX` as an optional env var (not a CLI flag) to keep the CLI surface stable. The benchmark driver in Part C sets it per iteration.

- [ ] **Step 2: Route the handoff file through the session dir**

Change:

```bash
HANDOFF_FILE="$FIXTURE_REPO/.stage-1-handoff.json"
```

to:

```bash
HANDOFF_FILE="$SESSION_DIR/handoff.json"
export AGENT_ORCH_HANDOFF_FILE="$HANDOFF_FILE"
```

- [ ] **Step 2a: Update `pr-handoff/SKILL.md` to honor the env var**

Read the current body of `fixtures/claude-plugin-observability/skills/pr-handoff/SKILL.md` and locate the concrete path it writes to. The current stub writes to a hard-coded path like `$FIXTURE_REPO/.stage-1-handoff.json`. Replace the path-derivation logic with this concrete block (adapt to the surrounding prose; the path line is what matters):

```markdown
## Step 2 — Write the handoff JSON

Determine the output path:

- If the environment variable `AGENT_ORCH_HANDOFF_FILE` is set (benchmark-harness mode), use its value verbatim.
- Otherwise (standalone-run mode), use `$FIXTURE_REPO/.stage-1-handoff.json` where `$FIXTURE_REPO` is the path of the functional repo (same convention as Stage 1).

Use the `Write` tool to write the payload JSON to that path. Do not use the `Bash` tool with `echo` / `cat <<EOF` — the `Write` tool is the correct contract.
```

This concrete before/after matters because Stage 1 showed SKILL.md prose is load-bearing for agent behavior. Prefer naming the mechanism (`Write` tool) over hand-waved "write the file." Commit this SKILL.md change in the same commit as the runner change (Step 6 below) so the env-var contract lands atomically on both sides.

- [ ] **Step 3: Extend `tests/test_runner_contract.bats` with DRY_RUN assertions for the new surface**

Add one test:

```bash
@test "DRY_RUN mode echoes scenario and variant in output" {
  DRY_RUN=1 run "$REPO_ROOT/scripts/run-scenario.sh" create-log-index local-hit
  [ "$status" -eq 0 ]
  [[ "$output" == *"scenario=create-log-index"* ]]
  [[ "$output" == *"variant=local-hit"* ]]
}
```

(The existing DRY_RUN line already prints these, so this is a characterization test to lock the contract.)

- [ ] **Step 4: Run bats**

```bash
.bats/bin/bats tests/
```

Expected: all tests pass.

- [ ] **Step 5: Real scenario smoke with env vars**

```bash
rm -rf /tmp/stage2-metrics
AGENT_ORCH_METRICS_FILE=/tmp/stage2-metrics.jsonl \
  ./scripts/run-scenario.sh create-log-index local-hit

# Inspect: scenario/variant should now be tagged correctly
jq -r '[.scenario, .variant, .run_ix] | @tsv' /tmp/stage2-metrics.jsonl | head -5
```

Expected: each line reads `create-log-index\tlocal-hit\t0`.

Note: the runner's own default (`$SESSION_DIR/metrics.jsonl`) wins when `AGENT_ORCH_METRICS_FILE` is pre-set as an env var on the command line — because the runner `export`s its value *after* that env var is inherited. Verify by leaving the override off:

```bash
./scripts/run-scenario.sh create-log-index local-hit
# Look at the "Session artifacts in: $SESSION_DIR" path; metrics.jsonl should be inside
```

- [ ] **Step 6: Commit**

```bash
git add scripts/run-scenario.sh tests/test_runner_contract.bats \
        fixtures/claude-plugin-observability/skills/pr-handoff/SKILL.md
git commit -m "feat: runner sets scenario/variant/run_ix env + per-run paths

Metrics file and handoff file both live under \$SESSION_DIR so concurrent
benchmark iterations don't clobber each other. AGENT_ORCH_HANDOFF_FILE
env var is the explicit contract with the pr-handoff skill."
```

---

# Part C — Benchmark driver + aggregator

### Task C1: Failing test for `scripts/aggregate-metrics.sh`

**Files:**
- Create: `tests/fixtures/aggregate-sample.jsonl`
- Create: `tests/test_aggregate_metrics.bats`

- [ ] **Step 1: Write the fixture JSONL**

Create `tests/fixtures/aggregate-sample.jsonl` with known token values that produce predictable P50/P95:

```jsonl
{"scenario":"create-log-index","variant":"local-hit","run_ix":1,"turn":1,"tokens_in":1000,"tokens_out":200,"cache_read":800,"cache_creation":0,"duration_ms":1500}
{"scenario":"create-log-index","variant":"local-hit","run_ix":1,"turn":2,"tokens_in":2000,"tokens_out":300,"cache_read":1600,"cache_creation":0,"duration_ms":2000}
{"scenario":"create-log-index","variant":"local-hit","run_ix":2,"turn":1,"tokens_in":1100,"tokens_out":210,"cache_read":850,"cache_creation":0,"duration_ms":1600}
{"scenario":"create-log-index","variant":"local-hit","run_ix":2,"turn":2,"tokens_in":2100,"tokens_out":310,"cache_read":1650,"cache_creation":0,"duration_ms":2100}
{"scenario":"create-log-index","variant":"local-hit","run_ix":3,"turn":1,"tokens_in":1200,"tokens_out":220,"cache_read":900,"cache_creation":0,"duration_ms":1700}
{"scenario":"create-log-index","variant":"local-hit","run_ix":3,"turn":2,"tokens_in":2200,"tokens_out":320,"cache_read":1700,"cache_creation":0,"duration_ms":2200}
{"scenario":"create-log-index","variant":"local-hit","run_ix":4,"turn":1,"tokens_in":1300,"tokens_out":230,"cache_read":950,"cache_creation":0,"duration_ms":1800}
{"scenario":"create-log-index","variant":"local-hit","run_ix":4,"turn":2,"tokens_in":2300,"tokens_out":330,"cache_read":1750,"cache_creation":0,"duration_ms":2300}
{"scenario":"create-log-index","variant":"local-hit","run_ix":5,"turn":1,"tokens_in":1400,"tokens_out":240,"cache_read":1000,"cache_creation":0,"duration_ms":1900}
{"scenario":"create-log-index","variant":"local-hit","run_ix":5,"turn":2,"tokens_in":2400,"tokens_out":340,"cache_read":1800,"cache_creation":0,"duration_ms":2400}
```

Per-run totals (tokens_in + tokens_out):
- run 1: 3500
- run 2: 4410 ... wait, recompute.

Let me compute. Per-run totals:
- run 1: 1000+200+2000+300 = 3500
- run 2: 1100+210+2100+310 = 3720
- run 3: 1200+220+2200+320 = 3940
- run 4: 1300+230+2300+330 = 4160
- run 5: 1400+240+2400+340 = 4380

Sorted: [3500, 3720, 3940, 4160, 4380].
- P50 = 3940 (middle value).
- P95 ≈ 4380 (tail; for N=5 and type-7 interpolation, P95 = value at index 0.95*(N-1) = 3.8, which interpolates between 4160 and 4380 at 0.8 → 4160 + 0.8*(4380-4160) = 4336).

Pick the percentile definition you implement (type-7 interpolation is what `numpy.percentile` default is; simple rank-based is easier in `jq`). **Pin the choice in the decision note at the top of the script** so the test can encode the right expected value.

- [ ] **Step 2: Write the bats test**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  FIXTURE="$REPO_ROOT/tests/fixtures/aggregate-sample.jsonl"
}

@test "aggregate prints one row per (scenario, variant)" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  # Expect exactly one data row for create-log-index / local-hit
  [ "$(echo "$output" | grep -c 'create-log-index.*local-hit')" -eq 1 ]
}

@test "aggregate reports P50 = 3940 for the sample fixture" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"3940"* ]]
}

@test "aggregate reports N=5 runs for the sample fixture" {
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"N=5"* ]] || [[ "$output" == *"| 5 "* ]]
}

@test "aggregate reports cache_ratio ≈ 0.78 for the sample fixture" {
  # Fixture totals: cache_read_sum=13000, tokens_in_sum=16500.
  # Ratio = 13000/16500 ≈ 0.7878. Aggregator truncates to 2 decimal places.
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"0.78"* ]]
}

@test "aggregate reports hot turn = 2 for the sample fixture" {
  # Turn 2 has larger totals than turn 1 in every run; aggregator surfaces the turn index.
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$FIXTURE"
  [[ "$output" == *"hot_turn"* ]]
  # The line summarizing create-log-index / local-hit should name turn 2 as the hot turn.
  HOT_LINE=$(echo "$output" | grep 'create-log-index.*local-hit')
  [[ "$HOT_LINE" == *"| 2 |"* ]] || [[ "$HOT_LINE" == *"turn=2"* ]]
}

@test "aggregate fails on empty input" {
  EMPTY="$(mktemp)"
  run "$REPO_ROOT/scripts/aggregate-metrics.sh" "$EMPTY"
  [ "$status" -ne 0 ]
  rm -f "$EMPTY"
}
```

**Pre-math reference for the implementer:**
- Per-run totals (sorted): [3500, 3720, 3940, 4160, 4380] → P50 = 3940, P95 = 4380 (rank-based, sorted[N-1]).
- `cache_read_sum` (all 10 lines): 800+1600+850+1650+900+1700+950+1750+1000+1800 = **13000**.
- `tokens_in_sum` (all 10 lines): 1000+2000+1100+2100+1200+2200+1300+2300+1400+2400 = **16500**.
- cache_ratio = 13000/16500 ≈ 0.7878 → truncated to **0.78**.
- `hot_turn`: turn 2 is always larger than turn 1 within a run (2000+300 vs 1000+200, etc.) → **2**.

- [ ] **Step 3: Run the test and confirm failure**

```bash
.bats/bin/bats tests/test_aggregate_metrics.bats
```

Expected: 4 failures (no script yet).

- [ ] **Step 4: Commit the failing test**

```bash
git add tests/fixtures/aggregate-sample.jsonl tests/test_aggregate_metrics.bats
git commit -m "test: failing bats for aggregate-metrics"
```

---

### Task C2: Implement `scripts/aggregate-metrics.sh`

**Files:**
- Create: `scripts/aggregate-metrics.sh`

- [ ] **Step 1: Implement**

```bash
#!/usr/bin/env bash
set -euo pipefail

# aggregate-metrics.sh — read one or more JSONL metrics files,
# group by (scenario, variant), compute per-run totals and
# percentiles, emit a markdown summary table to stdout.
#
# Percentile definition: simple rank-based (for N=5, P50 = sorted[2],
# P95 = sorted[4]). Type-7 interpolation is NOT used; PoC-scale N is
# small enough that the rank-based value is adequate and easier to
# reason about.

if [ "$#" -lt 1 ]; then
  echo "usage: aggregate-metrics.sh <metrics.jsonl> [more.jsonl ...]" >&2
  exit 2
fi

for f in "$@"; do
  [ -s "$f" ] || { echo "ERROR: $f is empty or missing" >&2; exit 1; }
done

cat "$@" | jq -s -r '
  group_by([.scenario, .variant])
  | map({
      scenario: .[0].scenario,
      variant:  .[0].variant,
      all_lines: .,
      runs:     (group_by(.run_ix) | map({
        run_ix: .[0].run_ix,
        total:  (map(.tokens_in + .tokens_out) | add),
        cache_read_sum: (map(.cache_read) | add),
        tokens_in_sum:  (map(.tokens_in)  | add)
      })),
    })
  | map(.runs |= sort_by(.total))
  | map({
      scenario: .scenario,
      variant:  .variant,
      n:        (.runs | length),
      p50:      (.runs[.runs | length / 2 | floor].total),
      p95:      (.runs[((.runs | length) - 1)].total),
      cache_ratio: (
        ([.runs[].cache_read_sum] | add) /
        ([.runs[].tokens_in_sum]  | add | if . == 0 then 1 else . end)
      ),
      hot_turn: (
        .all_lines
        | group_by(.turn)
        | map({ turn: .[0].turn, total: (map(.tokens_in + .tokens_out) | add) })
        | max_by(.total)
        | .turn
      )
    })
  | "| scenario | variant | N | P50 | P95 | cache_ratio | hot_turn |",
    "|---|---|---|---|---|---|---|",
    (.[] | "| \(.scenario) | \(.variant) | N=\(.n) | \(.p50) | \(.p95) | \(.cache_ratio | . * 100 | floor / 100) | \(.hot_turn) |")
'
```

Per spec §11.6 the aggregator surfaces: per-scenario total (via P50/P95), per-scenario variance (P50 vs P95 spread), variant delta (rows grouped by variant), cache effectiveness (cache_ratio), and hot-spot turns (hot_turn). Baseline cost is a *matrix-row* concern (add a `baseline` row when doc 4 lands); the aggregator itself needs no change.

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/aggregate-metrics.sh
```

- [ ] **Step 3: Run tests**

```bash
.bats/bin/bats tests/test_aggregate_metrics.bats
```

Expected: 4/4 pass. If a percentile assertion fails, the rank-based formula may be off-by-one — check against the computed values from C1 Step 1.

- [ ] **Step 4: Commit**

```bash
git add scripts/aggregate-metrics.sh
git commit -m "feat: aggregate-metrics emits P50/P95 markdown table"
```

---

### Task C3: Failing test for `scripts/run-benchmarks.sh`

**Why:** The driver iterates a matrix and calls `run-scenario.sh`. We want a bats test for the CLI contract (flags, DRY_RUN) — the "does it actually run the scenario correctly" check happens at the smoke-run in Task C5.

**Files:**
- Create: `scripts/matrix/stage-2-initial.tsv`
- Create/modify: `tests/test_runner_contract.bats` (adding benchmark-driver CLI assertions) OR a new `tests/test_benchmarks_contract.bats`

- [ ] **Step 1: Create the matrix file**

`scripts/matrix/stage-2-initial.tsv`:

```tsv
scenario	variant	n
create-log-index	local-hit	5
```

Header line + one data row. Stage 3 adds rows.

- [ ] **Step 2: Write the bats test**

Add a new file `tests/test_benchmarks_contract.bats`:

```bash
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
  # Should echo 5 planned invocations for the single matrix row (N=5)
  [ "$(echo "$output" | grep -c 'scenario=create-log-index')" -eq 5 ]
}

@test "run-benchmarks honors --n override" {
  DRY_RUN=1 run "$REPO_ROOT/scripts/run-benchmarks.sh" \
    --matrix "$REPO_ROOT/scripts/matrix/stage-2-initial.tsv" \
    --n 2
  [ "$(echo "$output" | grep -c 'scenario=create-log-index')" -eq 2 ]
}
```

- [ ] **Step 3: Run the test and confirm failure**

```bash
.bats/bin/bats tests/test_benchmarks_contract.bats
```

Expected: 3 failures.

- [ ] **Step 4: Commit**

```bash
git add scripts/matrix/stage-2-initial.tsv tests/test_benchmarks_contract.bats
git commit -m "test: failing bats for run-benchmarks CLI contract"
```

---

### Task C4: Implement `scripts/run-benchmarks.sh`

**Files:**
- Create: `scripts/run-benchmarks.sh`

- [ ] **Step 1: Implement**

```bash
#!/usr/bin/env bash
set -euo pipefail

# run-benchmarks.sh — iterate the matrix TSV, for each (scenario, variant, n)
# invoke run-scenario.sh n times in fresh sessions, collect metrics paths,
# and print the aggregate summary at the end.
#
# Each iteration inherits AGENT_ORCH_RUN_IX from the driver; the runner
# places its per-run metrics under $SESSION_DIR, which the driver captures
# so aggregate-metrics.sh can read all N files.

usage() {
  cat >&2 <<EOF
usage: run-benchmarks.sh --matrix <path.tsv> [--n <override>] [--out <dir>]
  --matrix  TSV file with columns: scenario, variant, n (header line required)
  --n       Override the per-row N (useful for smoke runs)
  --out     Directory to collect per-run metrics (default: auto mktemp)
EOF
  exit 2
}

MATRIX=""
N_OVERRIDE=""
OUT_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --matrix) MATRIX="$2"; shift 2 ;;
    --n)      N_OVERRIDE="$2"; shift 2 ;;
    --out)    OUT_DIR="$2"; shift 2 ;;
    *)        echo "unknown flag: $1" >&2; usage ;;
  esac
done

[ -n "$MATRIX" ] || usage
[ -f "$MATRIX" ] || { echo "ERROR: matrix file not found: $MATRIX" >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel)"
: "${OUT_DIR:=$(mktemp -d -t agent-orch-bench-XXXX)}"
mkdir -p "$OUT_DIR"

# Skip header line; iterate data rows.
tail -n +2 "$MATRIX" | while IFS=$'\t' read -r SCENARIO VARIANT N; do
  [ -n "$SCENARIO" ] || continue
  N="${N_OVERRIDE:-$N}"
  for i in $(seq 1 "$N"); do
    if [ "${DRY_RUN:-0}" = "1" ]; then
      echo "DRY_RUN: would run scenario=$SCENARIO variant=$VARIANT run_ix=$i"
      continue
    fi
    echo "[bench] scenario=$SCENARIO variant=$VARIANT run_ix=$i"
    export RUN_IX="$i"
    METRICS_PATH="$OUT_DIR/$SCENARIO-$VARIANT-$i.jsonl"
    export AGENT_ORCH_METRICS_FILE="$METRICS_PATH"
    "$REPO_ROOT/scripts/run-scenario.sh" "$SCENARIO" "$VARIANT" \
      > "$OUT_DIR/$SCENARIO-$VARIANT-$i.stdout" \
      2> "$OUT_DIR/$SCENARIO-$VARIANT-$i.stderr" \
      || echo "[bench] RUN FAILED: $SCENARIO / $VARIANT / $i (continuing)"
    unset RUN_IX AGENT_ORCH_METRICS_FILE
  done
done

if [ "${DRY_RUN:-0}" = "1" ]; then
  exit 0
fi

echo ""
echo "[bench] all runs complete. Metrics in: $OUT_DIR"
echo ""
"$REPO_ROOT/scripts/aggregate-metrics.sh" "$OUT_DIR"/*.jsonl
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/run-benchmarks.sh
```

- [ ] **Step 3: Run tests**

```bash
.bats/bin/bats tests/test_benchmarks_contract.bats
```

Expected: 3/3 pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/run-benchmarks.sh
git commit -m "feat: run-benchmarks iterates matrix; feeds aggregate-metrics"
```

---

### Task C5: End-to-end smoke — run the matrix at N=2

**Why:** C1–C4 tests exercise CLI contract and math on fixtures, but the full pipe (runner → hook → JSONL → aggregator) only gets exercised for real here. N=2 is enough to surface wiring bugs without burning the full N=5 budget.

**Files:** none (smoke run).

- [ ] **Step 1: Run the matrix at N=2**

```bash
./scripts/run-benchmarks.sh --matrix scripts/matrix/stage-2-initial.tsv --n 2 \
  | tee /tmp/stage-2-smoke.log
```

- [ ] **Step 2: Verify the summary table appeared**

Expected: final stdout includes a markdown table with one row for `create-log-index / local-hit` and `N=2`.

- [ ] **Step 3: Verify per-run metrics files exist and are non-empty**

```bash
# The OUT_DIR path is at the top of the bench log; grep it out.
OUT_DIR=$(grep -oE '/tmp/agent-orch-bench-[A-Za-z0-9]+' /tmp/stage-2-smoke.log | head -1)
ls -la "$OUT_DIR"/*.jsonl
wc -l "$OUT_DIR"/*.jsonl
```

Expected: two `.jsonl` files, each with ≥3 lines (turns per scenario run).

- [ ] **Step 4: If Step 3 shows zero-length metrics, debug the hook wiring**

Diagnostic ladder:
1. Did `settings/benchmark.settings.json` get passed to `claude -p`? (Check the runner.)
2. Does the registered event name in the settings file match what B1 confirmed?
3. Does `hooks/metric-capture.sh` have the execute bit?
4. Does `AGENT_ORCH_METRICS_FILE` actually reach the hook? (Temporarily add `echo "METRICS_FILE=$AGENT_ORCH_METRICS_FILE" >&2` near the top of the hook and re-run.)

No commit — this is verification only.

---

# Part D — Calibration pass + Stage-3 handoff

### Task D1: Full N=5 pass on `create-log-index / local-hit`

**Files:** none (data collection).

- [ ] **Step 1: Run the matrix at N=5 (full)**

```bash
./scripts/run-benchmarks.sh --matrix scripts/matrix/stage-2-initial.tsv \
  | tee /tmp/stage-2-d1.log
```

This takes real money and real time (5 fresh Claude sessions). Budget ~5–15 minutes depending on model speed.

- [ ] **Step 2: Capture the summary table and the OUT_DIR path**

Save the bottom of the log — the markdown table — somewhere you'll paste into `docs/stage-2-notes.md` in Task E1.

- [ ] **Step 3: Record the run's pass rate**

```bash
grep -c "RUN FAILED" /tmp/stage-2-d1.log
```

Expected: 0 (or ≤1). Non-zero means hardening has regressed since Part A; investigate before claiming Stage 2 done.

- [ ] **Step 4: Calculate the proposed token-budget tolerance**

Per spec §13.3 passing criteria: "Token usage falls within the scenario's declared budget."

Proposed heuristic: `budget = ceil(P95 * 1.20)`. The 20% margin accounts for LLM variability run-to-run; the P95 (not mean) accounts for the long-tail runs that the mean would hide.

Record both the measured P95 and the proposed budget in `docs/stage-2-notes.md`. Stage 3's assertion script will consume this value.

---

### Task D2: Write `docs/stage-2-notes.md`

**Files:**
- Create: `docs/stage-2-notes.md`

- [ ] **Step 1: Draft the notes**

Structure mirrors `docs/stage-1-notes.md`:

```markdown
# Stage 2 Notes — handoff to Stage 3

## What Stage 2 built

- Hardened `create-log-index` scenario: explicit Skill-tool handoff, forbidden fallbacks, narrow allowlist, no-brainstorming system directive. Pass rate: <fill from A5 and D1>.
- Claude Code hook `hooks/metric-capture.sh` emitting JSONL per turn.
- Benchmark settings `settings/benchmark.settings.json` with hook wiring and tool allowlist.
- Runner extensions: per-run session dir, per-run metrics path, per-run handoff path, env-var tagging.
- Matrix driver `scripts/run-benchmarks.sh` and aggregator `scripts/aggregate-metrics.sh`.
- First calibration pass: create-log-index / local-hit, N=5.

## Measurement summary

<paste the markdown table from D1 Step 2>

Proposed token-budget tolerance for Stage 3 assertions: **<P95 * 1.20>** tokens per invocation.

## Plan deviations worth recording

<capture any deviations from this plan during execution>

## Carry-forward risks

- **Still only one scenario, one variant.** The `remote-fallback` and `cwd-shortcut` variants need fixtures; additional scenarios (create-monitor, etc.) need doc 4.
- **Percentile formula is rank-based, not interpolated.** Fine for N=5; revisit if Stage 3 grows N.
- **Hook event confirmed only on this version of Claude Code.** Pin the version in `docs/` if Stage 3 hits hook-payload-shape drift.
- **`shellcheck` not yet in CI.** Stage-1 carry-forward risk persists into Stage 2.
- **pr-handoff is still a stub** — writes JSON, doesn't open a real PR.

## Decisions recorded

- Hook event: <from B1>
- Percentile definition: rank-based (P50 = sorted[N/2], P95 = sorted[N-1] for N=5)
- Tolerance heuristic: 1.20 × P95 (§13.3 budget)

## Open decisions for Stage 3

- Scenario list (from doc 4) — which additional scenarios land first.
- Whether to grow N beyond 5 for tighter P95 confidence.
- Whether to add a deterministic-fallback check for runs that fail the scenario contract (currently the aggregator treats failed runs as missing data, which understates P95).
```

- [ ] **Step 2: Commit**

```bash
git add docs/stage-2-notes.md
git commit -m "docs: stage-2 handoff notes for Stage 3

Includes first calibration pass P50/P95, proposed token-budget
tolerance, and carry-forward risks."
```

---

# Execution wrap-up

### Task E1: Final verification sweep

- [ ] **Step 1: Full bats suite**

```bash
.bats/bin/bats tests/
```

Expected: all tests pass (runner-contract + metric-hook + aggregate-metrics + benchmarks-contract).

- [ ] **Step 2: One standalone scenario run (no benchmark wrapper)**

```bash
./scripts/run-scenario.sh create-log-index local-hit
```

Expected: pass. Confirms the runner still works outside the matrix.

- [ ] **Step 3: `git status` is clean, `git log` shows expected commit series**

```bash
git status
git log --oneline $(git merge-base HEAD main)..HEAD
```

Expected: clean tree; ~10–15 commits on the Stage-2 branch.

---

### Task E2: Open PR #2

- [ ] **Step 1: Push the branch and open the PR**

```bash
git push -u origin stage-2-measurement-harness
gh pr create --title "Stage 2: scenario hardening + measurement harness" \
  --body "$(cat <<'EOF'
## Summary
- Hardens the create-log-index scenario so re-runs succeed deterministically (renamed pr-handoff, explicit Skill-tool invocation, narrow tool allowlist, no-brainstorming system prompt).
- Adds the §11 measurement harness: Claude Code hook emitting JSONL per turn, runner env-var tagging, matrix driver, P50/P95 aggregator.
- Calibration pass on create-log-index / local-hit at N=5. Proposed token-budget tolerance recorded in docs/stage-2-notes.md for Stage 3.

## Test plan
- [x] `bats tests/` all green
- [x] Standalone run of `scripts/run-scenario.sh create-log-index local-hit` passes
- [x] `scripts/run-benchmarks.sh --n 5` produces a non-empty markdown summary
- [x] 5-consecutive-runs stability check (Task A5) at ≥4/5 pass

## Out of scope (Stage 3)
- Additional scenarios (doc 4)
- Real PR authoring from pr-handoff
- shellcheck in CI
EOF
)"
```

---

## Plan Review Loop

After plan is saved: dispatch plan-document-reviewer with this plan path and the spec path. If the reviewer flags issues, fix them, re-review. Iterate up to 3 times before escalating to the user.

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-04-24-core-architecture-stage-2.md`. After review passes, offer:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review.
2. **Inline Execution** — batch execution with checkpoints.
