#!/usr/bin/env bash
set -euo pipefail

# aggregate-metrics.sh — read one or more JSONL metric files,
# group by (scenario, variant), compute per-run totals and percentiles,
# emit a markdown summary table to stdout.
#
# Percentile definition: rank-based (for N=5, P50 = sorted[2], P95 = sorted[4]).
# Type-7 interpolation is NOT used; PoC-scale N is small enough that the
# rank-based value is adequate and easier to reason about.

if [ "$#" -lt 1 ]; then
  echo "usage: aggregate-metrics.sh <metrics.jsonl> [more.jsonl ...]" >&2
  exit 2
fi

for f in "$@"; do
  [ -s "$f" ] || { echo "ERROR: $f is empty or missing" >&2; exit 1; }
done

cat "$@" | jq -s -r '
  group_by([.scenario, .variant])
  | map({
      scenario: .[0].scenario,
      variant:  .[0].variant,
      all_lines: .,
      runs:     (group_by(.run_ix) | map({
        run_ix: .[0].run_ix,
        total:  (map(.tokens_in + .tokens_out) | add),
        cache_read_sum: (map(.cache_read) | add),
        tokens_in_sum:  (map(.tokens_in)  | add)
      })),
    })
  | map(.runs |= sort_by(.total))
  | map({
      scenario: .scenario,
      variant:  .variant,
      n:        (.runs | length),
      p50:      (.runs[(.runs | length / 2 | floor)].total),
      p95:      (.runs[((.runs | length) - 1)].total),
      cache_ratio: (
        ([.runs[].cache_read_sum] | add) /
        ([.runs[].tokens_in_sum]  | add | if . == 0 then 1 else . end)
      ),
      hot_turn: (
        .all_lines
        | group_by(.turn)
        | map({ turn: .[0].turn, total: (map(.tokens_in + .tokens_out) | add) })
        | max_by(.total)
        | .turn
      )
    })
  | "| scenario | variant | N | P50 | P95 | cache_ratio | hot_turn |",
    "|---|---|---|---|---|---|---|",
    (.[] | "| \(.scenario) | \(.variant) | N=\(.n) | \(.p50) | \(.p95) | \(.cache_ratio | . * 100 | floor / 100) | \(.hot_turn) |")
'
