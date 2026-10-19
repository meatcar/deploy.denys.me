mock_provider "vault" {}

variables {
  project = "meatcar/deploy.denys.me"
  amp = {
    project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
    subject    = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
  }
  amp_auth_backend = "amp"
  environments     = { prod = { plan = ["cloudflare"] } }
  amp_grants       = []
}

run "empty_project" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "" }
  expect_failures = [var.project]
}

run "missing_repository" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar" }
  expect_failures = [var.project]
}

run "extra_project_segment" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar/repo/extra" }
  expect_failures = [var.project]
}

run "empty_owner" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "/repo" }
  expect_failures = [var.project]
}

run "empty_repository" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar/" }
  expect_failures = [var.project]
}

run "repeated_project_separator" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar//repo" }
  expect_failures = [var.project]
}

run "dot_owner" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "./repo" }
  expect_failures = [var.project]
}

run "dotdot_repository" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar/.." }
  expect_failures = [var.project]
}

run "wildcard_owner" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meat*/repo" }
  expect_failures = [var.project]
}

run "wildcard_repository" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar/rep+" }
  expect_failures = [var.project]
}

run "uppercase_project" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "Meatcar/repo" }
  expect_failures = [var.project]
}

run "url_encoded_project" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar/rep%2fo" }
  expect_failures = [var.project]
}

run "identity_template_project" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { project = "meatcar/{{identity.entity.id}}" }
  expect_failures = [var.project]
}

run "empty_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = [""] } } }
  expect_failures = [var.environments]
}

run "dot_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["."] } } }
  expect_failures = [var.environments]
}

run "dotdot_credential_component" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci/../session"] } } }
  expect_failures = [var.environments]
}

run "leading_credential_separator" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["/oci"] } } }
  expect_failures = [var.environments]
}

run "trailing_credential_separator" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci/"] } } }
  expect_failures = [var.environments]
}

run "repeated_credential_separator" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci//session"] } } }
  expect_failures = [var.environments]
}

run "wildcard_credential_first_component" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci*/session"] } } }
  expect_failures = [var.environments]
}

run "plus_credential_last_component" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci/+"] } } }
  expect_failures = [var.environments]
}

run "identity_template_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["{{identity.entity.id}}"] } } }
  expect_failures = [var.environments]
}

run "interpolation_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["$${identity.entity.id}"] } } }
  expect_failures = [var.environments]
}

run "directive_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["%%{if true}"] } } }
  expect_failures = [var.environments]
}

run "quoted_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci/\"session\""] } } }
  expect_failures = [var.environments]
}

run "backslash_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci\\session"] } } }
  expect_failures = [var.environments]
}

run "newline_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci\nsession"] } } }
  expect_failures = [var.environments]
}

run "whitespace_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci session"] } } }
  expect_failures = [var.environments]
}

run "control_character_credential" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci\tsession"] } } }
  expect_failures = [var.environments]
}

run "hcl_stanza_injection" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { plan = ["oci\" { capabilities = [\"sudo\"] }\npath \"*\" { capabilities = [\"read\"] }"] } } }
  expect_failures = [var.environments]
}

run "unknown_environment" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { staging = { plan = ["oci"] } } }
  expect_failures = [var.environments]
}

run "unknown_class" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { write = ["oci"] } } }
  expect_failures = [var.environments]
}

run "template_environment" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { "{{identity.entity.id}}" = { plan = ["oci"] } } }
  expect_failures = [var.environments]
}

run "wildcard_class" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { environments = { prod = { "*" = ["oci"] } } }
  expect_failures = [var.environments]
}

run "mismatched_subject" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    amp = {
      project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
      subject    = "user:user_one:project:4a4c6e0a-d0f0-4c1e-a9b6-fcfce93bf729"
    }
  }
  expect_failures = [var.amp]
}

run "non_project_subject" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    amp = {
      project_id = "d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
      subject    = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e:thread:any"
    }
  }
  expect_failures = [var.amp]
}

run "unknown_grant_target" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { amp_grants = ["dev/plan"] }
  expect_failures = [var.amp_grants]
}

run "empty_grant_target" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    environments = { prod = { plan = [] } }
    amp_grants   = ["prod/plan"]
  }
  expect_failures = [var.amp_grants]
}

run "admin_grant" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    environments = { prod = { admin = ["oci"] } }
    amp_grants   = ["prod/admin"]
  }
  expect_failures = [var.amp_grants]
}

run "inference_grant" {
  command = plan
  module { source = "./modules/project-layout" }
  variables {
    environments = { prod = { inference = ["cli-proxy-api"] } }
    amp_grants   = ["prod/inference"]
  }
  expect_failures = [var.amp_grants]
}

run "setup_grant" {
  command = plan
  module { source = "./modules/project-layout" }
  variables { amp_grants = ["setup/plan"] }
  expect_failures = [var.amp_grants]
}
