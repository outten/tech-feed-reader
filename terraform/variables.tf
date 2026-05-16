# All inputs come from terraform.tfvars (gitignored). Tokens are
# marked sensitive so they don't leak into terraform plan output.

variable "do_token" {
  description = "DigitalOcean Personal Access Token (read + write)."
  type        = string
  sensitive   = true
}

variable "do_spaces_access_id" {
  description = "DigitalOcean Spaces access key ID. Used by terraform to create the backups bucket; also needs to be set on the Droplet for the backup cron."
  type        = string
  sensitive   = true
}

variable "do_spaces_secret_key" {
  description = "DigitalOcean Spaces secret key."
  type        = string
  sensitive   = true
}

variable "cf_token" {
  description = "Cloudflare API token scoped to the zone (template: Edit zone DNS)."
  type        = string
  sensitive   = true
}

variable "cf_zone_id" {
  description = "Cloudflare zone ID for the domain. Found in the Cloudflare dashboard sidebar of the domain."
  type        = string
}

variable "domain" {
  description = "Bare domain (e.g. tfr.example.com). Used for DNS records, Caddy TLS, and WebAuthn RP ID."
  type        = string
}

variable "region" {
  description = "DigitalOcean region slug. nyc3 is east-coast US; sfo3 west; ams3 EU; sgp1 Asia."
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "DigitalOcean Droplet size slug. s-1vcpu-2gb ($12/mo) handles Sinatra + Sidekiq + Redis + Caddy without OOM. Downsize to s-1vcpu-1gb ($6/mo) only after verifying memory headroom."
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "ssh_key_fingerprint" {
  description = "Fingerprint of the SSH public key registered in DigitalOcean (Settings → Security). Get it via: ssh-keygen -lf ~/.ssh/id_ed25519.pub | awk '{print $2}'"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file. Must match the key whose fingerprint is in ssh_key_fingerprint. Cloud-init injects this into the deploy user's authorized_keys so you can SSH as deploy@droplet (not root) after first boot."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH (port 22). Default is your home/office IP only — find via `curl ifconfig.me` and append /32. Use [\"0.0.0.0/0\"] only if you're confident in your fail2ban / passwordless-auth setup."
  type        = list(string)
}

variable "backups_bucket_name" {
  description = "Name of the DO Space for nightly SQLite backups. Must be globally unique within the region."
  type        = string
  default     = "tech-feed-reader-backups"
}
