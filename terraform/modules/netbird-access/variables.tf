variable "bao_dns_zone_name" {
  type        = string
  description = "Hosted NetBird zone display name for bao.vpn.denys.me."
  default     = "Private OpenBao"
}

variable "private_server_ips" {
  type        = map(string)
  description = "Verified enrolled NetBird IPv4 addresses, keyed by host. Empty until enrollment is tested."
  default     = {}

  validation {
    condition = (
      alltrue([for name, ip in var.private_server_ips : contains(["vps"], name) && can(cidrnetmask("${ip}/32"))]) &&
      length(distinct(values(var.private_server_ips))) == length(var.private_server_ips)
    )
    error_message = "Only VPS may be supplied, with an IPv4 address verified after enrollment."
  }
}
