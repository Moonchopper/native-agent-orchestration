# Retention Tier Selection

## Principle
Prefer `Flex` retention unless the specific query workload justifies `Standard`.

## Rationale
`Flex` is roughly 100x cheaper than `Standard` for typical read-rarely workloads.
`Standard` incurs ongoing cost regardless of whether the data is queried.

## When Standard is justified
- The index is queried more than ~10 times per day by multiple distinct users.
- The index powers a dashboard with sub-second latency requirements.
- Compliance mandates retention characteristics that Flex cannot meet.

## How to check a draft
Inspect the proposed `retention` block's `tier`. If it is `"Standard"`, ask
the user whether the workload meets any of the "When Standard is justified"
criteria above. If not, suggest switching to `"Flex"`.

If the draft does not involve a retention block (e.g. the golden path is
unrelated to index creation), skip this check.
