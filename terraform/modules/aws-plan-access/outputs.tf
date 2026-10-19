output "role_arn" {
  value = aws_iam_role.plan.arn
}

output "audience" {
  value = local.audience
}
