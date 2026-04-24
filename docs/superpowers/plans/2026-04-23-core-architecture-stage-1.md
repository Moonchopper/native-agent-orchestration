# Core Architecture PoC — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the retrieval path end-to-end with one scenario. A user with the `observability` plugin installed, running Claude Code inside a fixture `datadog-operations` working tree, asks *"how do I create a log index in Datadog?"* — the agent locates the golden-path content, walks inputs, checks practices, drafts a Terraform file, and emits a PR payload. No measurement hook yet, no additional scenarios yet.

**Architecture:** Vanilla skills-driven (α from the spec, §5). Fixture functional repo and fixture plugin both live in this repo under `fixtures/`, each initialized as its own nested git repo so the detection ladder can exercise real `git` behavior. Scenario is driven by a Bash runner that invokes `claude -p` headlessly. No Python needed for Stage 1.

**Tech Stack:** Claude Code (plugin + skills), Bash (Git Bash-compatible for Windows), git, standard shell tools (`grep`, `jq`), Markdown, Terraform (syntax-only — never applied).

---

## Scope

**In scope for Stage 1:**
- Fixture `datadog-operations` functional repo with `agent/` structure populated for one topic (`create-log-index`).
- Fixture `claude-plugin-observability` plugin with one topic skill (`create-log-index/SKILL.md`).
- Three best-practice files referenced by the topic's `best-practices.md` pointer.
- A headless runner script (`scripts/run-scenario.sh`) that drives Claude Code through the scenario end-to-end.
- Assertions that verify the drafted Terraform file exists, matches an expected shape, and that PR-payload override-rationale behavior is correct when a practice is rejected.
- A stub orthogonal PR-authoring skill — just enough to receive the handoff payload and log it; real PR creation is out of scope for Stage 1.
- Project README with a quickstart.

**Explicitly deferred to Stage 2** (measurement harness plan): instrumentation hook, JSONL metrics, scenario matrix runner, analyzer script.

**Explicitly deferred to Stage 3** (scenario plan, driven by doc 4): additional topics (`create-monitor`, `add-apm-service`, ...), additional practices, the full measurement matrix.

## Precedent documents

- Spec: [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](../specs/2026-04-23-core-architecture-design.md)
- Problem & vision: [`docs/problem-and-vision.md`](../../problem-and-vision.md)
- Prior art: [`docs/prior-art-survey.md`](../../prior-art-survey.md)

## Branching

This plan introduces code, fixtures, and scripts. Execute on a feature branch rather than `main`:

```bash
git checkout -b stage-1-create-log-index
```

Merge to `main` after Stage 1 passes all assertions and the user has reviewed.

## File structure

All paths relative to repository root (`d:/git/native-agent-orchestration/`).

```
fixtures/
├── claude-plugin-observability/          # mock plugin (nested git repo)
│   ├── .claude-plugin/
│   │   └── plugin.json
│   └── skills/
│       ├── create-log-index/
│       │   └── SKILL.md                  # the α orchestration skill
│       └── _pr-handoff/
│           └── SKILL.md                  # stub orthogonal PR skill (Stage 1 only)
│
└── datadog-operations/                   # mock functional repo (nested git repo)
    ├── README.md
    ├── terraform/
    │   └── logs/
    │       └── indexes/
    │           └── .gitkeep
    └── agent/
        ├── golden-paths/
        │   └── create-log-index/
        │       ├── README.md
        │       ├── steps.md
        │       ├── best-practices.md     # pointer file
        │       └── example.tf
        └── best-practices/
            ├── retention-tier-selection.md
            ├── index-naming.md
            └── query-cost-awareness.md

scripts/
├── run-scenario.sh                       # headless runner
├── setup-plugin.sh                       # installs plugin fixture into Claude Code
├── lib/
│   ├── assert.sh                         # assertion helpers
│   └── scenario-util.sh                  # env prep, session dir handling
└── assertions/
    └── create-log-index-local-hit.sh     # scenario-specific assertions

tests/
├── test_assert_helpers.bats              # bats-core tests for scripts/lib/assert.sh
└── test_runner_contract.bats             # tests the runner's flag/output contract

README.md                                 # project README with PoC quickstart
.bats/                                    # bats-core vendored (or installed via package)
```

### File responsibilities

- **`fixtures/claude-plugin-observability/.claude-plugin/plugin.json`** — minimal manifest required by Claude Code.
- **`fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md`** — the whole α orchestration inlined (detect → load → walk → check → draft → handoff). The single most important file in this plan.
- **`fixtures/claude-plugin-observability/skills/_pr-handoff/SKILL.md`** — stub; receives the handoff payload, writes it to a known path, exits. Real PR-authoring is Stage 3/later.
- **`fixtures/datadog-operations/agent/golden-paths/create-log-index/*`** — author-oriented content for the golden path.
- **`fixtures/datadog-operations/agent/best-practices/*.md`** — three practices referenced by the pointer file.
- **`scripts/run-scenario.sh`** — top-level runner; parses `<scenario> <variant>`, prepares env, invokes `claude -p`, captures outputs, runs assertions.
- **`scripts/setup-plugin.sh`** — copies or symlinks the plugin fixture into Claude Code's plugin directory.
- **`scripts/lib/assert.sh`** — `assert_eq`, `assert_file_exists`, `assert_file_contains`, `assert_json_has_key`.
- **`scripts/assertions/create-log-index-local-hit.sh`** — checks the drafted Terraform file exists, matches expected shape, and that the handoff payload is well-formed.
- **`tests/*.bats`** — bats-core tests for the deterministic pieces.

---

