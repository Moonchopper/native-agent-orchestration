# Prior Art Survey

A categorized scan of existing patterns and tools that overlap with the proposed design (see `problem-and-vision.md`). The goal is to answer: **is this idea already solved, partially solved, or novel?**

The doc is organized as a shallow sweep; a subset of entries have been expanded to pass-2 depth based on their architectural relevance to the PoC.

### Conventions used in this document

- **Mention-only** — the entry is noted for completeness but deliberately not analyzed, because it is close enough to a sibling entry (or tangential enough) that expanding on it would add length without adding insight. Mention-only entries are *not* candidates for pass-2 expansion unless explicitly promoted out of that bucket.
- **Gap** — a capability the proposed design needs that the surveyed tool does not provide.
- **★ Pass-2 deep dive** — entry has been expanded beyond the one-paragraph shallow-sweep treatment. See the "Pass-2 coverage" section at the end of the document for what was and was not expanded, and why.

---

## 1. Internal Developer Platforms (IDPs)

### Backstage
Open-source developer portal from Spotify. Catalogs services, APIs, and resources via YAML descriptors checked into repos; offers "Software Templates" that scaffold new services with compliant defaults. Relevant because templates are exactly the "golden path" pattern — the user picks a template, Backstage runs a scaffolder. **Gap:** templates are for *creating* things, less so for *amending* existing infrastructure (adding a Datadog index to an existing account). Also: the interface is a web portal, not a coding agent.

### Port
Commercial IDP with similar primitives to Backstage (catalog + scorecards + self-service actions). Strong "scorecard" concept — measurable best-practice compliance per entity. **Gap:** web UI, not agent-native.

### Cortex
Commercial IDP focused on scorecards and service ownership. Useful mental model for "how does the agent know a PR violates best practice," but surfaced as dashboards rather than agent guidance.

### OpsLevel, Roadie
Adjacent commercial IDPs. Mention-only for this sweep.

---

## 2. Agent-addressable documentation conventions

### `llms.txt`
Proposed informal standard (Jeremy Howard, 2024) for a site to expose an LLM-friendly index at `/llms.txt`, with curated markdown links — optionally paired with `/llms-full.txt` that inlines everything. Directly relevant: it is the "agent as primary reader" framing. **Gap:** targets public websites, not private repos; no notion of *which* link the agent should pick for a given question.

### `.well-known/ai-plugin.json` (deprecated)
OpenAI's original ChatGPT plugin manifest. Worth noting as an early "here's how an agent discovers capabilities" pattern; superseded, but the manifest-based discovery idea persists.

---

## 3. Agent/IDE rule files

### Cursor rules
`.cursorrules` (legacy) and `.cursor/rules/*.mdc` (current). Markdown files checked into a repo that Cursor auto-loads into context while working in that codebase. Scoped rules (globs, `alwaysApply: false`) let rules activate per-file. **Closest prior art for "agent reads project-local instructions."** Gap: scoped to the currently open repo; no convention for cross-repo pointers.

### GitHub Copilot custom instructions
`.github/copilot-instructions.md`. Similar to Cursor rules but simpler and Copilot-specific. Mention-only.

### CLAUDE.md / AGENTS.md / GEMINI.md
Per-project instruction files that Claude Code, OpenAI Codex, and Gemini CLI respectively auto-load. Same pattern as Cursor rules. Mention-only.

### Windsurf, Aider, Cline rule files
Same convention, tool-specific. Mention-only.

---

## 4. Plugin & skill architectures

### Claude Code Skills ★

Skills are markdown files — typically `SKILL.md` — with YAML frontmatter and a body. Frontmatter carries at minimum a `name` and a `description`; the description tells Claude *when* to invoke the skill. At session start, Claude loads only the frontmatter of available skills into context, giving it a cheap index. When a user request matches a skill's description, Claude loads the full body into the conversation and follows its instructions. Skills can also be invoked explicitly via `/skill-name`. **This is the nearest match to the proposed retrieval model** — cheap index, expensive payload, loaded on demand.

