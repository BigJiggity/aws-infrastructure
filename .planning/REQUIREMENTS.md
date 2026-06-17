# Requirements: AWS Control Tower + AFT for chain-vote

**Defined:** 2026-06-17
**Core Value:** Every chain-vote account is provisioned consistently, enrolled under Control Tower governance, and reproducible from code with no manual ClickOps.

## v1 Requirements

### Foundation

- [ ] **FOUND-01**: Operator can run a pre-flight validation script that audits the existing org for CT enrollment blockers (Config recorders, conflicting SCPs, IAM role conflicts, Organizations trusted access gaps)
- [ ] **FOUND-02**: CT landing zone is deployed in the management account (us-east-1) with Log Archive and Audit accounts created and baselined
- [ ] **FOUND-03**: Nested OU structure exists in AWS Organizations: Root → chain-vote-ai → {dev, staging, prod}; Root → chain-vote-voting → {dev, staging, prod}
- [ ] **FOUND-04**: S3 state bucket and DynamoDB lock table are bootstrapped in the management account before any Terragrunt `run-all` executes

### AFT Setup

- [ ] **AFT-01**: 4 AFT GitHub repos exist in the existing GitHub org with correct directory structure (aft-account-request, aft-global-customizations, aft-account-customizations, aft-account-provisioning-customizations)
- [ ] **AFT-02**: AFT v1.20.1 module is deployed into the management account via Terragrunt + OpenTofu with `terraform_distribution = "oss"` and 5 required provider aliases configured
- [ ] **AFT-03**: CodeConnections GitHub connection is authorized and AFT CodePipeline is successfully wired to all 4 GitHub repos
- [ ] **AFT-04**: `aft_feature_delete_default_vpcs_enabled = true` removes default VPCs from all vended accounts at provisioning time

### Account Vending

- [ ] **ACCT-01**: Existing management/root account is enrolled under CT governance without breaking existing workloads
- [ ] **ACCT-02**: 6 chain-vote accounts are provisioned via AFT account-request files: chain-vote-ai-dev, chain-vote-ai-staging, chain-vote-ai-prod, chain-vote-voting-dev, chain-vote-voting-staging, chain-vote-voting-prod
- [ ] **ACCT-03**: All vended accounts have mandatory tags applied: CostCenter, Environment, Workload, Owner
- [ ] **ACCT-04**: Account provisioning process enforces serial submission (one account-request at a time) to avoid CT Service Catalog concurrency failures

### State and Config

- [ ] **STATE-01**: Terragrunt root config explicitly sets `terraform_binary = "tofu"` to prevent binary auto-detection non-determinism
- [ ] **STATE-02**: Terragrunt state keys are derived from directory path via `path_relative_to_include()` with no manual key management required

## v2 Requirements

### Security Guardrails

- **SEC-01**: Custom preventive SCPs restrict per-OU blast radius (e.g., chain-vote-voting production locked to us-east-1 only)
- **SEC-02**: Elective CT detective controls enabled on production OUs after workload access patterns are understood

### Identity

- **IDN-01**: IAM Identity Center permission sets defined per workload and environment (dev read/write, prod read-only)
- **IDN-02**: Permission sets assigned to accounts via AFT global-customizations

### Networking

- **NET-01**: Shared services VPC provisioned for cross-account connectivity
- **NET-02**: Transit Gateway hub-and-spoke connects chain-vote-ai and chain-vote-voting accounts per environment

### Observability

- **OBS-01**: Centralized CloudWatch cross-account observability configured for chain-vote workload accounts
- **OBS-02**: AWS Security Hub aggregated in audit account across all enrolled accounts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Custom SCPs in v1 | CT mandatory controls are the floor; elective guardrails need workload access patterns first |
| account-provisioning-customizations (Step Functions) | Anti-feature at this scale — anything needed can go in global customizations |
| Terraform Cloud / HCP state | S3 + DynamoDB is sufficient, no external dependency |
| Multi-region CT expansion | Single home region (us-east-1) for v1; expand per workload need |
| CodeCommit as VCS | Deprecated by AWS (no new customers since mid-2024); GitHub only |
| IAM Identity Center automation in v1 | Permission sets need workload identity design before automation |
| Secondary AFT state region | Skip replication for now; revisit if DR requirements emerge |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 | Pending |
| FOUND-02 | Phase 1 | Pending |
| FOUND-03 | Phase 1 | Pending |
| FOUND-04 | Phase 1 | Pending |
| STATE-01 | Phase 1 | Pending |
| STATE-02 | Phase 1 | Pending |
| AFT-01 | Phase 2 | Pending |
| AFT-02 | Phase 2 | Pending |
| AFT-03 | Phase 2 | Pending |
| AFT-04 | Phase 2 | Pending |
| ACCT-01 | Phase 3 | Pending |
| ACCT-02 | Phase 3 | Pending |
| ACCT-03 | Phase 3 | Pending |
| ACCT-04 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-17*
*Last updated: 2026-06-17 after roadmap creation*
