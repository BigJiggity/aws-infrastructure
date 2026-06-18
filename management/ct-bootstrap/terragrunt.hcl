# Inherits terraform_binary = "tofu" and remote_state from root terragrunt.hcl.
include "root" {
  path = find_in_parent_folders()
}