Skills can ship inside plugins (which then namespace them, e.g. `/observability:create-log-index`) or live locally under `~/.claude/skills/` or `.claude/skills/`. A skill's body is just markdown — it can invoke the agent's normal tools (Bash, Read, Glob, WebFetch) and can include pre-execution shell injection that runs before Claude sees the prompt, letting the skill splice fresh external content directly into the conversation.

**Fetching external content.** A skill can reach a separately versioned GitHub repo through several mechanisms: (1) the `gh` CLI via a pre-approved `Bash` tool, (2) `curl` / HTTP fetch, (3) `Glob` + `Read` if the repo is cloned locally, or (4) shell injection at invocation time. None of these are declarative — each skill implements its own fetch logic.

**Gap for our use case.** Skills have no declarative way to say "this skill's knowledge lives at `org/knowledge-repo` pinned to version `v1.2`." Every skill that fans out to external content must implement its own fetching, caching, and version handling. The retrieval *shape* is right; the declarative affordances for a versioned external knowledge repo are missing.

### Claude Code Plugins ★

Plugins are versioned, distributable packages that bundle skills, commands, sub-agents, hooks, and MCP-server references. Each plugin has a `.claude-plugin/plugin.json` manifest with at minimum a `name`, `description`, and `version`. Installing a plugin fetches it from a GitHub repo and makes its skills available under the plugin's namespace (e.g. `/observability:create-log-index`). Directly relevant as the shipping vehicle for the proposed `observability` plugin.

**Bundling vs. pointing.** A plugin can ship content inline (skills whose bodies contain the golden-path instructions directly) or ship *pointers* — skills whose bodies are thin and whose real content is fetched at invocation from a separate GitHub knowledge repo. Either works; the choice is a trade-off:

| Dimension | Bundled content | Pointers to knowledge repo |
|---|---|---|
| **Update cadence** | Requires a plugin release | Knowledge updates land immediately |
| **Offline behavior** | Works without network | Requires `gh` / network on each call |
| **Version pinning** | Plugin version pins everything | Requires separate pinning logic |
| **Blast radius** | Content and activation logic ship together | Content can change without the plugin being re-reviewed |

Initial lean for the PoC (to be validated in the architecture doc): **skills small, knowledge repo separate.** The plugin's job is discovery and orchestration; the knowledge repo's job is content.

**Gap for our use case.** The plugin manifest has no first-class field for declaring a dependent external repo or pinning its version. If the knowledge repo is renamed, moved, or changes schema, each plugin must be manually updated. No cache-invalidation story.

### Anthropic Skills (platform)
The same idea surfaced through the Anthropic API. Mention-only.

### Model Context Protocol (MCP) ★

MCP is an open JSON-RPC protocol for exposing three primitives to an LLM client: **resources** (addressable content — think files or URL-addressed blobs), **tools** (callable functions with typed arguments), and **prompts** (parameterized prompt templates). Transport is either stdio (local subprocess) or streamable HTTP (remote). A Claude Code plugin can declare MCP servers in its `.mcp.json`, which spawns them automatically on session start.

**Fronting a knowledge repo with MCP.** An MCP server dedicated to the knowledge repo would typically expose:

- `resources/list` that enumerates markdown files matching a query
- `resources/read` that returns a chosen file's contents
- Optionally a `search_knowledge` *tool* that takes a natural-language query and returns ranked paths or snippets

From the agent's perspective, this replaces ad-hoc `gh` shell calls with structured calls to a named server. The server can cache, rate-limit, authenticate once, and send notifications when resources change — things that are awkward to layer onto shell calls from skills.

**Skills vs. MCP for external knowledge.**

