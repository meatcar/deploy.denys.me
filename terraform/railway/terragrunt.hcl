include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  project_id   = "7cabdfa2-96a3-4644-b7bd-14c6628e9120"
  service_id   = "2ae937ef-bea3-46a0-ae21-282f070dfc43"
  service_name = "paseo-relay"
  region       = "us-east4-eqdc4a"

  project_ids = {
    rsshub  = "80237ef3-1e56-4402-94a7-9947cae05850"
    monitor = "0235b7ae-d5b0-4125-afa5-b250de4139bb"
  }
  service_ids = {
    rsshub      = "ec429b53-9851-4571-a77a-68f9498dd6dc"
    redis       = "387723a4-5e2d-4873-8bc9-eea916613dfe"
    uptime_kuma = "30c1fc53-a8db-42db-b8dd-d3503640cf17"
    mysql       = "91c961d5-9c56-4c59-8a0b-c53dc8aa41de"
  }
}