## Task 1: Feature-branch setup and directory scaffolding

**Files:**
- Create: `fixtures/`, `scripts/`, `scripts/lib/`, `scripts/assertions/`, `tests/` (empty directories)

- [ ] **Step 1: Create the feature branch**

Run:
```bash
git checkout -b stage-1-create-log-index
```
Expected: `Switched to a new branch 'stage-1-create-log-index'`

- [ ] **Step 2: Create the directory scaffolding**

Run:
```bash
mkdir -p fixtures/claude-plugin-observability/.claude-plugin
mkdir -p fixtures/claude-plugin-observability/skills/create-log-index
mkdir -p fixtures/claude-plugin-observability/skills/_pr-handoff
mkdir -p fixtures/datadog-operations/terraform/logs/indexes
mkdir -p fixtures/datadog-operations/agent/golden-paths/create-log-index
mkdir -p fixtures/datadog-operations/agent/best-practices
mkdir -p scripts/lib
mkdir -p scripts/assertions
mkdir -p tests
touch fixtures/datadog-operations/terraform/logs/indexes/.gitkeep
```
Expected: no output; directories exist.

- [ ] **Step 3: Verify scaffolding**

Run: `find fixtures scripts tests -type d | sort`
Expected: all directories listed above present.

- [ ] **Step 4: Commit scaffolding**

```bash
git add fixtures scripts tests
git commit -m "chore: scaffold stage-1 directories"
```

---

## Task 2: Fixture functional repo — git init and minimal structure

**Files:**
- Create: `fixtures/datadog-operations/README.md`
- Create: `fixtures/datadog-operations/.git/` (via `git init`)

- [ ] **Step 1: Initialize the nested git repo**

Run:
```bash
cd fixtures/datadog-operations
git init
git remote add origin https://github.com/fixture-org/datadog-operations.git
cd ../..
```
Expected: `Initialized empty Git repository in .../fixtures/datadog-operations/.git/`

- [ ] **Step 2: Tell the outer repo to ignore the inner repo's git state**

Append to repo-root `.gitignore`:
```
# Nested fixture git repos — track the working tree, ignore the git state
fixtures/*/.git
```
(Note: we want the *working-tree files* of the fixture repos under version control in the outer repo, but not their internal `.git/` directories. This lets developers see the fixture state without double-tracking git state.)

- [ ] **Step 3: Write the fixture repo's README**

Create `fixtures/datadog-operations/README.md`:
```markdown
# datadog-operations (fixture)

Mock functional repo for the agent-navigable-golden-paths PoC.

Not a real Datadog operations repo. All Terraform, YAML, and other files
here are for PoC exercise only. No changes are ever applied to a real
Datadog account.

## Structure

- `terraform/` — Datadog Terraform skeleton
- `agent/golden-paths/` — agent-oriented golden-path content
- `agent/best-practices/` — cross-cutting practice files

See the PoC root README for how this fixture is used.
```

- [ ] **Step 4: Commit inside the fixture repo**

Run:
```bash
cd fixtures/datadog-operations
git add README.md terraform/logs/indexes/.gitkeep
git commit -m "initial fixture commit"
cd ../..
```

- [ ] **Step 5: Commit the outer repo change**

```bash
git add .gitignore fixtures/datadog-operations/README.md fixtures/datadog-operations/terraform
git commit -m "feat(fixture): initial datadog-operations fixture repo"
```

---

## Task 3: Fixture functional repo — best-practice files

**Files:**
- Create: `fixtures/datadog-operations/agent/best-practices/retention-tier-selection.md`
- Create: `fixtures/datadog-operations/agent/best-practices/index-naming.md`
- Create: `fixtures/datadog-operations/agent/best-practices/query-cost-awareness.md`

- [ ] **Step 1: Author `retention-tier-selection.md`**

Create `fixtures/datadog-operations/agent/best-practices/retention-tier-selection.md`:
```markdown
# Retention Tier Selection

## Principle
Prefer `Flex` retention unless the specific query workload justifies `Standard`.

## Rationale
`Flex` is roughly 100x cheaper than `Standard` for typical read-rarely workloads.
`Standard` incurs ongoing cost regardless of whether the data is queried.

## When Standard is justified
- The index is queried more than ~10 times per day by multiple distinct users.
- The index powers a dashboard with sub-second latency requirements.
- Compliance mandates retention characteristics that Flex cannot meet.

## How to check a draft
Inspect the proposed `retention` block's `tier`. If it is `"Standard"`, ask
the user whether the workload meets any of the "When Standard is justified"
criteria above. If not, suggest switching to `"Flex"`.

If the draft does not involve a retention block (e.g. the golden path is
unrelated to index creation), skip this check.
```

- [ ] **Step 2: Author `index-naming.md`**

Create `fixtures/datadog-operations/agent/best-practices/index-naming.md`:
```markdown
# Index Naming

## Principle
Log index names must follow the pattern `<team>-<env>[-<purpose>]`.

## Rationale
Consistent naming enables cost attribution per team and per environment.
Platform's billing reports depend on this convention.

## How to check a draft
Inspect the proposed `name` field on the `datadog_logs_index` resource.
Assert it matches `^[a-z0-9]+-(prod|stage|dev)(-[a-z0-9-]+)?$`.

If it does not, suggest a correction that includes the team slug and
environment.
```

- [ ] **Step 3: Author `query-cost-awareness.md`**

