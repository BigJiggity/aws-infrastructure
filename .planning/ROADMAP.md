# Roadmap: AWS Control Tower + AFT for chain-vote

## Overview

Starting from an existing AWS organization with no Control Tower, this roadmap drives sequentially through three hard-ordered delivery gates: lay the foundation (pre-flight, state backend, CT landing zone, OU structure); bootstrap AFT (repos, pipeline, GitHub auth, OpenTofu config); and vend all six chain-vote accounts under CT governance. Each gate is a complete, verifiable capability before the next begins.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation** - Pre-flight checks, state bootstrap, CT landing zone, and OU structure are in place
- [ ] **Phase 2: AFT Bootstrap** - AFT pipeline is deployed, GitHub-connected, and validated end-to-end
- [ ] **Phase 3: Account Vending** - All six chain-vote accounts provisioned under CT governance

## Phase Details

### Phase 1: Foundation
**Goal**: The landing zone is live, remote state is bootstrapped, Terragrunt root config is wired, and the OU skeleton exists — ready to receive AFT
**Depends on**: Nothing (first phase)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, STATE-01, STATE-02
**Success Criteria** (what must be TRUE):
  1. Pre-flight script runs without errors and reports no CT enrollment blockers in the existing org
  2. S3 state bucket and DynamoDB lock table exist in the management account and Terragrunt can init against them
  3. Terragrunt root config uses `terraform_binary = "tofu"` and state keys are derived from directory path — no manual key management
  4. CT landing zone is deployed in us-east-1 with Log Archive and Audit accounts created and baselined (verified in CT console)
  5. AWS Organizations shows nested OU structure: Root → chain-vote-ai → {dev, staging, prod}; Root → chain-vote-voting → {dev, staging, prod}
**Plans**: TBD

Plans:
- [ ] 01-01: Pre-flight script + state bootstrap (FOUND-01, FOUND-04, STATE-01, STATE-02)
- [ ] 01-02: CT landing zone runbook + IaC wrapper (FOUND-02)
- [ ] 01-03: Nested OU structure via OpenTofu + Terragrunt (FOUND-03)

### Phase 2: AFT Bootstrap
**Goal**: AFT is deployed into the management account via Terragrunt + OpenTofu, wired to all four GitHub repos, and the CodePipeline executes successfully on a test commit
**Depends on**: Phase 1
**Requirements**: AFT-01, AFT-02, AFT-03, AFT-04
**Success Criteria** (what must be TRUE):
  1. Four AFT GitHub repos exist with correct directory structure (aft-account-request, aft-global-customizations, aft-account-customizations, aft-account-provisioning-customizations)
  2. `tofu apply` of the AFT module completes without error; AFT CodePipeline and supporting resources are visible in the management account
  3. CodeConnections GitHub connection shows "Available" status and all four repos are wired to their respective pipelines
  4. A test push to aft-global-customizations triggers a pipeline run that completes without error
  5. Default VPCs are flagged for removal at provisioning time (`aft_feature_delete_default_vpcs_enabled = true` confirmed in AFT config)
**Plans**: TBD

Plans:
- [ ] 02-01: Create 4 AFT GitHub repos with correct structure (AFT-01)
- [ ] 02-02: Deploy AFT module via Terragrunt + OpenTofu; authorize CodeConnections (AFT-02, AFT-03, AFT-04)

### Phase 3: Account Vending
**Goal**: All six chain-vote accounts are provisioned via AFT, enrolled under CT governance, tagged, and the management account itself is enrolled — no manual ClickOps remaining
**Depends on**: Phase 2
**Requirements**: ACCT-01, ACCT-02, ACCT-03, ACCT-04
**Success Criteria** (what must be TRUE):
  1. Management/root account is enrolled in CT without service disruption to existing workloads
  2. All six chain-vote accounts (chain-vote-ai-{dev,staging,prod} and chain-vote-voting-{dev,staging,prod}) appear in CT Account Factory and their OUs in AWS Organizations
  3. Every vended account has mandatory tags applied: CostCenter, Environment, Workload, Owner (verifiable in AWS Organizations tag editor)
  4. Account provisioning was submitted serially (one at a time) with each AFT pipeline completing before the next request is merged — no CT Service Catalog concurrency errors
**Plans**: TBD

Plans:
- [ ] 03-01: Enroll management account under CT (ACCT-01)
- [ ] 03-02: Submit and validate 6 account-request files serially; verify tags (ACCT-02, ACCT-03, ACCT-04)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 0/3 | Not started | - |
| 2. AFT Bootstrap | 0/2 | Not started | - |
| 3. Account Vending | 0/2 | Not started | - |
