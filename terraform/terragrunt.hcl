include "root" {
  path = "${get_terragrunt_dir()}/root.hcl"
}

inputs = {
  working_directory = get_terragrunt_dir()
}
