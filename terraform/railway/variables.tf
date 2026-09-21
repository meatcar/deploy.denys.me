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
