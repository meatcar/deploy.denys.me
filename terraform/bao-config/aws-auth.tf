variable "use_aws_auth" {
  type        = bool
  default     = true
  description = "Use AWS SSO login. Set false only for bootstrap using an existing VAULT_TOKEN."
}

resource "vault_plugin" "aws" {
  type    = "auth"
  name    = "aws"
  version = "v0.1.1"
  command = "openbao-plugin-auth-aws"
  sha256  = "7a77057e62973c1aae6035f52110e3302605a47b622756d954915b7b55eca10c"

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_auth_backend" "aws" {
  type = vault_plugin.aws.name
  path = "aws"

  tune {
    default_lease_ttl = "20m"
    max_lease_ttl     = "1h"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_aws_auth_backend_client" "aws" {
  backend                    = vault_auth_backend.aws.path
  iam_server_id_header_value = "bao.vpn.denys.me"
  use_sts_region_from_client = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_aws_auth_backend_role" "terraform_admin" {
  backend                  = vault_auth_backend.aws.path
  role                     = "terraform-admin"
  auth_type                = "iam"
  bound_iam_principal_arns = ["arn:aws:iam::148676508643:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_8e45cdd61884f702"]
  resolve_aws_unique_ids   = true
  token_policies           = [vault_policy.admin.name]
  token_ttl                = 1200
  token_max_ttl            = 3600
  token_explicit_max_ttl   = 3600
  token_no_default_policy  = true

  depends_on = [vault_aws_auth_backend_client.aws]

  lifecycle {
    prevent_destroy = true
  }
}
