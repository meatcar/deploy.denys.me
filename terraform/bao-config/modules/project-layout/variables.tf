variable "project" {
  description = "Literal lower-case owner/repository."
  type        = string
  nullable    = false

  validation {
    condition = length(split("/", var.project)) == 2 && alltrue([
      for segment in split("/", var.project) :
      can(regex("^[a-z0-9][a-z0-9._-]*$", segment)) && !contains([".", ".."], segment)
    ])
    error_message = "Project must be exactly two literal ASCII owner/repository segments matching [a-z0-9][a-z0-9._-]*, not . or ..."
  }
}

variable "amp" {
  description = "Verified Amp project identity, with a matching project-scope subject."
  type = object({
    project_id = string
    subject    = string
  })
  nullable = false

  validation {
    condition = (
      can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.amp.project_id)) &&
      can(regex("^(user|workspace):[A-Za-z0-9_-]+:project:${var.amp.project_id}$", var.amp.subject))
    )
    error_message = "Amp must use a UUID project ID and an exact user/workspace project-scope subject ending in the same ID."
  }
}

variable "environments" {
  description = "Exact credential names grouped by dev/prod and plan/inference/admin. Omitted classes are empty."
  type        = map(map(set(string)))
  nullable    = false

  validation {
    condition = alltrue([
      for environment, classes in var.environments :
      contains(["dev", "prod"], environment) && alltrue([
        for class, credentials in classes :
        contains(["plan", "inference", "admin"], class) && alltrue([
          for credential in credentials : alltrue([
            for segment in split("/", credential) :
            can(regex("^[a-z0-9][a-z0-9._-]*$", segment)) && !contains([".", ".."], segment)
          ])
        ])
      ])
    ])
    error_message = "Use dev/prod, plan/inference/admin, and literal ASCII credential segments matching [a-z0-9][a-z0-9._-]*. Empty, . and .. segments and ACL/template syntax are forbidden."
  }
}

variable "amp_grants" {
  description = "Explicit environment/plan grants with declared, non-empty credential sets."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for grant in var.amp_grants :
      contains(["dev/plan", "prod/plan"], grant) &&
      try(length(var.environments[split("/", grant)[0]]["plan"]) > 0, false)
    ])
    error_message = "Amp grants must be dev/plan or prod/plan and reference a declared, non-empty plan set. No inference, admin or setup grants."
  }
}

variable "amp_auth_backend" {
  description = "Shared Amp JWT authentication mount path."
  type        = string
  nullable    = false
}
