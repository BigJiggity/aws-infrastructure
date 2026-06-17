# AWS Control Tower + AFT for chain-vote

## What This Is

Infrastructure-as-code setup for AWS Control Tower with Account Factory for Terraform (AFT), managed via OpenTofu and Terragrunt. Governs an existing AWS organization with nested OUs (by workload then environment) and provisions six accounts for the chain-vote project — an AI chat service and a blockchain voting system — across dev/staging/prod.

## Core Value

Every chain-vote account is provisioned consistently, enrolled under Control Tower governance, and reproducible from code with no manual ClickOps.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Control Tower deployed in us-east-1 management account
- [ ] AFT pipeline configured using OpenTofu (not Terraform)
- [ ] Terragrunt orchestrates the full stack (CT + AFT + account vending)
- [ ] Nested OU structure: Root → {chain-vote-ai, chain-vote-voting} → {dev, staging, prod}
- [ ] 6 accounts provisioned: chain-vote-ai-{dev,staging,prod} and chain-vote-voting-{dev,staging,prod}
- [ ] Existing management/root account enrolled in Control Tower
- [ ] Remote state via S3 + DynamoDB locking
- [ ] Account vending is idempotent and repeatable from code

### Out of Scope

- Custom SCPs / guardrails — using CT defaults for now; define per-workload policies later
- Other workload accounts beyond chain-vote — only these 6 in scope
- Terraform Cloud / HCP — using S3 + DynamoDB only
- Log archive and audit account setup — not enrolling these existing accounts

## Context

- Project lives at `~/repos/aws-infrastructure`; chain-vote source at `~/repos/chain-vote`
- chain-vote has two workloads: an AI Chat service (LLM inference) and a voting system (likely blockchain-adjacent)
- Existing AWS org with a management/root account; no Control Tower deployed yet
- OpenTofu chosen over Terraform (licensing); Terragrunt for DRY multi-account orchestration
- AFT chosen over basic CT to get a proper account vending pipeline with customizations and hooks

## Constraints

- **IaC Runtime**: OpenTofu (not Terraform) — licensing preference
- **Orchestration**: Terragrunt — DRY pattern across accounts and environments
- **Account Factory**: AFT — AWS-managed pipeline, requires CodePipeline in management account
- **State Backend**: S3 + DynamoDB — no external state services
- **Home Region**: us-east-1 — Control Tower and AFT deployed here
- **Source of Truth**: This repo (`aws-infrastructure`) owns all CT/AFT/account config

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| AFT over basic CT | Need a proper vending pipeline with per-account customizations and hooks | — Pending |
| OpenTofu over Terraform | Licensing; AFT supports OpenTofu via `aft_feature_flags.aft_tf_distribution = "TF"` override | — Pending |
| Nested OUs (workload → env) | Keeps workload-level SCPs and env-level guardrails cleanly separated | — Pending |
| S3 + DynamoDB state | Standard, no external dependencies, management account hosts state bucket | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-16 after initialization*
