mock_provider "vault" {
  override_data {
    target = data.vault_kv_secrets_list_v2.registry
    values = { names = ["webapp"] }
  }

  override_data {
    target = data.vault_kv_secret_v2.registry
    values = {
      data_json = <<-EOT
        {
          "project": "acme/webapp",
          "amp": {
            "project_id": "7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f",
            "subject": "user:user_x:project:7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f"
          },
          "environments": {
            "dev": { "app": ["public", "database"] },
            "prod": { "app": ["public", "database"], "admin": ["sync-vercel", "ci"] }
          },
          "amp_grants": ["dev/app/public"],
          "agent_writes": ["prod/app/database"],
          "destinations": {
            "vercel": { "type": "vercel", "project_id": "prj_abc", "team_id": "team_abc", "credential": "prod/admin/sync-vercel" },
            "app-credential": { "type": "vercel", "project_id": "prj_def", "team_id": "team_abc", "credential": "prod/app/database" },
            "ghost": { "type": "vercel", "project_id": "prj_ghi", "team_id": "team_abc", "credential": "prod/admin/undeclared" }
          },
          "syncs": [
            { "source": "prod/app/public", "destination": "vercel", "target": "production", "keys": ["A"] },
            { "source": "prod/app/database", "destination": "vercel", "target": "production", "keys": ["B"] },
            { "source": "dev/app/public", "destination": "vercel", "target": "preview", "keys": ["A"] },
            { "source": "prod/app/undeclared", "destination": "vercel", "target": "production", "keys": ["C"] },
            { "source": "prod/admin/ci", "destination": "app-credential", "target": "production", "keys": ["D"] },
            { "source": "dev/app/database", "destination": "ghost", "target": "preview", "keys": ["E"] }
          ]
        }
      EOT
    }
  }
}

variables {
  projects = {}
}

run "registry_record_defines_project_and_exact_sync_access" {
  command = plan

  assert {
    condition = (
      module.project["acme/webapp"].mount == "projects/acme/webapp" &&
      module.project["acme/webapp"].role_names["dev/app/public"] == "project--acme--webapp--dev--app--public--read" &&
      module.project["acme/webapp"].write_role_name == "project--acme--webapp--write"
    )
    error_message = "A registry record must create the same layout as a projects entry."
  }

  assert {
    condition = trimspace(vault_policy.bao_minter.policy) == trimspace(<<-EOT
      path "auth/token/create/project--acme--webapp--write" {
        capabilities = ["update"]
      }
      path "auth/token/revoke-self" {
        capabilities = ["update"]
      }
    EOT
    )
    error_message = "bao-minter mints only project write roles."
  }

  assert {
    condition     = vault_mount.registry.path == "registry" && vault_mount.registry.options.version == "2"
    error_message = "The registry is a KV v2 mount at registry/."
  }

  assert {
    condition = trimspace(vault_policy.bao_sync.policy) == trimspace(<<-EOT
      path "auth/token/lookup-self" {
        capabilities = ["read"]
      }
      path "auth/token/renew-self" {
        capabilities = ["update"]
      }
      path "registry/metadata/" {
        capabilities = ["list"]
      }
      path "registry/data/+" {
        capabilities = ["read"]
      }
      path "projects/acme/webapp/detailed-metadata/dev/app/" {
        capabilities = ["list"]
      }
      path "projects/acme/webapp/detailed-metadata/prod/app/" {
        capabilities = ["list"]
      }
      path "projects/acme/webapp/data/dev/app/public" {
        capabilities = ["read"]
      }
      path "projects/acme/webapp/data/prod/admin/sync-vercel" {
        capabilities = ["read"]
      }
      path "projects/acme/webapp/data/prod/app/database" {
        capabilities = ["read"]
      }
      path "projects/acme/webapp/data/prod/app/public" {
        capabilities = ["read"]
      }
    EOT
    )
    error_message = "bao-sync reads only declared sources and credentials of syncs whose destination has a declared prod/admin credential."
  }
}

run "registry_and_variable_cannot_both_define_a_project" {
  command = plan
  variables {
    projects = {
      "acme/webapp" = {
        amp = {
          project_id = "4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
          subject    = "user:user_other:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
        }
        environments = { prod = { plan = ["cloudflare"] } }
        amp_grants   = []
      }
    }
  }
  expect_failures = [terraform_data.project_namespace_guard]
}

run "malformed_record_cannot_render_into_sync_policy" {
  command = plan
  plan_options {
    target = [vault_policy.bao_sync]
  }
  override_data {
    target = data.vault_kv_secret_v2.registry
    values = {
      data_json = <<-EOT
        {
          "project": "acme/*",
          "amp": { "project_id": "7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f", "subject": "user:user_x:project:7d1e2f40-3a5b-4c6d-8e9f-0a1b2c3d4e5f" },
          "environments": { "prod": { "app": ["public"], "admin": ["sync-vercel"] } },
          "amp_grants": [],
          "destinations": { "vercel": { "type": "vercel", "project_id": "prj_abc", "team_id": "team_abc", "credential": "prod/admin/sync-vercel" } },
          "syncs": [{ "source": "prod/app/public", "destination": "vercel", "target": "production", "keys": ["A"] }]
        }
      EOT
    }
  }
  expect_failures = [vault_policy.bao_sync]
}

run "soft_deleted_record_fails_the_plan" {
  command = plan
  override_data {
    target = data.vault_kv_secret_v2.registry
    values = { data_json = "null" }
  }
  expect_failures = [terraform_data.project_namespace_guard]
}
