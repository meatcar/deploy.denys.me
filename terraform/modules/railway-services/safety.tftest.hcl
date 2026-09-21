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
