# Future State: Documents as Code

> **This document is a vision sketch, deliberately out of scope for the PoC.** Its purpose is to capture the longer-arc idea so it does not contaminate the PoC design — and so, later, we can check whether the PoC is still a stepping stone in the right direction.

## The sketch

The PoC (see `problem-and-vision.md`) is about *retrieval*: helping a user find the right golden-path document and follow it. The future state extends the same primitives into *authoring and reconciliation*:

1. **Agent A** — the user's coding assistant — talks to the user, understands what they want, and writes a **desired-state markdown file**. The file describes the target in plain English:
   > Datadog log index `teamfoobar-prod`. 30-day `Flex` retention. 1B-log monthly quota. Filter `service:foobar-api`.

   Not HCL. Not YAML. Prose, plus a few structured fields where they help readability.

2. **Agent B** — a reconciler — reads the desired-state file, uses the tools it was prompted to use (Terraform? the Datadog API directly? a Kubernetes CRD controller?), and attempts to make the actual world match. Its tooling and best-practice constraints come from prompts/skills the Platform team supplied.

3. When reconciliation succeeds, Agent B writes an **actual-state markdown file** describing what it did and what it observed.

4. Drift detection is the same loop: re-run Agent B, compare the new actual-state output to the desired-state input, surface diffs for human (or agent) review.

## Why this is interesting

**Traceability.** Every layer is plain English. A non-specialist can read the desired state, read what the reconciler did, and read the resulting actual state — without learning HCL, Pulumi TypeScript, or `kubectl` output formats. Incidents can potentially be debugged by reading files instead of reading a Terraform plan.

**Portability.** The desired-state file does not know whether the reconciler uses Terraform, Pulumi, a SaaS API, or a human runbook. Swapping the reconciler does not require rewriting the desired state.

**Composition.** Desired-state files can be produced by other agents. A capacity-planning agent could, in principle, draft desired-state for next quarter's capacity, which humans review and a reconciler applies.

## Why this is hard

**Non-determinism.** Plain-language specs are ambiguous; reconcilers interpret them. Terraform's virtue is that `terraform plan` is exact. Losing that is a serious regression without strong guardrails.

**Cost.** Every reconciliation is one or more LLM invocations. Terraform is cheap to re-plan. Agent-driven reconciliation may cost real dollars per apply — and cost-per-apply scales with blast-radius rather than with complexity.

**Auditability and provenance.** Who authored the desired state — a human or an agent? What if the agent was prompt-injected by a comment in a README it read along the way? Provenance becomes non-trivial and must be signed or otherwise attested. By the same reasoning that drove the PoC to GitHub-only retrieval, desired-state and actual-state artifacts should live in git/GitHub: commits, PRs, and signed tags give the audit trail for free and keep the system operable with tools teams already trust.

**Schema drift.** Plain-language fields evolve. "30 day `Flex` retention" may mean different things to two reconcilers six months apart, or to the same reconciler after a model update. Some structured schema inevitably creeps back in — at which point the plain-language story weakens.

**Existing tools are good.** Terraform, Crossplane, and Pulumi are mature and battle-tested. The bar for *replacing* them is very high. The realistic positioning is almost certainly **on top of** these tools — the agent writes a plain-language spec, the reconciler generates Terraform, and `terraform apply` runs — rather than *instead of* them.

## What this means for the PoC

**The PoC should not build any of this.** It should build the retrieval half and stop. But it should:

- Emit markdown artifacts where reasonable (for example, the PR description is a plain-English summary of what the user asked for and why), so that if a reconciler is later introduced, the data it needs is already being produced.
- Avoid designing anything that would *preclude* this future state. In particular, do not bake agent-only conventions deep into the knowledge-repo schema; prefer file formats a human and a future reconciler can both read.

## The signal to watch for

If, during PoC use, users begin asking "can the agent just apply the PR for me?" — that is the signal that the retrieval path is working and the reconciliation gap is worth closing. Not before.
