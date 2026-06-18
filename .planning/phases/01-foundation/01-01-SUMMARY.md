---
phase: "01"
plan: "01"
subsystem: foundation
status: COMPLETE
tags: [preflight, state-backend, terragrunt, opentofu, s3, dynamodb]
dependency_graph:
  requires: []
  provides: [state-backend-scripts, root-terragrunt-config, preflight-validator]
  affects: [01-02, 01-03, all-future-terragrunt-units]
tech_stack:
  added: [OpenTofu, Terragrunt, AWS CLI, Bash]
  patterns: [idempotent-bootstrap, flat-layout, path-relative-state-keys]
key_files:
  created:
    - scripts/preflight.sh
    - scripts/bootstrap-state.sh
    - terragrunt.hcl
    - management/state-bootstrap/.gitkeep
  modified: []
key_decisions:
  - "terraform_binary = tofu pinned in root terragrunt.hcl to prevent non-deterministic binary detection (Pitfall 9)"
  - "us-east-1 bucket creation omits --create-bucket-configuration per AWS API constraint"
  - "SCP check degrades gracefully when jq absent — warns but does not block"
  - "AWSControlTowerExecution role check validates trust+policy when pre-existing rather than always blocking"
metrics:
  completed: "2026-06-18"
---

# Phase 1 Plan 01: Pre-flight Script + State Bootstrap Summary

**One-liner:** Bash pre-flight validator (5 CT enrollment checks) and idempotent S3+DynamoDB state bootstrap with root Terragrunt config pinned to OpenTofu.

## What Was Built

### Task 1 — `scripts/preflight.sh`

Read-only validation script that hard-blocks (exit 1) on any Control Tower enrollment blocker. Five checks:

1. **AWS Config recorders** — lists existing recorders; fails with per-recorder remediation commands.
2. **Conflicting SCPs** — inspects SCPs attached to the org root for Deny statements on `controltower:*`, `cloudformation:*`, `config:*`, `cloudtrail:*`. Degrades gracefully without `jq` (warns, does not block).
3. **IAM role conflicts** — checks `AWSControlTowerExecution` (validates trust+AdministratorAccess if pre-existing), plus `AWSControlTowerAdmin`, `AWSControlTowerCloudTrailRole`, `AWSControlTowerConfigRecorderRole`.
4. **Organizations trusted access** — verifies all four required service principals are enabled; emits per-principal remediation.
5. **CloudTrail multi-region conflicts** — detects multi-region trails with HomeRegion=us-east-1.

Script uses ANSI color output (`[PASS]` green, `[FAIL]` red, `[INFO]` yellow) and a `BLOCKERS` counter.

### Task 2 — `scripts/bootstrap-state.sh` + `terragrunt.hcl` + `management/state-bootstrap/.gitkeep`

- **bootstrap-state.sh** — resolves management account ID at runtime; creates `chain-vote-tofu-state-${ACCOUNT_ID}` S3 bucket (versioning + SSE-S3 + public access block) and `chain-vote-tofu-locks` DynamoDB table (PAY_PER_REQUEST). Fully idempotent — re-run safe.
- **terragrunt.hcl** (repo root) — sets `terraform_binary = "tofu"`, shared `remote_state` with `get_aws_account_id()` for bucket name and `path_relative_to_include()` for state key. Generates `versions.tf` (aws >= 6.0.0 < 7.0.0) and `provider.tf` (`if_exists = "skip"` to allow child overrides).
- **management/state-bootstrap/.gitkeep** — placeholder confirming D-01 flat layout.

## Files Created

| File | Purpose |
|------|---------|
| `scripts/preflight.sh` | CT enrollment pre-flight validator (executable) |
| `scripts/bootstrap-state.sh` | Idempotent S3+DynamoDB state backend bootstrap (executable) |
| `terragrunt.hcl` | Repo-root Terragrunt config (OpenTofu binary + shared remote state) |
| `management/state-bootstrap/.gitkeep` | Flat layout placeholder for D-01 |

## Commit

- `6830267` — `feat(01-01): pre-flight script + state bootstrap + root terragrunt config`

## Deviations from Plan

**1. [Rule 2 - Missing Critical Functionality] AWSControlTowerExecution role check enhanced**
- **Found during:** Task 1 implementation
- **Issue:** The plan described checking if the role "exists with wrong trust/policy" but did not specify what correct trust looks like.
- **Fix:** Added trust validation by comparing the role's `AssumeRolePolicyDocument` against the caller's management account ID, and verifying `AdministratorAccess` is attached. If both conditions are met, the check passes rather than hard-blocking on any pre-existing role.
- **Rationale:** A pre-existing CT execution role with correct configuration is valid (e.g., after a partial prior CT setup). Hard-blocking all pre-existing roles would require unnecessary remediation.
- **Files modified:** `scripts/preflight.sh`
- **Commit:** 6830267

**2. [Rule 2 - Missing Critical Functionality] SSE-S3 BucketKeyEnabled=true**
- **Found during:** Task 2 implementation
- **Issue:** Plan specified SSE-S3 encryption. Adding `BucketKeyEnabled: true` reduces KMS API call costs if encryption is later upgraded to SSE-KMS, and is a zero-cost improvement for SSE-S3.
- **Fix:** Added `"BucketKeyEnabled":true` to the `put-bucket-encryption` call.
- **Files modified:** `scripts/bootstrap-state.sh`
- **Commit:** 6830267

## AWS Credentials

AWS credentials were confirmed active at plan start:
- Account: `511531327508`
- IAM User: `arn:aws:iam::511531327508:user/jsreed`

## Known Stubs

None — all scripts are fully wired. State backend resources are created at runtime by `bootstrap-state.sh`.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes beyond what the plan's threat model addresses.

## Operator Next Steps

1. **Run pre-flight check** (requires management account credentials with Organizations, IAM, Config, CloudTrail read access):
   ```bash
   ./scripts/preflight.sh
   ```
   Fix any blockers before proceeding. The script exits 0 only when all 5 checks pass.

2. **Bootstrap state backend** (requires S3FullAccess + DynamoDBFullAccess in management account):
   ```bash
   ./scripts/bootstrap-state.sh
   ```
   This creates `chain-vote-tofu-state-511531327508` and `chain-vote-tofu-locks` in us-east-1.

3. **Proceed to Plan 01-02** — CT landing zone data source unit (`management/ct-bootstrap/`) which reads the landing zone after manual console deployment.

## Self-Check: PASSED

- [x] `scripts/preflight.sh` exists and is executable
- [x] `scripts/bootstrap-state.sh` exists and is executable
- [x] `terragrunt.hcl` exists at repo root with `terraform_binary = "tofu"` and `path_relative_to_include()`
- [x] `management/state-bootstrap/.gitkeep` exists
- [x] Both scripts pass `bash --norc -n` syntax check
- [x] Commit `6830267` confirmed in git log
- [x] No unexpected file deletions in commit
