# Core Architecture (PoC) — Design

**Status:** Design, approved through brainstorming on 2026-04-23.
**Precedents:** [`docs/problem-and-vision.md`](../../problem-and-vision.md), [`docs/prior-art-survey.md`](../../prior-art-survey.md).
**Successor:** reference scenario walkthrough (doc 4) and implementation plan, both pending.
**Anti-precedent:** [`docs/future-state-documents-as-code.md`](../../future-state-documents-as-code.md) — explicitly out of scope here.

---

## 1. Summary

This spec defines the proof-of-concept architecture for agent-navigable golden paths at a company. A Platform team ships a Claude Code plugin (the example uses `observability`) that points a user's agent at a separately versioned, GitHub-hosted functional repo (the example uses `datadog-operations`). When the user asks a natural-language question — *"how do I create a log index in Datadog?"* — the agent discovers the relevant golden path, retrieves its agent-oriented markdown from the functional repo, walks the user through the steps, checks the draft against referenced best practices, and hands off to an orthogonal PR-authoring skill to open a compliant pull request.

The PoC validates three things:

1. That a skill-driven, colocated-knowledge architecture is expressive enough to cover a realistic golden path end to end.
2. That the token cost of the retrieval path is bounded and predictable enough to reason about viability.
3. That the platform-team authoring surface (markdown in the functional repo) is tolerable for the people who would actually own this content.

## 2. Context

The motivation, Team Foobar narrative, and success criteria are captured in [`docs/problem-and-vision.md`](../../problem-and-vision.md). The survey of overlapping patterns — Claude Code Skills, Claude Code Plugins, MCP, GitHub Spec-Kit, Backstage, `llms.txt`, Cursor rules — is in [`docs/prior-art-survey.md`](../../prior-art-survey.md). The longer-arc vision for a plain-language reconciler is in [`docs/future-state-documents-as-code.md`](../../future-state-documents-as-code.md) and is deliberately deferred.

This spec assumes the reader has read at least `problem-and-vision.md`.

## 3. Execution-model boundary

The agent's terminus is a **pull request ready for human review**. It does not:

- Call vendor APIs directly (no Datadog, AWS, Snowflake, etc.)
- Run `terraform apply`
- Mutate any production system

Existing CI/CD and Platform-team review remain the deployment path. This PoC changes only how the PR gets authored; it does not change how PRs are applied. The "agent calls vendor APIs directly" pattern belongs to the future-state reconciler and is explicitly out of scope for this design.

Every later section in this document should be read with this boundary in mind.

## 4. Locked principles

These principles were established during brainstorming and constrain every design decision below.

| Principle | What it means |
|---|---|
| **Knowledge colocates with function** | Agent-oriented markdown lives in the functional repo where the work actually happens (`datadog-operations`), not in a separate knowledge repo. |
| **Local-first retrieval, remote fallback** | The agent prefers a locally cloned copy of the functional repo; falls back to `gh api` only for read-only discovery. Execution requires a working tree. |
| **Plugin is routing-only** | The plugin hosts skills and orchestration, not content. Content lives in the functional repo. |
| **Skills are self-contained** | Each topic ships as its own SKILL.md with full orchestration inlined (architecture α). |
| **Orthogonal concerns live in separate skills** | Cross-cutting conventions (Jira-prefixed commits, PR body format) are owned by a separate, orthogonal skill — not by the `observability` plugin. |
| **GitHub-only retrieval (PoC)** | Plugin, functional repo, and any fixtures are all hosted in GitHub. No Confluence, wikis, or vendor docs during the PoC. |
| **Topics in scope have a functional home** | Questions whose answer lives in an infra or service repo. Topics with no functional home (e.g. *"who owns OpenShift?"*) are deferred. |

## 5. Approach: α (vanilla skills-driven)

The PoC implements the **α** approach from brainstorming:

- Every topic skill is a self-contained markdown (one `SKILL.md` per golden path).
- Each skill body inlines: local-clone detection, freshness check, content load, step orchestration, practice checks, and PR hand-off.
- No shared `_lib/`, no bundled MCP server.

