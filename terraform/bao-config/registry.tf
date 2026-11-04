locals {
  registry_mount = "registry"
}

resource "vault_mount" "registry" {
  path    = local.registry_mount
  type    = "kv"
  options = { version = "2" }

  lifecycle {
    prevent_destroy = true
  }
}

# NOTE: LIST on an empty mount fails plans; this keeps one ignored "_/" entry.
resource "vault_kv_secret_v2" "registry_keep" {
  mount     = vault_mount.registry.path
  name      = "_/keep"
  data_json = jsonencode({})
}

# NOTE: Literal mount keeps reads at plan time; bootstrap with -target=vault_kv_secret_v2.registry_keep.
data "vault_kv_secrets_list_v2" "registry" {
  mount = local.registry_mount
}

data "vault_kv_secret_v2" "registry" {
  for_each = toset([for name in nonsensitive(data.vault_kv_secrets_list_v2.registry.names) : name if !endswith(name, "/")])

  mount = local.registry_mount
  name  = each.key
}

locals {
  # NOTE: Records hold locations and names only, never secret values.
  registry_raw     = { for record in data.vault_kv_secret_v2.registry : record.name => nonsensitive(jsondecode(record.data_json)) }
  registry_deleted = sort([for name, record in local.registry_raw : name if record == null])
  registry         = { for name, record in local.registry_raw : name => record if record != null }
  registry_documents = {
    for name, record in local.registry : record.project => flatten([
      for environment, classes in record.environments : [
        for class, documents in classes : [for document in documents : "${environment}/${class}/${document}"]
      ]
    ])
  }
  registry_projects = {
    for record in values(local.registry) : record.project => {
      amp          = record.amp
      environments = record.environments
      amp_grants   = record.amp_grants
      agent_writes = try(record.agent_writes, [])
    }
  }
  projects = merge(var.projects, local.registry_projects)

  sync_access = {
    for record in values(local.registry) : record.project => [
      for sync in try(record.syncs, []) : {
        source     = sync.source
        credential = record.destinations[sync.destination].credential
      }
      if alltrue([
        for document in [sync.source, try(record.destinations[sync.destination].credential, "")] :
        contains(local.registry_documents[record.project], document)
      ]) && startswith(try(record.destinations[sync.destination].credential, ""), "prod/admin/")
    ]
  }
}

resource "vault_policy" "bao_sync" {
  name = "bao-sync"

  lifecycle {
    # NOTE: Repeats module validation, which -target can skip.
    precondition {
      condition = alltrue(flatten([
        for project, access in local.sync_access : [
          for path in concat([project], [for sync in access : [sync.source, sync.credential]]...) : [
            for segment in split("/", path) : can(regex("^[a-z0-9][a-z0-9._-]*$", segment)) && !contains([".", ".."], segment)
          ]
        ]
      ]))
      error_message = "bao-sync policy paths must be literal lower-case segments."
    }
  }

  policy = join("", concat(
    [<<-EOT
      path "auth/token/lookup-self" {
        capabilities = ["read"]
      }
      path "auth/token/renew-self" {
        capabilities = ["update"]
      }
      path "${vault_mount.registry.path}/metadata/" {
        capabilities = ["list"]
      }
      path "${vault_mount.registry.path}/data/+" {
        capabilities = ["read"]
      }
    EOT
    ],
    flatten([
      for project, access in local.sync_access : concat(
        [
          for folder in sort(distinct([for sync in access : dirname(sync.source)])) : <<-EOT
            path "projects/${project}/detailed-metadata/${folder}/" {
              capabilities = ["list"]
            }
          EOT
        ],
        [
          for document in sort(distinct(flatten([for sync in access : [sync.source, sync.credential]]))) : <<-EOT
            path "projects/${project}/data/${document}" {
              capabilities = ["read"]
            }
          EOT
        ],
      )
    ]),
  ))
}
