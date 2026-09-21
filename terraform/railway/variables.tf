variable "project_id" {
  type        = string
  description = "Existing paseo-relay project UUID. Verify production is its oldest/default environment."
}

variable "service_id" {
  type        = string
  description = "Existing Paseo service UUID."
}

variable "service_name" {
  type        = string
  description = "Existing Paseo service display name; preserve it during adoption."
}

variable "region" {
  type        = string
  description = "Existing production deployment region; preserve it during adoption."
}

variable "project_ids" {
  type = object({
    rsshub  = string
    monitor = string
  })
  description = "Existing RSSHub and monitoring project UUIDs."
}

variable "service_ids" {
  type = object({
    rsshub      = string
    redis       = string
    uptime_kuma = string
    mysql       = string
  })
  description = "Existing RSSHub and monitoring service UUIDs."
}
