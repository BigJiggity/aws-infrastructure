# Phase 1: Foundation - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver: pre-flight validation, S3+DynamoDB state backend, Terragrunt root config wired to OpenTofu, CT landing zone live (manual console + IaC wrapper for ID capture), and the 6-OU nested structure in AWS Organizations. Nothing else — no AFT, no account vending.

</domain>

<decisions>
## Implementation Decisions

### Terragrunt Directory Layout
- **D-01:** Use **flat layout** — `management/ct-bootstrap/`, `management/aft/`, `management/state-bootstrap/`. Not environment-keyed. Simple, fewer directories, appropriate for a single-org management account.
- **D-02:** Root `terragrunt.hcl` at repo root sets `terraform_binary = "tofu"` and defines the shared remote_state config with `path_relative_to_include()` for state key derivation.

### CT Landing Zone Bootstrap
- **D-03:** **Manual console + IaC wrapper** — deploy CT landing zone via AWS console (~45 min). After CT is live, write an OpenTofu data source unit (`management/ct-bootstrap/`) that reads the landing zone via `aws_controltower_landing_zone` data source and exports Log Archive account ID, Audit account ID, and landing zone ARN as Terragrunt outputs for downstream use. Do NOT manage CT with `tofu apply` — CT self-manages via CloudFormation StackSets and will conflict.
- **D-04:** The CT console deployment step must be documented as a runbook in `docs/runbooks/01-ct-landing-zone.md` with explicit pre-checks and verification steps.

### State Backend Bootstrap
- **D-05:** **Bootstrap script** — `scripts/bootstrap-state.sh` creates the S3 state bucket and DynamoDB lock table via `aws` CLI before any `tofu init` or `terragrunt run-all` executes. One-time manual step. Script must be idempotent (safe to re-run). Documents bucket name and table name as outputs.
- **D-06:** State bucket name convention: `chain-vote-tofu-state-{management_account_id}` in us-east-1. DynamoDB table: `chain-vote-tofu-locks`.

### Pre-flight Script
- **D-07:** **Hard block (exit 1)** on any blocker found. The script fails loudly — operator must fix before proceeding to CT deploy. No warnings-only mode.
- **D-08:** Script checks: (1) existing AWS Config recorders per account, (2) conflicting SCPs that would block CT, (3) IAM role conflicts (`AWSControlTowerExecution` pre-existence), (4) Organizations trusted access for CT service principals, (5) existing CloudTrail trails that conflict with CT mandatory trail.
- **D-09:** Script output: colored pass/fail per check, with remediation command for each failure.

### Claude's Discretion
- OU registration tooling: researcher and planner choose whether OUs are created via `aws_organizations_organizational_unit` resources in a dedicated Terragrunt unit or via a separate approach — no user preference stated.
- Pre-flight script language: Bash is expected given the `aws` CLI usage pattern, but planner can use Python if there's a strong reason.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Context
- `.planning/PROJECT.md` — project constraints (OpenTofu over Terraform, S3+DynamoDB state, us-east-1, flat Terragrunt layout)
- `.planning/REQUIREMENTS.md` — v1 requirements; Phase 1 covers FOUND-01..04, STATE-01..02
- `.planning/ROADMAP.md` §Phase 1 — success criteria and plan breakdown

### Research Findings
- `.planning/research/STACK.md` — verified versions: AFT 1.20.1, OpenTofu 1.12.2, Terragrunt 1.0.8, aws provider ≥ 6.0.0
- `.planning/research/PITFALLS.md` — pre-flight checklist items, OU parent-before-child ordering, Terragrunt binary pinning
- `.planning/research/ARCHITECTURE.md` — build order, two separate state buckets (Terragrunt vs AFT), flat directory pattern
- `.planning/research/SUMMARY.md` — synthesized key facts for quick reference

### No external specs
No external ADRs or spec files exist yet — requirements fully captured in decisions above and REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield repo, no existing code.

### Established Patterns
- None yet — this phase establishes the foundational patterns all subsequent phases follow.

### Integration Points
- `management/ct-bootstrap/` outputs (Log Archive account ID, Audit account ID, landing zone ARN) are consumed by the AFT module in Phase 2.
- Root `terragrunt.hcl` remote_state config is inherited by all Terragrunt units in Phases 2 and 3.

</code_context>

<specifics>
## Specific Ideas

- Flat directory layout chosen explicitly: `management/ct-bootstrap/`, `management/aft/`, `management/state-bootstrap/`
- State bucket name must embed management account ID: `chain-vote-tofu-state-{management_account_id}`
- Pre-flight script at `scripts/bootstrap-state.sh` (bootstrap) and `scripts/preflight.sh` (CT checks)
- CT landing zone runbook at `docs/runbooks/01-ct-landing-zone.md`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 1-Foundation*
*Context gathered: 2026-06-17*
