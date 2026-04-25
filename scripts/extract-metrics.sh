#!/usr/bin/env bash
set -euo pipefail

# extract-metrics.sh — read a Claude Code session transcript (JSONL)
# and emit one JSONL summary line per assistant LLM call, tagged with
# scenario / variant / run_ix from the environment.
#
# Why this isn't a Stop hook (recorded 2026-04-25):
# The Stop hook payload from `claude -p` carries no token-usage data —
# only {session_id, transcript_path, cwd, permission_mode, hook_event_name,
# stop_hook_active, last_assistant_message}. Token data lives in the
# transcript JSONL at .message.usage.{input_tokens, output_tokens,
# cache_read_input_tokens, cache_creation_input_tokens} and .message.model.
# Reading the transcript post-`claude -p` is simpler and equivalent for
# the spec §11.6 analysis dimensions.

usage() {
  echo "usage: extract-metrics.sh <transcript.jsonl>" >&2
  echo "  Env vars (optional):" >&2
  echo "    AGENT_ORCH_SCENARIO       default: untagged" >&2
  echo "    AGENT_ORCH_VARIANT        default: untagged" >&2
  echo "    AGENT_ORCH_RUN_IX         default: 0" >&2
  echo "    AGENT_ORCH_METRICS_FILE   if set, append JSONL here; else write to stdout" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
TRANSCRIPT="$1"
[ -f "$TRANSCRIPT" ] || { echo "ERROR: transcript not found: $TRANSCRIPT" >&2; exit 1; }

SCENARIO="${AGENT_ORCH_SCENARIO:-untagged}"
VARIANT="${AGENT_ORCH_VARIANT:-untagged}"
RUN_IX="${AGENT_ORCH_RUN_IX:-0}"

SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)

OUTPUT=$(jq -c \
  --arg scenario "$SCENARIO" \
  --arg variant "$VARIANT" \
  --argjson run_ix "$RUN_IX" \
  --arg session_id "$SESSION_ID" \
  '
  [inputs]
  | map(select(.message.usage))
  | to_entries
  | .[]
  | {
      ts:             (.value.timestamp // "unknown"),
      session_id:     $session_id,
      scenario:       $scenario,
      variant:        $variant,
      run_ix:         $run_ix,
      turn:           (.key + 1),
      model:          (.value.message.model // "unknown"),
      tokens_in:      (.value.message.usage.input_tokens // 0),
      tokens_out:     (.value.message.usage.output_tokens // 0),
      cache_read:     (.value.message.usage.cache_read_input_tokens // 0),
      cache_creation: (.value.message.usage.cache_creation_input_tokens // 0),
      duration_ms:    0,
      skill_active:   null
    }
  ' < "$TRANSCRIPT")

if [ -n "${AGENT_ORCH_METRICS_FILE:-}" ]; then
  mkdir -p "$(dirname "$AGENT_ORCH_METRICS_FILE")"
  echo "$OUTPUT" >> "$AGENT_ORCH_METRICS_FILE"
else
  echo "$OUTPUT"
fi
