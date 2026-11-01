resource "netbird_account_settings" "this" {
  network_range                       = "10.201.0.0/16"
  groups_propagation_enabled          = true
  jwt_groups_enabled                  = false
  user_approval_required              = true
  peer_approval_enabled               = false
  regular_users_view_blocked          = true
  peer_login_expiration_enabled       = true
  peer_login_expiration               = 86400
  peer_inactivity_expiration_enabled  = false
  peer_expose_enabled                 = false
  lazy_connection_enabled             = true
  routing_peer_dns_resolution_enabled = true
  network_traffic_logs_enabled        = false
  auto_update_version                 = "disabled"

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_settings" "this" {
  disabled_management_groups = []
}

resource "netbird_user" "owner" {
  is_service_user = false
  role            = "owner"
  auto_groups     = [netbird_group.role_admins.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_user" "terraform" {
  is_service_user = true
  name            = "terraform@deploy.denys.me"
  role            = "admin"
  auto_groups     = []

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_setup_key" "agent_vms" {
  # NOTE: Replacement writes the plaintext key to state. Rotate instead, see README.
  name                   = "amp--orbs"
  type                   = "reusable"
  ephemeral              = true
  usage_limit            = 0
  allow_extra_dns_labels = false
  auto_groups            = [netbird_group.role_agent_vms.id]

  lifecycle {
    prevent_destroy = true
  }
}

data "netbird_group" "all" {
  name = "All"
}

resource "netbird_policy" "default" {
  name        = "Default"
  description = "This is a default rule that allows connections between all the resources"
  enabled     = false

  rule {
    name          = "Default"
    description   = "This is a default rule that allows connections between all the resources"
    enabled       = true
    action        = "accept"
    bidirectional = true
    protocol      = "all"
    sources       = [data.netbird_group.all.id]
    destinations  = [data.netbird_group.all.id]
  }

  lifecycle {
    prevent_destroy = true
  }
}
