#!/usr/bin/env bash
set -euo pipefail

# run-benchmarks.sh — iterate the matrix TSV; for each (scenario, variant, n)
# invoke run-scenario.sh n times in fresh sessions, collect per-run metrics
# files, and print the aggregate summary at the end.
#
# Each iteration sets RUN_IX (consumed by run-scenario.sh -> extract-metrics.sh)
# and AGENT_ORCH_METRICS_FILE so the metrics for each run land at a known path.

usage() {
  cat >&2 <<EOF
usage: run-benchmarks.sh --matrix <path.tsv> [--n <override>] [--out <dir>]
  --matrix  TSV with columns: scenario, variant, n (header line required)
  --n       Override the per-row N (useful for smoke runs)
  --out     Directory to collect per-run metrics (default: auto mktemp)
EOF
  exit 2
}

MATRIX=""
N_OVERRIDE=""
OUT_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --matrix) MATRIX="$2"; shift 2 ;;
    --n)      N_OVERRIDE="$2"; shift 2 ;;
    --out)    OUT_DIR="$2"; shift 2 ;;
    *)        echo "unknown flag: $1" >&2; usage ;;
  esac
done

[ -n "$MATRIX" ] || usage
[ -f "$MATRIX" ] || { echo "ERROR: matrix file not found: $MATRIX" >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel)"
: "${OUT_DIR:=$(mktemp -d -t agent-orch-bench-XXXX)}"
mkdir -p "$OUT_DIR"

# Skip header line; iterate data rows.
# NOTE: trailing `_BUDGET` absorbs the optional 4th column so that `N` does
# not pick up the rest of the line. The aggregator reads budgets directly
# from the matrix; we only need (scenario, variant, n) here.
tail -n +2 "$MATRIX" | while IFS=$'\t' read -r SCENARIO VARIANT N _BUDGET; do
  [ -n "$SCENARIO" ] || continue
  N="${N_OVERRIDE:-$N}"
  for i in $(seq 1 "$N"); do
    if [ "${DRY_RUN:-0}" = "1" ]; then
      echo "DRY_RUN: would run scenario=$SCENARIO variant=$VARIANT run_ix=$i"
      continue
    fi
    echo "[bench] scenario=$SCENARIO variant=$VARIANT run_ix=$i"
    METRICS_PATH="$OUT_DIR/$SCENARIO-$VARIANT-$i.jsonl"

    # remote-fallback requires NO clone at any conventional path before each
    # run. The runner's preflight errors if a clone exists; we clean here so
    # the matrix can iterate hermetically. (run-scenario.sh's preflight
    # remains as a guardrail for manual single-shot runs.)
    if [ "$VARIANT" = "remote-fallback" ]; then
      rm -rf "$HOME/src/Moonchopper/datadog-operations" \
             "$HOME/code/Moonchopper/datadog-operations" \
             "$HOME/git/Moonchopper/datadog-operations" \
             "$HOME/work/Moonchopper/datadog-operations"
    fi

    RUN_IX="$i" \
    AGENT_ORCH_METRICS_FILE="$METRICS_PATH" \
      "$REPO_ROOT/scripts/run-scenario.sh" "$SCENARIO" "$VARIANT" \
      > "$OUT_DIR/$SCENARIO-$VARIANT-$i.stdout" \
      2> "$OUT_DIR/$SCENARIO-$VARIANT-$i.stderr" \
      || echo "[bench] RUN FAILED: $SCENARIO / $VARIANT / $i (continuing)"
  done
done

if [ "${DRY_RUN:-0}" = "1" ]; then
  exit 0
fi

echo ""
echo "[bench] all runs complete. Metrics in: $OUT_DIR"
echo ""
"$REPO_ROOT/scripts/aggregate-metrics.sh" --matrix "$MATRIX" "$OUT_DIR"/*.jsonl