**DRY cost is accepted.** Common orchestration (locate-repo, freshness, PR hand-off) will be near-identical across topic skills. This is deliberate — we trade duplication for simplicity at PoC scale (≤ ~5 topics).

**Refactor path documented, not taken.** When topic count exceeds ~5–10, or a governance case calls for declarative audit, the natural evolution is:

- **β: skills + shared helpers.** Extract common orchestration into `_lib/find-clone.md`, `_lib/check-freshness.md`, etc. Topic skills direct the agent to read helpers first.
- **γ: skills + bundled MCP server.** Orchestration becomes typed MCP tool calls; clean separation, unit-testable; higher operational complexity.

The PoC's per-topic skill bodies will contain the exact routing data β would lift — this is why the refactor is mechanical.

## 6. Architecture at a glance

Three locations, all in GitHub.

```
┌────────────────────────┐   ┌─────────────────────────────┐   ┌──────────────────────────────────┐
│   User's machine       │   │   Plugin repo (GitHub)      │   │   Functional repo (GitHub)       │
│                        │   │                             │   │                                  │
│   Claude Code IDE      │   │   org/claude-plugin-        │   │   org/datadog-operations         │
│   + observability      │   │     observability           │   │                                  │
│     plugin installed   │   │                             │   │   ├── terraform/…                │
│                        │   │   ├── .claude-plugin/       │   │   └── agent/                     │
│   Working tree may or  │   │   │     plugin.json         │   │       ├── golden-paths/          │
│   may not contain a    │   │   └── skills/               │   │       │     ├── create-log-     │
│   clone of the         │   │         ├── create-log-     │   │       │     │     index/        │
│   functional repo.     │   │         │     index/        │   │       │     │     ├── README.md │
│                        │   │         │     SKILL.md      │   │       │     │     ├── steps.md  │
│                        │   │         ├── create-monitor/ │   │       │     │     ├── best-     │
│                        │   │         │     SKILL.md      │   │       │     │     │   practices │
│                        │   │         └── add-apm-service/│   │       │     │     │   .md       │
│                        │   │                SKILL.md     │   │       │     │     └── example.tf│
│                        │   │                             │   │       │     └── …               │
│                        │   │                             │   │       └── best-practices/       │
│                        │   │                             │   │             ├── query-cost-     │
│                        │   │                             │   │             │   awareness.md    │
│                        │   │                             │   │             ├── index-naming.md │
│                        │   │                             │   │             └── retention-tier- │
│                        │   │                             │   │                 selection.md    │
└────────────────────────┘   └─────────────────────────────┘   └──────────────────────────────────┘
```

**Runtime flow in one sentence:** user asks → skill matches → skill body directs the agent to find the local clone of the functional repo (or fall back to `gh api`), read the colocated golden-path content, walk the user through the steps, check against referenced best practices, and hand the drafted changes to the orthogonal PR-authoring skill.

## 7. Components — file contracts

All file contracts are described as **expected shape**, not final content. Real content will be authored in the fixture repos as part of implementation.

### 7.1 Plugin manifest

**Path:** `.claude-plugin/plugin.json` (in the plugin repo)

**Purpose:** minimal manifest required for Claude Code to load the plugin.

**Shape:**

```json
{
  "name": "observability",
  "description": "Platform team's Datadog and observability golden paths",
  "version": "0.1.0"
}
```

### 7.2 Topic skill

**Path:** `skills/<topic>/SKILL.md` (in the plugin repo)

**Purpose:** one skill per golden path. Self-contained orchestration (architecture α). Frontmatter drives intent match; body drives the end-to-end flow.

**Required frontmatter fields:** `name`, `description`.
**Recommended frontmatter fields:** `allowed-tools` (pre-approve `Bash(git …)`, `Bash(gh …)`, `Read`, `Glob`, `Edit`, `Write`).

**Body sections (order matters):**

1. **Goal** — what this skill achieves in one sentence.
2. **Locate the functional repo** — clone-detection ladder (see §9).
3. **Freshness check** — `git fetch` + ahead/behind comparison (see §9).
4. **Load golden-path content** — explicit `Read()` calls against `agent/golden-paths/<topic>/` and dereferencing of `best-practices.md` into `agent/best-practices/*.md`.
5. **Walk the user through the steps** — pauses at user checkpoints (see §8).
6. **Pre-draft practice check** — run practice "How to check" against user inputs.
7. **Draft changes** — create/edit files in working tree using `example.*` as a template.
8. **Post-draft practice check** — run practice "How to check" against drafted files.
9. **Show diff and await approval.**
10. **Hand off to PR-authoring skill** — pass drafted changes + PR body + any override rationale.

