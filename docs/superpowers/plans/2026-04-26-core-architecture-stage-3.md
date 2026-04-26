# Stage 3 Implementation Plan: Externalize Fixtures and Complete the Matrix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the in-tree fixture content (`fixtures/datadog-operations/` and `fixtures/claude-plugin-observability/`) into real, separately versioned GitHub repos so the architecture's GitHub-API retrieval boundary is actually exercised; then expand the measurement matrix from 1 row to 5 per [doc 4 §6](../../reference-scenarios.md#6-the-matrix), authoring `create-monitor` content as the second scenario; lock per-row token budgets and write Stage 3 handoff notes.

**Architecture:** Three phases. **Phase A** externalizes the two fixture trees into standalone GitHub repos under `Moonchopper/`, points the project's marketplace.json at the remote plugin repo, refactors `run-scenario.sh` to clone the functional repo per-variant (always for `local-hit`/`cwd-shortcut`, **deliberately not** for `remote-fallback`), updates [doc 4 §4](../../reference-scenarios.md#4-fixture-state--what-each-variant-needs) wording, and re-validates `create-log-index/local-hit` against the new layout to lock a fresh budget. **Phase B** adds the `cwd-shortcut`, `remote-fallback`, `baseline`, and `create-monitor/local-hit` matrix rows, authoring new fixture content in the now-external `Moonchopper/datadog-operations` and `Moonchopper/claude-plugin-observability` repos. **Phase C** runs the full matrix end-to-end, locks the per-row budgets, writes `docs/stage-3-notes.md`.

**Tech Stack:** bash (`set -euo pipefail`), `jq`, bats-core (vendored under `.bats/`), Claude Code `claude -p` headless, `claude plugin marketplace add`, `gh` CLI, `terraform` CLI, GitHub.

**Precedents:**
- Spec: [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](../specs/2026-04-23-core-architecture-design.md) — §9 (detection ladder), §11 (measurement), §13 (passing criteria).
- Doc 4: [`docs/reference-scenarios.md`](../../reference-scenarios.md) — §3 (variants), §5 (the three scenarios), §6 (the matrix), §7 (budget assertions), §9 (open decisions resolved here).
- Stage-2 handoff: [`docs/stage-2-notes.md`](../../stage-2-notes.md) — "Open decisions for Stage 3" and "Carry-forward risks for Stage 3."

**Out of scope (deferred):**
- **Real `pr-handoff` implementation** (still writes JSON; an actual `gh pr create` flow is its own track per stage-2-notes §"Open decisions").
- **`add-apm-service`** scenario (per doc 4 §8).
- **`shellcheck` in CI** (Stage-1 carry-forward risk; nice-to-have).
- **Network-availability mitigations.** If `gh api` fails because the network is down, the user couldn't have opened a PR by hand either; the agent's failure mode there is the same as the human's. No caching, no retries, no offline mode.
- **Versioning / pinning** of plugin or functional repo (architecture spec §15 future concern).

**Vocabulary note — "real" vs "deployable":** when this plan says the `datadog-operations` repo is "now real" or "real GitHub-hosted," it means *the repo is a real GitHub-hosted git repository the agent retrieves content from*. It does **not** mean *the Terraform inside it is a deployable Datadog configuration*. The `terraform/` tree, `example.tf`, and any drafted artifacts remain fixture content. `terraform validate` may or may not pass depending on Datadog provider availability; that's a separate axis we are not testing. The agent's terminus is still PR per architecture spec §3 — nothing in this Stage 3 changes that.

---

## File Structure

### Repos — created (outside this repo)

- **`Moonchopper/datadog-operations`** (new public GitHub repo) — receives the contents of `fixtures/datadog-operations/` plus a top-level `README.md` explaining its fixture purpose. Stage 3 also adds new content here for `create-monitor`.
- **`Moonchopper/claude-plugin-observability`** (new public GitHub repo) — receives the contents of `fixtures/claude-plugin-observability/` plus a top-level `README.md` explaining its fixture purpose. Stage 3 also adds a new `create-monitor/SKILL.md` here.

### In this repo — modify

- `.claude-plugin/marketplace.json` — change the plugin's `source` field from a relative path (`./fixtures/claude-plugin-observability`) to point at the remote GitHub plugin repo. Exact source-field syntax is verified in Task A1.
- `scripts/setup-plugin.sh` — adapt to the new marketplace.json source; preserve the post-install verification.
- `scripts/run-scenario.sh` — split per-variant fixture-state setup into a helper section before `claude -p`. Three variants: `local-hit` (clone functional repo to a conventional path; CWD = run scratch dir, **not** the clone), `cwd-shortcut` (clone functional repo; CWD = the clone), `remote-fallback` (no clone, ensure none exists at conventional paths). Plus per-variant `FIXTURE_REPO` derivation for the assertion script.
- `scripts/assertions/create-log-index-local-hit.sh` — accept the new clone-path-based `FIXTURE_REPO` (was: in-tree fixture path).
- `tests/test_runner_contract.bats` — extend with: variant-specific dry-run output assertions, fixture-state preflight assertions.
- `docs/reference-scenarios.md` — update §4 wording to reflect real GitHub repos (was: in-tree paths). Small (~10-line) edit.

### In this repo — create

- `scripts/lib/clone-or-detect.sh` — small shared helper invoked by `run-scenario.sh` to handle per-variant fixture-repo state. Stays inline if it's <30 lines after first draft; promoted to a file only if multiple consumers emerge.
- `scripts/assertions/create-log-index-cwd-shortcut.sh` — assertion script for the `cwd-shortcut` variant. Same artifact assertions as `local-hit`, plus a transcript assertion that detection-ladder steps 2–4 did not run.
- `scripts/assertions/create-log-index-remote-fallback.sh` — assertion script for `remote-fallback`. Same artifact assertions, plus: clone exists post-run, `gh auth status` invoked before any clone, drafted paths are relative to the cloned working tree.
- `scripts/assertions/create-monitor-local-hit.sh` — assertion script for `create-monitor/local-hit`. Asserts `terraform/monitors/foobar-api-error-rate.tf` exists, contains a `datadog_monitor` resource, override rationale appears in PR body.
- `scripts/assertions/baseline-baseline.sh` — assertion script for the off-topic baseline. Asserts no `Skill(observability:*)` invocation in transcript.
- `scripts/matrix/poc-full.tsv` — TSV with all five matrix rows (replaces `stage-2-initial.tsv` as the canonical matrix; `stage-2-initial.tsv` is preserved unchanged for historical reproducibility).
- `tests/fixtures/transcript-no-skill.jsonl` — canned transcript fragment for the baseline assertion test.
- `tests/test_assertions_baseline.bats` — bats coverage for the baseline assertion script (deterministic transcript-grep behavior).
- `docs/stage-3-notes.md` — handoff: what Stage 3 built, full-matrix measurement summary, plan deviations, decisions deferred, carry-forward risks for any post-Stage-3 work.

### In this repo — delete (Phase A's last step)

- `fixtures/datadog-operations/` — content has moved to the remote repo.
- `fixtures/claude-plugin-observability/` — content has moved to the remote repo.
- `fixtures/` directory itself, if it ends up empty.

---

## Why this ordering

Phase A is foundational because every Stage 3 measurement is invalidated until the fixture extraction is done. Running new variants against in-tree fixtures and *then* re-running them against extracted repos would burn budget twice and produce two non-comparable numbers per row. Extract first, lock the new `local-hit` baseline, then expand.

Within Phase A, repo creation (A2, A3) precedes marketplace/runner changes (A4–A6) because the new install path needs a real remote to point at. The doc-4 wording update (A7) is intentionally low in the order — it's a follow-the-implementation correction, easy to slot in once A2–A6 have made the new repo paths concrete. Re-validation (A8) is the gate before deletion (A9): we don't delete the in-tree fixtures until the runner is proven to work without them.

Phase B's task order is `cwd-shortcut → remote-fallback → create-monitor → baseline`. Rationale:
- `cwd-shortcut` is the smallest delta from `local-hit` (one CWD difference); proves the variant infrastructure works with minimal new surface.
- `remote-fallback` reuses the variant infrastructure but adds the deliberate-no-clone preflight, the offer-to-clone interaction in the prompt, and the gh-auth assertion.
- `create-monitor` is the largest single chunk of work (new fixture content + new skill + new best-practice file with a deliberate override case); doing it after the variant work means runner+assertion patterns are settled before adding scenario complexity.
- `baseline` is trivial relative to the others; landing it last keeps Phase B's last commit small and reviewable.

Phase C is the final integration pass. Locking budgets only after all rows have been measured at least once avoids re-deriving budgets if a Phase B task accidentally affects an earlier row.

---

# Phase A — Externalize Fixtures

