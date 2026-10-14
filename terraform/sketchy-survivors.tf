resource "cloudflare_worker" "sketchy_survivors" {
  account_id = var.cloudflare_account_id
  name       = "sketchy-survivors"
  subdomain = {
    enabled          = true
    previews_enabled = true
  }

  lifecycle {
    # NOTE: meatcar/sketchy-survivors CI owns Worker settings through wrangler deploy.
    ignore_changes = all
  }
}

resource "cloudflare_d1_database" "sketchy_survivors" {
  for_each = toset(["prod-a", "prod-b", "dev"])

  account_id            = var.cloudflare_account_id
  name                  = "sketchy-survivors-${each.key}"
  primary_location_hint = "enam"
  read_replication      = { mode = "disabled" }

  lifecycle {
    prevent_destroy = true
  }
}
