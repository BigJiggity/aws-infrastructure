# Architecture Patterns: CT + AFT + Terragrunt

**Domain:** AWS multi-account landing zone with AFT account vending
**Researched:** 2026-06-16
**Confidence:** HIGH (AWS official docs + GitHub source + Terragrunt official docs)

---

## System Overview

This codebase manages three distinct concerns that sit at different layers of the AWS account hierarchy:

1. **Control Tower landing zone** — the governance foundation (OUs, guardrails, shared accounts, IAM Identity Center). Deployed once into the management account via the CT console or CT API. Not managed by Terraform directly; CT manages itself through CloudFormation StackSets under the hood.

2. **AFT deployment** — a Terraform module (`aws-ia/terraform-aws-control_tower_account_factory`) that you apply once into the management account to stand up AFT infrastructure: CodePipeline, CodeBuild, Step Functions, DynamoDB, and four CodeCommit/GitHub repos. AFT lives in the management account but delegates to a separate **AFT management account** it creates internally for its own runtime state.

3. **Account requests + customizations** — ongoing GitOps: Terraform files in the account-request repo describe accounts to vend; global and per-account customization repos hold Terraform applied to each vended account after creation.

Terragrunt wraps layers 2 and 3 for DRY orchestration and state management.

---

## Component Map

```
Management Account (org root)
├── Control Tower (Console/API bootstrap — not IaC-managed after init)
│   ├── Security OU
│   │   ├── Log Archive Account
│   │   └── Audit Account
│   ├── Sandbox OU (CT default)
│   └── chain-vote OU  ← you create this
│       ├── chain-vote-ai OU
│       │   ├── chain-vote-ai-dev
│       │   ├── chain-vote-ai-staging
│       │   └── chain-vote-ai-prod
│       └── chain-vote-voting OU
│           ├── chain-vote-voting-dev
│           ├── chain-vote-voting-staging
│           └── chain-vote-voting-prod
│
├── AFT Infrastructure (Terraform-deployed into mgmt account)
│   ├── CodePipeline: ct-aft-account-request
│   ├── CodePipeline: ct-aft-account-provisioning-customizations (per-account)
│   ├── CodeBuild projects (account-request, global-customizations, account-customizations)
│   ├── Step Functions state machines
│   ├── DynamoDB (account request queue)
│   ├── SQS (event routing)
│   └── S3 (AFT state + artifact storage)
│
└── AFT Management Account (created by AFT, separate from CT management)
    └── AFT runtime Terraform state (S3 + DynamoDB)

Four Git Repositories (CodeCommit or GitHub)
├── aft-account-request          ← declare accounts to vend
├── aft-global-customizations    ← Terraform applied to ALL vended accounts
├── aft-account-customizations   ← Terraform applied to SPECIFIC accounts
└── aft-account-provisioning-customizations  ← Step Functions / Lambda pre-provisioning hooks
```

---

## AFT's Four Repositories in Detail

### aft-account-request

Contains one or more `.tf` files, each calling the AFT account-request module:

```hcl
module "chain_vote_ai_dev" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "chain-vote-ai-dev@example.com"
    AccountName               = "chain-vote-ai-dev"
    ManagedOrganizationalUnit = "chain-vote-ai (ou-xxxx-xxxxxxxx)"
    SSOUserEmail              = "admin@example.com"
    SSOUserFirstName          = "Admin"
    SSOUserLastName           = "User"
  }

  account_tags = {
    workload    = "chain-vote-ai"
    environment = "dev"
    managed-by  = "aft"
  }

  change_management_parameters = {
    change_requested_by = "terraform"
    change_reason       = "initial account vending"
  }

  custom_fields = {
    group = "chain-vote"
  }

  account_customizations_name = "chain-vote-ai"  # links to aft-account-customizations/<name>/
}
```

You can put all six account requests in a single `.tf` file or one per account. AFT processes them FIFO from SQS.

### aft-global-customizations

```
aft-global-customizations/
├── api_helpers/
│   └── python/
│       └── requirements.txt   # Lambda helper deps (AFT-provided hooks)
└── terraform/
    ├── main.tf                 # resources created in every vended account
    ├── variables.tf
    └── # NO backend.tf or provider.tf — AFT generates these via Jinja templates
```

