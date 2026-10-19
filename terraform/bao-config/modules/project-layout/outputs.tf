output "mount" {
  description = "Project KV v2 mount."
  value       = vault_mount.project.path
}

output "secret_keys" {
  description = "Exact relative KV keys by environment/class. No secret values."
  value = {
    for scope in keys(vault_policy.read) :
    scope => toset([for credential in local.credential_sets[scope] : "${scope}/${credential}"])
  }
}

output "policy_names" {
  description = "Read policies by environment/class."
  value       = { for scope, policy in vault_policy.read : scope => policy.name }
}

output "role_names" {
  description = "Amp plan roles by environment/class."
  value       = { for scope, role in vault_jwt_auth_backend_role.plan : scope => role.role_name }
}
