mock_provider "vault" {}

run "aws_login_trusts_only_the_resolved_sso_role" {
  command = plan

  assert {
    condition = (
      vault_aws_auth_backend_role.terraform_admin.auth_type == "iam" &&
      vault_aws_auth_backend_role.terraform_admin.resolve_aws_unique_ids &&
      toset(vault_aws_auth_backend_role.terraform_admin.bound_iam_principal_arns) == toset([
        "arn:aws:iam::148676508643:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_8e45cdd61884f702"
      ]) &&
      toset(vault_aws_auth_backend_role.terraform_admin.token_policies) == toset(["admin"]) &&
      vault_aws_auth_backend_role.terraform_admin.token_ttl == 1200 &&
      vault_aws_auth_backend_role.terraform_admin.token_explicit_max_ttl == 3600
    )
    error_message = "AWS login must bind the exact resolved SSO role and issue short-lived admin tokens."
  }

  assert {
    condition = (
      vault_aws_auth_backend_client.aws.iam_server_id_header_value == "bao.vpn.denys.me" &&
      vault_aws_auth_backend_client.aws.use_sts_region_from_client &&
      vault_aws_auth_backend_client.aws.access_key == null &&
      vault_aws_auth_backend_client.aws.secret_key == null
    )
    error_message = "AWS login must require Bao's signed server-ID header and avoid static credentials in Terraform."
  }
}

run "adoption_cannot_write_or_delete_the_admin_password" {
  command = plan

  assert {
    condition = (
      vault_generic_endpoint.admin_token_settings.path == "auth/userpass/users/denys" &&
      vault_generic_endpoint.admin_token_settings.disable_delete &&
      vault_generic_endpoint.admin_token_settings.disable_read != true &&
      vault_generic_endpoint.admin_token_settings.ignore_absent_fields &&
      jsondecode(vault_generic_endpoint.admin_token_settings.data_json) == {
        token_policies = ["admin"]
        token_ttl      = 3600
        token_max_ttl  = 28800
      }
    )
    error_message = "Adoption must manage only administrator token settings, preserve the password, and retain drift detection."
  }
}

run "cli_proxy_api_secret_is_write_only_and_project_scoped" {
  command = plan

  assert {
    condition = (
      vault_mount.kv.path == "kv" && vault_mount.kv.options.version == "2" &&
      vault_kv_secret_v2.cli_proxy_api.name == "github/meatcar/deploy.denys.me/dev/cli-proxy-api" &&
      vault_kv_secret_v2.cli_proxy_api_pending.name == "github/meatcar/deploy.denys.me/dev/cli-proxy-api-pending" &&
      vault_kv_secret_v2.cli_proxy_api.data_json == null &&
      vault_kv_secret_v2.cli_proxy_api_pending.data_json == null &&
      vault_kv_secret_v2.cli_proxy_api.data_json_wo_version == vault_kv_secret_v2.cli_proxy_api_pending.data_json_wo_version &&
      terraform_data.cli_proxy_api_deployment.triggers_replace[0] == vault_kv_secret_v2.cli_proxy_api.data_json_wo_version
    )
    error_message = "Stage and publish a versioned, write-only key under the repository's dev path."
  }

  assert {
    condition = trimspace(vault_policy.cli_proxy_api_read.policy) == trimspace(<<-EOT
      path "kv/data/github/meatcar/deploy.denys.me/dev/cli-proxy-api" {
        capabilities = ["read"]
      }
    EOT
    )
    error_message = "Consumers must not read pending keys, other projects or environments, or write secrets."
  }
}

run "manager_admin_key_is_separate_from_inference_credentials" {
  command = plan

  assert {
    condition = trimspace(vault_policy.cli_proxy_api_admin_read.policy) == trimspace(<<-EOT
      path "kv/data/github/meatcar/deploy.denys.me/prod/cli-proxy-api/manager-admin" {
        capabilities = ["read"]
      }
    EOT
    )
    error_message = "Admin access must be an explicit exact-path read, without pending-secret or write permissions."
  }
}
