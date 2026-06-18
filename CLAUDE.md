# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Build & Test

_Add your build and test commands here_

```bash
# Example:
# npm install
# npm test
```

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_

<!-- GSD:project-start source:PROJECT.md -->
## Project

**AWS Control Tower + AFT for chain-vote**

Infrastructure-as-code setup for AWS Control Tower with Account Factory for Terraform (AFT), managed via OpenTofu and Terragrunt. Governs an existing AWS organization with nested OUs (by workload then environment) and provisions six accounts for the chain-vote project — an AI chat service and a blockchain voting system — across dev/staging/prod.

**Core Value:** Every chain-vote account is provisioned consistently, enrolled under Control Tower governance, and reproducible from code with no manual ClickOps.

### Constraints

- **IaC Runtime**: OpenTofu (not Terraform) — licensing preference
- **Orchestration**: Terragrunt — DRY pattern across accounts and environments
- **Account Factory**: AFT — AWS-managed pipeline, requires CodePipeline in management account
- **State Backend**: S3 + DynamoDB — no external state services
- **Home Region**: us-east-1 — Control Tower and AFT deployed here
- **Source of Truth**: This repo (`aws-infrastructure`) owns all CT/AFT/account config
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### IaC Runtime
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| OpenTofu | `>= 1.8, < 2.0` (pin to `1.12.2`) | IaC runtime replacing Terraform | Licensing preference; fully compatible with AFT's HCL syntax which requires `>= 1.6.1`. OpenTofu 1.8+ tracks Terraform 1.8 feature parity. Current stable is 1.12.2 (2026-06-12). |
| Terragrunt | `1.0.8` | DRY orchestration, provider injection, remote state wiring | v1.x is now the stable major release (2026-06-10). Critically: Terragrunt v1.x defaults its binary lookup to `tofu`, not `terraform` — no extra config needed to run OpenTofu. |
### AFT Module
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| aws-ia/terraform-aws-control_tower_account_factory | `1.20.1` (2026-05-20) | Deploys AFT pipeline into management account | Official AWS-maintained module. Only supported AFT delivery mechanism. Do NOT use community forks — the invert-inc fork is stale (last updated 2023). |
### AWS Provider
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| hashicorp/aws | `>= 6.0.0, < 7.0.0` (pin to `6.50.0`) | All AWS resource management | AFT versions.tf mandates this range. Current release is 6.50.0 (2026-06-10). |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tofuutils/tenv | latest | Manages multiple OpenTofu/Terraform versions locally and in CI | Use in CI CodeBuild containers to install the right OpenTofu version; also handles developer workstations |
## Critical Architecture Constraint: OpenTofu + AFT
## Layer Architecture
## AFT Required Accounts
| Account | Purpose | Required Before AFT? |
|---------|---------|---------------------|
| Management account | Runs AFT module via OpenTofu/Terragrunt | Yes |
| Log Archive account | CT-managed; must exist in CT | Yes (CT creates it) |
| Audit account | CT-managed; must exist in CT | Yes (CT creates it) |
| AFT Management account | Dedicated account for AFT pipeline | Yes — must be vended via CT Service Catalog before `tofu apply` |
## AFT Module Inputs (Relevant to This Project)
## Terragrunt Configuration Pattern
# infrastructure/management/aft/terragrunt.hcl
# Terragrunt generates backend.tf — AFT module README explicitly says
# "does not manage a backend Terraform state"
# Terragrunt generates providers.tf with multi-account provider aliases
# AFT module requires 5 AWS provider aliases
## State Backend
| Resource | Config | Why |
|----------|--------|-----|
| S3 bucket | `chain-vote-tofu-state-{account_id}` in management account | Standard; management account owns all state |
| DynamoDB table | `chain-vote-tofu-locks` | State locking; prevents concurrent applies |
| Encryption | SSE-S3 (default) or SSE-KMS | Enable KMS for compliance if needed |
| Versioning | Enabled | Required for state recovery |
| Region | `us-east-1` | Same as CT home region |
## AWS Providers Required
# In root terragrunt.hcl or versions.tf equivalent
- `aws.ct_management` — management account
- `aws.log_archive` — log archive account
- `aws.audit` — audit account
- `aws.aft_management` — AFT management account
- `aws.tf_backend_secondary_region` — secondary region for AFT backend replication
## What NOT to Use
| Option | Why Not |
|--------|---------|
| Landing Zone Accelerator (LZA) | CloudFormation-based, not OpenTofu/Terragrunt; different toolchain entirely. Overkill for 6 accounts. |
| Gruntwork terraform-aws-control-tower module | Requires Gruntwork subscription (paid). No public releases found. |
| terraform-aws-modules/* for CT | No terraform-aws-modules Control Tower modules exist. The community module set covers networking/compute, not CT. |
| Community AFT forks | stale (invert-inc last updated 2023). Maintenance liability. |
| CodeCommit repos for AFT | AWS deprecated CodeCommit. Use GitHub (supported by AFT via `vcs_provider = "github"`). |
| Terraform Cloud / HCP | Out of scope per PROJECT.md. AFT supports it via `terraform_distribution = "tfc"` but not needed. |
| `aft_tf_distribution = "TF"` flag | This variable does not exist in AFT. The PROJECT.md reference is incorrect. |
## Installation
# Install OpenTofu (macOS)
# or via tenv (recommended for version management)
# Install Terragrunt
# or
# Verify
## Confidence Assessment
| Claim | Confidence | Source |
|-------|-----------|--------|
| AFT version 1.20.1 is current | HIGH | GitHub releases API (live, 2026-06-10) |
| AFT requires `>= 1.6.1, < 2.0.0` | HIGH | versions.tf fetched live from main branch |
| AFT requires `hashicorp/aws >= 6.0.0` | HIGH | versions.tf fetched live |
| AFT has NO OpenTofu support | HIGH | variables.tf validation, buildspec content, open issue #451 |
| `terraform_distribution` values are `oss/tfc/tfe` only | HIGH | variables.tf validation constraint, fetched live |
| `aft_feature_flags.aft_tf_distribution` does not exist | HIGH | Full variables.tf scan, no such variable found |
| Terragrunt v1.x defaults to `tofu` binary | HIGH | Context7 docs (gruntwork-io/terragrunt), `--tf-path` flag docs |
| Terragrunt 1.0.8 is current | HIGH | GitHub releases API (live, 2026-06-10) |
| OpenTofu 1.12.2 is current stable | HIGH | GitHub releases API (live, 2026-06-12) |
| hashicorp/aws 6.50.0 is current | HIGH | GitHub releases API (live, 2026-06-10) |
| AFT buildspecs download from releases.hashicorp.com | HIGH | aft-account-customizations-terraform.yml fetched live |
| CodeCommit deprecated by AWS | MEDIUM | Web search consensus; AWS deprecated CodeCommit in 2024 |
## Sources
- AFT GitHub repo: https://github.com/aws-ia/terraform-aws-control_tower_account_factory
- AFT OpenTofu issue: https://github.com/aws-ia/terraform-aws-control_tower_account_factory/issues/451
- AFT versions.tf (live): https://raw.githubusercontent.com/aws-ia/terraform-aws-control_tower_account_factory/main/versions.tf
- AFT variables.tf (live): https://raw.githubusercontent.com/aws-ia/terraform-aws-control_tower_account_factory/main/variables.tf
- AFT buildspec (live): https://raw.githubusercontent.com/aws-ia/terraform-aws-control_tower_account_factory/main/modules/aft-customizations/buildspecs/aft-account-customizations-terraform.yml
- Terragrunt --tf-path docs: https://github.com/gruntwork-io/terragrunt (Context7)
- OpenTofu releases: https://github.com/opentofu/opentofu/releases
- Terragrunt releases: https://github.com/gruntwork-io/terragrunt/releases
- AWS provider releases: https://github.com/hashicorp/terraform-provider-aws/releases
- AWS AFT docs: https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
