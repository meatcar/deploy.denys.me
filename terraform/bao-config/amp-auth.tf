resource "vault_jwt_auth_backend" "amp" {
  path               = "amp"
  oidc_discovery_url = "https://ampcode.com/api/workload-identity"
  bound_issuer       = "https://ampcode.com/api/workload-identity"
  jwt_supported_algs = ["RS256"]

  lifecycle {
    prevent_destroy = true
  }
}
