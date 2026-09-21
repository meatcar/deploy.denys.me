terraform_binary = "tofu"

terraform {
  exclude_from_copy = [
    "**/.env*",
    "**/.terraform/**",
    "**/.terragrunt-cache/**",
    "**/output/**",
    "**/*.tfstate*",
    "**/*.tfplan",
    "**/*.tfvars",
    "**/*.tfvars.json",
    "**/crash*.log",
  ]
}