| Dimension | Skills | MCP |
|---|---|---|
| **Discovery** | Descriptions in context; body on match | Resources/tools enumerated at connection |
| **Freshness** | Fetch per invocation | Cacheable, with change notifications |
| **Auth** | Inherits user's `gh` / env vars | Server owns credentials |
| **Deployment** | None (pure markdown) | Requires a running server (local binary or remote) |
| **Coupling** | Skill embeds fetch logic | Abstract resource URIs, decoupled |

**Gap for our use case.** MCP is architecturally cleaner than raw shell fetching, but introduces operational overhead (a server per knowledge domain, per user, or per org). There is also no `plugin.json` convention for declaring "this plugin requires an MCP server pinned to knowledge-repo version X." A pragmatic hybrid is plausible: plugin ships skills; skills call a plugin-bundled MCP server; the server handles GitHub retrieval and caching. This trade-off is a decision for the architecture doc.

### OpenAI Custom GPTs — "Knowledge"
User uploads documents; GPT performs RAG over them. Closed-platform, not filesystem-native, not versionable in git. Mention-only.

---

## 5. Repo Q&A and codebase chat

### DeepWiki (Cognition / Devin)
Auto-generates a wiki for any public GitHub repo and lets you chat with it. Relevant for the *retrieval* question — they have thought hard about "answer a question over a repo without reading every file." **Gap:** read-only Q&A, no write path, no PR authoring.

### Sourcegraph Cody
Codebase-aware chat using embeddings plus a code graph. Mention-only; similar retrieval problem at larger scale.

### GitHub Copilot `@workspace`
Similar in spirit. Mention-only.

---

## 6. Doc-as-code and spec-driven development

### GitHub Spec-Kit ★

