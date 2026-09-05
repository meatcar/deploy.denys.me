resource "vault_policy" "admin" {
  name            = "admin"
  allow_overwrite = false
  policy          = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo", "patch"]
    }
  EOT

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_policy" "backup" {
  name            = "backup"
  allow_overwrite = false
  policy          = <<-EOT
    path "sys/storage/raft/snapshot" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
  EOT

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_generic_endpoint" "admin_token_settings" {
  path                 = "auth/${vault_auth_backend.userpass.path}/users/denys"
  ignore_absent_fields = true
  disable_delete       = true
  data_json = jsonencode({
    token_policies = [vault_policy.admin.name]
    token_ttl      = 3600
    token_max_ttl  = 28800
  })

  lifecycle {
    prevent_destroy = true
  }
}