Create `fixtures/datadog-operations/agent/best-practices/query-cost-awareness.md`:
```markdown
# Query Cost Awareness

## Principle
Avoid creating one monolithic index that covers many services. Prefer
multiple narrow indexes when query patterns differ.

## Rationale
Flex warehouse queries charge proportional to index size *and* scanned
volume. A single 10B-log index that teams query independently costs more
than five 2B-log indexes that each team queries in isolation.

## How to check a draft
Inspect the proposed `filter.query` field. If it is a broad catch-all
(e.g. `*` or covers more than two services), suggest narrowing it or
splitting into multiple indexes.

If the draft does not create a new index (e.g. it updates an existing
one), skip this check.
```

- [ ] **Step 4: Commit inside the fixture repo**

```bash
cd fixtures/datadog-operations
git add agent/best-practices/
git commit -m "feat: add three best-practice files"
cd ../..
```

- [ ] **Step 5: Commit in the outer repo**

```bash
git add fixtures/datadog-operations/agent/best-practices
git commit -m "feat(fixture): seed best-practice files for create-log-index"
```

---

## Task 4: Fixture functional repo — golden-path content for `create-log-index`

**Files:**
- Create: `fixtures/datadog-operations/agent/golden-paths/create-log-index/README.md`
- Create: `fixtures/datadog-operations/agent/golden-paths/create-log-index/steps.md`
- Create: `fixtures/datadog-operations/agent/golden-paths/create-log-index/best-practices.md`
- Create: `fixtures/datadog-operations/agent/golden-paths/create-log-index/example.tf`

- [ ] **Step 1: Author `README.md`**

Create `fixtures/datadog-operations/agent/golden-paths/create-log-index/README.md`:
```markdown
# Create Datadog Log Index

**What:** Provisions a Datadog log index via Terraform.
**Who:** Any product team that needs log retention beyond Live Tail's 15 minutes.
**Effort:** One PR to this repo, reviewed by the Platform team.

## Prerequisites
- This repo (`datadog-operations`) is cloned locally.
- A Jira ticket tracking the work.
- Rough answers to: index name, filter query, retention tier, retention days, daily quota.

## Files you will touch
- `terraform/logs/indexes/<team>.tf` — you will create this file.

## Referenced best practices
See `best-practices.md` in this directory for the list of referenced practices.
```

- [ ] **Step 2: Author `steps.md`**

Create `fixtures/datadog-operations/agent/golden-paths/create-log-index/steps.md`:
```markdown
# Steps

1. **Confirm inputs with the user:**
   - Index name (pattern: `<team>-<env>[-<purpose>]`, e.g. `foobar-prod`)
   - Filter query (e.g. `service:foobar-api env:prod`)
   - Retention tier (`Flex` or `Standard`)
   - Retention days (1–30)
   - Daily log quota (number of logs per day)

2. **Apply the pre-draft best-practice check** using the referenced practices
   in `best-practices.md`. Surface any violations before proceeding to draft.

3. **Create `terraform/logs/indexes/<team>.tf`** using the `example.tf`
   template in this directory. Substitute the confirmed inputs.

4. **Format and validate:**
   - Run `terraform fmt` on the new file.
   - Run `terraform validate` in the `terraform/` directory.
   - Halt on any validation failure.

5. **Apply the post-draft best-practice check** against the drafted file.
   Surface any violations and collect override rationale if the user rejects
   a suggestion.

6. **Show the diff to the user and await approval.**

7. **Prepare the PR payload** containing:
   - The drafted file path and contents
   - A PR body from the template below
   - The list of override rationales, if any

8. **Hand off to the `_pr-handoff` skill** with the payload.

## PR body template

```
## Summary
Creates log index `<name>` under team `<team>` for the `<env>` environment.

## Retention
- Tier: `<tier>`
- Days: `<days>`
- Daily quota: `<quota>`

## Filter
`<filter>`
```
```

- [ ] **Step 3: Author `best-practices.md` (pointer file)**

Create `fixtures/datadog-operations/agent/golden-paths/create-log-index/best-practices.md`:
```markdown
# Best practices to apply for this golden path

For the `create-log-index` golden path, consult these practices. The agent
MUST evaluate each one's "How to check a draft" during both the pre-draft
and post-draft phases.

- [retention-tier-selection](../../best-practices/retention-tier-selection.md) — when Flex beats Standard.
- [index-naming](../../best-practices/index-naming.md) — team-and-environment tagging convention.
- [query-cost-awareness](../../best-practices/query-cost-awareness.md) — avoid monolithic indexes.
```

- [ ] **Step 4: Author `example.tf`**

Create `fixtures/datadog-operations/agent/golden-paths/create-log-index/example.tf`:
```terraform
# Template — substitute the values enclosed in <> with the confirmed inputs.
# This file is copied (with substitutions) to terraform/logs/indexes/<team>.tf.

resource "datadog_logs_index" "<team>" {
  name = "<team>-<env>"

  filter {
    query = "<filter>"
  }

  retention {
    tier = "<tier>"  # "Flex" or "Standard"
    days = <days>
  }

  daily_limit = <quota>
}
```

- [ ] **Step 5: Commit inside the fixture repo**

```bash
cd fixtures/datadog-operations
git add agent/golden-paths/
git commit -m "feat: add create-log-index golden path content"
cd ../..
```

- [ ] **Step 6: Commit in the outer repo**

```bash
git add fixtures/datadog-operations/agent/golden-paths
git commit -m "feat(fixture): seed create-log-index golden path"
```

---

## Task 5: Fixture plugin — manifest and stub PR-handoff skill

**Files:**
- Create: `fixtures/claude-plugin-observability/.claude-plugin/plugin.json`
- Create: `fixtures/claude-plugin-observability/skills/_pr-handoff/SKILL.md`

