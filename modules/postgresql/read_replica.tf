/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  primary_zone       = var.zone
  read_replica_zones = compact(split(",", var.read_replica_zones))

  zone_mapping = {
    enabled  = local.read_replica_zones
    disabled = local.primary_zone
  }

  zones_enabled = length(local.read_replica_zones) > 0
  mod_by        = local.zones_enabled ? length(local.read_replica_zones) : 1

  zones = local.zone_mapping[local.zones_enabled ? "enabled" : "disabled"]

  read_replica_ip_configuration_enabled = length(keys(var.read_replica_ip_configuration)) > 0 ? true : false

  read_replica_ip_configurations = {
    enabled  = var.read_replica_ip_configuration
    disabled = {}
  }
}

resource "google_sql_database_instance" "replicas" {
  count                = var.read_replica_size
  project              = var.service_project_id
  name                 = "${var.name}-replica${var.read_replica_name_suffix}${count.index}"
  database_version     = var.database_version
  region               = var.region
  master_instance_name = google_sql_database_instance.default.name
  dynamic "replica_configuration" {
    for_each = [var.read_replica_configuration]
    content {
      ca_certificate            = lookup(replica_configuration.value, "ca_certificate", null)
      client_certificate        = lookup(replica_configuration.value, "client_certificate", null)
      client_key                = lookup(replica_configuration.value, "client_key", null)
      connect_retry_interval    = lookup(replica_configuration.value, "connect_retry_interval", null)
      dump_file_path            = lookup(replica_configuration.value, "dump_file_path", null)
      failover_target           = false
      master_heartbeat_period   = lookup(replica_configuration.value, "master_heartbeat_period", null)
      password                  = lookup(replica_configuration.value, "password", null)
      ssl_cipher                = lookup(replica_configuration.value, "ssl_cipher", null)
      username                  = lookup(replica_configuration.value, "username", null)
      verify_server_certificate = lookup(replica_configuration.value, "verify_server_certificate", null)
    }
  }

  settings {
    tier                        = var.read_replica_tier
    activation_policy           = var.read_replica_activation_policy
    authorized_gae_applications = var.authorized_gae_applications
    availability_type           = var.read_replica_availability_type
    dynamic "ip_configuration" {
      for_each = [local.read_replica_ip_configurations[local.read_replica_ip_configuration_enabled ? "enabled" : "disabled"]]
      content {
        ipv4_enabled    = lookup(ip_configuration.value, "ipv4_enabled", null)
        private_network = lookup(ip_configuration.value, "private_network", null)
        require_ssl     = lookup(ip_configuration.value, "require_ssl", null)

        dynamic "authorized_networks" {
          for_each = lookup(ip_configuration.value, "authorized_networks", [])
          content {
            expiration_time = lookup(authorized_networks.value, "expiration_time", null)
            name            = lookup(authorized_networks.value, "name", null)
            value           = lookup(authorized_networks.value, "value", null)
          }
        }
      }
    }

    crash_safe_replication = var.read_replica_crash_safe_replication
    disk_autoresize        = var.read_replica_disk_autoresize
    disk_size              = var.read_replica_disk_size
    disk_type              = var.read_replica_disk_type
    pricing_plan           = var.read_replica_pricing_plan
    replication_type       = var.read_replica_replication_type
    user_labels            = var.read_replica_user_labels
    dynamic "database_flags" {
      for_each = var.read_replica_database_flags
      content {
        name  = lookup(database_flags.value, "name", null)
        value = lookup(database_flags.value, "value", null)
      }
    }

    location_preference {
      zone = length(local.zones) == 0 ? "" : "${var.region}-${local.zones[count.index % local.mod_by]}"
    }

    maintenance_window {
      day          = var.read_replica_maintenance_window_day
      hour         = var.read_replica_maintenance_window_hour
      update_track = var.read_replica_maintenance_window_update_track
    }
  }

  depends_on = [google_sql_database_instance.default]


  lifecycle {
    ignore_changes = [
      settings[0].disk_size
    ]
  }


  timeouts {
    create = var.create_timeout
    update = var.update_timeout
    delete = var.delete_timeout
  }
}

resource "google_sql_ssl_cert" "client_cert_rr" {
  count                = var.read_replica_size
  common_name = google_sql_database_instance.replicas[count.index].name
  project = var.service_project_id
  instance    = google_sql_database_instance.replicas[count.index].name
  depends_on = [google_sql_database_instance.replicas]
}

