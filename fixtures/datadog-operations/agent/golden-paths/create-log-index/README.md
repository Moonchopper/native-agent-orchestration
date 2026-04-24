# Create Datadog Log Index

**What:** Provisions a Datadog log index via Terraform.
**Who:** Any product team that needs log retention beyond Live Tail's 15 minutes.
**Effort:** One PR to this repo, reviewed by the Platform team.

## Prerequisites
- This repo (`datadog-operations`) is cloned locally.
- A Jira ticket tracking the work.
- Rough answers to: index name, filter query, retention tier, retention days, daily quota.

## Files you will touch
- `terraform/logs/indexes/<team>.tf` — you will create this file.

## Referenced best practices
See `best-practices.md` in this directory for the list of referenced practices.