### Task A1: Verify the marketplace.json source-field syntax for a remote GitHub plugin repo

**Why:** Today's `.claude-plugin/marketplace.json` uses `"source": "./fixtures/claude-plugin-observability"` — a relative directory path. To point at a remote GitHub repo, the field needs a different value. The exact syntax (string vs object, `github:org/repo` shorthand vs `{type, url}` object, etc.) is documented in Claude Code's plugin documentation and may differ across CLI versions. This task resolves it before A4 commits to a specific shape.

**Files:** none modified; this is a diagnostic step. Output is a short note in this plan (or in stage-3-notes.md once Phase A is committed) recording the working syntax.

- [ ] **Step 1: Read Claude Code's plugin docs for marketplace.json schema**

Search the local Claude Code installation for documentation:

```bash
find ~/.claude -name "*.md" -path "*plugin*" 2>/dev/null | head
```

Or fetch from the Claude Code repo / docs site for the `marketplace.json` schema. Capture the exact `source` shape that is documented for remote GitHub repos.

Expected: documented options include at least one of:
- `"source": "github:Moonchopper/claude-plugin-observability"`
- `"source": {"source": "github", "repo": "Moonchopper/claude-plugin-observability"}`
- `"source": {"source": "git", "url": "https://github.com/Moonchopper/claude-plugin-observability"}`

- [ ] **Step 2: Test the syntax against a sandbox marketplace.json**

In a temporary working directory, write a `.claude-plugin/marketplace.json` using the documented syntax pointing at any small public Claude Code plugin repo (or a stub repo we own). Run:

```bash
claude plugin marketplace add /path/to/sandbox --scope project
claude plugin marketplace list
```

Expected: the marketplace registers without error; `marketplace list` shows it.

- [ ] **Step 3: Record the working syntax**

Add a short note to `docs/stage-3-notes.md` (under "Decisions recorded") capturing:
- The exact `source` value shape that worked.
- The Claude Code CLI version it was verified against.
- Any quirks (e.g. shorthand vs object form differences).

This is the contract A4 implements against. If A1 reveals that *no* remote source shape currently works for marketplace.json, halt and surface to the human before continuing Phase A. The fallback in that case is to host marketplace.json in a third repo (`Moonchopper/native-agent-marketplace`) — an option, not the default.

### Task A2: Create `Moonchopper/datadog-operations` GitHub repo and seed it from `fixtures/datadog-operations/`

**Why:** The functional repo's content (`agent/golden-paths/`, `agent/best-practices/`, `terraform/`, `README.md`) currently lives in this repo's working tree. Per doc 4 §1 and the conversation that motivated this plan, it must live in a separately versioned GitHub repo for the architecture's retrieval boundary to be real.

**Files:**
- Read: `fixtures/datadog-operations/**` (existing in this repo)
- Create (in the new remote repo): everything from `fixtures/datadog-operations/`, plus a new top-level `README.md`.

- [ ] **Step 1: Create the GitHub repo if it doesn't already exist**

Existence check first so this task is safe to re-run on a partial Phase A:

```bash
if gh repo view Moonchopper/datadog-operations >/dev/null 2>&1; then
  echo "Repo Moonchopper/datadog-operations already exists; skipping create."
else
  gh repo create Moonchopper/datadog-operations --public \
    --description "Fixture functional repo for native-agent-orchestration PoC. Contains agent-retrieval test content, NOT a deployable Datadog Terraform project."
fi
```

Expected on first run: `gh` returns the new repo URL. Expected on re-run: skip message, no error. If the repo exists but with unexpected content (e.g. someone else owns this name), halt and surface to the human — do not blindly proceed to overwrite.

- [ ] **Step 2: Initialize a local clone in a scratch directory**

```bash
SCRATCH=$(mktemp -d)
cd "$SCRATCH"
gh repo clone Moonchopper/datadog-operations
cd datadog-operations
```

Do NOT clone into this repo's working tree — keep the new repo's working tree separate from this one's.

- [ ] **Step 3: Copy fixture content into the new repo**

```bash
REPO_ROOT=$(cd /d/git/native-agent-orchestration && pwd)
cp -R "$REPO_ROOT/fixtures/datadog-operations/." .
```

Verify the tree looks correct:

```bash
find . -type f -not -path "./.git/*" | sort
```

Expected: same files that `find fixtures/datadog-operations -type f` shows in the harness repo. Specifically:
- `README.md`
- `agent/best-practices/{index-naming,query-cost-awareness,retention-tier-selection}.md`
- `agent/golden-paths/create-log-index/{README.md,steps.md,best-practices.md,example.tf}`
- `terraform/logs/indexes/.gitkeep`

- [ ] **Step 4: Replace the top-level README.md with a new one that explains fixture purpose**

The current `fixtures/datadog-operations/README.md` was authored as the *functional repo's* README. It still works in spirit, but we want to add an explicit fixture caveat at the top. Write a new README with this structure:

```markdown
# datadog-operations (fixture repo)

> **This is a fixture repository for the [native-agent-orchestration](https://github.com/Moonchopper/native-agent-orchestration) PoC.**
>
> The repo is real — it is GitHub-hosted, agent-retrievable, and exercises the architecture's retrieval boundary. The Terraform tree it contains is NOT a deployable Datadog configuration. `example.tf` and any drafted artifacts are illustrative content for testing agent retrieval; they are not meant to be `terraform apply`'d against a real Datadog account.
>
> If you landed here looking for a real Datadog Terraform pattern, this is not that. Datadog's official Terraform provider documentation is the right starting point.

[then preserve the existing README content describing the agent-oriented `agent/` tree]
```

- [ ] **Step 5: Commit and push**

```bash
git add .
git commit -m "Initial import from native-agent-orchestration fixtures"
git push origin main
```

Verify on github.com that the repo's tree matches expectation.

### Task A3: Create `Moonchopper/claude-plugin-observability` GitHub repo and seed it from `fixtures/claude-plugin-observability/`

**Why:** Same rationale as A2, for the plugin repo. The plugin must be installable from a real GitHub source for the architecture's plugin install path to be real.

**Files:**
- Read: `fixtures/claude-plugin-observability/**`
- Create (in the new remote repo): everything from `fixtures/claude-plugin-observability/`, plus a top-level `README.md`.

- [ ] **Step 1: Create the GitHub repo if it doesn't already exist**

Same existence-check pattern as A2:

```bash
if gh repo view Moonchopper/claude-plugin-observability >/dev/null 2>&1; then
  echo "Repo Moonchopper/claude-plugin-observability already exists; skipping create."
else
  gh repo create Moonchopper/claude-plugin-observability --public \
    --description "Fixture Claude Code plugin for native-agent-orchestration PoC. Hosts skills that drive agent retrieval against the datadog-operations fixture repo."
fi
```

Expected on first run: `gh` returns the new repo URL. Expected on re-run: skip message, no error.

- [ ] **Step 2: Initialize a local clone in a separate scratch directory**

```bash
SCRATCH=$(mktemp -d)
cd "$SCRATCH"
gh repo clone Moonchopper/claude-plugin-observability
cd claude-plugin-observability
```

- [ ] **Step 3: Copy plugin content**

```bash
REPO_ROOT=$(cd /d/git/native-agent-orchestration && pwd)
cp -R "$REPO_ROOT/fixtures/claude-plugin-observability/." .
```

Expected tree:
- `.claude-plugin/plugin.json`
- `skills/create-log-index/SKILL.md`
- `skills/pr-handoff/SKILL.md`

- [ ] **Step 3.5: Audit `skills/create-log-index/SKILL.md` clone-detection prose for §9.1-step-1 compliance**

**Why this matters:** Architecture spec §9.1 step 1 reads *"`git rev-parse --show-toplevel` succeeds **and** `git config --get remote.origin.url` matches the target."* Stage 2's skill body was authored against an in-tree fixture directory with no `remote.origin` — so the body's clone-detection prose may only check `git rev-parse --show-toplevel` and skip the origin-URL match. If so, `cwd-shortcut` (Task B1) will pass when the test driver runs from *any* git repo, not just `Moonchopper/datadog-operations` — voiding the variant-delta hypothesis. Read the skill body, find the clone-detection step, and confirm it does both checks.

