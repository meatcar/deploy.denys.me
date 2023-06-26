
variable "digitalocean_region" {
  type    = string
  default = "tor1"
}

variable "digitalocean_spaces_key" {
  type    = string
  default = "${env("TF_VAR_digitalocean_spaces_key")}"
}

variable "digitalocean_spaces_secret" {
  type      = string
  default   = "${env("TF_VAR_digitalocean_spaces_secret")}"
  sensitive = true
}

variable "digitalocean_token" {
  type    = string
  default = "${env("TF_VAR_digitalocean_token")}"
}

variable "version" {
  type    = string
  default = "${env("BASE_NIX_VERSION")}"
}

variable "image" {
  type    = string
  default = ""
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "file" "base_image" {
  source = "${var.image}"
  target = "${var.version}-target"
}

build {
  sources = ["source.file.base_image"]

  post-processor "digitalocean-import" {
    api_token          = "${var.digitalocean_token}"
    spaces_key         = "${var.digitalocean_spaces_key}"
    spaces_secret      = "${var.digitalocean_spaces_secret}"
    spaces_region      = "nyc3"
    space_name         = "meatcar-images"
    image_description  = "Packer import ${local.timestamp}"
    image_distribution = "NixOS"
    image_name         = "${var.version}"
    image_regions      = ["${var.digitalocean_region}"]
    image_tags         = ["custom", "packer", "nixos", "nixos-generate"]
  }
}