### 7.3 Golden-path directory

**Path:** `agent/golden-paths/<topic>/` (in the functional repo)

**Purpose:** everything the agent needs to execute this specific golden path.

**Required files:**

| File | Purpose |
|---|---|
| `README.md` | What and why; prerequisites; files that will be touched |
| `steps.md` | Ordered, actionable steps for the agent to walk through |
| `best-practices.md` | Pointer file listing which `../../best-practices/*.md` apply |
| `example.<ext>` | Reference implementation template the agent adapts. Extension varies by golden-path domain (e.g. `example.tf`) |

### 7.4 Best-practice file

**Path:** `agent/best-practices/<practice-name>.md` (in the functional repo)

**Purpose:** one practice per file, self-contained. Written so an agent can both *explain* it to the user and *check* it against a draft.

**Required sections:**

- `## Principle` — the rule in one sentence.
- `## Rationale` — why it matters.
- `## When <exception> is justified` — legitimate carve-outs, if any.
- `## How to check a draft` — narrative instructions the agent applies, optionally containing a shell command for deterministic checking.

### 7.5 Directory naming

The top-level directory name is `agent/` (non-hidden). Rationale: this content is load-bearing and deserves to be visible during normal repo browsing; `.agent/` connotes user-local / tool-local state, which this is not.

## 8. Runtime flow — end-to-end

Twelve steps from user question to opened PR. Colors from the brainstorming timeline are preserved here as labels.

| # | Actor | Step |
|---|---|---|
| 1 | **User** | Asks a natural-language question in the IDE. |
| 2 | **Agent + skill-picker** | Matches the question against topic-skill `description` frontmatters (already in context). Winning skill body is pulled into the conversation. |
| 3 | **Fetch** | Locate functional repo via the detection ladder (§9). Outcomes: local hit, local miss→clone, local miss→gh api (read-only). |
| 4 | **Fetch** | Freshness check on local hit: `git fetch`; compare HEAD to `origin/<default-branch>`. If behind, prompt user (pull / proceed / abort). |
| 5 | **Fetch** *(hot token spot)* | Load golden-path content: `agent/golden-paths/<topic>/{README,steps,best-practices}.md` plus `example.*`. Parse `best-practices.md` pointer list; load referenced `agent/best-practices/*.md`. |
| 6 | **User checkpoint** | Per `steps.md`: confirm inputs (index name, filter, retention tier, window, quota). Agent may suggest defaults. |
| 7 | **Agent** | Pre-draft practice check: for each referenced practice, apply its "How to check" against user inputs. |
| 8 | **Agent** | Draft changes in the working tree using `example.*` as a template. Run domain-appropriate validation (`terraform fmt`, `terraform validate`). |
| 9 | **Agent** | Post-draft practice check: re-apply each practice's "How to check" against the drafted files. |
| 10 | **User checkpoint** | Show diff. User approves or iterates. |
| 11 | **Hand-off** | Invoke the orthogonal PR-authoring skill with `{drafted_files, pr_body, override_rationale[]}`. |
| 12 | **Agent** | Reports the PR URL. User reviews in GitHub via the normal Platform-team workflow. |

**User checkpoints: two, not zero and not five.** Steps 6 (confirm inputs) and 10 (review diff). No step 11 approval — that belongs to the PR-authoring skill's own conventions.

**Hot token spot: step 5.** Everything read in step 5 stays in context for the rest of the invocation. The measurement plan (§11) targets this explicitly.

**Practice checks run twice — pre and post.** The practice's "How to check" prose is identical for both passes; the agent applies it to whatever artifact is current (inputs, then drafted files).

**Practice checks use inspection, not validation.** The default is LLM narrative judgment over the practice's "How to check" prose. A practice may include a shell command for deterministic checking when judgment is insufficient; this is an escape hatch, not the default.