If the body checks `rev-parse` only, patch the prose to also require `git config --get remote.origin.url` to match `git@github.com:Moonchopper/datadog-operations.git` or `https://github.com/Moonchopper/datadog-operations.git` (or the equivalent for the agent's gh-auth scheme). Land the patch in the same initial-import commit (Step 5) — there is no value in landing a known-broken first commit.

- [ ] **Step 4: Author a top-level README.md**

```markdown
# claude-plugin-observability (fixture plugin)

> **This is a fixture plugin for the [native-agent-orchestration](https://github.com/Moonchopper/native-agent-orchestration) PoC.**
>
> The plugin is real and installable via `claude plugin install`; the skills it ships are illustrative content for testing the architecture's retrieval and orchestration boundaries against the [`Moonchopper/datadog-operations`](https://github.com/Moonchopper/datadog-operations) fixture repo. It is not intended for production observability work.

## Skills

- `create-log-index` — drives the agent through authoring a Datadog log-index Terraform PR.
- `pr-handoff` — receives a drafted-changes payload and (in the PoC) writes a JSON handoff artifact. A real `gh pr create` implementation is out of scope for the PoC.
```

- [ ] **Step 5: Commit and push**

```bash
git add .
git commit -m "Initial import from native-agent-orchestration fixtures"
git push origin main
```

### Task A4: Update `.claude-plugin/marketplace.json` to point at the remote plugin repo

**Why:** The marketplace.json `source` field is the single point of indirection that decides where the plugin comes from. Changing this from a relative path to a GitHub source is the architectural pivot.

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Read current state**

```bash
cat .claude-plugin/marketplace.json
```

Confirm it matches the shape recorded earlier (relative-path source).

- [ ] **Step 2: Replace the `source` field per A1's verified syntax**

If A1 verified the GitHub-shorthand form, the change is:

```json
{
  "name": "native-agent-observability-local",
  "owner": { "name": "native-agent-orchestration" },
  "plugins": [
    {
      "name": "observability",
      "source": "github:Moonchopper/claude-plugin-observability",
      "description": "PoC fixture plugin: skills for Datadog observability golden paths"
    }
  ]
}
```

If A1 verified the object form, use `{"source": "github", "repo": "Moonchopper/claude-plugin-observability"}`. The exact value comes from A1.

Also: rename the marketplace itself from `native-agent-observability-local` to `native-agent-observability-remote` (or `native-agent-observability`) so the name reflects reality. This requires a corresponding update in `setup-plugin.sh` (A5) and `settings/benchmark.settings.json`'s `enabledPlugins` field.

- [ ] **Step 3: Verify the JSON parses**

```bash
jq . .claude-plugin/marketplace.json
```

Expected: pretty-printed JSON, no errors.

### Task A5: Update `scripts/setup-plugin.sh` for the new marketplace source

**Why:** `setup-plugin.sh` hard-codes `MARKETPLACE_NAME="native-agent-observability-local"`. If A4 renamed the marketplace, this constant must follow. The post-install verification (`grep -q "$PLUGIN_NAME@$MARKETPLACE_NAME"`) depends on the new name.

**Files:**
- Modify: `scripts/setup-plugin.sh`

- [ ] **Step 1: Update the marketplace-name constant**

Edit line 12 to match the new name from A4:

```bash
MARKETPLACE_NAME="native-agent-observability-remote"
```

- [ ] **Step 2: Read the marketplace.json check at lines 21–24 and confirm it still applies**

The check `[ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ]` is correct — the marketplace.json still lives in this repo, only its `source` points elsewhere.

- [ ] **Step 3: Run setup-plugin.sh end-to-end on a clean machine state**

```bash
# Clean any prior install
claude plugin uninstall observability@native-agent-observability-local 2>/dev/null || true
claude plugin uninstall observability@native-agent-observability-remote 2>/dev/null || true
claude plugin marketplace remove native-agent-observability-local 2>/dev/null || true
claude plugin marketplace remove native-agent-observability-remote 2>/dev/null || true

# Run the updated script
bash scripts/setup-plugin.sh
```

Expected output: `Installed fixture plugin 'observability' from local marketplace 'native-agent-observability-remote'`.

- [ ] **Step 4: Verify the plugin is enrolled and points at the remote repo**

```bash
claude plugin list
claude plugin marketplace list
```

Expected: `observability@native-agent-observability-remote` appears in `plugin list`; the marketplace's `source` shows the GitHub URL/shorthand.

- [ ] **Step 5: Update `settings/benchmark.settings.json`'s `enabledPlugins` key**

The current value is `"observability@native-agent-observability-local": true`. Change to match the new marketplace name. Read the file first to confirm exact key shape.

- [ ] **Step 6: Commit Phase A's marketplace + setup-plugin changes**

```bash
git add .claude-plugin/marketplace.json scripts/setup-plugin.sh settings/benchmark.settings.json
git commit -m "feat: point plugin marketplace at Moonchopper/claude-plugin-observability"
```

### Task A6: Refactor `scripts/run-scenario.sh` for per-variant fixture state

**Why:** The current runner does `cd "$FIXTURE_REPO"` (line 85) where `$FIXTURE_REPO="$REPO_ROOT/fixtures/datadog-operations"`. Two things change:

1. The functional repo no longer lives in-tree. The runner must clone it (for `local-hit` and `cwd-shortcut`) or deliberately not (for `remote-fallback`).
2. The `cd` line conflated `local-hit` with `cwd-shortcut` — Stage 2's "local-hit" was actually CWD = fixture repo, which is closer to `cwd-shortcut`. Phase A6 separates them: `local-hit` sets CWD to the run scratch directory (`SESSION_DIR`), forcing the agent's detection ladder to walk from CWD-miss through conventional-paths-hit; `cwd-shortcut` sets CWD = the clone.

**Files:**
- Modify: `scripts/run-scenario.sh` (substantial — the fixture-state setup is new logic, ~50–80 lines)
- Modify: `scripts/assertions/create-log-index-local-hit.sh` (FIXTURE_REPO derivation)
- Modify: `tests/test_runner_contract.bats` (variant-specific dry-run output)

- [ ] **Step 1: Write the failing tests for variant dry-run output**

In `tests/test_runner_contract.bats`, add tests that assert the runner's `DRY_RUN=1` output for each new variant:

```bash
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
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
.bats/bin/bats tests/test_runner_contract.bats
```

Expected: 2 failures (cwd-shortcut, remote-fallback rejected by current variant check at line 25).

- [ ] **Step 3: Add `cwd-shortcut` and `remote-fallback` to the variant allowlist**

Edit `scripts/run-scenario.sh` lines 24–30:

```bash
case "$VARIANT" in
  local-hit|cwd-shortcut|remote-fallback) ;;
  *)
    echo "ERROR: unknown variant '$VARIANT'" >&2
    usage
    ;;
esac
```

Re-run bats: dry-run tests pass; the runner now accepts the new variants but doesn't yet do anything different for them.

- [ ] **Step 4: Refactor the fixture-state block (the largest change)**

Replace the block from line 39 (`REPO_ROOT=$(git rev-parse --show-toplevel)`) through line 58 (`rm -f "$FIXTURE_REPO/terraform/logs/indexes/foobar.tf"`) with per-variant logic. New shape:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
SESSION_DIR=$(mktemp -d)

# Conventional path the detection ladder will find for `local-hit`.
# (Per architecture spec §9.1 step 2: ~/src/<org>/<repo> is the first probed
# conventional path.)
CONVENTIONAL_CLONE_DIR="$HOME/src/Moonchopper/datadog-operations"

# Per-variant fixture-state setup. The runner's job is to put the working
# tree in the right state BEFORE claude -p starts. The agent's detection
# ladder then runs against that state.
case "$VARIANT" in
  local-hit)
    # Functional repo present at conventional path; CWD = run scratch dir
    # (NOT the clone). Agent's CWD-match check (§9.1 step 1) misses;
    # conventional-path check (§9.1 step 2) hits.
    if [ ! -d "$CONVENTIONAL_CLONE_DIR/.git" ]; then
      mkdir -p "$(dirname "$CONVENTIONAL_CLONE_DIR")"
      gh repo clone Moonchopper/datadog-operations "$CONVENTIONAL_CLONE_DIR"
    else
      # Refresh to a known-clean state for run reproducibility.
      git -C "$CONVENTIONAL_CLONE_DIR" fetch origin
      git -C "$CONVENTIONAL_CLONE_DIR" reset --hard origin/main
      git -C "$CONVENTIONAL_CLONE_DIR" clean -fd
    fi
    FIXTURE_REPO="$CONVENTIONAL_CLONE_DIR"
    INVOCATION_CWD="$SESSION_DIR"
    ;;

  cwd-shortcut)
    # Functional repo present at conventional path; CWD = the clone.
    # Agent's CWD-match check (§9.1 step 1) hits immediately.
    if [ ! -d "$CONVENTIONAL_CLONE_DIR/.git" ]; then
      mkdir -p "$(dirname "$CONVENTIONAL_CLONE_DIR")"
      gh repo clone Moonchopper/datadog-operations "$CONVENTIONAL_CLONE_DIR"
    else
      git -C "$CONVENTIONAL_CLONE_DIR" fetch origin
      git -C "$CONVENTIONAL_CLONE_DIR" reset --hard origin/main
      git -C "$CONVENTIONAL_CLONE_DIR" clean -fd
    fi
    FIXTURE_REPO="$CONVENTIONAL_CLONE_DIR"
    INVOCATION_CWD="$CONVENTIONAL_CLONE_DIR"
    ;;

  remote-fallback)
    # NO clone at any conventional path. Agent's detection ladder must
    # miss steps 1-3 and hit step 4 (ask user / offer to clone).
    # The test driver's prompt answers "yes, clone it."
    for dir in \
      "$HOME/src/Moonchopper/datadog-operations" \
      "$HOME/code/Moonchopper/datadog-operations" \
      "$HOME/git/Moonchopper/datadog-operations" \
      "$HOME/work/Moonchopper/datadog-operations"; do
      if [ -d "$dir/.git" ]; then
        echo "ERROR: remote-fallback requires NO clone at conventional paths." >&2
        echo "Found pre-existing clone at: $dir" >&2
        echo "Remove it (or rename) and re-run." >&2
        exit 1
      fi
    done
    # EXPECTED_CLONE_PATH is the single source of truth for "where the agent
    # is told to clone to" — referenced by both the PROMPT (clone authorization
    # text) and the assertion script (clone-existence check). One literal,
    # not two; prevents drift between prompt and assertion.
    FIXTURE_REPO="$HOME/src/Moonchopper/datadog-operations"
    INVOCATION_CWD="$SESSION_DIR"
    ;;
