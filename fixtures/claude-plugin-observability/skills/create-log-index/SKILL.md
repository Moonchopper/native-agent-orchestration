---
name: create-log-index
description: Use when a user wants to create or provision a Datadog log index — e.g. for retention beyond the 15-minute Live Tail, for routing logs to a dedicated index, or for cost-aware log scoping. Trigger phrases include "create log index", "retain logs for longer than 15 minutes", "make a Datadog index", "provision a log index".
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# Create Datadog Log Index

## Goal
Help the user open a compliant Terraform PR to `fixture-org/datadog-operations`
that provisions a Datadog log index. End state: a PR-handoff payload has been
written via the `pr-handoff` skill with the drafted file and PR body.

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

## Step 9 — Hand off to `pr-handoff`

Assemble the payload:
- `drafted_files`: `[{path: "terraform/logs/indexes/$team.tf", contents: <contents>}]`
- `pr_body`: fill the PR body template from `steps.md` with the confirmed values
- `override_rationale`: `overrides[]` collected above

Invoke the `pr-handoff` skill (`/observability:pr-handoff`) with the
payload. In Stage 1 the handoff skill serializes the payload to a JSON
file for assertion; it does NOT create a PR.

## Error handling

If any step halts (auth failure, validation failure, missing file, etc.),
DO NOT silently continue. Surface the error to the user and stop.
