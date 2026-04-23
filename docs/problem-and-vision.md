# Problem & Vision: Agent-Navigable Golden Paths

## The gap

Large engineering organizations produce an enormous amount of institutional knowledge: how to request a Datadog index, where to open an RBAC ticket, which repo owns the Terraform for a given SaaS tool, what the cost guardrails are, who to ping in what Slack channel. Platform teams typically invest heavily in documenting this ("golden paths"), but the documentation is written for humans, scattered across Confluence, GitHub READMEs, and Slack threads, and often organized around the platform team's internal model rather than the consumer's goal.

The result is a recurring cost: every product team that needs a service eventually reinvents the wheel by hand, burning developer-hours on a path the platform team has already paved.

## Illustrative scenario — Team Foobar

Team Foobar at COMPANY A is finishing deployment of an ECS application on AWS. They have the Datadog Agent running as a sidecar and their logs visible in Datadog Live Tail. They now need a log index for retention past 15 minutes, but the Datadog GUI will not let them create one.

What follows is the ~2-hour journey that the Platform team wishes it did not have to inflict:

1. Team Foobar discovers by word of mouth that Datadog is owned by the Platform team.
2. Platform redirects them to a Confluence page with high information density and a wide audience — technically complete, but not organized around the question "what do I do next?"
3. Eventually they learn the answer is "open a PR in `datadog-operations`," a Terraform repo.
4. They read the repo README, experiment, and produce a PR requesting 30-day standard retention with a 1B-log quota.
5. Platform reviews, gently points out the `Flex` retention tier is two orders of magnitude cheaper than `Standard` for their workload, and asks them to revise.
6. Team Foobar revises. Platform approves. PR merges. Done.

Every step except step 6 represents work the Platform team already paid to eliminate. The Confluence page exists. The repo README exists. The Flex-vs-Standard cost guidance is documented. The PR template has a cost-estimate comment. None of that content is missing — it is simply not retrievable by the person who needs it, in the order they need it, at the moment they need it.

## Thesis

An AI coding agent already installed in the user's IDE can close this gap, given three things:

1. A **plugin/skill** supplied by the Platform team that tells the agent where the golden-path content lives and how to locate the right piece within it.
2. **Knowledge-store content** — markdown hosted in GitHub, written with an agent as the primary reader and structured for retrieval rather than human prose. GitHub is the authoritative location for both plugin/skill definitions and golden-path content; the PoC does not retrieve from Confluence, wikis, or other non-GitHub sources.
3. A **navigable path from question to action**: the user asks "how do I create a log index?" in natural language, and the agent ends up opening the correct PR, in the correct repo, with the correct best-practice defaults already applied.

If this works, the Platform team gets leverage on documentation it has already written, and product teams see a dramatic reduction in time-to-golden-path.

## What success looks like for the PoC

A user with the Platform team's `observability` plugin installed at COMPANY A can ask "How do I create a logging index in Datadog Prod?" and, within ~5 minutes, the agent has:

- Located the correct repo (`datadog-operations`).
- Recognized whether the user already has it cloned (and if so, used it in place rather than starting from scratch).
- Authored a compliant PR with sensible defaults — for example, `Flex` retention unless the query workload justifies `Standard`.
- Warned the user about anything in the PR that would violate documented best practices, with a rationale the user can override or accept. This justification should also be included in the PR, if the user has chosen to override best practices.
- Followed the company's branching and commit conventions — for example, Jira-ticket-prefixed commits — which are supplied by a separate, orthogonal skill, not by the `observability` plugin.

## What this is not

- Not a replacement for human code review on infrastructure changes.
- Not a general-purpose "chat with your wiki" product — the target is action, not Q&A.
- Not a replacement for Terraform, IDPs like Backstage or Port, or existing platform tooling. It sits on top of them.
- Not the long-term end state. See `future-state-documents-as-code.md` for a speculative extension into plain-language reconciliation. That extension is explicitly out of PoC scope.

## Non-goals for the PoC

- Multi-tenant or SaaS deployment.
- Any UI beyond the user's existing coding agent.
- Authoring a *tool* for platform teams to produce golden-path content. The PoC assumes such markdown already exists.
- Semantic search or embeddings-based retrieval. The PoC should be reachable with simple, explicit indexing.

## Mock content as PoC fixtures

The PoC is permitted — and expected — to **mock up representative golden-path content** for validation purposes. **All fixture content lives in GitHub**, consistent with the broader constraint that GitHub is the authoritative host for all retrieval in this design. Concretely:

- A fictional `observability` plugin whose skills stand in for what the Platform team would ship, hosted in a GitHub repo.
- A fictional `datadog-operations` GitHub repo containing plausible (but fake) Terraform, README, PR-template, and best-practice markdown.
- Any other sample artifacts needed to exercise the retrieval path end-to-end — also hosted in GitHub (e.g. as additional repos under the same org, or as files within an existing fixture repo).

These fixtures are stand-ins for real platform content, not proposed production artifacts. Their purpose is to let us validate the retrieval path, cost model, and PR-authoring flow without depending on a real company's internal content. Where realism matters (for example, the `Standard` vs. `Flex` cost guidance in the Team Foobar scenario), fixtures should be grounded in publicly documented behavior of the underlying tool — not invented out of whole cloth — so the accuracy test is meaningful.

## Open questions (deferred to later docs)

- **Retrieval cost model.** Every markdown file read costs tokens. How does the agent avoid reading all of them on every question? *(Core architecture.)*
- **Plugin vs. knowledge-repo split.** Does the plugin ship the markdown, point to it, or both? *(Core architecture.)*
- **Best-practice enforcement.** How does the agent know a user's PR violates a best practice before a human reviewer sees it? *(Core architecture.)*
- **IDE context shortcut.** When the user is already inside `datadog-operations`, the agent should skip the "which repo?" step. *(Core architecture.)*
- **Upstream vendor documentation.** Some user questions may be answered by vanilla upstream docs (e.g. Datadog's own documentation) rather than by a company-authored golden path. How — or whether — the agent should reach for upstream docs in addition to, or instead of, the GitHub-hosted golden path is **deferred**. The PoC constrains retrieval to GitHub.
