locals {
  projects = {
    rsshub  = { name = "RSSHub", description = "" }
    monitor = { name = "monitor.denys.me", description = "Uptime Kuma monitoring" }
  }
  image_services = {
    redis = {
      name    = "Redis"
      project = "rsshub"
      image   = "bitnami/redis"
      volume  = { name = "redis-volume", mount_path = "/bitnami" }
    }
    uptime_kuma = {
      name    = "uptime-kuma"
      project = "monitor"
      image   = "louislam/uptime-kuma:2.5.5"
      volume  = { name = "uptime-kuma-volume", mount_path = "/app/data" }
    }
    mysql = {
      name    = "MySQL"
      project = "monitor"
      image   = "mysql:9.7.2"
      volume  = { name = "mysql-volume", mount_path = "/var/lib/mysql" }
    }
  }
}

resource "railway_project" "application" {
  for_each = local.projects

  name        = each.value.name
  description = each.value.description
  default_environment = {
    name = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "railway_service" "image" {
  for_each = local.image_services

  name         = each.value.name
  project_id   = railway_project.application[each.value.project].id
  source_image = each.value.image
  volume       = each.value.volume

  lifecycle {
    prevent_destroy = true
  }
}

resource "railway_service" "rsshub" {
  name           = "RSSHub"
  project_id     = railway_project.application["rsshub"].id
  root_directory = "/"

  lifecycle {
    prevent_destroy = true
    # NOTE: Existing DIYgod/RSSHub connection has no branch trigger readable by this provider.
    ignore_changes = [source_repo, source_repo_branch]
  }
}

resource "railway_service_domain" "rsshub" {
  subdomain      = "rsshub-production-7bff"
  environment_id = railway_project.application["rsshub"].default_environment.id
  service_id     = railway_service.rsshub.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "railway_custom_domain" "monitor" {
  domain         = "monitor.denys.me"
  target_port    = 8080
  environment_id = railway_project.application["monitor"].default_environment.id
  service_id     = railway_service.image["uptime_kuma"].id

  lifecycle {
    prevent_destroy = true
  }
}