- [ ] **Step 1: Initialize the plugin's nested git repo**

```bash
cd fixtures/claude-plugin-observability
git init
git remote add origin https://github.com/fixture-org/claude-plugin-observability.git
cd ../..
```

- [ ] **Step 2: Author `plugin.json`**

Create `fixtures/claude-plugin-observability/.claude-plugin/plugin.json`:
```json
{
  "name": "observability",
  "description": "Platform team's Datadog and observability golden paths (fixture for PoC)",
  "version": "0.1.0"
}
```

- [ ] **Step 3: Author the stub PR-handoff skill**

Create `fixtures/claude-plugin-observability/skills/_pr-handoff/SKILL.md`:
````markdown
---
name: _pr-handoff
description: STUB. Receives a PR-authoring payload from a golden-path skill and writes it to a known path for Stage 1 assertions. This is NOT a real PR-authoring implementation; see the spec's execution-model boundary — real PR creation is out of scope for Stage 1.
allowed-tools: Write
---

# PR-handoff stub (Stage 1)

You have been invoked with a handoff payload from a golden-path skill. The
payload contains:

- `drafted_files`: list of `{path, contents}` the golden path drafted
- `pr_body`: the PR description text
- `override_rationale`: list of `{practice_name, rationale}`, possibly empty

Your job in Stage 1 is ONLY to serialize this payload to a known path.
DO NOT attempt to create a git branch, commit, or open a pull request.
Those are Stage 3 responsibilities.

## Step 1 — Serialize

Write the full payload as JSON to `.stage-1-handoff.json` in the functional
repo's working tree root. Use the schema:

```json
{
  "drafted_files": [
    {"path": "terraform/logs/indexes/foobar.tf", "contents": "..."}
  ],
  "pr_body": "## Summary\n...",
  "override_rationale": [
    {"practice_name": "retention-tier-selection", "rationale": "incident response"}
  ]
}
```

## Step 2 — Confirm

Tell the user: "Handoff payload written to `.stage-1-handoff.json`. Stage 1 scenario complete."
````

- [ ] **Step 4: Commit inside the plugin repo**

```bash
cd fixtures/claude-plugin-observability
git add .claude-plugin/plugin.json skills/_pr-handoff/SKILL.md
git commit -m "feat: plugin manifest and stub _pr-handoff skill"
cd ../..
```

- [ ] **Step 5: Commit in the outer repo**

```bash
git add fixtures/claude-plugin-observability
git commit -m "feat(fixture): plugin manifest and stub _pr-handoff"
```

---

## Task 6: Fixture plugin — `create-log-index` skill body (the α orchestration)

**Files:**
- Create: `fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md`

This is the most important artifact in the plan. It inlines the full α orchestration. Authoring happens in one pass because the skill body is a continuous narrative — splitting by step would fragment its meaning.

- [ ] **Step 1: Author the skill body**

Create `fixtures/claude-plugin-observability/skills/create-log-index/SKILL.md`:
````markdown
---
name: create-log-index
description: Use when a user wants to create or provision a Datadog log index — e.g. for retention beyond the 15-minute Live Tail, for routing logs to a dedicated index, or for cost-aware log scoping. Trigger phrases include "create log index", "retain logs for longer than 15 minutes", "make a Datadog index", "provision a log index".
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# Create Datadog Log Index

## Goal
Help the user open a compliant Terraform PR to `fixture-org/datadog-operations`
that provisions a Datadog log index. End state: a PR-handoff payload has been
written via the `_pr-handoff` skill with the drafted file and PR body.

## Execution-model boundary
You author a PR. You do NOT call the Datadog API directly. You do NOT run
`terraform apply`. Human review and the existing CI/CD pipeline handle
deployment. If the user asks you to bypass review or apply directly, decline
and explain this boundary.

## Step 1 — Locate the functional repo

Run the detection ladder, in order. Stop at the first hit.

**1a. CWD match.** Run:
```bash
git rev-parse --show-toplevel 2>/dev/null
git config --get remote.origin.url 2>/dev/null
```
If the toplevel exists AND the origin URL matches `*datadog-operations*`,
set `REPO_ROOT` to the toplevel and skip to Step 2.

**1b. Conventional paths.** For each of these paths, check if it is a valid
clone of the target (i.e. `.git/` exists and origin matches):
- `~/src/fixture-org/datadog-operations`
- `~/code/fixture-org/datadog-operations`
- `~/git/fixture-org/datadog-operations`
- `~/work/fixture-org/datadog-operations`

First match wins.

**1c. Ask the user.** If nothing was found, ask: "I couldn't find a clone
of `fixture-org/datadog-operations` locally. Where is it, or shall I clone
it to `~/src/fixture-org/datadog-operations`?" Wait for the answer before
proceeding.

**Auth preflight.** Before attempting any `gh api` fallback, run:
```bash
gh auth status
```
If it fails, halt and direct the user: "Please run `gh auth login` first."

## Step 2 — Freshness check

On a local hit, run:
```bash
cd "$REPO_ROOT"
git fetch --quiet origin
git rev-list --left-right --count HEAD...origin/main 2>/dev/null
```
Interpret the output: `<ahead>\t<behind>`.

- If behind > 0: show the user "Your clone is <behind> commits behind
  origin/main. Pull, proceed with local, or abort?" Wait for answer.
- If diverged (ahead > 0 AND behind > 0): warn and let the user decide.

## Step 3 — Load golden-path content

