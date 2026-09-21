variable "parked_domains" {
  type        = set(string)
  description = "Existing Cloudflare zones to park with web aliases and Fastmail delivery."
}

variable "ipv4_address" {
  type        = string
  description = "Web origin for the parked domains."
}
