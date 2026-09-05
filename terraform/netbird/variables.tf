variable "bao_dns_zone_id" {
  type        = string
  description = "Existing hosted NetBird DNS zone ID for bao.vpn.denys.me."
}

variable "bao_dns_record_id" {
  type        = string
  description = "Existing A record ID within the Bao zone."
}

variable "bao_policy_id" {
  type        = string
  description = "Existing bao-admin-access policy ID."
}

variable "bao_dns_zone_name" {
  type        = string
  description = "Preserve the existing hosted NetBird zone display name during adoption."
  default     = "Private OpenBao"
}

variable "bao_admin_peer_ids" {
  type        = set(string)
  description = "Complete existing bao-admins peer membership, verified against hosted NetBird before import."

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
