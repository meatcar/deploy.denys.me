include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  repository_root = dirname(get_parent_terragrunt_dir())
}

dependencies {
  paths = ["../bao", "../netbird"]
}