AFT renders `backend.tf` and `provider.tf` at apply time using Jinja. You must NOT commit those files. If you need extra providers, create `providers.tf` yourself.

### aft-account-customizations

```
aft-account-customizations/
├── chain-vote-ai/              # matches account_customizations_name in account-request
│   ├── api_helpers/
│   │   └── python/
│   └── terraform/
│       └── main.tf
└── chain-vote-voting/
    ├── api_helpers/
    │   └── python/
    └── terraform/
        └── main.tf
```

The directory name under `aft-account-customizations/` must match `account_customizations_name` set in the account-request module call. Accounts sharing the same customization directory get the same Terraform applied.

### aft-account-provisioning-customizations

Pre-provisioning hooks using AWS Step Functions + Lambda. Use for: external CMDB registration, tagging enforcement checks, IPAM allocations before the account is enrolled. Most small deployments leave this nearly empty (just the skeleton state machine definition).

```
aft-account-provisioning-customizations/
└── lambda/
    └── (optional Lambda functions)
```

---

## Monorepo vs. Separate Repos

**The standard AFT design is four separate repos.** AFT CodePipeline triggers are configured on repo-push events; each of the four repos is registered independently when you deploy the AFT Terraform module.

**Monorepo is not natively supported.** GitHub issue [aws-ia#544](https://github.com/aws-ia/terraform-aws-control_tower_account_factory/issues/544) tracks this as a feature request with no ship date as of 2026-06.

**For this project:** The `aws-infrastructure` repo is the Terragrunt orchestration repo and the AFT deployment repo. The four AFT customization repos should be separate repositories. Recommended naming:

```
aws-infrastructure          ← this repo (CT + AFT deployment + Terragrunt live)
aft-account-request         ← separate repo, registered with AFT pipeline
aft-global-customizations   ← separate repo
aft-account-customizations  ← separate repo
aft-account-provisioning-customizations  ← separate repo (can start empty)
```

This repo (`aws-infrastructure`) holds the Terragrunt `live/` tree and the AFT module invocation (`modules/aft/main.tf`). The four AFT repos are separate because AFT's CodePipeline source actions point to those repos by name/URL.

---

## Recommended Directory Layout: aws-infrastructure

```
aws-infrastructure/
│
├── root.hcl                          # Terragrunt root: remote_state, generate provider
│
├── modules/
│   └── aft/
│       └── main.tf                   # AFT module invocation (aws-ia/terraform-aws-control_tower_account_factory)
│                                     # Sets: ct_management_account_id, vcs_provider, repo names, terraform_distribution
│
└── live/                             # Terragrunt live environment tree
    │
    ├── management/                   # Management account resources
    │   └── us-east-1/
    │       ├── account.hcl           # account_id = "111122223333", account_name = "management"
    │       └── aft-deployment/
    │           └── terragrunt.hcl    # calls modules/aft, depends on CT being live
    │
    └── chain-vote/                   # Workload accounts (post-vend config via Terragrunt, optional)
        ├── ai/
        │   ├── dev/
        │   │   └── us-east-1/
        │   │       ├── account.hcl
        │   │       └── <modules>/
        │   ├── staging/
        │   └── prod/
        └── voting/
            ├── dev/
            ├── staging/
            └── prod/
```

**Key pattern:** `root.hcl` at the repo root uses `path_relative_to_include()` to derive unique S3 keys automatically. Each `terragrunt.hcl` leaf calls `find_in_parent_folders("root.hcl")`.

---

## Root Terragrunt Config (root.hcl)

```hcl
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "aws-infra-tfstate-${local.account_id}"
    key            = "${path_relative_to_include()}/tofu.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "aws-infra-tfstate-lock"
    # Assume role into the target account for cross-account state access:
    role_arn       = "arn:aws:iam::${local.account_id}:role/TerragruntStateRole"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${local.account_id}:role/TerragruntDeployRole"
  }
}
EOF
}
```

---

## S3 State Bucket Layout

There are two distinct state storage concerns that must not be confused:

### Terragrunt-managed state (your IaC in this repo)

Use **per-account buckets** to avoid cross-account S3 permission complexity:

```
s3://aws-infra-tfstate-<mgmt-account-id>/
  management/us-east-1/aft-deployment/tofu.tfstate

s3://aws-infra-tfstate-<ai-dev-account-id>/
  chain-vote/ai/dev/us-east-1/<module>/tofu.tfstate
```

OR a **single bucket in the management account** with per-account prefixes:

```
s3://aws-infra-tfstate-<mgmt-account-id>/
  management/us-east-1/aft-deployment/tofu.tfstate
  chain-vote/ai/dev/us-east-1/<module>/tofu.tfstate
  chain-vote/ai/staging/us-east-1/<module>/tofu.tfstate
  ...
```

The path key is automatically derived from directory structure by `path_relative_to_include()`.

Recommendation: **single bucket in management account** for simplicity at this scale (6 workload accounts). Add a bucket policy restricting access by account ID prefix in the state key.

### AFT-managed state (AFT pipeline state for vended account customizations)

AFT creates and manages its own S3 bucket in the AFT management account. State keys follow:

```
s3://aft-backend-<aft-mgmt-account-id>-<region>/
  <vended-account-id>-aft-global-customizations/terraform.tfstate
  <vended-account-id>-aft-account-customizations/terraform.tfstate
```

You do not manage this bucket. AFT owns it. Do not mix this with Terragrunt state.

---

## AFT Pipeline Flow

```
Developer pushes to aft-account-request repo
           |
           v
ct-aft-account-request CodePipeline (in management account)
  Stage 1: CodeBuild — validate Terraform, write account details to DynamoDB
           |
           v
  Stage 2: Lambda — DynamoDB stream triggers SQS message
           |
           v
  Stage 3: Lambda — reads SQS, calls CT Account Factory (Service Catalog) API
           |
           v
  CT Account Factory creates/enrolls the AWS account (~15-30 min)
           |
           v
  Stage 4: Lambda — account created event triggers per-account CodePipeline
           |
           v
Per-account CodePipeline (one per vended account)
  Stage 1: aft-account-provisioning-customizations (Step Functions)
           — runs pre-provisioning Lambda hooks
           |
           v
  Stage 2: aft-global-customizations CodeBuild
           — tofu init / plan / apply in vended account
           — applies to ALL accounts (e.g., baseline IAM, CloudTrail settings)
           |
           v
  Stage 3: aft-account-customizations CodeBuild
           — tofu init / plan / apply for account_customizations_name
           — applies only to accounts with that customization label
```

Re-running customizations without re-vending: push to `aft-global-customizations` or `aft-account-customizations` — AFT triggers a customization-only pipeline run against all existing accounts without re-creating them.

---

## Where CT Landing Zone Config Lives vs. AFT Config

| Concern | Where it lives | How to change |
|---------|---------------|---------------|
| CT landing zone version, home region | CT console / CT API | `aws controltower update-landing-zone` or console |
| OU structure (Security, Sandbox, custom OUs) | CT console / Organizations API | `aws organizations create-organizational-unit` then CT register |
| CT guardrails / controls | CT console or CT controls API | Terraform `aws_controltower_control` resource (post-deployment) |
| IAM Identity Center config | IAM Identity Center console or SSO Terraform provider | Terraform `aws_ssoadmin_*` resources |
| AFT infrastructure (pipelines, DynamoDB, S3) | `live/management/us-east-1/aft-deployment/terragrunt.hcl` | `tofu apply` |
| AFT feature flags (CloudTrail events, delete default VPC) | `aft_feature_*` vars in AFT module | change vars, re-apply AFT module |
| Account requests (which accounts to create) | `aft-account-request` repo | push .tf file, pipeline runs |
| Per-account baseline (global customizations) | `aft-global-customizations` repo | push changes, pipeline re-applies to all |
| Per-workload config (account customizations) | `aft-account-customizations/<name>/` | push changes, pipeline re-applies to matching accounts |

---

## OpenTofu + AFT Compatibility

AFT's `terraform_distribution` variable accepts `"oss"` (open source Terraform), `"cloud"`, or `"enterprise"`. There is no native `"opentofu"` value.

The community workaround is to set `terraform_distribution = "oss"` and replace the Terraform binary in the CodeBuild build environment with OpenTofu by modifying the AFT buildspec. AFT's `aft_tf_distribution` variable (referenced in PROJECT.md) refers to this override mechanism: setting it to `"TF"` causes AFT to use the `terraform_distribution` path rather than the default managed binary, allowing substitution of the `tofu` binary.

Confidence: MEDIUM — the approach is documented in community posts and the AFT GitHub README, but the exact variable name `aft_tf_distribution` was introduced in a specific AFT module version. Verify against `aws-ia/terraform-aws-control_tower_account_factory` at the version you pin.

---

## Component Boundaries: What Talks to What

```
┌─────────────────────────────────────────────────────────────────┐
│  aws-infrastructure repo (Terragrunt)                            │
│                                                                   │
│  root.hcl ─────────────────────────────────────────────────────► S3 state bucket
│                                                                   │
│  live/management/.../aft-deployment/terragrunt.hcl              │
│    └── calls aws-ia AFT module ──────────────────────────────► Management acct:
│                                                                   │ CodePipeline
│                                                                   │ CodeBuild
│                                                                   │ Step Functions
└─────────────────────────────────────────────────────────────────┘
                              │
        AFT reads from        │         AFT writes to
        ─────────────────────►│◄─────────────────────────────────
                              │
          aft-account-request repo         DynamoDB (account queue)
          aft-global-customizations repo   SQS (event routing)
          aft-account-customizations repo  CT Account Factory (Service Catalog)
          aft-account-provisioning-        Each vended account (AWSControlTowerExecution role)
            customizations repo
```

AFT assumes the `AWSAFTExecution` role (created in the management account by the AFT Terraform module) to drive CodePipeline and Lambda. It assumes `AWSControlTowerExecution` in each vended account to apply customizations. These roles are created automatically by AFT and CT respectively; you do not manage them.

---

## Build Order (What Must Exist Before What)

The following is the mandatory sequencing. Each step is a hard dependency on the previous.

```
Step 1: AWS Organization + Management Account
  — Must exist (pre-existing in this project)
  — Confirm: no SCPs blocking CT prerequisite services

Step 2: Control Tower Landing Zone (console bootstrap)
  — Creates: Security OU, Log Archive account, Audit account, Sandbox OU
  — Creates: AWSControlTowerExecution role in management account
  — Creates: IAM Identity Center (SSO) instance
  — Duration: 30-60 min
  — HOW: CT console or `aws controltower create-landing-zone` API
  — BLOCKS: everything else

Step 3: Create custom OUs in Organizations
  — chain-vote OU → chain-vote-ai OU, chain-vote-voting OU
  — Register each OU with CT (console: "Register OU") to apply CT governance
  — HOW: `aws organizations create-organizational-unit` + CT console register

Step 4: Deploy AFT (via Terragrunt in this repo)
  — `cd live/management/us-east-1/aft-deployment && terragrunt apply`
  — Provisions: CodePipeline, CodeBuild, Step Functions, DynamoDB, SQS, S3
  — Requires: CT landing zone live, management account ID, four repo URLs
  — Duration: 20-30 min
  — BLOCKS: account requests

Step 5: Push initial account requests
  — Add six account request modules to aft-account-request repo
  — `git push` triggers ct-aft-account-request CodePipeline
  — CT creates each account, enrolls it, applies guardrails
  — Duration: 15-30 min per account (processes sequentially from SQS)
  — BLOCKS: customizations (but customizations apply automatically after vending)

Step 6: Validate customizations
  — Confirm global and account customizations applied correctly
  — Check per-account CodePipeline run status in management account
```

---

## Data Flow Summary

```
Code (in git repos)
     │
     │ git push
     ▼
CodePipeline (management account)
     │
     │ CodeBuild: tofu validate/plan/apply
     ▼
DynamoDB + SQS (account request queue)
     │
     │ Lambda triggers
     ▼
CT Account Factory (Service Catalog provisioned product)
     │
     │ CT vends account + enrolls in OU
     ▼
New AWS Account (in correct OU, under CT governance)
     │
     │ AFT per-account pipeline triggers
     ▼
CodeBuild: tofu apply (assumes AWSControlTowerExecution in target account)
     │
     │ applies global then account customizations
     ▼
Configured AWS Account (IAM, baseline resources, tags as defined in customization repos)
```

---

## Scalability Notes

At 6 accounts, all complexity is bootstrapping, not scale. AFT is designed for hundreds of accounts; the architecture does not change for this scope.

The primary operational model going forward:
- New account needed: add module block to `aft-account-request`, push
- Change baseline config: update `aft-global-customizations`, push (re-applies to all 6 accounts)
- Change workload-specific config: update `aft-account-customizations/chain-vote-ai/`, push

---

## Patterns to Follow

### Pattern: account.hcl for account metadata
Each environment directory contains an `account.hcl` with `account_id` and `account_name` locals. The root `root.hcl` reads this via `read_terragrunt_config(find_in_parent_folders("account.hcl"))`. This makes state keys, role ARNs, and provider configs fully automatic from directory structure.

### Pattern: generate blocks for provider + backend
Use Terragrunt `generate` blocks (not `remote_state` block alone) to emit `backend.tf` and `provider.tf`. This allows Terragrunt to inject `assume_role` into the provider block, enabling cross-account deployments without hardcoded credentials.

### Pattern: dependency blocks for sequencing
Use Terragrunt `dependency` blocks when a module needs outputs from another module:
```hcl
dependency "aft" {
  config_path = "../../aft-deployment"
}
```
This creates explicit DAG edges rather than relying on apply order.

---

## Anti-Patterns to Avoid

### Anti-pattern: Managing CT-created resources in Terraform directly
Control Tower creates and manages Log Archive and Audit accounts, the CloudTrail org trail, and SCPs that implement CT guardrails. Do not import these into Terraform state. CT will overwrite your changes on the next CT update. Manage them through CT APIs or console only.

### Anti-pattern: Putting AFT customization code in this repo
The four AFT repos must be separate repositories with clean histories. AFT CodePipeline source actions point to those repos. Embedding them as directories in `aws-infrastructure` will not trigger AFT pipelines on push (as of 2026-06; see GitHub issue #544).

### Anti-pattern: Backend block in AFT customization Terraform files
AFT's CodeBuild generates `backend.tf` via Jinja template at apply time. If you commit your own `backend.tf` in `aft-global-customizations/terraform/` or `aft-account-customizations/*/terraform/`, the build will fail with a conflict.

### Anti-pattern: Single DynamoDB lock table across accounts
If using a single-bucket approach for Terragrunt state, each account should still use the same DynamoDB table in the management account (Terragrunt supports this). Do not create per-account lock tables — they add cost and complexity with no benefit at this scale.

### Anti-pattern: Applying AFT before CT landing zone is complete
AFT requires CT to be fully deployed and the management account to have the `AWSControlTowerExecution` role active. Running `tofu apply` on the AFT module before CT setup completes will fail with IAM permission errors that look like networking issues.

---

## Sources

- [AFT Architecture — AWS Control Tower docs](https://docs.aws.amazon.com/controltower/latest/userguide/aft-architecture.html) — HIGH confidence
- [Provision a new account with AFT](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html) — HIGH confidence
- [AFT GitHub source — aws-ia/terraform-aws-control_tower_account_factory](https://github.com/aws-ia/terraform-aws-control_tower_account_factory) — HIGH confidence
- [AFT account-request example file](https://github.com/aws-ia/terraform-aws-control_tower_account_factory/blob/main/sources/aft-customizations-repos/aft-account-request/examples/account-request.tf) — HIGH confidence
- [AFT monorepo feature request — GitHub issue #544](https://github.com/aws-ia/terraform-aws-control_tower_account_factory/issues/544) — HIGH confidence (unresolved as of research date)
- [Terragrunt S3 remote state with path_relative_to_include()](https://terragrunt.gruntwork.io/docs/features/state-backend/) — HIGH confidence (Context7 + official docs)
- [AFT Component Services](https://docs.aws.amazon.com/controltower/latest/userguide/aft-components.html) — HIGH confidence
- [AFT Account Customizations](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html) — HIGH confidence
- [AFT in Terraform: Lessons from the Trenches — Medium/practical-aws](https://medium.com/practical-aws/account-factory-for-terraform-lessons-from-the-trenches-7e86a5c4d3ee) — MEDIUM confidence (community, unverified detail)
- [HashiCorp AFT Tutorial](https://developer.hashicorp.com/terraform/tutorials/aws/aws-control-tower-aft) — HIGH confidence
- [AFT inside the black box — OpenCredo](https://opencredo.com/blogs/aws-account-factory-for-terraform-get-inside-the-black-box-by-thinking-outside-the-box) — MEDIUM confidence (community deep-dive)