## 9. Local-clone detection and freshness

### 9.1 Detection ladder

Checked in order; first hit wins.

1. **CWD match.** `git rev-parse --show-toplevel` succeeds **and** `git config --get remote.origin.url` matches the target. This is the happy-path shortcut: the user is already in the functional repo.
2. **Conventional paths.** Check, in order: `~/src/<org>/<repo>`, `~/code/<org>/<repo>`, `~/git/<org>/<repo>`, `~/work/<org>/<repo>`. First valid clone wins.
3. **Plugin-configured path prefix.** Claude Code `settings.json` may pin a project-specific root (e.g. `observability.clonePath = "~/work/platform"`). When set, overrides step 2.
4. **Ask the user.** No silent guessing — surface: *"I don't know where your clone of `org/repo` is. Path? Or shall I clone it?"*

### 9.2 Freshness check

On local hit only:

- `git fetch` (refs only — cheap).
- `git rev-list --left-right --count HEAD...origin/<default-branch>` for ahead / behind counts.
- **Behind:** show count and a 1-line summary of the top N remote commits; offer (a) pull, (b) proceed with local state, (c) abort. Default is to ask.
- **Diverged** (local has unpushed commits on default branch): warn; user decides. Unusual in practice.

### 9.3 Remote fallback

`gh api` is sufficient for **read-only discovery** (*"show me what this golden path expects"*). It is **not sufficient for execution** — drafting changes requires a working tree.

- If user intent is read: `gh api` is enough.
- If user intent is execute and no clone exists: the agent **offers to clone**. Default path: `~/src/<org>/<repo>`. Configurable.

### 9.4 Auth preflight

First thing after step 3 of the runtime flow: `gh auth status`. If not authenticated, halt and direct the user to `gh auth login`. Private repos are the norm for platform teams; fail fast rather than produce confusing 404s.

## 10. Best-practice violation detection

### 10.1 The mechanism

Each `agent/best-practices/<practice>.md` file is self-executing — its `## How to check a draft` section is prose the agent follows. No separate rule engine. No custom DSL.

**Example (abbreviated):**

```markdown
## How to check a draft
Inspect the proposed `retention_tier`. If it is `Standard`,
ask the user whether the workload meets the criteria in
"When Standard is justified" above. If not, suggest `Flex`.
```

### 10.2 When checks run

Pre-draft (step 7) and post-draft (step 9). The practice file's "How to check" prose is identical across the two passes; the agent applies it to whatever artifact is current.

### 10.3 Skipping irrelevant practices

A practice file may begin its "How to check" with a precondition — *"Skip this check if the golden path does not involve log queries."* The agent evaluates the precondition first; irrelevant practices are no-ops. This bounds cost when a golden path's `best-practices.md` references many practices, only some of which apply to a given draft.

### 10.4 Violation surface and override handling

For each triggered violation, the agent surfaces: **practice name**, **what is wrong**, **suggested change**. The user has exactly two options:

- **Accept** — the agent applies the suggested change and re-runs the post-draft check.
- **Reject (with rationale)** — the user supplies a non-empty free-form rationale. The agent records it and proceeds.

**The agent records. It does not argue.** The rationale field is an audit artifact, not a debate surface. Once the user has given one, the override stands. A human Platform reviewer can challenge the rationale in PR review — that is the appropriate escalation surface.

The only floor is non-empty: if the user submits blank, the agent re-asks once, then accepts any non-blank text including terse answers like *"one-off for incident response."* The goal is to require *thought*, not a particular quality of answer.

### 10.5 PR surface for overrides

All accepted override rationales are included in the PR body under a `## Best-practice overrides` heading. Human reviewers see explicit, surfaced disagreements — never silent ones.

### 10.6 Deterministic escape hatch

When narrative judgment is insufficient, a practice's "How to check" section may prescribe a shell command:

```markdown
## How to check a draft
Run `terraform plan -target=<resource> -no-color | grep retention_days`.
Assert the value is ≤ 30.
```

The agent runs the command via its pre-approved `Bash` tool and interprets pass/fail. This is used sparingly — default stays narrative.

### 10.7 Cost bound

