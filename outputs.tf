output "ip" {
  value = "${digitalocean_droplet.www.ipv4_address}"
}

output "fqdn" {
  value = "${var.hostname}"
}