Read, in this order:
- `$REPO_ROOT/agent/golden-paths/create-log-index/README.md`
- `$REPO_ROOT/agent/golden-paths/create-log-index/steps.md`
- `$REPO_ROOT/agent/golden-paths/create-log-index/best-practices.md`
- `$REPO_ROOT/agent/golden-paths/create-log-index/example.tf`

Parse `best-practices.md` for the list of referenced practice files. For
each reference, Read the corresponding file under
`$REPO_ROOT/agent/best-practices/`.

## Step 4 — Walk the user through the steps

Follow the numbered steps in `steps.md` verbatim. At Step 1 of `steps.md`
(confirm inputs), collect from the user:

- `team` — team slug (e.g. `foobar`)
- `env` — environment (`prod`, `stage`, `dev`)
- `filter` — Datadog filter query
- `tier` — `Flex` or `Standard`
- `days` — integer 1–30
- `quota` — integer, daily log count

If the user's initial prompt already provides these, confirm them rather
than re-asking. Suggest defaults where reasonable (`tier=Flex`, `days=30`,
etc.) but let the user override.

## Step 5 — Pre-draft best-practice check

For each referenced practice file, apply its `## How to check a draft`
section to the user's confirmed inputs (not yet drafted files). Check the
"skip if" preconditions first; skip practices that don't apply.

For each violation:
1. Summarize: practice name, what is wrong, suggested change.
2. Offer two options: **Accept** (apply the change) or **Reject** (require
   non-empty free-form rationale).
3. The agent records. The agent does not argue. If the rationale is empty,
   re-ask once, then accept any non-blank text.

Collect all accepted rationales into `overrides[]`.

## Step 6 — Draft the change

Create `$REPO_ROOT/terraform/logs/indexes/$team.tf` using `example.tf` as
the template. Substitute `<team>`, `<env>`, `<filter>`, `<tier>`, `<days>`,
`<quota>` with the confirmed values.

Run:
```bash
cd "$REPO_ROOT"
terraform fmt terraform/logs/indexes/$team.tf
```

Run (from `$REPO_ROOT/terraform`):
```bash
terraform validate
```

Halt on any validation failure and surface the error to the user.

## Step 7 — Post-draft best-practice check

Re-run each referenced practice's "How to check" against the drafted file
contents (not the inputs). Handle violations exactly as in Step 5.

## Step 8 — Show diff and await approval

Run:
```bash
cd "$REPO_ROOT"
git diff --no-color terraform/logs/indexes/$team.tf
```

Show the diff to the user. Ask: "Approve and prepare the PR payload, or
iterate further?" Wait for answer.

## Step 9 — Hand off to `_pr-handoff`

Assemble the payload:
- `drafted_files`: `[{path: "terraform/logs/indexes/$team.tf", contents: <contents>}]`
- `pr_body`: fill the PR body template from `steps.md` with the confirmed values
- `override_rationale`: `overrides[]` collected above

Invoke the `_pr-handoff` skill (`/observability:_pr-handoff`) with the
payload. In Stage 1 the handoff skill serializes the payload to a JSON
file for assertion; it does NOT create a PR.

## Error handling

If any step halts (auth failure, validation failure, missing file, etc.),
DO NOT silently continue. Surface the error to the user and stop.
````

- [ ] **Step 2: Commit inside the plugin repo**

```bash
cd fixtures/claude-plugin-observability
git add skills/create-log-index/SKILL.md
git commit -m "feat: create-log-index skill (α orchestration)"
cd ../..
```

- [ ] **Step 3: Commit in the outer repo**

```bash
git add fixtures/claude-plugin-observability/skills/create-log-index
git commit -m "feat(fixture): create-log-index skill body"
```

---

## Task 7: Bats-core test harness and assertion helpers

**Files:**
- Create: `scripts/lib/assert.sh`
- Create: `tests/test_assert_helpers.bats`

