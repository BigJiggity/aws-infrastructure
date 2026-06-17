# Technology Stack

**Project:** AWS Control Tower + AFT for chain-vote
**Researched:** 2026-06-16
**Sources:** aws-ia/terraform-aws-control_tower_account_factory GitHub (verified live), gruntwork-io/terragrunt Context7 docs, opentofu/opentofu GitHub releases, hashicorp/terraform-provider-aws GitHub releases

---

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

---

## Critical Architecture Constraint: OpenTofu + AFT

**This is the most important finding in this research.**

AFT does NOT natively support OpenTofu. GitHub issue [#451 "Allow AFT to support OpenTofu"](https://github.com/aws-ia/terraform-aws-control_tower_account_factory/issues/451) has been open since April 2024 and is still open as of June 2026. AWS acknowledged the request internally in March 2025 but has not shipped support.

**What AFT actually does:**

The AFT buildspecs (CodeBuild YAML files) hardcode downloading from `https://releases.hashicorp.com/terraform/${TF_VERSION}/...` and running `/opt/aft/bin/terraform`. The `terraform_distribution` variable only accepts `"oss"`, `"tfc"`, or `"tfe"` — not `"TOFU"` or `"opentofu"`.

**The `aft_feature_flags.aft_tf_distribution = "TF"` reference in PROJECT.md is incorrect.** That variable does not exist in AFT.

**What this means for the project:**

The split is:
1. **Management plane** (deploying AFT itself via Terragrunt): Run OpenTofu locally. Terragrunt calls OpenTofu to apply the `aws-ia/terraform-aws-control_tower_account_factory` module. This works — the module's HCL is fully compatible with OpenTofu >= 1.6.1.
2. **AFT pipeline** (CodeBuild inside AWS running account customizations): This runs Terraform OSS downloaded from HashiCorp, not OpenTofu. You do not control this binary — AFT manages it.

**Decision:** Accept this split. The AFT pipeline running Terraform internally is an implementation detail of AWS's managed service. Your IaC (the code you write and run) uses OpenTofu. The customization Terraform code that AFT's CodeBuild runs is vanilla HCL compatible with both binaries. The licensing concern applies to your developer toolchain, not AWS's internal pipeline execution.

**Do NOT try to fork AFT to replace the binary.** Maintaining a fork of a fast-moving AWS-managed module is a significant maintenance burden. The pipeline binary is irrelevant to licensing exposure (AWS runs it, not you).

---

## Layer Architecture

```
Layer 1: Local / CI pipeline (you control this)
  - OpenTofu 1.12.2
  - Terragrunt 1.0.8
  - Applies: Control Tower bootstrap + AFT module deployment
  - State: S3 + DynamoDB in management account

Layer 2: AFT Pipeline (AWS manages this)
  - CodePipeline + CodeBuild in AFT management account
  - Downloads Terraform OSS from releases.hashicorp.com
  - Runs account customization code (your HCL, AWS's binary)
  - State: AFT-managed S3 backend
```

---

## AFT Required Accounts

AFT is not a simple module call. It requires a specific AWS account topology pre-created in Control Tower before the module runs:

| Account | Purpose | Required Before AFT? |
|---------|---------|---------------------|
| Management account | Runs AFT module via OpenTofu/Terragrunt | Yes |
| Log Archive account | CT-managed; must exist in CT | Yes (CT creates it) |
| Audit account | CT-managed; must exist in CT | Yes (CT creates it) |
| AFT Management account | Dedicated account for AFT pipeline | Yes — must be vended via CT Service Catalog before `tofu apply` |

The AFT module requires four account IDs as required inputs with no defaults: `ct_management_account_id`, `log_archive_account_id`, `audit_account_id`, `aft_management_account_id`. Control Tower must be deployed and these accounts provisioned before AFT module runs.

---

## AFT Module Inputs (Relevant to This Project)

```hcl
module "aft" {
  source  = "github.com/aws-ia/terraform-aws-control_tower_account_factory"
  # Pin to exact release tag
  # source = "git::https://github.com/aws-ia/terraform-aws-control_tower_account_factory.git?ref=1.20.1"

  # Required: four account IDs
  ct_management_account_id  = var.management_account_id
  log_archive_account_id    = var.log_archive_account_id
  audit_account_id          = var.audit_account_id
  aft_management_account_id = var.aft_management_account_id

  ct_home_region              = "us-east-1"
  tf_backend_secondary_region = ""  # Single region for now; add us-west-2 if HA needed

  # VCS: GitHub (not CodeCommit — deprecated)
  vcs_provider                                  = "github"
  account_request_repo_name                     = "jsreed/aft-account-request"
  global_customizations_repo_name               = "jsreed/aft-global-customizations"
  account_customizations_repo_name              = "jsreed/aft-account-customizations"
  account_provisioning_customizations_repo_name = "jsreed/aft-account-provisioning-customizations"

  # Terraform runtime (OSS = open source, the non-Cloud/Enterprise path)
  terraform_distribution = "oss"
  terraform_version      = "1.6.1"  # Minimum; AFT downloads this for its CodeBuild jobs

  # Feature flags
  aft_feature_cloudtrail_data_events    = false
  aft_feature_enterprise_support        = false
  aft_feature_delete_default_vpcs_enabled = true  # Recommended: clean new accounts

  # Performance
  maximum_concurrent_customizations  = 5
  concurrent_account_factory_actions = 5
}
```

**Note on `terraform_version`:** This is the version AFT's internal CodeBuild jobs download and run for account customizations. Set to `1.6.1` (the default). Do not set this to an OpenTofu version — it pulls from HashiCorp's release server.

---

## Terragrunt Configuration Pattern

Terragrunt wraps the AFT module call (Layer 1). It does NOT wrap AFT's internal pipeline.

```hcl
# infrastructure/management/aft/terragrunt.hcl

terraform {
  source = "git::https://github.com/aws-ia/terraform-aws-control_tower_account_factory.git?ref=1.20.1"
}

# Terragrunt generates backend.tf — AFT module README explicitly says
# "does not manage a backend Terraform state"
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "chain-vote-tofu-state-${local.account_id}"
    key            = "management/aft/tofu.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "chain-vote-tofu-locks"
  }
}

# Terragrunt generates providers.tf with multi-account provider aliases
# AFT module requires 5 AWS provider aliases
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias  = "ct_management"
      region = "us-east-1"
      # assume management account role
    }
    provider "aws" {
      alias  = "log_archive"
      region = "us-east-1"
      assume_role { role_arn = "arn:aws:iam::${local.log_archive_id}:role/AWSControlTowerExecution" }
    }
    provider "aws" {
      alias  = "audit"
      region = "us-east-1"
      assume_role { role_arn = "arn:aws:iam::${local.audit_id}:role/AWSControlTowerExecution" }
    }
    provider "aws" {
      alias  = "aft_management"
      region = "us-east-1"
      assume_role { role_arn = "arn:aws:iam::${local.aft_mgmt_id}:role/AWSControlTowerExecution" }
    }
    provider "aws" {
      alias  = "tf_backend_secondary_region"
      region = "us-west-2"
    }
  EOF
}

inputs = {
  ct_management_account_id  = local.management_account_id
  log_archive_account_id    = local.log_archive_id
  audit_account_id          = local.audit_id
  aft_management_account_id = local.aft_mgmt_id
  ct_home_region            = "us-east-1"
  # ... rest of inputs
}
```

**Terragrunt binary**: With Terragrunt v1.x, `tofu` is the default binary. No `--tf-path` flag needed if `tofu` is in PATH. Set `TERRAGRUNT_TFPATH=tofu` in CI environment or use `--tf-path $(which tofu)` to be explicit.

---

## State Backend

| Resource | Config | Why |
|----------|--------|-----|
| S3 bucket | `chain-vote-tofu-state-{account_id}` in management account | Standard; management account owns all state |
| DynamoDB table | `chain-vote-tofu-locks` | State locking; prevents concurrent applies |
| Encryption | SSE-S3 (default) or SSE-KMS | Enable KMS for compliance if needed |
| Versioning | Enabled | Required for state recovery |
| Region | `us-east-1` | Same as CT home region |

AFT also creates its own S3 backend in the AFT management account for its internal pipeline state. Do not confuse with the Terragrunt-managed backend above — they are separate.

---

## AWS Providers Required

```hcl
# In root terragrunt.hcl or versions.tf equivalent
terraform {
  required_version = ">= 1.8, < 2.0"  # OpenTofu version range

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
```

The AFT module itself requires **five** `aws` provider aliases via `configuration_aliases`:
- `aws.ct_management` — management account
- `aws.log_archive` — log archive account
- `aws.audit` — audit account
- `aws.aft_management` — AFT management account
- `aws.tf_backend_secondary_region` — secondary region for AFT backend replication

There is no separate `aws-control-tower` provider. Control Tower is managed entirely through the standard `hashicorp/aws` provider.

---

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

---

## Installation

```bash
# Install OpenTofu (macOS)
brew install opentofu
# or via tenv (recommended for version management)
brew install tofuutils/tap/tenv
tenv tofu install 1.12.2
tenv tofu use 1.12.2

# Install Terragrunt
brew install terragrunt
# or
curl -sL https://github.com/gruntwork-io/terragrunt/releases/download/v1.0.8/terragrunt_darwin_arm64 -o /usr/local/bin/terragrunt
chmod +x /usr/local/bin/terragrunt

# Verify
tofu --version   # OpenTofu v1.12.2
terragrunt --version  # terragrunt version v1.0.8
```

---

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

---

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
