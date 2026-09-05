resource "vault_policy" "cli_proxy_api_admin_read" {
  name   = "github-meatcar-deploy.denys.me-prod-cli-proxy-api-admin-read"
  policy = <<-EOT
    path "${vault_mount.kv.path}/data/${local.cli_proxy_api_config.admin_secret_path}" {
      capabilities = ["read"]
    }
  EOT
}
