# native-agent-orchestration — PoC

Exploratory proof-of-concept for **agent-navigable golden paths**. A platform
team ships a Claude Code plugin that points a user's agent at a GitHub-hosted
functional repo containing colocated golden-path markdown. The agent retrieves,
walks the user through the steps, and opens a compliant PR.

See [`docs/problem-and-vision.md`](docs/problem-and-vision.md) for the motivation
and [`docs/superpowers/specs/2026-04-23-core-architecture-design.md`](docs/superpowers/specs/2026-04-23-core-architecture-design.md)
for the architecture.

## Status

- **Stage 1** — single scenario (`create-log-index / local-hit`) end-to-end. Merged via PR #1.
- **Stage 2** — scenario hardening + measurement harness. **This PoC.** Open as PR #2.
- Stage 3 (planned) — additional scenarios per doc 4.

**Stage-2 calibration (N=5, `create-log-index / local-hit`):** P50 = 8755 tokens/invocation, P95 = 9356, cache_ratio = 0.96, hot_turn = 32. See [`docs/stage-2-notes.md`](docs/stage-2-notes.md) for the proposed Stage-3 budget tolerance and the full plan-deviation log.

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

# Enroll the fixture plugin via the project-local marketplace.
# Writes a project-scoped enrollment to .claude/settings.json (gitignored).
./scripts/setup-plugin.sh

# Run a single scenario end-to-end (~4 minutes, real claude -p spend)
./scripts/run-scenario.sh create-log-index local-hit
# Expected final line: "All assertions passed."

# Run the full measurement matrix (N=5, ~20 minutes)
./scripts/run-benchmarks.sh --matrix scripts/matrix/stage-2-initial.tsv
# Emits a markdown summary table with N, P50, P95, cache_ratio, hot_turn.

# Or smoke-run at N=2 (~8 minutes)
./scripts/run-benchmarks.sh --matrix scripts/matrix/stage-2-initial.tsv --n 2
```

## Layout

- `docs/` — research docs, architecture spec, Stage-1 and Stage-2 implementation plans, and Stage-1 / Stage-2 handoff notes.
- `.claude-plugin/marketplace.json` — local marketplace pointing at the remote fixture plugin (read by `claude plugin marketplace add`).
- Fixture content lives in two standalone GitHub repos under `Moonchopper/`:
  - [`Moonchopper/claude-plugin-observability`](https://github.com/Moonchopper/claude-plugin-observability) — mock platform-team plugin (skills `create-log-index` and `pr-handoff`). Installed by `setup-plugin.sh`.
  - [`Moonchopper/datadog-operations`](https://github.com/Moonchopper/datadog-operations) — mock functional repo with `agent/golden-paths/` and `agent/best-practices/`. Cloned by the runner per-variant.
- `settings/benchmark.settings.json` — `claude -p` runtime settings: tools allowlist + `enabledPlugins` for the fixture plugin.
- `scripts/` — `run-scenario.sh` (single-run), `run-benchmarks.sh` (matrix driver), `extract-metrics.sh` (transcript → JSONL), `aggregate-metrics.sh` (JSONL → markdown table), `setup-plugin.sh` (plugin enrollment), `assertions/` (per-scenario), `matrix/` (TSV matrix files).
- `tests/` — bats-core tests for the runner CLI contract, extract-metrics, aggregate-metrics, and run-benchmarks contract. Fixtures under `tests/fixtures/`.

## What this PoC does NOT do

- It does NOT call the Datadog API or any vendor API.
- It does NOT run `terraform apply`.
- It does NOT open a real GitHub pull request (the handoff is stubbed to a local JSON file).

See §3 of the architecture spec for the execution-model boundary.

## Between runs

The runner clones `Moonchopper/datadog-operations` to `~/src/Moonchopper/datadog-operations` and resets it to a clean state before each run. Drafted artifacts (e.g. `terraform/logs/indexes/foobar.tf` and `.stage-1-handoff.json`) live inside that clone — they're created during the run and discarded by the next `git reset --hard` + `clean -fd`. No manual cleanup needed.

## How metrics are captured

After `claude -p` exits, `run-scenario.sh` finds the session transcript that Claude Code wrote (under `~/.claude/projects/<project-slug>/<session-id>.jsonl`) and pipes it through `scripts/extract-metrics.sh`, which emits one JSONL line per assistant LLM call to `$AGENT_ORCH_METRICS_FILE` (default: `$SESSION_DIR/metrics.jsonl`). The benchmark driver collects per-run files and feeds them to `aggregate-metrics.sh` for the markdown summary.

There is **no Stop hook** — early Stage-2 work found that the actual `claude -p` Stop payload carries no token data; transcript post-processing is simpler and equivalent. See `docs/stage-2-notes.md` for the full rationale.

## Known limitations (Stage 2)

- Only one scenario (`create-log-index`) and one variant (`local-hit`) are exercised. The `remote-fallback` and `cwd-shortcut` variants need new fixture states; additional scenarios need doc 4.
- `pr-handoff` is still a JSON-writing stub; no real PR is opened.
- `skill_active` and `duration_ms` in the per-turn metrics are emitted as `null` / `0` (not in the transcript schema; deferred to Stage 3).
- Fixture repo origins are fictional (`github.com/fixture-org/...`); the runner's freshness-check path is not exercised against a real remote.
- `setup-plugin.sh` writes a machine-specific path into `.claude/settings.json` (gitignored); each developer must run it once on a fresh clone.
