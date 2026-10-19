mock_provider "vault" {}

variables {
  project = "meatcar/deploy.denys.me"
  amp = {
    project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
    subject    = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
  }
  amp_auth_backend = "amp"
  environments = {
    prod = {
      plan      = ["cloudflare", "netbird"]
      inference = ["cli-proxy-api"]
      admin     = ["cli-proxy-api/inference-pending", "cli-proxy-api/manager-admin", "cli-proxy-api/manager-admin-pending"]
    }
  }
  amp_grants = ["prod/plan"]
}

run "exact_project_permissions_and_ap01_binding" {
  command = plan
  module { source = "./modules/project-layout" }

  assert {
    condition = (
      vault_mount.project.path == "projects/meatcar/deploy.denys.me" &&
      vault_mount.project.type == "kv" && vault_mount.project.options.version == "2" &&
      length(vault_policy.read) == 3 &&
      alltrue([for policy in vault_policy.read : policy.allow_overwrite == false]) &&
      vault_policy.read["prod/plan"].name == "project--meatcar--deploy.denys.me--prod--plan--read" &&
      vault_policy.read["prod/inference"].name == "project--meatcar--deploy.denys.me--prod--inference--read" &&
      vault_policy.read["prod/admin"].name == "project--meatcar--deploy.denys.me--prod--admin--read"
    )
    error_message = "Each non-empty class gets its exact policy and cannot adopt an unmanaged policy."
  }

  assert {
    condition = trimspace(vault_policy.read["prod/plan"].policy) == trimspace(<<-EOT
      path "projects/meatcar/deploy.denys.me/data/prod/plan/cloudflare" {
        capabilities = ["read"]
      }
      path "projects/meatcar/deploy.denys.me/data/prod/plan/netbird" {
        capabilities = ["read"]
      }
    EOT
    )
    error_message = "Plan ACLs must contain only the exact declared data reads."
  }

  assert {
    condition = (
      trimspace(vault_policy.read["prod/inference"].policy) == trimspace(<<-EOT
        path "projects/meatcar/deploy.denys.me/data/prod/inference/cli-proxy-api" {
          capabilities = ["read"]
        }
      EOT
      ) &&
      trimspace(vault_policy.read["prod/admin"].policy) == trimspace(<<-EOT
        path "projects/meatcar/deploy.denys.me/data/prod/admin/cli-proxy-api/inference-pending" {
          capabilities = ["read"]
        }
        path "projects/meatcar/deploy.denys.me/data/prod/admin/cli-proxy-api/manager-admin" {
          capabilities = ["read"]
        }
        path "projects/meatcar/deploy.denys.me/data/prod/admin/cli-proxy-api/manager-admin-pending" {
          capabilities = ["read"]
        }
      EOT
      )
    )
    error_message = "Inference and admin declarations must remain separate, including explicitly named pending keys."
  }

  assert {
    condition = (
      length(vault_jwt_auth_backend_role.plan) == 1 &&
      vault_jwt_auth_backend_role.plan["prod/plan"].backend == "amp" &&
      vault_jwt_auth_backend_role.plan["prod/plan"].role_name == "project--meatcar--deploy.denys.me--prod--plan--read" &&
      vault_jwt_auth_backend_role.plan["prod/plan"].role_type == "jwt" &&
      toset(vault_jwt_auth_backend_role.plan["prod/plan"].bound_audiences) == toset(["bao"]) &&
      vault_jwt_auth_backend_role.plan["prod/plan"].bound_subject == "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e" &&
      vault_jwt_auth_backend_role.plan["prod/plan"].bound_claims_type == "glob" &&
      vault_jwt_auth_backend_role.plan["prod/plan"].bound_claims == tomap({
        project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
        thread_id  = "*"
        token_use  = "exchanged"
      }) &&
      vault_jwt_auth_backend_role.plan["prod/plan"].user_claim == "sub" &&
      toset(vault_jwt_auth_backend_role.plan["prod/plan"].token_policies) == toset(["project--meatcar--deploy.denys.me--prod--plan--read"]) &&
      vault_jwt_auth_backend_role.plan["prod/plan"].token_ttl == 300 &&
      vault_jwt_auth_backend_role.plan["prod/plan"].token_max_ttl == 300 &&
      vault_jwt_auth_backend_role.plan["prod/plan"].token_explicit_max_ttl == 300 &&
      vault_jwt_auth_backend_role.plan["prod/plan"].token_no_default_policy &&
      vault_jwt_auth_backend_role.plan["prod/plan"].groups_claim == null &&
      vault_jwt_auth_backend_role.plan["prod/plan"].verbose_oidc_logging == false
    )
    error_message = "Only exchanged project tokens with audience bao may receive the one plan policy, for at most five minutes. No workspace, setup, group or default grant."
  }
}

run "second_project_does_not_reuse_the_first_scope" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    project = "other/worker"
    amp = {
      project_id = "4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
      subject    = "user:user_other:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
    }
    environments = { dev = { plan = ["oci/session"] } }
    amp_grants   = ["dev/plan"]
  }

  assert {
    condition = (
      vault_mount.project.path == "projects/other/worker" &&
      length(vault_policy.read) == 1 &&
      vault_policy.read["dev/plan"].name == "project--other--worker--dev--plan--read" &&
      !vault_policy.read["dev/plan"].allow_overwrite &&
      trimspace(vault_policy.read["dev/plan"].policy) == trimspace(<<-EOT
        path "projects/other/worker/data/dev/plan/oci/session" {
          capabilities = ["read"]
        }
      EOT
      ) &&
      length(vault_jwt_auth_backend_role.plan) == 1 &&
      vault_jwt_auth_backend_role.plan["dev/plan"].role_name == "project--other--worker--dev--plan--read" &&
      toset(vault_jwt_auth_backend_role.plan["dev/plan"].token_policies) == toset(["project--other--worker--dev--plan--read"]) &&
      vault_jwt_auth_backend_role.plan["dev/plan"].bound_subject == "user:user_other:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729" &&
      vault_jwt_auth_backend_role.plan["dev/plan"].bound_claims == tomap({ project_id = "4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729", thread_id = "*", token_use = "exchanged" }) &&
      toset(vault_jwt_auth_backend_role.plan["dev/plan"].bound_audiences) == toset(["bao"]) &&
      vault_jwt_auth_backend_role.plan["dev/plan"].token_no_default_policy &&
      vault_jwt_auth_backend_role.plan["dev/plan"].token_ttl == 300 &&
      vault_jwt_auth_backend_role.plan["dev/plan"].token_max_ttl == 300 &&
      vault_jwt_auth_backend_role.plan["dev/plan"].token_explicit_max_ttl == 300
    )
    error_message = "The second project's dev grant must not reuse the first project's paths or identity."
  }
}

run "empty_project_has_no_permissions" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    project = "other/empty"
    amp = {
      project_id = "4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
      subject    = "user:user_one:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
    }
    environments = {}
    amp_grants   = []
  }
  assert {
    condition = (
      vault_mount.project.path == "projects/other/empty" &&
      length(vault_policy.read) == 0 && length(vault_jwt_auth_backend_role.plan) == 0 &&
      length(output.secret_keys) == 0 && length(output.policy_names) == 0 && length(output.role_names) == 0
    )
    error_message = "Onboarding an empty project creates a mount, not speculative permissions."
  }
}
