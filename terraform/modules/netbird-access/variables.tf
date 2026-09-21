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
