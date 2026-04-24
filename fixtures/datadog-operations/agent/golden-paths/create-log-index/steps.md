# Steps

1. **Confirm inputs with the user:**
   - Index name (pattern: `<team>-<env>[-<purpose>]`, e.g. `foobar-prod`)
   - Filter query (e.g. `service:foobar-api env:prod`)
   - Retention tier (`Flex` or `Standard`)
   - Retention days (1–30)
   - Daily log quota (number of logs per day)

2. **Apply the pre-draft best-practice check** using the referenced practices
   in `best-practices.md`. Surface any violations before proceeding to draft.

3. **Create `terraform/logs/indexes/<team>.tf`** using the `example.tf`
   template in this directory. Substitute the confirmed inputs.

4. **Format and validate:**
   - Run `terraform fmt` on the new file.
   - Run `terraform validate` in the `terraform/` directory.
   - Halt on any validation failure.

5. **Apply the post-draft best-practice check** against the drafted file.
   Surface any violations and collect override rationale if the user rejects
   a suggestion.

6. **Show the diff to the user and await approval.**

7. **Prepare the PR payload** containing:
   - The drafted file path and contents
   - A PR body from the template below
   - The list of override rationales, if any

8. **Hand off to the `_pr-handoff` skill** with the payload.

## PR body template

```
## Summary
Creates log index `<name>` under team `<team>` for the `<env>` environment.

## Retention
- Tier: `<tier>`
- Days: `<days>`
- Daily quota: `<quota>`

## Filter
`<filter>`
```