esac

# Single source of truth for where remote-fallback expects the clone to
# end up. local-hit/cwd-shortcut clone before claude -p so this is
# already-known; remote-fallback uses it in the PROMPT text.
export EXPECTED_CLONE_PATH="$FIXTURE_REPO"

HANDOFF_FILE="$FIXTURE_REPO/.stage-1-handoff.json"
rm -f "$HANDOFF_FILE"
# Clean any drafted Terraform from prior runs (only if FIXTURE_REPO exists).
[ -d "$FIXTURE_REPO" ] && rm -f "$FIXTURE_REPO/terraform/logs/indexes/foobar.tf"
```

- [ ] **Step 5: Update the `cd` line to use `$INVOCATION_CWD`**

Replace `cd "$FIXTURE_REPO"` (was line 85) with `cd "$INVOCATION_CWD"`.

- [ ] **Step 6: Adapt the `PROMPT` variable per variant**

For `remote-fallback`, the prompt must explicitly authorize cloning. Add a variant-conditional preamble:

```bash
CLONE_AUTHORIZATION=""
if [ "$VARIANT" = "remote-fallback" ]; then
  CLONE_AUTHORIZATION="If you discover that the datadog-operations repo is not cloned locally, run gh auth status FIRST, then clone it to $EXPECTED_CLONE_PATH (do not invent a different path), and only then cd into the clone to draft files. Do not cd into the clone before the auth check.

"
fi

PROMPT=$(cat <<EOF
${CLONE_AUTHORIZATION}Invoke the observability:create-log-index skill ...
[rest of existing prompt unchanged]
EOF
)
```

For `local-hit` and `cwd-shortcut`, no preamble — the agent should not need to clone.

- [ ] **Step 7: Adapt the `PROJECT_SLUG` derivation, and handle slug rotation for `remote-fallback`**

The current line `PROJECT_SLUG=$(echo "$FIXTURE_REPO" | sed -e 's/[\\:/.]/-/g' -e 's/^-*//')` derives the transcript path from `FIXTURE_REPO`. With variants, the transcript lives at the slug derived from `INVOCATION_CWD`, not `FIXTURE_REPO`. Change:

```bash
PROJECT_SLUG=$(echo "$INVOCATION_CWD" | sed -e 's/[\\:/.]/-/g' -e 's/^-*//')
```

**Known caveat for `remote-fallback`:** the `cd-only-after-auth-and-clone` instruction in Step 6's PROMPT text is *intended* to keep all turns in the SESSION_DIR slug. The instruction is not a hard guarantee — Claude Code may rotate to a new project slug if the agent `cd`s mid-run, and the auth-status invocation is then split across two slug directories. Mitigation, in order of preference:

1. **Verify on the first manual run (Task B2 Step 3).** Inspect `~/.claude/projects/` after a `remote-fallback` run; confirm a single transcript covers the auth-then-clone-then-draft sequence.
2. **If two slugs are produced**, extend the runner to read transcripts from *both* the SESSION_DIR slug and the post-clone slug (`$FIXTURE_REPO`-derived) and concatenate them (chronologically by `.timestamp` field) before passing to `extract-metrics.sh`. Capture this in stage-3-notes as a deviation if needed.

Recording this as a known caveat rather than pre-mitigating: Stage 2's transcript-derivation logic was deliberately heuristic (per stage-2-notes carry-forward risks), and the right fix surfaces only with a real `remote-fallback` transcript in hand.

- [ ] **Step 8: Run the bats tests; expect green**

```bash
.bats/bin/bats tests/test_runner_contract.bats
```

Expected: all tests pass, including new variant ones.

- [ ] **Step 9: Adapt `scripts/assertions/create-log-index-local-hit.sh`**

The current script derives `FIXTURE_REPO` from `$(dirname "$HANDOFF_FILE")`. That still works after the refactor — the handoff file lives in the cloned functional repo. No code change needed; just verify with a manual run after A8.

- [ ] **Step 10: Commit**

```bash
git add scripts/run-scenario.sh tests/test_runner_contract.bats
git commit -m "feat: per-variant fixture-state setup in run-scenario.sh"
```

### Task A7: Update doc 4 §4 wording for real-repo paths

**Why:** Doc 4's §4 was authored assuming in-tree fixtures. After A2/A3, the fixture repos are real; the wording must follow.

**Files:**
- Modify: `docs/reference-scenarios.md` — §4 only.

- [ ] **Step 1: Read §4**

```bash
grep -n "## 4." docs/reference-scenarios.md
```

Find the section bounds.

- [ ] **Step 2: Update §4 contents**

Replace references to `fixtures/datadog-operations/` with `Moonchopper/datadog-operations` (the GitHub repo). Update the table to reflect:
- `local-hit`: "Clone `Moonchopper/datadog-operations` to `~/src/Moonchopper/datadog-operations`. The runner's CWD is a scratch directory, not the clone."
- `cwd-shortcut`: "Same clone setup as `local-hit`. Runner's CWD is the clone."
- `remote-fallback`: "No clone at any conventional path. The runner verifies absence; the agent's detection ladder must reach step 4 and offer to clone."

Also clarify in the section preamble: "The functional repo `Moonchopper/datadog-operations` is a real GitHub-hosted repository; the agent retrieves content via clone or `gh api`. It is *not* a deployable Datadog Terraform project — see the repo's README for the fixture caveat."

- [ ] **Step 3: Update §5.1.1's "Pre-run fixture state" row**

The row currently says `Clone at ~/src/Moonchopper/datadog-operations (or whatever conventional path the detection ladder is configured for)`. After A6, the runner clones from `Moonchopper/datadog-operations`. Update the row to reflect this is automated, not manually configured. Same for §5.1.2 and §5.1.3.

- [ ] **Step 4: Verify internal markdown links still resolve**

```bash
grep -n "fixtures/" docs/reference-scenarios.md
```

Expected: zero hits. (All fixture references should be replaced.)

- [ ] **Step 5: Commit**

```bash
git add docs/reference-scenarios.md
git commit -m "docs: update doc 4 §4 wording for externalized fixture repos"
```

### Task A8: Re-validate `create-log-index/local-hit` against the new layout (N=5)

**Why:** Stage 2's `11228`-token budget was measured against in-tree fixtures with the runner's CWD = the fixture directory. After A6, the runner's CWD is a scratch dir (forcing detection-ladder step 2 to actually run), and the functional repo is reached via a real clone. These are material changes to the retrieval path; the locked budget must be re-derived.

**Files:**
- Modify: `scripts/matrix/poc-full.tsv` (creating in B7; in this task, work against `stage-2-initial.tsv` for the single-row run)
- Read: `tests/test_runner_contract.bats` to confirm green
- Read: aggregated output

- [ ] **Step 1: Run the matrix once for the single row**

```bash
bash scripts/run-benchmarks.sh --matrix scripts/matrix/stage-2-initial.tsv
```

Expected: 5 invocations of `run-scenario.sh create-log-index local-hit`, each producing a metrics file. Pass rate should be 5/5; if any fail, halt and diagnose before proceeding.

- [ ] **Step 2: Run the aggregator and capture the table**

```bash
bash scripts/aggregate-metrics.sh <metrics-paths-from-step-1>
```

Expected output: a markdown row of the form `| create-log-index | local-hit | 5 | <P50> | <P95> | <cache_ratio> | <hot_turn> |`.

- [ ] **Step 3: Compute the new budget**

`ceil(P95 * 1.20)`. Record both raw P95 and the budget in `docs/stage-3-notes.md` (this file is created later in Phase C; for now, capture the numbers in the worktree's notes).

- [ ] **Step 4: Compare to Stage 2's number**

Stage 2: P50=8755, P95=9356, budget=11228. Record the delta (likely larger now, because detection-ladder steps 2 and the clone-detection turns are no longer skipped).

If the new P95 is *lower* than Stage 2's, that's surprising and worth investigating before continuing — it would suggest the in-tree fixture setup was costing tokens we expected to save. Either outcome is a finding.

- [ ] **Step 5: Document the finding**

Add a one-paragraph note to the work-in-progress `stage-3-notes.md` content (which becomes a real file in Phase C):

```
Phase A baseline re-measurement (create-log-index/local-hit, N=5): P50=<x>, P95=<y>, cache_ratio=<r>, hot_turn=<h>. Δ vs Stage 2: P50 <±%>, P95 <±%>. Budget locked at ceil(P95 * 1.20) = <budget>.
```

### Task A9: Delete in-tree fixtures

**Why:** `fixtures/datadog-operations/` and `fixtures/claude-plugin-observability/` no longer have any reader: the runner clones from GitHub, the marketplace.json points at GitHub, the assertions read from the cloned working tree. Leaving the in-tree fixtures encourages drift between the harness repo and the real fixture repos. Delete them.

**Files:**
- Delete: `fixtures/datadog-operations/` (entire directory)
- Delete: `fixtures/claude-plugin-observability/` (entire directory)
- Delete: `fixtures/` (if empty after the above)
- Modify: any references in `.gitignore`, `README.md`, etc., that mention `fixtures/`

- [ ] **Step 1: Grep for any remaining references to `fixtures/`**

```bash
grep -rn "fixtures/" --include="*.md" --include="*.sh" --include="*.json" --include="*.bats" .
```

Capture the list. Each hit must be either:
- Updated to point at the GitHub repos (most likely).
- Removed if it's a dead reference.

- [ ] **Step 2: Resolve each hit**

Iterate through the grep output. Common cases:
- `README.md` mentions `fixtures/` in setup instructions — update to point at the GitHub repos.
- Old `.gitignore` entries — verify still relevant; remove if not.
- Stage-1/2 plan documents — leave as historical record (they accurately described state at their time).
- `docs/stage-2-notes.md` — leave as historical record.

- [ ] **Step 3: Delete the directories**

```bash
git rm -r fixtures/
```

Expected: `git status` shows the deletion.

- [ ] **Step 4: Re-run all bats tests**

```bash
.bats/bin/bats tests/
```

Expected: all green. If a test depends on `fixtures/`, that's a bug — the runner is the only thing that should know about fixture paths now.

- [ ] **Step 5: Re-run the matrix**

```bash
bash scripts/run-benchmarks.sh --matrix scripts/matrix/stage-2-initial.tsv
```

Expected: 5/5 pass. (If A8 ran clean, this is a regression check on the deletion.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove in-tree fixtures (now hosted in Moonchopper/datadog-operations and Moonchopper/claude-plugin-observability)"
```

