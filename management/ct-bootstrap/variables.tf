variable "management_account_id" {
  description = "AWS account ID of the CT management account. Set after CT setup."
  type        = string
}

variable "log_archive_account_id" {
  description = "AWS account ID of the CT-managed Log Archive account. Set after CT console setup."
  type        = string
}

variable "audit_account_id" {
  description = "AWS account ID of the CT-managed Audit account. Set after CT console setup."
  type        = string
}
