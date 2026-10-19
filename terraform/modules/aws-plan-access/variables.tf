variable "backup_bucket" {
  type        = string
  description = "Bao backup bucket whose configuration, but never object contents, may be read."
}

variable "openbao_kms_key_arn" {
  type        = string
  description = "OpenBao auto-unseal key ARN, for metadata refresh only."
}
