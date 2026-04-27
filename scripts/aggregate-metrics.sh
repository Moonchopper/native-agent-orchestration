#!/usr/bin/env bash
set -euo pipefail

# aggregate-metrics.sh — read one or more JSONL metric files,
# group by (scenario, variant), compute per-run totals and percentiles,
# emit a markdown summary table to stdout.
#
# Percentile definition: rank-based (for N=5, P50 = sorted[2], P95 = sorted[4]).
# Type-7 interpolation is NOT used; PoC-scale N is small enough that the
# rank-based value is adequate and easier to reason about.
#
# Optional budget enforcement (Task C2):
#   --matrix <path.tsv>   TSV with header "scenario\tvariant\tn\tbudget".
#                         Each row's `max` per-invocation total is compared
#                         against the row's `budget`.
#                           PASS         iff max <= budget
#                           FAIL         iff max  > budget
#                           BUDGET_UNSET iff no matrix supplied or budget is
#                                        missing / "-" for that row
#                         Exit 1 iff any row is FAIL; else exit 0
#                         (PASS-only or BUDGET_UNSET-only).

usage() {
  cat >&2 <<EOF
usage: aggregate-metrics.sh [--matrix <path.tsv>] <metrics.jsonl> [more.jsonl ...]
EOF
  exit 2
}

MATRIX=""
FILES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --matrix) MATRIX="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *)  FILES+=("$1"); shift ;;
  esac
done

if [ "${#FILES[@]}" -lt 1 ]; then
  usage
fi

for f in "${FILES[@]}"; do
  [ -s "$f" ] || { echo "ERROR: $f is empty or missing" >&2; exit 1; }
done

if [ -n "$MATRIX" ] && [ ! -f "$MATRIX" ]; then
  echo "ERROR: matrix file not found: $MATRIX" >&2
  exit 1
fi

# Build a JSON map: { "<scenario><variant>": <budget-or-null> } from the
# matrix TSV (skip header). Empty / "-" budget cells become null. If --matrix
# was not supplied, use an empty map (every row will be BUDGET_UNSET).
BUDGETS_JSON='{}'
if [ -n "$MATRIX" ]; then
  BUDGETS_JSON="$(
    tail -n +2 "$MATRIX" | awk -F'\t' '
      NF >= 2 && $1 != "" {
        budget = (NF >= 4) ? $4 : ""
        printf "%s\t%s\t%s\n", $1, $2, budget
      }
    ' | jq -R -s '
      split("\n")
      | map(select(length > 0))
      | map(split("\t"))
      | map({ key: (.[0] + "" + .[1]),
              value: (if (.[2] // "") | (. == "" or . == "-") then null else (.[2] | tonumber) end) })
      | from_entries
    '
  )"
fi

# Compute aggregates and produce TWO outputs:
#   1) The markdown table on stdout
#   2) A summary line "FAIL_COUNT=<n>" we can grep for to decide exit code
#
# We embed the budgets map via --argjson.
OUTPUT="$(
  cat "${FILES[@]}" | jq -s -r --argjson budgets "$BUDGETS_JSON" '
    group_by([.scenario, .variant])
    | map({
        scenario: .[0].scenario,
        variant:  .[0].variant,
        all_lines: .,
        runs:     (group_by(.run_ix) | map({
          run_ix: .[0].run_ix,
          total:  (map(.tokens_in + .tokens_out) | add),
          cache_read_sum: (map(.cache_read) | add),
          tokens_in_sum:  (map(.tokens_in)  | add),
          cache_creation_sum: (map(.cache_creation) | add)
        })),
      })
    | map(.runs |= sort_by(.total))
    | map(
        . as $row
        | ($budgets[(.scenario + "" + .variant)] // null) as $budget
        | (.runs[((.runs | length) - 1)].total) as $max
        | {
            scenario: .scenario,
            variant:  .variant,
            n:        (.runs | length),
            p50:      (.runs[(.runs | length / 2 | floor)].total),
            p95:      $max,
            max:      $max,
            budget:   $budget,
            status:   (
              if $budget == null then "BUDGET_UNSET"
              elif $max <= $budget then "PASS"
              else "FAIL"
              end
            ),
            cache_ratio: (
              ([.runs[].cache_read_sum] | add) as $cr
              | ($cr + ([.runs[].tokens_in_sum] | add) + ([.runs[].cache_creation_sum] | add)) as $total
              | if $total == 0 then 0 else $cr / $total end
            ),
            hot_turn: (
              .all_lines
              | group_by(.turn)
              | map({ turn: .[0].turn, total: (map(.tokens_in + .tokens_out) | add) })
              | max_by(.total)
              | .turn
            )
          }
      )
    | (map(select(.status == "FAIL")) | length) as $fail_count
    | (
        "| scenario | variant | N | P50 | P95 | max | budget | status | cache_ratio | hot_turn |",
        "|---|---|---|---|---|---|---|---|---|---|",
        (.[] | "| \(.scenario) | \(.variant) | N=\(.n) | \(.p50) | \(.p95) | \(.max) | \(.budget // "-") | \(.status) | \(.cache_ratio | . * 100 | floor / 100) | \(.hot_turn) |"),
        "FAIL_COUNT=\($fail_count)"
      )
  '
)"

# Print the table (everything except the FAIL_COUNT marker line).
echo "$OUTPUT" | grep -v '^FAIL_COUNT='

# Decide exit code from the marker.
FAIL_COUNT="$(echo "$OUTPUT" | awk -F= '/^FAIL_COUNT=/{print $2; exit}')"
if [ "${FAIL_COUNT:-0}" -gt 0 ]; then
  exit 1
fi
exit 0
