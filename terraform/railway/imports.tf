import {
  to = railway_project.paseo
  id = var.project_id
}

import {
  to = railway_service.paseo
  id = var.service_id
}

import {
  to = railway_custom_domain.paseo
  id = "${var.service_id}:production:paseo.denys.me"
}

import {
  to = railway_variable_collection.paseo
  id = "${var.service_id}:production:${join(":", sort(keys(local.variables)))}"
}

import {
  for_each = var.project_ids
  to       = railway_project.application[each.key]
  id       = each.value
}

import {
  for_each = local.image_services
  to       = railway_service.image[each.key]
  id       = var.service_ids[each.key]
}

import {
  to = railway_service.rsshub
  id = var.service_ids.rsshub
}

import {
  to = railway_service_domain.rsshub
  id = "${var.service_ids.rsshub}:production:rsshub-production-7bff.up.railway.app"
}

import {
  to = railway_custom_domain.monitor
  id = "${var.service_ids.uptime_kuma}:production:monitor.denys.me"
}
