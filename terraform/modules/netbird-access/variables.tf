variable "bao_dns_zone_name" {
  type        = string
  description = "Hosted NetBird zone display name for bao.vpn.denys.me."
  default     = "Private OpenBao"
}

variable "bao_admin_peer_ids" {
  type        = set(string)
  description = "Complete bao-admins peer membership."

  validation {
    condition     = length(var.bao_admin_peer_ids) > 0
    error_message = "Supply the complete, nonempty administrator peer list to avoid removing access."
  }
}

variable "cpa_admin_peer_ids" {
  type        = set(string)
  description = "Peers explicitly authorized to access CPA management on TCP/443."

  validation {
    condition     = length(var.cpa_admin_peer_ids) > 0
    error_message = "At least one administrator peer must be authorized for CPA."
  }
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

variable "private_access_peer_ids" {
  type = object({
    administrators = set(string)
  })
  description = "Complete administrator membership for management and SSH/Mosh."
  default = {
    administrators = []
  }
}
