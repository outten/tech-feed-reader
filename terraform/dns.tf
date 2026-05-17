# DigitalOcean DNS records for the app.
#
# The domain (tmoneystuff.com) is hosted in DO — the user pointed
# the registrar's NS records at ns{1,2,3}.digitalocean.com and added
# the zone in the DO control panel. We reference it via `data` (not
# `resource`) so Terraform doesn't try to re-create the zone, and so
# we leave the apex / other-app records the user manages outside
# this app's Terraform alone (the user plans to deploy additional
# apps to other subdomains of the same zone).
#
# This app serves at `${var.app_subdomain}.${var.domain}` (default
# `feeder.tmoneystuff.com`). Only one record is managed here: an A
# record for the subdomain pointing at the Droplet's IPv4.
#
# TLS: Caddy on the Droplet mints a Let's Encrypt cert directly via
# the HTTP-01 challenge. Firewall opens port 80 + 443 to the world.
# No CDN / WAF in front for v1 — could add one later as a follow-up.

data "digitalocean_domain" "zone" {
  name = var.domain
}

resource "digitalocean_record" "app" {
  domain = data.digitalocean_domain.zone.name
  type   = "A"
  name   = var.app_subdomain
  value  = digitalocean_droplet.app.ipv4_address
  ttl    = 300
}