With N applicable practices and both passes, practice checking is roughly `2N` agent reasoning turns per invocation. At PoC scale (N ≤ 5) this is tolerable. Measurement (§11) exposes whether it remains tolerable as topics grow; at larger N, practice bundling (one file with multiple rules) is the natural response.

## 11. Measurement

Token cost is a **first-class PoC deliverable**, not a post-hoc nice-to-have. Without measurement, viability is unanswerable.

### 11.1 Instrumentation

A Claude Code hook (concrete event selected during implementation — `Stop` or equivalent) fires on each turn, reads the API response's token metadata, and appends a JSONL line to `~/.local/share/agent-orch/metrics/<session_id>.jsonl`.

### 11.2 Log schema

One line per turn:

```json
{
  "ts": "2026-04-23T19:45:12Z",
  "session_id": "abc123",
  "scenario": "create-log-index",
  "variant": "local-hit",
  "run_ix": 3,
  "turn": 7,
  "model": "claude-opus-4-7",
  "tokens_in": 4821,
  "tokens_out": 612,
  "cache_read": 3900,
  "cache_creation": 0,
  "duration_ms": 2140,
  "skill_active": "observability:create-log-index"
}
```

### 11.3 Scenario tagging

Each scenario run sets `AGENT_ORCH_SCENARIO=<name>` and `AGENT_ORCH_VARIANT=<variant>` as environment variables before the Claude Code session starts. The hook reads them and stamps each line. A session without the tags still logs, but aggregates into an `untagged` bucket.

### 11.4 Isolation

Runs happen in **fresh Claude Code sessions** — no context carryover, no compaction noise. A wrapper script (`scripts/run-benchmarks.sh`) spawns a session per run.

### 11.5 Scenario matrix

Illustrative shape — final list lives in doc 4.

| Scenario | local-hit | remote-fallback | cwd-shortcut |
|---|---|---|---|
| `baseline` (plugin installed, off-topic question) | N=5 | — | — |
| `create-log-index` | N=5 | N=5 | N=5 |
| `create-monitor` | N=5 | — | — |

### 11.6 Analysis dimensions

- **Baseline cost** — tokens consumed just by having the plugin installed and asking an off-topic question. Floor of the system.
- **Per-scenario total** — sum of `tokens_in + tokens_out` across all turns of one invocation. Headline number.
- **Per-scenario variance** — P50 / P95 across N runs. Exposes whether the cost model is stable or the LLM's behavior varies wildly.
- **Variant delta** — `local-hit` vs `remote-fallback` vs `cwd-shortcut`. Tells us whether local-first is worth its complexity.
- **Hot-spot turns** — which turn of a scenario accounts for the most tokens. Expectation: step 5 (load golden-path content).
- **Cache effectiveness** — `cache_read / tokens_in` ratio. Shows whether prompt-caching is pulling its weight.

### 11.7 Acceptance

A single command — `scripts/run-benchmarks.sh` — runs the full matrix in fresh sessions and emits a summary table. Implementation of the script lands in the implementation plan.

### 11.8 Deliberately not measured in the PoC

- **Wall-clock from the user's perspective.** Per-turn `duration_ms` is captured, but editor-level latency and tool-call time are not benchmarked end-to-end.
- **Quality of the opened PR.** A correctness test, not a cost test; handled via scenario assertions in doc 4.
- **Real vendor-API traffic.** Fixtures only; the reference `datadog-operations` is a mock repo. This is a statement about the *benchmark environment*, **not** about the agent's production behavior — which is PR-only by design (§3).

## 12. Error handling

The overarching theme: **fail loudly, never guess, never silently mutate.**

| Failure | Response |
|---|---|
| No local clone found and user declines to clone | Halt with an explanation. No silent `gh api` fallback when intent is *execute*. |
| `gh auth status` fails | Halt; direct user to `gh auth login`. |
| Target repo renamed or missing | Surface the actual error; do not guess a new location. |
| Clone detected but `remote.origin` points to a fork | Detect `remote.upstream` if set; otherwise warn and ask. |
| Multiple local clones of the target repo | Prefer CWD; otherwise first-found in the detection ladder. |
| Referenced practice file missing from `agent/best-practices/` | Halt on that practice; report the broken reference; continue with remaining practices. |
| Domain validation fails (e.g. `terraform validate`) | Halt; show the validation error; do not push through. |
| User's working tree is dirty | Warn; offer to stash or abort; never silently commit on top. |
| Draft would overwrite an existing un-reviewed file | Warn; diff preview; require explicit confirmation. |
| Freshness check shows local behind origin | Prompt (pull / proceed / abort); no silent default. |