We use [bats-core](https://github.com/bats-core/bats-core) (assumed installed; the plan's README documents `npm install -g bats` or equivalent) as the test runner for the shell scripts. TDD proceeds in this task.

- [ ] **Step 1: Write the failing bats test for `assert_eq`**

Create `tests/test_assert_helpers.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load '../scripts/lib/assert.sh'
}

@test "assert_eq succeeds when values match" {
  run assert_eq "hello" "hello"
  [ "$status" -eq 0 ]
}

@test "assert_eq fails with non-zero status when values differ" {
  run assert_eq "hello" "world"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected"* ]]
  [[ "$output" == *"hello"* ]]
  [[ "$output" == *"world"* ]]
}

@test "assert_file_exists succeeds when file exists" {
  tmpfile=$(mktemp)
  run assert_file_exists "$tmpfile"
  [ "$status" -eq 0 ]
  rm -f "$tmpfile"
}

@test "assert_file_exists fails when file is missing" {
  run assert_file_exists "/nonexistent/path/${RANDOM}"
  [ "$status" -ne 0 ]
}

@test "assert_file_contains succeeds when file contains pattern" {
  tmpfile=$(mktemp)
  echo "hello world" > "$tmpfile"
  run assert_file_contains "$tmpfile" "hello"
  [ "$status" -eq 0 ]
  rm -f "$tmpfile"
}

@test "assert_file_contains fails when file missing pattern" {
  tmpfile=$(mktemp)
  echo "hello world" > "$tmpfile"
  run assert_file_contains "$tmpfile" "goodbye"
  [ "$status" -ne 0 ]
  rm -f "$tmpfile"
}

@test "assert_json_has_key succeeds when JSON has the key" {
  run assert_json_has_key '{"foo":"bar"}' "foo"
  [ "$status" -eq 0 ]
}

@test "assert_json_has_key fails when JSON missing key" {
  run assert_json_has_key '{"foo":"bar"}' "baz"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Create the (empty) assert.sh so bats can load it**

Create `scripts/lib/assert.sh`:
```bash
#!/usr/bin/env bash
# Assertion helpers for scenario assertions. Intentionally dependency-light.
```

- [ ] **Step 3: Run bats; confirm all tests fail**

Run:
```bash
bats tests/test_assert_helpers.bats
```
Expected: 8 tests fail (functions not defined).

- [ ] **Step 4: Implement `assert_eq`**

Append to `scripts/lib/assert.sh`:
```bash
assert_eq() {
  local expected="$1"
  local actual="$2"
  if [ "$expected" != "$actual" ]; then
    echo "assert_eq failed: expected '$expected', got '$actual'" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 5: Implement `assert_file_exists`**

Append:
```bash
assert_file_exists() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "assert_file_exists failed: '$path' does not exist" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 6: Implement `assert_file_contains`**

Append:
```bash
assert_file_contains() {
  local path="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$path"; then
    echo "assert_file_contains failed: '$path' does not contain '$pattern'" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 7: Implement `assert_json_has_key`**

Append:
```bash
assert_json_has_key() {
  local json="$1"
  local key="$2"
  if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
    echo "assert_json_has_key failed: JSON does not have key '$key'" >&2
    return 1
  fi
  return 0
}
```

- [ ] **Step 8: Run bats; confirm all tests pass**

Run:
```bash
bats tests/test_assert_helpers.bats
```
Expected: 8 tests pass.

- [ ] **Step 9: Commit**

```bash
git add scripts/lib/assert.sh tests/test_assert_helpers.bats
git commit -m "feat: assertion helpers with bats tests"
```

---

## Task 8: Plugin setup script

**Files:**
- Create: `scripts/setup-plugin.sh`

This script installs the fixture plugin into Claude Code's plugin directory so the skill can be invoked in a session.

- [ ] **Step 1: Author `setup-plugin.sh`**

Create `scripts/setup-plugin.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Copies the fixture plugin into the user's Claude Code plugin directory.
# Idempotent: re-running overwrites the existing installation.

REPO_ROOT=$(git rev-parse --show-toplevel)
SRC="$REPO_ROOT/fixtures/claude-plugin-observability"
DEST_BASE="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
DEST="$DEST_BASE/observability-fixture"

if [ ! -d "$SRC" ]; then
  echo "ERROR: fixture plugin not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST_BASE"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Installed fixture plugin to: $DEST"
echo "Verify Claude Code picks it up: claude /plugin list (or your local equivalent)"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/setup-plugin.sh`

- [ ] **Step 3: Smoke test**

Run:
```bash
./scripts/setup-plugin.sh
ls -la "${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}/observability-fixture"
```
Expected: the fixture plugin's files are copied to the destination.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-plugin.sh
git commit -m "feat: plugin setup script"
```

---

## Task 9: Runner script — TDD the contract

**Files:**
- Create: `tests/test_runner_contract.bats`
- Create: `scripts/run-scenario.sh`

The runner's contract (outward-facing behavior) is TDD-able even without a live LLM. We assert:
- It rejects an unknown scenario/variant with a clear error and exit code 2.
- It accepts the valid `create-log-index local-hit` pair.
- It sets the expected environment variables before invoking.

We use a `DRY_RUN` env var to test the runner's setup phase without actually calling `claude`.

- [ ] **Step 1: Write the failing contract tests**

Create `tests/test_runner_contract.bats`:
```bash
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
```

- [ ] **Step 2: Create an empty runner so bats can invoke it**

Create `scripts/run-scenario.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# Runner — see plan task 9/10.
```

Run: `chmod +x scripts/run-scenario.sh`

- [ ] **Step 3: Run the bats tests; confirm they fail**

Run: `bats tests/test_runner_contract.bats`
Expected: 4 tests fail.

- [ ] **Step 4: Implement the runner's argument contract**

Replace `scripts/run-scenario.sh` contents with:
```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: run-scenario.sh <scenario> <variant>" >&2
  echo "  scenarios: create-log-index" >&2
  echo "  variants : local-hit" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

SCENARIO="$1"
VARIANT="$2"

case "$SCENARIO" in
  create-log-index) ;;
  *)
    echo "ERROR: unknown scenario '$SCENARIO'" >&2
    usage
    ;;
esac

case "$VARIANT" in
  local-hit) ;;
  *)
    echo "ERROR: unknown variant '$VARIANT'" >&2
    usage
    ;;
esac

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN: would run scenario=$SCENARIO variant=$VARIANT"
  exit 0
fi

# Real run — implemented in Task 10.
echo "ERROR: non-dry-run not yet implemented (Task 10)"
exit 1
```

- [ ] **Step 5: Run the bats tests; confirm they pass**

Run: `bats tests/test_runner_contract.bats`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/run-scenario.sh tests/test_runner_contract.bats
git commit -m "feat: runner argument contract (TDD)"
```

---

## Task 10: Runner script — wire in the real invocation

**Files:**
- Modify: `scripts/run-scenario.sh`

- [ ] **Step 1: Add the real-run implementation**

Replace the `# Real run — implemented in Task 10.` section (and the lines below it) in `scripts/run-scenario.sh` with:

```bash
# --- Real run ---

REPO_ROOT=$(git rev-parse --show-toplevel)
FIXTURE_REPO="$REPO_ROOT/fixtures/datadog-operations"
SESSION_DIR=$(mktemp -d)
HANDOFF_FILE="$FIXTURE_REPO/.stage-1-handoff.json"

# Clean any prior handoff artifact so the assertion reflects this run only.
rm -f "$HANDOFF_FILE"

# Canned prompt — provides all inputs up front so the agent can proceed
# without an interactive confirmation loop.
PROMPT=$(cat <<'EOF'
Create a Datadog log index with these parameters:
- team: foobar
- env: prod
- filter: service:foobar-api env:prod
- tier: Flex
- days: 30
- quota: 1000000

Accept best-practice suggestions as-is. When the PR payload is ready,
hand off to the _pr-handoff skill.
EOF
)

# Invoke Claude Code headlessly from the fixture repo's working tree so
# the CWD-detection ladder hits its first branch.
cd "$FIXTURE_REPO"

# `claude -p` runs non-interactively. Settings override is intentionally
# left empty for Stage 1; in Stage 2 we'll pass a settings.json with the
# metric-capture hook configured.
claude -p "$PROMPT" > "$SESSION_DIR/session.out" 2> "$SESSION_DIR/session.err" || {
  echo "ERROR: claude invocation failed" >&2
  echo "--- stderr ---" >&2
  cat "$SESSION_DIR/session.err" >&2
  exit 1
}

echo "Scenario completed. Session artifacts in: $SESSION_DIR"
echo "Handoff file: $HANDOFF_FILE"

# Run scenario-specific assertions.
ASSERTION_SCRIPT="$REPO_ROOT/scripts/assertions/${SCENARIO}-${VARIANT}.sh"
if [ -x "$ASSERTION_SCRIPT" ]; then
  "$ASSERTION_SCRIPT" "$HANDOFF_FILE"
else
  echo "WARN: no assertion script at $ASSERTION_SCRIPT — skipping assertions" >&2
fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/run-scenario.sh
git commit -m "feat: runner real-run invocation"
```

---

## Task 11: Scenario-specific assertion script

**Files:**
- Create: `scripts/assertions/create-log-index-local-hit.sh`

- [ ] **Step 1: Author the assertion script**

Create `scripts/assertions/create-log-index-local-hit.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
source "$REPO_ROOT/scripts/lib/assert.sh"

HANDOFF_FILE="${1:?handoff file path required}"
FIXTURE_REPO="$REPO_ROOT/fixtures/datadog-operations"

# 1. Handoff file exists
assert_file_exists "$HANDOFF_FILE"

# 2. Payload has required top-level keys
PAYLOAD=$(cat "$HANDOFF_FILE")
assert_json_has_key "$PAYLOAD" "drafted_files"
assert_json_has_key "$PAYLOAD" "pr_body"
assert_json_has_key "$PAYLOAD" "override_rationale"

# 3. Drafted file is referenced in the payload
DRAFTED_PATH=$(echo "$PAYLOAD" | jq -r '.drafted_files[0].path')
assert_eq "terraform/logs/indexes/foobar.tf" "$DRAFTED_PATH"

# 4. Drafted file actually exists on disk
assert_file_exists "$FIXTURE_REPO/$DRAFTED_PATH"

# 5. Drafted file contains the expected resource and values
assert_file_contains "$FIXTURE_REPO/$DRAFTED_PATH" 'resource "datadog_logs_index"'
assert_file_contains "$FIXTURE_REPO/$DRAFTED_PATH" 'foobar-prod'
assert_file_contains "$FIXTURE_REPO/$DRAFTED_PATH" 'tier *= *"Flex"'
assert_file_contains "$FIXTURE_REPO/$DRAFTED_PATH" 'days *= *30'

# 6. PR body mentions the index name
PR_BODY=$(echo "$PAYLOAD" | jq -r '.pr_body')
echo "$PR_BODY" | grep -q "foobar-prod"

echo "All assertions passed."
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/assertions/create-log-index-local-hit.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/assertions/create-log-index-local-hit.sh
git commit -m "feat: assertions for create-log-index/local-hit"
```

---

## Task 12: End-to-end verification

**Files:**
- No new files.

- [ ] **Step 1: Install the fixture plugin**

Run: `./scripts/setup-plugin.sh`
Expected: plugin copied to `~/.claude/plugins/observability-fixture/`.

- [ ] **Step 2: Run the scenario**

Run: `./scripts/run-scenario.sh create-log-index local-hit`
Expected: scenario completes; assertions pass; terminal prints "All assertions passed."

- [ ] **Step 3: If assertions fail, iterate**

Common failure modes and their likely cause:
- Missing handoff file → skill body never reached Step 9; read the session stdout/stderr.
- Drafted file missing → skill body failed at Step 6 (fmt/validate); check the skill body's error surface.
- Practice violation unexpectedly surfaced → one of the practice files flagged the canned inputs; adjust the practice's "How to check" or the prompt.

Work the failures in sequence; re-run after each fix.

- [ ] **Step 4: Clean up the fixture repo state between runs**

The runner's real-run section deletes `.stage-1-handoff.json` before each run, but the drafted `terraform/logs/indexes/foobar.tf` persists. Between runs, either:
```bash
cd fixtures/datadog-operations
git clean -fd
git checkout .
cd ../..
```
or delete the specific drafted file. Document this in the README.

- [ ] **Step 5: Commit any skill/practice corrections made during iteration**

Use the fixture repo's commit process from Tasks 3–6.

---

## Task 13: Root README and PoC quickstart

**Files:**
- Create: `README.md` (at repo root)

- [ ] **Step 1: Author the README**

Create `README.md`:
````markdown
# native-agent-orchestration — PoC

