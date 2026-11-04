variable "projects" {
  description = "Public project credential locations and reviewed Amp grants. No secret values. Private projects live in the registry."
  type = map(object({
    amp = object({
      project_id = string
      subject    = string
    })
    environments = map(map(set(string)))
    amp_grants   = set(string)
    agent_writes = optional(set(string), [])
  }))
  nullable = false
  default = {
    "meatcar/deploy.denys.me" = {
      amp = {
        project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
        subject    = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
      }
      environments = {
        prod = {
          plan = ["cloudflare", "digitalocean", "ovh", "netbird", "oci"]
        }
      }
      amp_grants = ["prod/plan"]
    }
  }
}

locals {
  project_mounts  = [for project in keys(local.projects) : "projects/${project}"]
  policy_prefixes = [for project in keys(local.projects) : "project--${replace(project, "/", "--")}"]
  amp_project_ids = [for project in values(local.projects) : project.amp.project_id]
  project_policies = flatten([
    for project, config in local.projects : concat(
      [
        for environment, classes in config.environments : [
          for class, credentials in classes :
          "project--${replace(project, "/", "--")}--${environment}--${class}--read" if length(credentials) > 0
        ]
      ],
      [
        for grant in config.amp_grants :
        "project--${replace(project, "/", "--")}--${replace(grant, "/", "--")}--read" if startswith(grant, "dev/app/")
      ],
    )
  ])
  amp_roles = flatten([
    for project, config in local.projects : [
      for grant in config.amp_grants : "amp/project--${replace(project, "/", "--")}--${replace(grant, "/", "--")}--read"
    ]
  ])
}

resource "terraform_data" "project_namespace_guard" {
  lifecycle {
    precondition {
      condition = (
        length(distinct(local.project_mounts)) == length(local.project_mounts) &&
        length(distinct(local.policy_prefixes)) == length(local.policy_prefixes) &&
        length(distinct(local.project_policies)) == length(local.project_policies) &&
        length(distinct(local.amp_roles)) == length(local.amp_roles)
      )
      error_message = "Project mounts, policy namespaces and per-auth-backend role names must be unique, including -- join collisions."
    }
    precondition {
      condition     = length(distinct(local.amp_project_ids)) == length(local.amp_project_ids)
      error_message = "Each project must have a unique Amp project ID."
    }
    precondition {
      condition     = length(setintersection(keys(var.projects), keys(local.registry_projects))) == 0
      error_message = "A project is defined in projects or the registry, not both."
    }
    precondition {
      condition     = length(local.registry_deleted) == 0
      error_message = "Soft-deleted registry records: ${join(", ", local.registry_deleted)}. Undelete, or remove with kv metadata delete."
    }
  }
}

module "project" {
  source   = "./modules/project-layout"
  for_each = local.projects

  project          = each.key
  amp              = each.value.amp
  environments     = each.value.environments
  amp_grants       = each.value.amp_grants
  agent_writes     = each.value.agent_writes
  amp_auth_backend = vault_jwt_auth_backend.amp.path

  depends_on = [terraform_data.project_namespace_guard]
}

resource "vault_policy" "bao_minter" {
  name            = "bao-minter"
  allow_overwrite = false
  policy = join("", concat(
    [
      for role in sort(compact([for project in module.project : project.write_role_name])) : <<-EOT
        path "auth/token/create/${role}" {
          capabilities = ["update"]
        }
      EOT
    ],
    [<<-EOT
      path "auth/token/revoke-self" {
        capabilities = ["update"]
      }
    EOT
    ],
  ))
}

# NOTE: Create the user and its 1Password password first; tofu owns only token settings.
resource "vault_generic_endpoint" "bao_minter" {
  path                 = "auth/${vault_auth_backend.userpass.path}/users/bao-minter"
  ignore_absent_fields = true
  disable_delete       = true
  data_json = jsonencode({
    token_policies          = [vault_policy.bao_minter.name]
    token_no_default_policy = true
    token_ttl               = 60
    token_max_ttl           = 60
  })
}
