mock_provider "vault" {}

run "two_projects_remain_independent" {
  command = plan
  variables {
    projects = {
      "meatcar/deploy.denys.me" = {
        amp = {
          project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
          subject    = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
        }
        environments = { prod = { plan = ["cloudflare"] } }
        amp_grants   = ["prod/plan"]
      }
      "other/worker" = {
        amp = {
          project_id = "4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
          subject    = "user:user_other:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
        }
        environments = { dev = { plan = ["oci/session"] } }
        amp_grants   = ["dev/plan"]
      }
    }
  }
  assert {
    condition = (
      module.project["meatcar/deploy.denys.me"].mount == "projects/meatcar/deploy.denys.me" &&
      module.project["other/worker"].mount == "projects/other/worker" &&
      module.project["meatcar/deploy.denys.me"].policy_names["prod/plan"] == "project--meatcar--deploy.denys.me--prod--plan--read" &&
      module.project["other/worker"].policy_names["dev/plan"] == "project--other--worker--dev--plan--read" &&
      module.project["meatcar/deploy.denys.me"].role_names["prod/plan"] == "project--meatcar--deploy.denys.me--prod--plan--read" &&
      module.project["other/worker"].role_names["dev/plan"] == "project--other--worker--dev--plan--read" &&
      module.project["other/worker"].secret_keys["dev/plan"] == toset(["dev/plan/oci/session"])
    )
    error_message = "Projects must have disjoint mounts, policies, roles and credential sets."
  }
}

run "joined_namespace_collision_with_different_scopes" {
  command = plan
  variables {
    projects = {
      "a--b/c" = {
        amp = {
          project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
          subject    = "user:user_one:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
        }
        environments = { prod = { plan = ["cloudflare"] } }
        amp_grants   = ["prod/plan"]
      }
      "a/b--c" = {
        amp = {
          project_id = "4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
          subject    = "user:user_two:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
        }
        environments = { dev = { plan = ["oci"] } }
        amp_grants   = ["dev/plan"]
      }
    }
  }
  expect_failures = [terraform_data.project_namespace_guard]
}

run "duplicate_amp_project_ids" {
  command = plan
  variables {
    projects = {
      "a/one" = {
        amp = {
          project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
          subject    = "user:user_one:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
        }
        environments = {}
        amp_grants   = []
      }
      "b/two" = {
        amp = {
          project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
          subject    = "user:user_one:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
        }
        environments = {}
        amp_grants   = []
      }
    }
  }
  expect_failures = [terraform_data.project_namespace_guard]
}
