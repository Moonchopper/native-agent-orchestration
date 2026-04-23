# Prior Art Survey (Pass 1: Shallow Sweep)

A categorized scan of existing patterns and tools that overlap with the proposed design (see `problem-and-vision.md`). One short paragraph each. The goal is to answer: **is this idea already solved, partially solved, or novel?**

After review, pick the entries that deserve a pass-2 deep dive — those will be expanded inline in this document.

### Conventions used in this document

- **Mention-only** — the entry is noted for completeness but deliberately not analyzed, because it is close enough to a sibling entry (or tangential enough) that expanding on it would add length without adding insight. Mention-only entries are *not* candidates for the pass-2 deep dive unless explicitly promoted out of that bucket.
- **Gap** — a capability the proposed design needs that the surveyed tool does not provide.
- **Candidate for deep dive** — flagged for pass-2 expansion; see the list at the end of the document.

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

### Claude Code Skills
Markdown files with YAML frontmatter (`name`, `description`, when-to-invoke). The agent matches user intent against descriptions and loads the full skill body only when triggered. **This is the nearest match to the proposed retrieval model** — a cheap index (frontmatter only) and an expensive payload (full body) loaded on demand.

### Claude Code Plugins
Distributable bundles of skills, commands, agents, and MCP servers. Installable from GitHub. Directly relevant as the shipping vehicle for the proposed `observability` plugin.

### Anthropic Skills (platform)
The same idea surfaced through the Anthropic API. Mention-only.

### Model Context Protocol (MCP)
Open protocol for exposing tools, resources, and prompts to LLM clients. Relevant because a knowledge repo could equally be fronted by an MCP server that performs retrieval, instead of the agent walking files. **Viable alternative architecture; candidate for deep dive.**

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

### GitHub Spec-Kit
Toolkit for spec-driven development: markdown specs → plan → tasks → code, each stage driven by an agent. Overlapping philosophy with the "future-state reconciler" idea — spec as primary artifact, agents transforming between stages. **Candidate for deep dive.**

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

## Candidates for pass-2 deep dive

Suggested, in rough priority order:

1. **Claude Code Skills + Plugins** — foundational for the PoC; deserves careful treatment.
2. **MCP servers** — viable alternative architecture; worth comparing directly.
3. **Cursor rules / `.cursor/rules/`** — cross-agent portability considerations.
4. **Backstage Software Templates** — what the scaffolding side of golden paths already does.
5. **GitHub Spec-Kit** — closest published pattern to the future-state reconciler.

Indicate which of these (or others) to expand, and pass 2 will be inlined in this document.
