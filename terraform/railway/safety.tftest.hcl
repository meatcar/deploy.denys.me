mock_provider "railway" {
  mock_resource "railway_project" {
    defaults = {
      id = "00000000-0000-4000-8000-000000000010"
    }
  }
  mock_resource "railway_service" {
    defaults = {
      id = "00000000-0000-4000-8000-000000000012"
    }
  }
}

variables {
  project_id   = "00000000-0000-4000-8000-000000000001"
  service_id   = "00000000-0000-4000-8000-000000000002"
  service_name = "paseo-relay"
  region       = "us-east4-eqdc4a"
  project_ids = {
    rsshub  = "00000000-0000-4000-8000-000000000003"
    monitor = "00000000-0000-4000-8000-000000000004"
  }
  service_ids = {
    rsshub      = "00000000-0000-4000-8000-000000000005"
    redis       = "00000000-0000-4000-8000-000000000006"
    uptime_kuma = "00000000-0000-4000-8000-000000000007"
    mysql       = "00000000-0000-4000-8000-000000000008"
  }
}

run "preserve_storage" {
  command = plan

  plan_options {
    target = [railway_service.image]
  }

  assert {
    condition = {
      for name, service in railway_service.image : name => [service.volume.name, service.volume.mount_path]
      } == {
      redis       = ["redis-volume", "/bitnami"]
      uptime_kuma = ["uptime-kuma-volume", "/app/data"]
      mysql       = ["mysql-volume", "/var/lib/mysql"]
    }
    error_message = "Adoption must retain every existing persistent volume and mount path."
  }
}
