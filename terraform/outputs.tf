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

output "ssh_command" {
  description = "Convenience: copy/paste to SSH into the Droplet."
  value       = "ssh deploy@${digitalocean_droplet.app.ipv4_address}"
}