## 13. Testing and fixtures

### 13.1 Fixture repos (all in GitHub)

- `org/claude-plugin-observability` — the mock plugin. ~3 topic skills.
- `org/datadog-operations` — the mock functional repo. Contains `agent/golden-paths/`, `agent/best-practices/`, and a minimal Terraform tree.

Fixture content is grounded in publicly documented Datadog behavior — Flex vs. Standard retention, index tagging conventions, quota semantics — so correctness assertions are meaningful and not authored out of whole cloth. This matches the fixtures clause already established in [`docs/problem-and-vision.md`](../../problem-and-vision.md).

### 13.2 Scenarios are the tests

Each reference scenario in doc 4 is an end-to-end test. `scripts/run-benchmarks.sh` is simultaneously the test runner and the measurement runner (§11.7).

### 13.3 Passing criteria per scenario

- Scenario completes without halting on an error not deliberately part of the scenario.
- Drafted artifacts match an expected shape: specific file path, specific resource type, acceptable value range.
- Practice-override rationale appears in the PR body when and only when the user overrode a practice.
- Token usage falls within the scenario's declared budget (tolerance set after a first measurement pass).

### 13.4 No unit tests of skill body prose

LLM-driven orchestration is not productively unit-tested. End-to-end scenarios are the contract. The deterministic escape hatches in practice files (§10.6) *can* be unit-tested where present, since they are shell commands.

## 14. Out of scope

Explicit non-goals for this PoC:

- **Semantic / embeddings-based retrieval.** Ladder-based discovery only.
- **Topics without a functional repo home.** Preserved from problem-and-vision.
- **The Documents-as-Code reconciler.** Future-state vision; not built here.
- **Non-Claude-Code agents.** Cursor, Copilot, Codex portability is a future concern.
- **Routing refactor to β or γ.** α with a documented refactor path, not β or γ directly.
- **Auth flows beyond `gh auth login`.** No SAML, OIDC repo-access, or other SSO handling.
- **Cost-optimization passes.** Measured in the PoC; optimized in a follow-up.
- **Real vendor-API integration.** Terminus is PR; see §3.

## 15. Open questions (resolved in the implementation plan, not here)

- **Exact Claude Code hook event.** `Stop` is the current candidate for per-turn token capture; the implementation plan confirms via Claude Code documentation and an integration smoke-test.
- **Concrete tolerance for token-budget assertions.** Set after the first end-to-end measurement pass on one scenario; not guessed in advance.
- **Default clone path when the agent offers to clone.** `~/src/<org>/<repo>` is the current default, but worth a one-line Claude Code `settings.json` knob for teams that have a convention. (See also §9.1 step 3.)
- **Shallow vs. full clones when the agent clones on the user's behalf.** Full clone is the default for PoC (blame/history-preserving); shallow is a future optimization.

**Doc 4 (reference scenario walkthrough) is a *soft* prerequisite for the implementation plan, not a hard one.** The plan can begin with a single placeholder scenario (`create-log-index`, the worked example already threaded through this spec) and expand the scenario matrix (§11.5) as doc 4 formalizes the others. The architectural work — plugin scaffolding, fixture repo shape, detection ladder, measurement hook — does not depend on the final scenario list.

## 16. Dependencies and references

- Claude Code plugin and skill conventions — see [`docs/prior-art-survey.md`](../../prior-art-survey.md) §4.
- Model Context Protocol — considered and deferred (architecture γ); see [`docs/prior-art-survey.md`](../../prior-art-survey.md) §4.
- `gh` CLI — required for auth preflight and remote fallback.
- Reference scenario walkthrough (doc 4) — pending; will name the specific scenarios in §11.5's matrix and §13.3's passing criteria.
- Implementation plan — follows this spec via `writing-plans`.
