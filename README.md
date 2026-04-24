# native-agent-orchestration — PoC

Exploratory proof-of-concept for **agent-navigable golden paths**. A platform
team ships a Claude Code plugin that points a user's agent at a GitHub-hosted
functional repo containing colocated golden-path markdown. The agent retrieves,
walks the user through the steps, and opens a compliant PR.

See [`docs/problem-and-vision.md`](docs/problem-and-vision.md) for the motivation
and [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](docs/superpowers/specs/2026-04-23-core-architecture-design.md)
for the architecture.

## Status

- **Stage 1** — single scenario (`create-log-index / local-hit`) end-to-end. **This PoC.**
- Stage 2 (planned) — measurement harness.
- Stage 3 (planned) — additional scenarios per doc 4.

## Prerequisites

- [Claude Code CLI](https://claude.com/claude-code) — `claude --version` should succeed.
- `gh` CLI, authenticated (`gh auth status`).
- `git`.
- `jq`.
- `terraform` CLI (used for `fmt` and `validate` during the scenario — never `apply`).

Bats-core is **vendored** at `.bats/` (gitignored); the quickstart below clones it if missing.

## Quickstart

```bash
# Clone bats-core test runner (first-time only; gitignored, not committed)
[ -d .bats ] || git clone --depth 1 https://github.com/bats-core/bats-core.git .bats

# Install the fixture plugin into Claude Code's plugin directory
./scripts/setup-plugin.sh

# Run the scenario end-to-end
./scripts/run-scenario.sh create-log-index local-hit
```

Expected final line: `All assertions passed.`

## Layout

- `docs/` — research docs, architecture spec, and implementation plan.
- `fixtures/claude-plugin-observability/` — mock platform-team plugin.
- `fixtures/datadog-operations/` — mock functional repo with `agent/golden-paths/` and `agent/best-practices/`.
- `scripts/` — runner, plugin setup, and scenario assertions.
- `tests/` — bats-core tests for the runner CLI contract.

## What this PoC does NOT do

- It does NOT call the Datadog API or any vendor API.
- It does NOT run `terraform apply`.
- It does NOT open a real GitHub pull request (the handoff is stubbed to a local JSON file).

See §3 of the architecture spec for the execution-model boundary.

## Between runs

The scenario writes `fixtures/datadog-operations/.stage-1-handoff.json` and drafts
`fixtures/datadog-operations/terraform/logs/indexes/foobar.tf`. Re-running the runner
clears the handoff file automatically, but not the drafted Terraform. To reset the
fixture for a clean run:

```bash
rm -f fixtures/datadog-operations/.stage-1-handoff.json \
      fixtures/datadog-operations/terraform/logs/indexes/foobar.tf
```

## Known limitations (Stage 1)

- Only one scenario (`create-log-index`) and one variant (`local-hit`) are exercised.
- Runner uses `--permission-mode bypassPermissions` because the scenario runs inside a fixture sandbox; production use would narrow this via a settings file.
- Fixture repo origins are fictional (`github.com/fixture-org/...`); the runner's freshness-check path is not exercised against a real remote in Stage 1.
