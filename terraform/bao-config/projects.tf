variable "projects" {
  description = "Project credential locations and reviewed Amp plan grants. No secret values."
  type = map(object({
    amp = object({
      project_id = string
      subject    = string
    })
    environments = map(map(set(string)))
    amp_grants   = set(string)
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
  project_mounts  = [for project in keys(var.projects) : "projects/${project}"]
  policy_prefixes = [for project in keys(var.projects) : "project--${replace(project, "/", "--")}"]
  amp_project_ids = [for project in values(var.projects) : project.amp.project_id]
  project_policies = flatten([
    for project, config in var.projects : [
      for environment, classes in config.environments : [
        for class, credentials in classes :
        "project--${replace(project, "/", "--")}--${environment}--${class}--read" if length(credentials) > 0
      ]
    ]
  ])
  amp_roles = flatten([
    for project, config in var.projects : [
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
  }
}

module "project" {
  source   = "./modules/project-layout"
  for_each = var.projects

  project          = each.key
  amp              = each.value.amp
  environments     = each.value.environments
  amp_grants       = each.value.amp_grants
  amp_auth_backend = vault_jwt_auth_backend.amp.path

  depends_on = [terraform_data.project_namespace_guard]
}
