variable "ssh_fingerprint" {
  description = "The ssh key fingerprint (ssh-keygen -l -E md5 -f ~/.ssh/id_rsa.pub | awk '{ print $2 }' | sed 's/MD5://)'"
}

variable "digitalocean_token" {
  description = "Digital Ocean Private Access Token"
}

variable "cloudflare_email" {
  description = "Cloudflare email"
}

variable "cloudflare_token" {
  description = "Cloudflare token (https://dash.cloudflare.com/profile/api-tokens)"
}

variable "cloudflare_domain" {
  description = "Cloudflare Domain to set DNS on"
}

variable "parked_domains" {
  type = list(string)
  description = "Parked domains, not in use"
}

variable "hostname" {
  description = "The hostname we want to serve"
}

variable "wg_nodes" {
  description = "A list of descriptive wireguard node names"
  default     = ["server", "laptop", "phone", "cube.denys.me", "steamdeck"]
}

variable "nix_znc_password" {
  description = "ZNC User's password for misc plugins"
}

variable "nix_znc_hash" {
  description = "ZNC User's password hash using 'echo pass\npass | nix-shell -p znc --command \"znc --makepass\"'"
}

variable "nix_znc_salt" {
  description = "ZNC User's password salt using 'echo pass\npass | nix-shell -p znc --command \"znc --makepass\"'"
}

variable "nix_znc_nickservpassword" {
  description = "ZNC User's nickserv password"
}
