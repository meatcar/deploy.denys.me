output "openbao_iam_user" {
  value = aws_iam_user.openbao.name
}

output "openbao_kms_key_arn" {
  value = aws_kms_key.openbao.arn
}

output "backup_bucket" {
  value = aws_s3_bucket.backup.bucket
}

output "backup_iam_user" {
  value = aws_iam_user.backup.name
}
