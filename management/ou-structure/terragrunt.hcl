# Inherits terraform_binary = "tofu" and remote_state from root terragrunt.hcl.
include "root" {
  path = find_in_parent_folders()
}

# Depend on ct-bootstrap to ensure CT is live and root OU ID is available.
# This also enforces the Plan 01-02 → Plan 01-03 ordering at the Terragrunt level.
dependency "ct_bootstrap" {
  config_path = "../ct-bootstrap"
  mock_outputs = {
    management_account_id = "000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
