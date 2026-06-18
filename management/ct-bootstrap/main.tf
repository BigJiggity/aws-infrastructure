# management/ct-bootstrap/main.tf
#
# Purpose: Read the CT landing zone and AWS Organization state via data sources.
# This unit does NOT create any resources — it is a pure data source / output exporter.
# IaC does not manage CT itself (per D-03 in 01-CONTEXT.md). CT self-manages via
# CloudFormation StackSets and will conflict if managed via resource blocks.
#
# CONSTRAINT: This file must contain ZERO resource blocks. Code reviewers must enforce this.
#
# Pre-condition: CT landing zone must be deployed via the console runbook at
# docs/runbooks/01-ct-landing-zone.md before running terragrunt init/apply here.

# Data source: caller identity (used as fallback for management account ID)
data "aws_caller_identity" "current" {}

# Data source: AWS Organization
# Provides master_account_id, org ARN, and account list metadata.
data "aws_organizations_organization" "current" {}

# Data source: CT landing zones (returns list of deployed landing zones)
#
# NOTE ON DATA SOURCE NAME: aws_controltower_landing_zones (plural) is the correct
# data source name as of hashicorp/aws >= 5.27.0 (included in the >= 6.0.0 range
# required by this project). It returns an `arns` list attribute.
#
# VERIFICATION REQUIRED before first `tofu init`: confirm this data source exists
# in the provider version installed by Terragrunt. Run:
#   tofu providers schema -json | jq '.provider_schemas."registry.terraform.io/hashicorp/aws".data_source_schemas | keys | map(select(startswith("aws_controltower")))'
#
# FALLBACK: If the data source is unavailable in the installed provider version,
# comment out this block and use the locals fallback below instead.
data "aws_controltower_landing_zones" "current" {}

# FALLBACK (disabled): If aws_controltower_landing_zones is not available in the
# provider, capture the landing zone ARN manually from the CLI and set it here:
#
# locals {
#   landing_zone_arn = "REPLACE_WITH_ARN_FROM: aws controltower list-landing-zones --query 'landingZones[0].arn' --output text"
# }
#
# Then update outputs.tf to reference local.landing_zone_arn instead of
# data.aws_controltower_landing_zones.current.arns[0].

# Data source: Log Archive account
# Looks up the account by ID (supplied via variable after CT console setup).
# Will fail at plan time if the account ID is invalid — this is intentional.
data "aws_organizations_account" "log_archive" {
  id = var.log_archive_account_id
}

# Data source: Audit account
# Looks up the account by ID (supplied via variable after CT console setup).
data "aws_organizations_account" "audit" {
  id = var.audit_account_id
}
