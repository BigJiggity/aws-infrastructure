output "landing_zone_arn" {
  description = "ARN of the CT landing zone. Consumed by Phase 2 AFT module."
  value       = try(data.aws_controltower_landing_zones.current.arns[0], "NOT_YET_DEPLOYED")
}

output "log_archive_account_id" {
  description = "Account ID of the CT-managed Log Archive account."
  value       = data.aws_organizations_account.log_archive.id
}

output "audit_account_id" {
  description = "Account ID of the CT-managed Audit account."
  value       = data.aws_organizations_account.audit.id
}

output "management_account_id" {
  description = "Account ID of the CT management account."
  value       = data.aws_organizations_organization.current.master_account_id
}
