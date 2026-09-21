include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  project_id   = "7cabdfa2-96a3-4644-b7bd-14c6628e9120"
  service_id   = "2ae937ef-bea3-46a0-ae21-282f070dfc43"
  service_name = "paseo-relay"
  region       = "us-east4-eqdc4a"
}
