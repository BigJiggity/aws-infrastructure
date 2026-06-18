# Root Terragrunt configuration
# All child units inherit this via include {} block.

# Explicitly pin OpenTofu binary (Pitfall 9: non-deterministic binary detection)
# Terragrunt v1.x defaults to "tofu" but explicit pin makes intent unambiguous (STATE-01).
terraform_binary = "tofu"

# Shared remote state configuration (STATE-02).
# State key is derived from the calling unit's path relative to this file,
# so no manual key management is required.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "chain-vote-tofu-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "chain-vote-tofu-locks"
  }
}

# Generate provider version constraints inherited by all child units.
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.8, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
EOF
}

# Generate provider configuration inherited by all child units.
# Units that need additional providers (e.g., multi-account aliases) override locally.
generate "provider" {
  path      = "provider.tf"
  if_exists = "skip"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
}
EOF
}
