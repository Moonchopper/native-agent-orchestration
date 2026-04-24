# Query Cost Awareness

## Principle
Avoid creating one monolithic index that covers many services. Prefer
multiple narrow indexes when query patterns differ.

## Rationale
Flex warehouse queries charge proportional to index size *and* scanned
volume. A single 10B-log index that teams query independently costs more
than five 2B-log indexes that each team queries in isolation.

## How to check a draft
Inspect the proposed `filter.query` field. If it is a broad catch-all
(e.g. `*` or covers more than two services), suggest narrowing it or
splitting into multiple indexes.

If the draft does not create a new index (e.g. it updates an existing
one), skip this check.