Exploratory proof-of-concept for **agent-navigable golden paths**. A platform
team ships a Claude Code plugin that points a user's agent at a GitHub-hosted
functional repo containing colocated golden-path markdown. The agent retrieves,
walks the user through the steps, and opens a compliant PR.

See [`docs/problem-and-vision.md`](docs/problem-and-vision.md) for the motivation
and [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](docs/superpowers/specs/2026-04-23-core-architecture-design.md)
for the architecture.

## Status

- Stage 1: single scenario (`create-log-index`) end-to-end — **this PoC**.
- Stage 2 (planned): measurement harness.
- Stage 3 (planned): additional scenarios per `docs/<reference-scenarios>.md`.

## Prerequisites

- Claude Code CLI (`claude --version` should work)
- `gh` CLI, authenticated (`gh auth status`)
- `git`
- `jq`
- `bats-core` (e.g. `npm install -g bats` or via your package manager)
- `terraform` CLI (for `fmt` and `validate` during the scenario)

## Quickstart

```bash
# 1. Install the fixture plugin into Claude Code
./scripts/setup-plugin.sh

# 2. Run the scenario
./scripts/run-scenario.sh create-log-index local-hit
```

Expected final line: `All assertions passed.`

## Layout

- `docs/` — research docs and the architecture spec.
- `fixtures/` — mock plugin and mock functional repo.
- `scripts/` — runner, setup, assertions, helpers.
- `tests/` — bats-core tests for the deterministic pieces.

## What this PoC does NOT do

- It does NOT call the Datadog API or any vendor API.
- It does NOT run `terraform apply`.
- It does NOT open a real GitHub pull request (the handoff is stubbed).

See §3 of the architecture spec for the execution-model boundary.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: repo README with PoC quickstart"
```

---

## Task 14: Stage-1 handoff artifact

**Files:**
- Create: `docs/stage-1-notes.md`

Summarizes what Stage 1 produced and what the next plan (Stage 2) will need.

- [ ] **Step 1: Author the handoff notes**

Create `docs/stage-1-notes.md`:
```markdown
# Stage 1 Notes — handoff to Stage 2

## What Stage 1 built
- One end-to-end scenario working: `create-log-index / local-hit`.
- Fixture plugin with one orchestration skill and one stub handoff skill.
- Fixture functional repo with one golden path and three practice files.
- Runner + assertion infrastructure, tested with bats.

## What Stage 2 needs from Stage 1
- Runner script (`scripts/run-scenario.sh`) is the integration point for the
  measurement hook. Stage 2 will set `AGENT_ORCH_SCENARIO` and
  `AGENT_ORCH_VARIANT` from inside the runner before invoking `claude -p`.
- Scenario/variant tuples need to become a table so Stage 2 can iterate.
- `.stage-1-handoff.json` is a per-run artifact; Stage 2 will need to capture
  it *per run iteration* (not overwrite) when measuring P50/P95 across N runs.

## Decisions deferred
- Exact Claude Code hook event name — to be confirmed during Stage 2 setup
  against current Claude Code docs.
- Token-budget tolerance — set after the first measurement pass.

## Carry-forward risks
- The `_pr-handoff` stub must eventually be replaced by a real PR-authoring
  skill. That belongs to Stage 3 or a separate "PR-authoring skill" track,
  not Stage 2.
- Detection ladder is only exercised on the CWD-match branch in Stage 1.
  The `remote-fallback` and `cwd-shortcut` variants need fixtures for
  "no local clone" and "in a totally unrelated repo" scenarios — Stage 2
  or Stage 3.
```

- [ ] **Step 2: Commit**

```bash
git add docs/stage-1-notes.md
git commit -m "docs: stage-1 handoff notes for future plans"
```

---

## Task 15: Merge Stage 1 to `main`

- [ ] **Step 1: Run the full test suite one final time**

Run:
```bash
bats tests/
./scripts/run-scenario.sh create-log-index local-hit
```
Expected: all tests pass; scenario prints "All assertions passed."

- [ ] **Step 2: Review the branch**

Run: `git log --oneline main..HEAD`
Expected: clear, atomic commits that tell the Stage 1 story.

- [ ] **Step 3: Merge to main (fast-forward)**

```bash
git checkout main
git merge --ff-only stage-1-create-log-index
```

- [ ] **Step 4: Delete the feature branch**

```bash
git branch -d stage-1-create-log-index
```

- [ ] **Step 5: (Optional) Push to remote**

If a remote is configured, `git push`. If not, this PoC is local-only; skip.

---

## Open implementation questions (resolve as encountered)

- **Claude Code plugin install path on Windows.** `scripts/setup-plugin.sh` assumes `~/.claude/plugins/`. If Claude Code uses a different layout on the execution environment, adjust the `DEST_BASE` logic and document it in the README.
- **`claude -p` stdin/stdout conventions.** If the headless mode expects prompts via stdin rather than CLI arg, adjust the runner's invocation.
- **Terraform availability.** If the execution environment lacks Terraform, the skill body's `terraform fmt`/`validate` calls will fail. Stage 1 halts loudly on this; flag it in the README as a prerequisite.
- **Fixture repo origin URLs are fictional** (`fixture-org/...`). `git fetch` against them will fail. The skill body tolerates fetch failure gracefully via the `2>/dev/null` guards, but if you want to test the freshness prompt, change the origin temporarily or mock it.

---

## Done when

- All 15 tasks' checkboxes are checked.
- `bats tests/` passes.
- `./scripts/run-scenario.sh create-log-index local-hit` ends with "All assertions passed."
- The `stage-1-create-log-index` branch is merged to `main`.
- `docs/stage-1-notes.md` exists and is up to date.
