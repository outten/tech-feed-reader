# Surfaced after `terraform apply` so the Phase 3 deploy steps have
# everything they need without going hunting in the DO dashboard.

output "droplet_ipv4" {
  description = "Public IPv4 of the Droplet. SSH to deploy@<this> after first boot."
  value       = digitalocean_droplet.app.ipv4_address
}

output "droplet_id" {
  description = "DigitalOcean Droplet ID."
  value       = digitalocean_droplet.app.id
}

output "backups_bucket" {
  description = "DO Space bucket name for backups. Set BACKUP_BUCKET on the Droplet to this value."
  value       = digitalocean_spaces_bucket.backups.name
}

output "backups_endpoint" {
  description = "S3-compatible endpoint for the backups bucket. Set BACKUP_ENDPOINT on the Droplet to this value."
  value       = "https://${var.region}.digitaloceanspaces.com"
}

output "public_url" {
  description = "The HTTPS URL the app will serve from once docker compose is up + Caddy has minted a cert."
  value       = "https://${var.app_subdomain}.${var.domain}"
}

output "app_hostname" {
  description = "Bare hostname the app serves at. Drop into /opt/app/.env on the Droplet as DOMAIN= for Caddy and as WEBAUTHN_RP_ID for the app."
  value       = "${var.app_subdomain}.${var.domain}"
}

# Phase 5 / D-PG-4 — Managed PostgreSQL connection string. Sensitive
# (carries the doadmin password). After `terraform apply` of the
# database stack, copy this into /opt/app/.env on the Droplet as
# DATABASE_URL=… ; the app's adapter routes to PG when this is set.
# We build the URI ourselves rather than use private_uri so it points
# at the `tfr` database we created (DO's private_uri targets the
# default `defaultdb`).
output "db_connection_string" {
  description = "postgresql:// URI for the managed cluster's `tfr` database. Sensitive — paste into /opt/app/.env as DATABASE_URL on the Droplet."
  value = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    digitalocean_database_cluster.pg.user,
    digitalocean_database_cluster.pg.password,
    digitalocean_database_cluster.pg.private_host,
    digitalocean_database_cluster.pg.port,
    digitalocean_database_db.tfr.name
  )
  sensitive = true
}

output "db_host" {
  description = "Private VPC host the Droplet reaches the cluster on (no port)."
  value       = digitalocean_database_cluster.pg.private_host
}

output "ssh_command" {
  description = "Convenience: copy/paste to SSH into the Droplet."
  value       = "ssh deploy@${digitalocean_droplet.app.ipv4_address}"
}
