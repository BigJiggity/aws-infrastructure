---
phase: "01"
plan: "02"
subsystem: ct-bootstrap
tags: [control-tower, runbook, data-sources, terragrunt, opentofu]
dependency_graph:
  requires: [01-01]
  provides: [landing_zone_arn, log_archive_account_id, audit_account_id, management_account_id]
  affects: [management/ct-bootstrap, docs/runbooks]
tech_stack:
  added: []
  patterns:
    - "data-source-only Terragrunt unit (no resource blocks)"
    - "try() guard for pre-CT-deploy output safety"
    - "tfvars.example + .gitignore pattern for account IDs"
key_files:
  created:
    - docs/runbooks/01-ct-landing-zone.md
    - management/ct-bootstrap/main.tf
    - management/ct-bootstrap/outputs.tf
    - management/ct-bootstrap/variables.tf
    - management/ct-bootstrap/terragrunt.hcl
    - management/ct-bootstrap/terraform.tfvars.example
  modified:
    - .gitignore
decisions:
  - "Used aws_controltower_landing_zones (plural) data source with try() guard and fallback comment per plan spec"
  - "Added aws_caller_identity data source for management account ID fallback alongside aws_organizations_organization.master_account_id"
  - "Terragrunt .gitignore patterns added without duplicating existing *.tfvars and *.tfstate entries"
metrics:
  duration: "15 minutes"
  completed: "2026-06-18"
  tasks_completed: 2
  files_created: 6
  files_modified: 1
---

# Phase 01 Plan 02: CT Landing Zone Runbook + IaC Data-Source Wrapper Summary

**One-liner:** Operator runbook for CT console deployment and a data-source-only Terragrunt unit that captures landing zone ARN, Log Archive ID, and Audit ID for Phase 2 AFT consumption.

## Status

**Code artifacts:** COMPLETE

**Human action required:** BLOCKED ON OPERATOR — CT landing zone is not yet deployed. The operator must follow `docs/runbooks/01-ct-landing-zone.md` before `management/ct-bootstrap/` can be initialized.

## What Was Built

### Task 1: CT Landing Zone Runbook

`docs/runbooks/01-ct-landing-zone.md` — 8-section operator runbook covering:

1. Pre-flight gate: gate on `./scripts/preflight.sh` exit 0
2. State backend gate: verify S3 + DynamoDB exist
3. Trusted access enablement: 4 `aws organizations enable-aws-service-access` commands (frequently absent from AWS docs)
4. Console deployment: exact step-by-step CT setup instructions
5. Post-setup verification: CLI commands to confirm landing zone ARN and account presence
6. Account ID capture: shell commands to extract MGMT/LOG_ARCHIVE/AUDIT IDs
7. IaC wrapper initialization: `terragrunt init/validate/plan/apply` sequence
8. Known pitfalls table: Pitfalls 1, 2, 5, 7 with mitigations

The runbook explicitly states CT is deployed via console, NOT via `tofu apply`, per D-03.

### Task 2: management/ct-bootstrap/ Terragrunt Unit

Data-source-only OpenTofu unit. **Zero resource blocks** — constraint enforced and verified.

| File | Purpose |
|------|---------|
| `terragrunt.hcl` | Child unit inheriting root config via `find_in_parent_folders()` |
| `variables.tf` | Three input vars: management_account_id, log_archive_account_id, audit_account_id |
| `main.tf` | Data sources: aws_controltower_landing_zones, aws_organizations_organization, aws_organizations_account (x2), aws_caller_identity |
| `outputs.tf` | Four exports: landing_zone_arn, log_archive_account_id, audit_account_id, management_account_id |
| `terraform.tfvars.example` | Template for operator to populate after CT console setup |

`main.tf` includes a verification note and fallback `locals {}` comment for the case where `aws_controltower_landing_zones` is unavailable in the provider version.

`outputs.tf` uses `try(..., "NOT_YET_DEPLOYED")` guard on `landing_zone_arn` so `terragrunt output` is safe to call before CT is live.

### .gitignore update

Added Terragrunt-generated file patterns: `**/.terragrunt-cache/`, `**/backend.tf`, `**/provider.tf`, `**/versions.tf`. Existing `*.tfvars` and `*.tfstate` entries were already present — not duplicated.

## Human Checkpoint

**Operator must complete before `management/ct-bootstrap/` can run:**

1. Run `./scripts/preflight.sh` — all 5 checks must pass
2. Follow `docs/runbooks/01-ct-landing-zone.md` sections 1–6 (~45–60 min)
3. Populate `management/ct-bootstrap/terraform.tfvars` from the example file
4. Run `terragrunt init && terragrunt apply` in `management/ct-bootstrap/`

After apply, these outputs are available for Phase 2:
- `landing_zone_arn`
- `log_archive_account_id`
- `audit_account_id`
- `management_account_id`

## Outputs Available After Apply

| Output | Description | Phase 2 Consumer |
|--------|-------------|-----------------|
| `landing_zone_arn` | ARN of the CT landing zone | AFT module `aws_controltower_landing_zone_arn` input |
| `log_archive_account_id` | CT-managed Log Archive account | AFT module + provider aliases |
| `audit_account_id` | CT-managed Audit account | AFT module + provider aliases |
| `management_account_id` | Management (root) account | AFT module + state backend config |

## Deviations from Plan

### Auto-added: aws_caller_identity data source

Added `data "aws_caller_identity" "current"` to `main.tf` as a supplementary source for management account ID (in addition to `aws_organizations_organization.current.master_account_id` which the plan specified). This provides a local fallback and is consistent with the runbook's CLI command that also uses `aws sts get-caller-identity`. No impact on outputs — `management_account_id` output uses `master_account_id` per plan spec.

### .gitignore: no duplication of existing patterns

The plan specified adding `**/terraform.tfvars` and `**/*.tfstate` patterns. The existing `.gitignore` already covered these as `*.tfvars` and `*.tfstate` (non-globstar). Added only the Terragrunt-specific patterns that were genuinely absent to avoid duplication.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes were introduced. The data-source-only constraint eliminates the risk of accidental CT resource management.

## Self-Check: PASSED

- [x] docs/runbooks/01-ct-landing-zone.md — FOUND
- [x] management/ct-bootstrap/main.tf — FOUND
- [x] management/ct-bootstrap/outputs.tf — FOUND
- [x] management/ct-bootstrap/variables.tf — FOUND
- [x] management/ct-bootstrap/terragrunt.hcl — FOUND
- [x] management/ct-bootstrap/terraform.tfvars.example — FOUND
- [x] .gitignore modified — FOUND
- [x] Commit c8bf21d — FOUND (git log verified)
- [x] Zero resource blocks in main.tf — VERIFIED