### Task A10: Push Phase A; open or update PR

**Why:** Phase A is a coherent unit: extracted fixtures, updated harness, locked new baseline. Worth a review boundary.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin <stage-3-branch-name>
```

- [ ] **Step 2: Open a PR (or update if one already exists)**

```bash
gh pr create --base main --title "Stage 3 Phase A: externalize fixtures to standalone repos" \
  --body "..."
```

Body should cover: what moved, why, link to the two new repos, the new locked `local-hit` budget, and a note that Phase B (matrix expansion) follows.

- [ ] **Step 3: Update memory**

Update `project_status.md` to record: Phase A merged; Phase B in progress; new locked budget; reference to the two GitHub repos.

---

# Phase B — Matrix Expansion

### Task B1: `create-log-index/cwd-shortcut` end-to-end

**Why:** The smallest delta from `local-hit` (one CWD difference). Proves the per-variant infrastructure works before adding scenario complexity.

**Files:**
- Create: `scripts/assertions/create-log-index-cwd-shortcut.sh`
- Modify: `scripts/run-benchmarks.sh` (no change expected — already iterates by row)
- Modify: `scripts/matrix/poc-full.tsv` (created in B7; for this task, append the row to a working copy)

- [ ] **Step 1: Author the assertion script**

Copy `scripts/assertions/create-log-index-local-hit.sh` to `cwd-shortcut.sh`. Modify the assertion list to include a transcript-based check that detection-ladder steps 2–4 did not run.

The transcript is at `$HOME/.claude/projects/<slug>/<session>.jsonl` (slug derived from `INVOCATION_CWD`). The assertion should:

1. Find the transcript file (most recent under the slug directory).
2. Grep for any Bash invocation against `~/src/`, `~/code/`, `~/git/`, `~/work/` for `datadog-operations` resolution.
3. Fail if any are found.

This is a cwd-shortcut-specific assertion: detection-ladder step 1 should have hit, eliminating the need for step 2's path-probing.

```bash
fail_if_path_probed() {
  local transcript="$1"
  local probed
  probed=$(jq -r 'select(.message.content[]?.input.command? // "" | test("(~|\\$HOME)/(src|code|git|work)/[^/]*/datadog-operations"))' "$transcript" 2>/dev/null | head -1)
  if [ -n "$probed" ]; then
    fail "cwd-shortcut should skip path-probing; found probe of conventional path in transcript"
  fi
}
```

The exact jq filter may need iteration; treat the snippet above as a starting point. The bats test in step 2 verifies it.

- [ ] **Step 2: Write a bats test for the new assertion**

Create `tests/fixtures/transcript-cwd-shortcut-clean.jsonl` (no path probe) and `tests/fixtures/transcript-cwd-shortcut-probed.jsonl` (contains a probe). Add a bats file `tests/test_assertions_cwd_shortcut.bats` that runs the assertion against each fixture and verifies the expected outcome.

- [ ] **Step 3: Run-scenario the variant manually once**

```bash
bash scripts/run-scenario.sh create-log-index cwd-shortcut
```

Expected: assertion script passes; manually inspect the transcript to confirm detection-ladder behavior matches expectation.

- [ ] **Step 4: Run N=5 via the matrix driver**

Append the row to a working matrix file:

```
create-log-index	cwd-shortcut	5
```

Run:

```bash
bash scripts/run-benchmarks.sh --matrix <working-matrix.tsv>
```

Expected: 5/5 pass.

- [ ] **Step 5: Aggregate and capture the budget**

Aggregator output gives P50/P95. Budget = `ceil(P95 * 1.20)`. Record in stage-3-notes WIP.

- [ ] **Step 6: Verify the variant-delta hypothesis**

Per [doc 4 §5.1.2](../../reference-scenarios.md#5-1-2-variant-cwd-shortcut), `cwd-shortcut` P50 should be **at least one full LLM call lower** than `local-hit` P50. Confirm or surface as a finding.

- [ ] **Step 7: Commit**

```bash
git add scripts/assertions/create-log-index-cwd-shortcut.sh tests/test_assertions_cwd_shortcut.bats tests/fixtures/transcript-cwd-shortcut-*.jsonl
git commit -m "feat: create-log-index/cwd-shortcut end-to-end"
```

### Task B2: `create-log-index/remote-fallback` end-to-end

**Why:** Tests the offer-to-clone branch (architecture spec §9.3). Validates that `gh auth status` runs, the clone happens, and the rest of the flow proceeds against the freshly cloned tree.

**Files:**
- Create: `scripts/assertions/create-log-index-remote-fallback.sh`
- Modify: `scripts/run-scenario.sh` (only if remote-fallback's INVOCATION_CWD or post-run FIXTURE_REPO derivation needs adjustment after first manual run)

- [ ] **Step 1: Author the assertion script**

Three remote-fallback-specific assertions in addition to the standard `local-hit` ones:

1. **Clone exists post-run** at `~/src/Moonchopper/datadog-operations`.
2. **`gh auth status` invoked before any clone** in the transcript.
3. **Drafted paths are relative to the fresh clone** (assertion logic same as local-hit, but FIXTURE_REPO is now the post-clone path).

Sketch:

```bash
#!/usr/bin/env bash
set -euo pipefail

HANDOFF_FILE="${1:?handoff file path required}"
TRANSCRIPT="${TRANSCRIPT_PATH:?TRANSCRIPT_PATH env var required}"

POST_RUN_CLONE="$HOME/src/Moonchopper/datadog-operations"

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

# 1. Clone exists post-run
[ -d "$POST_RUN_CLONE/.git" ] || fail "clone not found at $POST_RUN_CLONE"

