# Index Naming

## Principle
Log index names must follow the pattern `<team>-<env>[-<purpose>]`.

## Rationale
Consistent naming enables cost attribution per team and per environment.
Platform's billing reports depend on this convention.

## How to check a draft
Inspect the proposed `name` field on the `datadog_logs_index` resource.
Assert it matches `^[a-z0-9]+-(prod|stage|dev)(-[a-z0-9-]+)?$`.

If it does not, suggest a correction that includes the team slug and
environment.
