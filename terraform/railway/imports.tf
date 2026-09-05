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
