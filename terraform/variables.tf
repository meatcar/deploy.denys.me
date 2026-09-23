variable "ssh_fingerprint" {
  type        = string
  description = "The ssh key fingerprint (ssh-keygen -l -E md5 -f ~/.ssh/id_rsa.pub | awk '{ print $2 }' | sed 's/MD5://)'"
}

variable "digitalocean_token" {
  type        = string
  description = "Digital Ocean Private Access Token"
}

variable "cloudflare_token" {
  type        = string
  description = "Cloudflare token (https://dash.cloudflare.com/profile/api-tokens)"
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID that owns the managed zone"
}

variable "cloudflare_domain" {
  type        = string
  description = "Cloudflare Domain to set DNS on"
}

variable "parked_domains" {
  type        = list(string)
  description = "Parked domains, not in use"
}

variable "hostname" {
  type        = string
  description = "The hostname we want to serve"
}

variable "oci_config_file_profile" {
  type        = string
  description = "OCI CLI config profile to use for security-token authentication"
  default     = "meatcar"
}

variable "oci_region" {
  type        = string
  description = "OCI region for the chunkymonkey instance"
}

variable "oci_compartment_ocid" {
  type        = string
  description = "OCI compartment OCID containing the chunkymonkey instance"
}

variable "private_server_ips" {
  type        = map(string)
  description = "Verified Cube/VPS NetBird IPv4 addresses after enrollment; no destination access is created while empty."
  default     = {}
}

variable "private_access_peer_ids" {
  type = object({
    administrators = set(string)
    household      = set(string)
    storage        = set(string)
  })
  description = "Complete administrator, Cube household HTTPS and SMB client memberships, managed independently."
  default = {
    administrators = ["dag13hqfadhs739d7rg0"]
    household      = []
    storage        = []
  }
}
