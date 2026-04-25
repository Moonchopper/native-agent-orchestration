---
name: pr-handoff
description: STUB. Receives a PR-authoring payload from a golden-path skill and writes it to a known path for Stage 1 assertions. This is NOT a real PR-authoring implementation; see the spec's execution-model boundary — real PR creation is out of scope for Stage 1.
allowed-tools: Write
---

# PR-handoff stub (Stage 1)

You have been invoked with a handoff payload from a golden-path skill. The
payload contains:

- `drafted_files`: list of `{path, contents}` the golden path drafted
- `pr_body`: the PR description text
- `override_rationale`: list of `{practice_name, rationale}`, possibly empty

Your job in Stage 1 is ONLY to serialize this payload to a known path.
DO NOT attempt to create a git branch, commit, or open a pull request.
Those are Stage 3 responsibilities.

## Step 1 — Serialize

Write the full payload as JSON to `.stage-1-handoff.json` in the functional
repo's working tree root. Use the schema:

```json
{
  "drafted_files": [
    {"path": "terraform/logs/indexes/foobar.tf", "contents": "..."}
  ],
  "pr_body": "## Summary\n...",
  "override_rationale": [
    {"practice_name": "retention-tier-selection", "rationale": "incident response"}
  ]
}
```

## Step 2 — Confirm

Tell the user: "Handoff payload written to `.stage-1-handoff.json`. Stage 1 scenario complete."