# 2. gh auth status invoked before any clone
auth_idx=$(jq -r '[.message.content[]?.input.command? // ""] | map(select(test("gh auth status"))) | length' "$TRANSCRIPT" 2>/dev/null)
clone_idx=$(jq -r '[.message.content[]?.input.command? // ""] | map(select(test("gh repo clone|git clone.*datadog-operations"))) | length' "$TRANSCRIPT" 2>/dev/null)
[ "$auth_idx" -gt 0 ] || fail "gh auth status not invoked"
[ "$clone_idx" -gt 0 ] || fail "no clone invocation found in transcript"

# 3. Standard handoff/drafted-file assertions (copy from local-hit)
# ... (FIXTURE_REPO=$POST_RUN_CLONE here)
```

The exact jq filters need iteration against a real transcript; this is a starting point.

- [ ] **Step 2: Write a bats test for the new assertion**

Canned transcript fixtures: one with `gh auth status` + clone, one without. Same pattern as B1.

- [ ] **Step 3: Run-scenario the variant manually once**

Pre-flight: ensure no clone exists at any conventional path (the runner's preflight in A6 handles this; manually verify the first time):

```bash
ls -d $HOME/src/Moonchopper/datadog-operations 2>/dev/null && echo "clone exists; remove it first"
bash scripts/run-scenario.sh create-log-index remote-fallback
```

Expected: assertion script passes; clone now exists at `$HOME/src/Moonchopper/datadog-operations`.

- [ ] **Step 4: Run N=5 via the matrix driver**

Each run requires the clone to NOT exist beforehand. The runner's preflight should error if a clone exists from a prior run. Add a per-row pre-step in `scripts/run-benchmarks.sh` (or a wrapper for `remote-fallback`) that removes the clone if it exists:

```bash
# In run-benchmarks.sh, before invoking run-scenario.sh for remote-fallback:
if [ "$VARIANT" = "remote-fallback" ]; then
  rm -rf "$HOME/src/Moonchopper/datadog-operations"
fi
```

Or: keep this logic out of `run-benchmarks.sh` and document in the matrix file's preamble that `remote-fallback` rows are best run with manual clone-cleanup between iterations. Decision: **add the cleanup to `run-benchmarks.sh`** — the matrix should be hermetic.

Run:

```bash
bash scripts/run-benchmarks.sh --matrix <working-matrix.tsv>
```

Expected: 5/5 pass.

- [ ] **Step 5: Aggregate, capture the budget**

Per doc 4 §7: `remote-fallback` budget should land **higher** than `local-hit`. Record by how much; this is the "is local-first worth its complexity" answer.

- [ ] **Step 6: Commit**

```bash
git add scripts/assertions/create-log-index-remote-fallback.sh scripts/run-benchmarks.sh tests/test_assertions_remote_fallback.bats tests/fixtures/transcript-remote-fallback-*.jsonl
git commit -m "feat: create-log-index/remote-fallback end-to-end"
```

### Task B3: Author `create-monitor` fixture content in `Moonchopper/datadog-operations`

**Why:** `create-monitor` is the second scenario per doc 4 §5.2. It exists to prove the architecture generalizes — a different practice set, a different drafted artifact path, a deliberate override case.

**Files (in the remote `Moonchopper/datadog-operations` repo, NOT this repo):**
- Create: `agent/golden-paths/create-monitor/README.md`
- Create: `agent/golden-paths/create-monitor/steps.md`
- Create: `agent/golden-paths/create-monitor/best-practices.md`
- Create: `agent/golden-paths/create-monitor/example.tf`
- Create: `agent/best-practices/monitor-notification-target.md`
- Create: `agent/best-practices/monitor-evaluation-window-floor.md`

- [ ] **Step 1: Clone the `Moonchopper/datadog-operations` repo locally for editing**

In a scratch directory (NOT this harness repo's working tree):

```bash
SCRATCH=$(mktemp -d)
gh repo clone Moonchopper/datadog-operations "$SCRATCH/datadog-operations"
cd "$SCRATCH/datadog-operations"
git checkout -b stage-3-create-monitor
```

- [ ] **Step 2: Author `agent/best-practices/monitor-notification-target.md`**

This is the deliberate-override case from doc 4 §5.2.1. The practice is: monitors must page a team channel, not an individual.

```markdown
# Monitors must page a team channel, not an individual

## Principle
A monitor's notification target must be a team Slack channel or PagerDuty
service — not an individual user.

## Rationale
On-call rotates; individuals leave teams. A monitor wired to `@user-foo`
is on a clock until that user changes role, in which case the alert
silently routes to nobody. Team channels survive personnel changes.

## When an exception is justified
- Temporary monitor (sub-week lifespan) wired during incident response
  while the proper team-routing is being set up.
- Personal investigation monitor on a sandbox workload.

## How to check a draft
Inspect the proposed `notify_target`. If it is `@<user>` (single user),
ask the user whether either of the carve-outs above applies. If not,
suggest the team channel for the service's owning team. The `notify_target`
must start with `@` and reference a team or service, e.g. `@slack-platform-team`
or `@pagerduty-platform-oncall`.
```

- [ ] **Step 3: Author `agent/best-practices/monitor-evaluation-window-floor.md`**

The practice is: monitors with windows under 5 minutes are noisy; require justification.

```markdown
# Monitor evaluation window must be ≥ 5 minutes unless justified

## Principle
A monitor's evaluation window (the duration over which the metric is
aggregated) should be at least 5 minutes.

## Rationale
Sub-5-minute windows produce noisy alerts on transient spikes that
self-heal before a human can act. The 5-minute floor is the smallest
window that consistently produces actionable signal for most workloads.

## When an exception is justified
- Latency or availability SLOs with sub-minute objectives.
- Security or fraud-detection monitors where minutes of delay are unacceptable.

## How to check a draft
Inspect the proposed evaluation window in the monitor's `query`. If it
is less than `5m`, ask the user whether either of the carve-outs above
applies. If not, suggest `5m`.
```

- [ ] **Step 4: Author `agent/golden-paths/create-monitor/example.tf`**

```hcl
resource "datadog_monitor" "example" {
  name    = "<name>"
  type    = "metric alert"
  message = "<message text> Notify: <notify_target>"

  query = "<query>"

  monitor_thresholds {
    critical = 0.02
  }

  evaluation_delay = 60
  include_tags     = true
  notify_no_data   = false

  tags = ["team:<team>", "env:<env>"]
}
```

- [ ] **Step 5: Author `agent/golden-paths/create-monitor/README.md`, `steps.md`, `best-practices.md`**

`README.md` — same shape as `create-log-index/README.md` (what, who, prereqs, files touched, referenced practices).

`steps.md` — 8 steps, modeled on `create-log-index/steps.md`. Inputs to confirm:
- `name` (monitor name)
- `query` (the metric query)
- `window` (evaluation window — passed to query)
- `notify_target` (slack/pagerduty target)

`best-practices.md` — pointer to `monitor-notification-target.md` and `monitor-evaluation-window-floor.md`.

- [ ] **Step 6: Add `terraform/monitors/.gitkeep`**

```bash
mkdir -p terraform/monitors
touch terraform/monitors/.gitkeep
```

- [ ] **Step 7: Commit and push the `Moonchopper/datadog-operations` branch; merge it**

```bash
git add agent/ terraform/monitors/
git commit -m "feat: create-monitor golden path and best-practice files"
git push -u origin stage-3-create-monitor
gh pr create --title "create-monitor fixture content" --body "..."
gh pr merge --squash  # or merge from the GitHub UI
```

After merge, the `Moonchopper/datadog-operations` `main` branch has the new content. The harness's runner will pick it up automatically on next clone.

### Task B4: Author `create-monitor` skill in `Moonchopper/claude-plugin-observability`

**Files (in the remote `Moonchopper/claude-plugin-observability` repo):**
- Create: `skills/create-monitor/SKILL.md`

- [ ] **Step 1: Clone for editing in a separate scratch dir**

```bash
SCRATCH=$(mktemp -d)
gh repo clone Moonchopper/claude-plugin-observability "$SCRATCH/plugin"
cd "$SCRATCH/plugin"
git checkout -b stage-3-create-monitor-skill
```

- [ ] **Step 2: Copy `create-log-index/SKILL.md` as a starting point**

```bash
cp -R skills/create-log-index skills/create-monitor
```

- [ ] **Step 3: Edit `skills/create-monitor/SKILL.md`**

Update:
- Frontmatter `name` to `create-monitor`.
- Frontmatter `description` to match the `create-monitor` golden path's intent (e.g. "Author a Datadog monitor PR for a team's service via the platform team's golden path.").
- Body references from `create-log-index` to `create-monitor` (golden-path directory, drafted file path, example.tf path, etc.).
- Inputs section to use `create-monitor`'s inputs (name, query, window, notify_target — not retention/quota).

The skill should reference the same plugin-level conventions as `create-log-index` (CWD detection, freshness check, practice loading, pr-handoff at the end). The DRY cost is accepted per architecture spec §5.

- [ ] **Step 4: Verify SKILL.md frontmatter renders**

```bash
head -10 skills/create-monitor/SKILL.md
```

Expected: well-formed YAML frontmatter with name, description, allowed-tools.

- [ ] **Step 5: Push and merge**

```bash
git add skills/create-monitor/
git commit -m "feat: create-monitor skill body"
git push -u origin stage-3-create-monitor-skill
gh pr create --title "create-monitor skill" --body "..."
gh pr merge --squash
```

After merge and the next `claude plugin update` (or fresh marketplace re-add), the new skill is available.

- [ ] **Step 6: Re-run `setup-plugin.sh` from this repo**

```bash
cd /d/git/native-agent-orchestration
bash scripts/setup-plugin.sh
```

May need to add `claude plugin update` after `claude plugin marketplace add` to pull the new skill. Verify:

```bash
claude plugin list
# Should show `create-monitor` skill as available under the `observability` plugin.
```

### Task B5: `create-monitor/local-hit` runner integration + assertion

**Files:**
- Modify: `scripts/run-scenario.sh` — add `create-monitor` to scenario allowlist; per-scenario PROMPT.
- Create: `scripts/assertions/create-monitor-local-hit.sh`

- [ ] **Step 1: Add `create-monitor` to the scenario allowlist**

Edit `scripts/run-scenario.sh` lines 16–22:

```bash
case "$SCENARIO" in
  create-log-index|create-monitor) ;;
  *)
    echo "ERROR: unknown scenario '$SCENARIO'" >&2
    usage
    ;;