Spec-Kit is an open-source toolkit from GitHub ([`github/spec-kit`](https://github.com/github/spec-kit), MIT-licensed) shipped as a `specify` CLI installable via `uv tool install specify-cli`. Its thesis: specifications should be *executable* artifacts that generate working code rather than scaffolding discarded once coding begins. It is agent-agnostic — it integrates with Claude Code, Copilot, Cursor, Codex, and more by installing slash-command prompt files into each agent's config directory. Specs live as markdown under `.specify/` in the repo.

**Workflow stages.** Each stage is issued as a slash-command (`/speckit.*`, or `$speckit-*` in Codex skills mode), is agent-authored, and is human-gated before the next command:

1. **`/speckit.constitution`** — agent drafts `constitution.md` of project principles.
2. **`/speckit.specify`** — agent produces `spec.md` (*what/why*). Feature branch is auto-created.
3. **`/speckit.plan`** — agent emits `plan.md` (tech stack and architecture).
4. **`/speckit.tasks`** — agent decomposes the plan into `tasks.md`.
5. **`/speckit.implement`** — agent writes code against the task list.

(Additional optional commands exist in the broader workflow, e.g. for clarification and cross-artifact consistency checks.)

All artifacts are markdown; every transformation is agent-driven but human-gated. The CLI itself (`specify init`, `specify check`, `specify extension add`, `specify preset add`) handles scaffolding and a layered template system (core → extensions → presets → project overrides).

**Overlap with the Documents-as-Code reconciler vision.** Strong alignment at the level of philosophy: markdown as the load-bearing artifact, staged agent-authored transformations from plain-language intent to executable outcome, a layered extension model, and git-branch-per-feature as the unit of work. Where it diverges: Spec-Kit is a *forward generator* focused on net-new feature code. It has no built-in idempotent apply loop, no drift detection, no reconciliation against live state, and no written-back *actual-state* markdown.

Notably, the community has already felt this gap. Third-party extensions including [`spec-kit-reconcile`](https://github.com/stn1slv/spec-kit-reconcile), [`spec-kit-sync`](https://github.com/bgervin/spec-kit-sync), and [`spec-kit-retrospective`](https://github.com/emi-dm/spec-kit-retrospective) bolt on drift detection and spec-update-from-reality flows, and upstream issue [`github/spec-kit#1063`](https://github.com/github/spec-kit/issues/1063) proposes a built-in `/speckit.reconcile` — suggesting the reconciler pattern is a recognized missing primitive, not a core concern.

**Gap for our use case.** Spec-Kit gives us the spec → plan → code agent choreography but provides no reconciler loop, no drift primitive, and no actual-state output. Those remain ours to design if the future-state vision is pursued.

### Readme-driven development
Older convention (Tom Preston-Werner, ~2010). Write the README first. Related in spirit to "markdown as source of truth," but not agent-native.

---

## 7. Infrastructure-from-natural-language

### Pulumi AI / Pulumi Copilot
Natural language → Pulumi program (TypeScript/Python). The nearest production-grade attempt at "plain language → infra." **Gap:** output is a Pulumi program that still requires Pulumi expertise to review; markdown is not a first-class artifact.

### Terraform copilots (HashiCorp and others)
Natural language → HCL. Same shape as Pulumi AI. Mention-only.

### Crossplane
Kubernetes-native infrastructure-as-code. "Reconcile desired vs. actual state" is its core loop. Relevant as a mental model for the future-state reconciler, not as direct prior art.

### Kubernetes operators (general)
The reconcile-loop reference architecture. Mention-only.

---

## 8. Adjacent but not-quite

### Retool, Stackstorm, Rundeck
"Runbook automation" — scripted self-service actions fronted by forms. An older-era golden path. Mention-only.

### ChatOps (Hubot lineage)
Chat-triggered scripts. Mention-only, for historical perspective.

---

## Summary of gaps (one line each)

- **IDPs** solve the *catalog and scaffolding* but not the *retrieval-at-question-time* part.
- **`llms.txt`** solves the *index* but does not help the agent *pick* the right link.
- **Cursor rules / CLAUDE.md** work for the *currently open* repo but have no convention for cross-linking to another repo's rules.
- **Claude Code Skills** have the right *retrieval shape* but ship with the plugin; there is no established pattern for a skill to fan out to a *separately versioned GitHub-hosted knowledge repo*.
- **DeepWiki** has great *Q&A retrieval* but no *write/PR path*.
- **Pulumi AI / Terraform copilots** generate code, not markdown; humans still review HCL.
- **No existing tool** handles "recognize when the user is already in the relevant repo, and skip the discovery step."
- **No existing tool** cleanly resolves the **upstream-vendor-docs question** — i.e. when to reach for a company-authored golden path versus the underlying vendor's public documentation (e.g. Datadog's own docs). Deferred for the PoC.

The provisional answer is: **partially solved**. Most of the building blocks exist. The novel element is the *composition* — specifically, a skill-indexed plugin that points to one or more separately versioned GitHub-hosted knowledge repos, with a convention for IDE-context shortcuts and an end-to-end write path (user question → PR).

---

## Pass-2 coverage

Entries expanded to pass-2 depth (marked ★ above):

1. **Claude Code Skills** — foundational retrieval primitive for the PoC.
2. **Claude Code Plugins** — the shipping vehicle; bundling-vs-pointing trade-off flagged for the architecture doc.
3. **Model Context Protocol (MCP)** — viable alternative or complement to skills for external knowledge; pros/cons table included.
4. **GitHub Spec-Kit** — closest published pattern to the future-state reconciler.

Entries deliberately **not** expanded, and why:

- **Cursor rules / `.cursor/rules/`** — the pattern is well understood from the pass-1 summary and the cross-repo gap is already captured. Portability across agents is a concern for the *plugin distribution* layer, not the retrieval layer; pick this up if the PoC later needs to support a non-Claude-Code agent.
- **Backstage Software Templates** — the scaffolding-vs-retrieval distinction is clear enough from pass 1 to inform the design. Backstage is useful as a reference for what an IDP layer looks like, but the PoC is explicitly not trying to be an IDP.

If a later question makes one of these entries load-bearing, it can be promoted and expanded without re-running the full survey.
