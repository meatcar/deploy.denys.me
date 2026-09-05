locals {
  variables = {
    PORT                                 = "4000"
    ELIXIR_ERL_OPTIONS                   = "+fnu"
    PASEO_RELAY_HOST                     = "0.0.0.0"
    PASEO_RELAY_PORT                     = "4000"
    PASEO_RELAY_MIN_CLUSTER_SIZE         = "1"
    PASEO_RELAY_ACCEPTORS                = "10"
    PASEO_RELAY_CONNECTIONS_PER_ACCEPTOR = "100"
    PASEO_RELAY_MEMORY_WATERMARK_BYTES   = "1610612736"
  }
}

resource "railway_project" "paseo" {
  name = "paseo-relay"

  default_environment = {
    name = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "railway_service" "paseo" {
  name               = var.service_name
  project_id         = railway_project.paseo.id
  source_repo        = "meatcar/paseo-relay"
  source_repo_branch = "main"
  regions = [{
    region       = var.region
    num_replicas = 1
  }]

  lifecycle {
    prevent_destroy = true
  }
}

resource "railway_custom_domain" "paseo" {
  domain         = "paseo.denys.me"
  target_port    = 4000
  environment_id = railway_project.paseo.default_environment.id
  service_id     = railway_service.paseo.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "railway_variable_collection" "paseo" {
  environment_id = railway_project.paseo.default_environment.id
  service_id     = railway_service.paseo.id
  variables      = [for name, value in local.variables : { name = name, value = value }]

  lifecycle {
    prevent_destroy = true
  }
}