esac
```

- [ ] **Step 2: Author per-scenario PROMPT**

Add a per-scenario PROMPT block:

```bash
case "$SCENARIO" in
  create-log-index)
    PROMPT=$(cat <<'EOF'
... (existing prompt)
EOF
)
    ;;
  create-monitor)
    PROMPT=$(cat <<'EOF'
Invoke the observability:create-monitor skill and execute its golden
path end-to-end. Do NOT enter brainstorming or planning mode.

Parameters (already confirmed by the operator):
- name: foobar-api-error-rate
- team: foobar
- env: prod
- query: sum:foobar.api.errors{*}.as_rate() > 0.02
- window: 5m
- notify_target: @user-foo

When the practice check raises a violation about notify_target, override
with this rationale: "temporary while team rotation is being set up."
Accept all other practice suggestions as-is.
EOF
)
    ;;
esac
```

The override rationale is part of the test — the assertion checks that it appears in the PR body.

- [ ] **Step 3: Update HANDOFF_FILE / drafted-file cleanup logic to be scenario-aware**

The current `rm -f "$FIXTURE_REPO/terraform/logs/indexes/foobar.tf"` is `create-log-index`-specific. Generalize:

```bash
case "$SCENARIO" in
  create-log-index)
    rm -f "$FIXTURE_REPO/terraform/logs/indexes/foobar.tf"
    ;;
  create-monitor)
    rm -f "$FIXTURE_REPO/terraform/monitors/foobar-api-error-rate.tf"
    ;;
esac
```

- [ ] **Step 4: Author `scripts/assertions/create-monitor-local-hit.sh`**

Modeled on `create-log-index-local-hit.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

HANDOFF_FILE="${1:?handoff file path required}"
FIXTURE_REPO=$(cd "$(dirname "$HANDOFF_FILE")" && pwd)

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

[ -f "$HANDOFF_FILE" ] || fail "handoff file '$HANDOFF_FILE' does not exist"
PAYLOAD=$(cat "$HANDOFF_FILE")

for key in drafted_files pr_body override_rationale; do
  echo "$PAYLOAD" | jq -e "has(\"$key\")" >/dev/null || fail "payload missing key '$key'"
done

DRAFTED_PATH=$(echo "$PAYLOAD" | jq -r '.drafted_files[0].path')
[ "$DRAFTED_PATH" = "terraform/monitors/foobar-api-error-rate.tf" ] \
  || fail "expected 'terraform/monitors/foobar-api-error-rate.tf', got '$DRAFTED_PATH'"

[ -f "$FIXTURE_REPO/$DRAFTED_PATH" ] || fail "drafted file does not exist on disk"

DRAFTED=$(cat "$FIXTURE_REPO/$DRAFTED_PATH")
for pattern in 'resource "datadog_monitor"' 'foobar-api-error-rate' '@user-foo'; do
  echo "$DRAFTED" | grep -qE "$pattern" || fail "drafted file missing pattern: $pattern"
done

# Override-specific assertions:
echo "$PAYLOAD" | jq -r '.pr_body' | grep -q "## Best-practice overrides" \
  || fail "PR body missing '## Best-practice overrides' heading"
echo "$PAYLOAD" | jq -r '.pr_body' | grep -q "team rotation" \
  || fail "PR body missing override rationale"

echo "All assertions passed."
```

- [ ] **Step 5: Run-scenario manually once**

```bash
bash scripts/run-scenario.sh create-monitor local-hit
```

Expected: assertion script passes. If the override doesn't fire, inspect the practice file and the skill body — likely the practice's "How to check" prose needs sharpening.

- [ ] **Step 6: Run N=5 via the matrix driver**

Working matrix row: `create-monitor	local-hit	5`. Expected: 5/5 pass.

- [ ] **Step 7: Aggregate, capture the budget**

Record P50/P95 in stage-3-notes WIP. Budget = `ceil(P95 * 1.20)`. Compare cache_ratio to `create-log-index/local-hit` — should be similar if the architecture is generalizing well.

- [ ] **Step 8: Commit**

```bash
git add scripts/run-scenario.sh scripts/assertions/create-monitor-local-hit.sh
git commit -m "feat: create-monitor/local-hit end-to-end"
```

### Task B6: `baseline/baseline` scenario

**Why:** The cost floor — "how expensive is the plugin when it isn't routing anything?"

**Files:**
- Modify: `scripts/run-scenario.sh` — `baseline` scenario + `baseline` variant in allowlists
- Create: `scripts/assertions/baseline-baseline.sh`
- Create: `tests/test_assertions_baseline.bats`
- Create: `tests/fixtures/transcript-no-skill.jsonl`

- [ ] **Step 1: Add `baseline` to allowlists**

```bash
case "$SCENARIO" in
  create-log-index|create-monitor|baseline) ;;
  ...
esac

case "$VARIANT" in
  local-hit|cwd-shortcut|remote-fallback|baseline) ;;
  ...
esac
```

- [ ] **Step 2: Author the baseline PROMPT**

```bash
baseline)
  PROMPT="What is the capital of France? Answer in one word."
  ;;
```

For `baseline`, no fixture-state setup. INVOCATION_CWD = `$SESSION_DIR`. No drafted artifact to clean up.

- [ ] **Step 3: Skip handoff/drafted-file cleanup for baseline**

Wrap the cleanup in `case "$SCENARIO"`:

```bash
case "$SCENARIO" in
  baseline)
    HANDOFF_FILE=""  # not used
    ;;
  *)
    HANDOFF_FILE="$FIXTURE_REPO/.stage-1-handoff.json"
    rm -f "$HANDOFF_FILE"
    ;;
esac
```

- [ ] **Step 4: Author `scripts/assertions/baseline-baseline.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Baseline takes no handoff file — passes the transcript path directly.
TRANSCRIPT="${1:?transcript path required}"

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

# Assert: no Skill(observability:*) tool use anywhere in the transcript.
SKILL_USES=$(jq -r '.message.content[]?.input.skill? // ""' "$TRANSCRIPT" 2>/dev/null \
  | grep -c "^observability:" || true)
[ "$SKILL_USES" -eq 0 ] || fail "expected no Skill(observability:*) invocations; found $SKILL_USES"

echo "Baseline assertion passed: no observability skill invoked."
```

The exact jq filter depends on transcript schema; verify against a real off-topic transcript.

- [ ] **Step 5: Author the bats tests — both no-skill (passes) AND with-skill (must fail)**

The assertion's whole job is to detect skill invocations. A test that only confirms it returns 0 against a no-skill transcript cannot tell you whether the jq filter is *broken in a way that always returns 0*. You need a positive control too.

```bash
@test "baseline assertion passes when no observability skill is invoked" {
  run scripts/assertions/baseline-baseline.sh tests/fixtures/transcript-no-skill.jsonl
  [ "$status" -eq 0 ]
}

