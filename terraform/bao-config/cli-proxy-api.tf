locals {
  cli_proxy_api_config_file = abspath("${path.module}/../../nixos/systems/chunkymonkey/cli-proxy-api.json")
  cli_proxy_api_config      = jsondecode(file(local.cli_proxy_api_config_file))
  cli_proxy_api_path        = local.cli_proxy_api_config.inference_secret_path

  # NOTE: Increment to generate and deploy a replacement key; old keys remain valid.
  cli_proxy_api_key_generation = 1
}

resource "vault_mount" "kv" {
  path    = local.cli_proxy_api_config.secret_mount
  type    = "kv"
  options = { version = "2" }

  lifecycle {
    prevent_destroy = true
  }
}

ephemeral "random_password" "cli_proxy_api" {
  length  = 48
  special = false
}

resource "vault_kv_secret_v2" "cli_proxy_api_pending" {
  mount = vault_mount.kv.path
  name  = "${local.cli_proxy_api_path}-pending"
  data_json_wo = jsonencode({
    base_url = "https://${local.cli_proxy_api_config.public_host}/v1"
    api_key  = ephemeral.random_password.cli_proxy_api.result
  })
  # NOTE: Only generation changes persist a newly generated key.
  data_json_wo_version = local.cli_proxy_api_key_generation

  lifecycle {
    prevent_destroy = true
  }
}

ephemeral "vault_kv_secret_v2" "cli_proxy_api_pending" {
  mount = vault_mount.kv.path
  name  = vault_kv_secret_v2.cli_proxy_api_pending.name

  depends_on = [vault_kv_secret_v2.cli_proxy_api_pending]

  lifecycle {
    postcondition {
      condition     = self.data["base_url"] == "https://${local.cli_proxy_api_config.public_host}/v1"
      error_message = "The staged endpoint differs from the deployment profile. Advance cli_proxy_api_key_generation to stage credentials for the new endpoint."
    }
  }
}

resource "terraform_data" "cli_proxy_api_deployment" {
  triggers_replace = [
    local.cli_proxy_api_key_generation,
    filesha256("${path.module}/../../packages/cli-proxy-api/src/cli_proxy_api/deploy_key.py"),
    filesha256("${path.module}/../../packages/cli-proxy-api/src/cli_proxy_api/deployment.py"),
    filesha256(local.cli_proxy_api_config_file),
  ]

  provisioner "local-exec" {
    command = "cli-proxy-api-deploy-key"
    environment = {
      CLI_PROXY_API_KEY    = ephemeral.vault_kv_secret_v2.cli_proxy_api_pending.data["api_key"]
      CLI_PROXY_API_CONFIG = local.cli_proxy_api_config_file
    }
  }
}

resource "vault_kv_secret_v2" "cli_proxy_api" {
  mount                = vault_mount.kv.path
  name                 = local.cli_proxy_api_path
  data_json_wo         = jsonencode(ephemeral.vault_kv_secret_v2.cli_proxy_api_pending.data)
  data_json_wo_version = local.cli_proxy_api_key_generation

  depends_on = [terraform_data.cli_proxy_api_deployment]

  lifecycle {
    prevent_destroy = true
  }
}

ephemeral "vault_kv_secret_v2" "cli_proxy_api_published" {
  mount = vault_mount.kv.path
  name  = vault_kv_secret_v2.cli_proxy_api.name

  depends_on = [vault_kv_secret_v2.cli_proxy_api]

  lifecycle {
    postcondition {
      condition     = self.data == ephemeral.vault_kv_secret_v2.cli_proxy_api_pending.data
      error_message = "Published CLIProxyAPI credentials must match the deployed staged credentials."
    }
  }
}

resource "vault_policy" "cli_proxy_api_read" {
  name   = "github-meatcar-deploy.denys.me-dev-cli-proxy-api-read"
  policy = <<-EOT
    path "${vault_mount.kv.path}/data/${local.cli_proxy_api_path}" {
      capabilities = ["read"]
    }
  EOT
}
