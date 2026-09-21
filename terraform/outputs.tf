output "ip" {
  value = digitalocean_droplet.www.ipv4_address
}

output "fqdn" {
  value = var.hostname
}

output "openbao_iam_user" {
  value = module.bao_support.openbao_iam_user
}

output "openbao_kms_key_arn" {
  value = module.bao_support.openbao_kms_key_arn
}

output "backup_bucket" {
  value = module.bao_support.backup_bucket
}

output "backup_iam_user" {
  value = module.bao_support.backup_iam_user
}
