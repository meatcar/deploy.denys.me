terraform {
  required_version = ">= 1.11.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "= 5.12.0"
    }
  }
}

locals {
  credential_sets = merge({}, [
    for environment, classes in var.environments : {
      for class, credentials in classes : "${environment}/${class}" => credentials if length(credentials) > 0
    }
  ]...)
  policy_names = {
    for scope in keys(local.credential_sets) :
    scope => "project--${replace(var.project, "/", "--")}--${replace(scope, "/", "--")}--read"
  }
}

resource "vault_mount" "project" {
  path    = "projects/${var.project}"
  type    = "kv"
  options = { version = "2" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_policy" "read" {
  for_each = local.credential_sets

  name            = local.policy_names[each.key]
  allow_overwrite = false
  policy = join("", [
    for credential in sort(tolist(each.value)) : <<-EOT
      path "${vault_mount.project.path}/data/${each.key}/${credential}" {
        capabilities = ["read"]
      }
    EOT
  ])
}

resource "vault_jwt_auth_backend_role" "plan" {
  for_each = var.amp_grants

  backend         = var.amp_auth_backend
  role_name       = vault_policy.read[each.key].name
  role_type       = "jwt"
  bound_audiences = ["bao"]
  bound_subject   = var.amp.subject
  # NOTE: Setup tokens lack thread_id; a missing bound claim fails login.
  bound_claims_type = "glob"
  bound_claims = {
    project_id = var.amp.project_id
    thread_id  = "*"
    token_use  = "exchanged"
  }
  user_claim              = "sub"
  token_policies          = [vault_policy.read[each.key].name]
  token_ttl               = 300
  token_max_ttl           = 300
  token_explicit_max_ttl  = 300
  token_no_default_policy = true
  verbose_oidc_logging    = false
}