@test "baseline assertion FAILS when an observability skill is invoked" {
  run scripts/assertions/baseline-baseline.sh tests/fixtures/transcript-with-skill.jsonl
  [ "$status" -ne 0 ]
  [[ "$output" == *"ASSERTION FAILED"* ]]
}
```

Generate both fixtures from real runs:
- `transcript-no-skill.jsonl` — captured from an off-topic baseline run. Should contain zero `Skill(observability:*)` invocations.
- `transcript-with-skill.jsonl` — captured from any successful `create-log-index/local-hit` run. Should contain at least one `Skill(observability:create-log-index)` invocation.

If the with-skill test passes (assertion returned 0) when run against a transcript that *did* invoke the skill, the jq filter is broken — fix it before considering Step 5 complete.

- [ ] **Step 6: Update `run-scenario.sh` to invoke baseline assertion with transcript path**

The current code does:

```bash
ASSERTION_SCRIPT="$REPO_ROOT/scripts/assertions/${SCENARIO}-${VARIANT}.sh"
"$ASSERTION_SCRIPT" "$HANDOFF_FILE"
```

For baseline, the argument should be `$TRANSCRIPT`. Switch:

```bash
case "$SCENARIO" in
  baseline)
    ASSERTION_ARG="$TRANSCRIPT"
    ;;
  *)
    ASSERTION_ARG="$HANDOFF_FILE"
    ;;
esac
"$ASSERTION_SCRIPT" "$ASSERTION_ARG"
```

- [ ] **Step 7: Run-scenario manually once**

```bash
bash scripts/run-scenario.sh baseline baseline
```

Expected: assertion passes; metrics file captured; no skill invoked.

- [ ] **Step 8: Run N=5 via matrix**

Working matrix row: `baseline	baseline	5`. Expected: 5/5 pass.

- [ ] **Step 9: Aggregate, capture cost floor**

This is the architectural denominator — record per doc 4 §5.3.

- [ ] **Step 10: Commit**

```bash
git add scripts/run-scenario.sh scripts/assertions/baseline-baseline.sh tests/test_assertions_baseline.bats tests/fixtures/transcript-no-skill.jsonl
git commit -m "feat: baseline scenario (off-topic question, plugin enrolled)"
```

### Task B7: Author `scripts/matrix/poc-full.tsv`

**Files:**
- Create: `scripts/matrix/poc-full.tsv`

- [ ] **Step 1: Author the TSV**

```
scenario	variant	n
create-log-index	local-hit	5
create-log-index	cwd-shortcut	5
create-log-index	remote-fallback	5
create-monitor	local-hit	5
baseline	baseline	5
```

- [ ] **Step 2: Commit**

```bash
git add scripts/matrix/poc-full.tsv
git commit -m "feat: full PoC matrix (5 rows per doc 4 §6)"
```

`stage-2-initial.tsv` is preserved unchanged for historical reproducibility.

---

# Phase C — Lock and Write Up

### Task C1: Run the full matrix end-to-end

- [ ] **Step 1: Run**

```bash
bash scripts/run-benchmarks.sh --matrix scripts/matrix/poc-full.tsv
```

Expected: 25 invocations total (5 rows × N=5). Pass rate target: 25/25. If any fail, halt and diagnose before proceeding to C2.

- [ ] **Step 2: Aggregate**

```bash
bash scripts/aggregate-metrics.sh <all-metrics-paths>
```

Expected: 5-row markdown table with P50/P95/cache_ratio/hot_turn per row.

### Task C2: Lock per-row token budgets

- [ ] **Step 1: Compute `ceil(P95 * 1.20)` per row**

One number per matrix row.

- [ ] **Step 2: Add per-row budget enforcement to the aggregator**

Currently the assertion scripts don't check token budget — that lives in the aggregator. Decision: keep budget checking in the aggregator (one place to update), record per-row budgets in `scripts/matrix/poc-full.tsv` as a fourth column:

```
scenario	variant	n	budget
create-log-index	local-hit	5	<budget>
...
```

**Budget contract — precise semantics:**

- A **per-invocation total** is the sum of `tokens_in + tokens_out` across all assistant LLM turns in one scenario run (one row of the per-run JSONL).
- A **row PASSes** iff `max(per-invocation-total over the N runs of that row) <= budget`. Worst-of-N, not P50, not P95. Rationale: doc 4 §7's `ceil(P95 * 1.20)` already builds in 20% headroom over P95 — within that envelope, worst-of-N is the right gate, otherwise an outlier silently steals the headroom.
- The aggregator emits **markdown table** showing the row's P50, P95, max-per-invocation, budget, and PASS/FAIL.
- The aggregator's **exit code is 0 iff every row PASSes**, else 1. This lets `run-benchmarks.sh` halt the matrix or be made to bubble the failure upward (e.g. for CI use later).
- Rows missing a `budget` column value (or a sentinel like `-`) are reported as `BUDGET_UNSET` and do **not** affect exit code — useful while a new row's first measurement pass is in flight.

Update `aggregate-metrics.sh` per the contract above. If the addition is >30 lines, factor into a separate `scripts/check-budgets.sh` invoked after the aggregator with the same exit-code semantics.

- [ ] **Step 3: Re-run the matrix to verify budgets pass**

```bash
bash scripts/run-benchmarks.sh --matrix scripts/matrix/poc-full.tsv
```

Expected: aggregator output shows PASS for all 5 rows.

- [ ] **Step 4: Commit**

```bash
git add scripts/matrix/poc-full.tsv scripts/aggregate-metrics.sh
git commit -m "feat: per-row token budgets in poc-full.tsv"
```

### Task C3: Write `docs/stage-3-notes.md`

Same shape as [docs/stage-2-notes.md](../../stage-2-notes.md). Mirror its structure exactly:

- **What Stage 3 built** (1 paragraph per significant deliverable)
- **Measurement summary** (the full 5-row table from C1)
- **Plan deviations worth recording** (one entry per material divergence from this plan)
- **Carry-forward risks** (incl. real `pr-handoff` still deferred, third scenario `add-apm-service` not authored, etc.)
- **Decisions recorded** (e.g. the marketplace.json source-field syntax verified in A1)
- **Open decisions for whatever comes after Stage 3** (if the PoC continues, what's the natural next slice)

- [ ] **Step 1: Read `stage-2-notes.md` for shape reference**

- [ ] **Step 2: Author `stage-3-notes.md` per the captured WIP notes from Phase A and B**

- [ ] **Step 3: Cross-reference all matrix budgets against doc 4 hypotheses**

Did `cwd-shortcut < local-hit < remote-fallback`? Surface findings.

- [ ] **Step 4: Commit**

```bash
git add docs/stage-3-notes.md
git commit -m "docs: stage-3 handoff notes"
```

### Task C4: Update README and prepare for PR

- [ ] **Step 1: Update top-level README.md if needed**

Stage 2 added a section to README about the matrix. Stage 3 may need to update setup instructions (re: cloning the new repos automatically vs manual setup) and the matrix command (now `poc-full.tsv`).

- [ ] **Step 2: Update memory**

Update `project_status.md` to record Stage 3 completion, full matrix passing, locked budgets, the two new repos.

- [ ] **Step 3: Mark PR ready for review**

If a PR was opened during Phase A:

```bash
gh pr ready  # if it's a draft
```

Or open one if the work has been on a single non-PR'd branch the whole time.

---

## Phase boundaries summary

- **End of Phase A:** in-tree fixtures gone; runner clones from real GitHub; `create-log-index/local-hit` re-validated and budget locked.
- **End of Phase B:** all 5 matrix rows have working assertion scripts and have passed at least once; `create-monitor` content authored in the real repos.
- **End of Phase C:** full matrix passes 25/25; per-row budgets locked in `poc-full.tsv`; `stage-3-notes.md` written.

Each phase ends at a natural review checkpoint. If execution is paused mid-stage, the next session can resume at the next unchecked checkbox.

## Worktree convention

Per Stage 2 precedent, this work is best done in a dedicated worktree (e.g. `.worktrees/stage-3-externalize-and-extend/`) so the in-tree fixture deletion in A9 does not affect any other branches you may have open.

## Things deliberately not in this plan

- **Real `pr-handoff` implementation.** Per scope decision #1(a) earlier in the conversation. If user wants this added, it becomes Phase D.
- **CI integration of bats tests.** Stage-1 and Stage-2 carry-forward risk; not on Stage 3's critical path.
- **`shellcheck` enforcement.** Same.
- **Caching `gh api` responses for `remote-fallback`.** Per the scope decision: network availability is not a mitigation concern.
- **Per-scenario fixture-state preflight checks beyond what's needed for variant correctness.** E.g. asserting `terraform validate` works against the cloned `example.tf` is a fixture-correctness test, not an architecture test. Doc 4 §8 deliberately excludes it.
