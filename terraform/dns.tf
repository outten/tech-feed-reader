# Cloudflare DNS pointing the domain at the Droplet. Proxied through
# Cloudflare (orange cloud) for CDN + WAF + DDoS protection.
#
# CAA records pin certificate issuance to Let's Encrypt only — both
# CF (which has its own internal cert for the proxied edge) and Caddy
# (which mints the origin cert via Let's Encrypt). Without these,
# anyone with a compromised CA could issue a cert for the domain.
#
# IMPORTANT: with Cloudflare proxy on, Caddy's HTTP-01 challenge has
# to traverse CF. CF passes /.well-known/acme-challenge/* through to
# the origin, so HTTP-01 still works — but if it fails, fall back to
# DNS-01 via the caddy-dns/cloudflare plugin (requires a custom Caddy
# build; see DEPLOYMENT.md Phase 3 notes).

resource "cloudflare_record" "apex" {
  zone_id = var.cf_zone_id
  name    = var.domain
  type    = "A"
  value   = digitalocean_droplet.app.ipv4_address
  ttl     = 1       # 1 = "Auto" when proxied
  proxied = true
}

resource "cloudflare_record" "www" {
  zone_id = var.cf_zone_id
  name    = "www.${var.domain}"
  type    = "A"
  value   = digitalocean_droplet.app.ipv4_address
  ttl     = 1
  proxied = true
}

# Pin certificate issuance to Let's Encrypt for both regular and
# wildcard certs. issuewild "letsencrypt.org" covers any future
# subdomains we might want under Caddy.
resource "cloudflare_record" "caa_issue" {
  zone_id = var.cf_zone_id
  name    = var.domain
  type    = "CAA"
  ttl     = 3600

  data {
    flags = "0"
    tag   = "issue"
    value = "letsencrypt.org"
  }
}

resource "cloudflare_record" "caa_issuewild" {
  zone_id = var.cf_zone_id
  name    = var.domain
  type    = "CAA"
  ttl     = 3600

  data {
    flags = "0"
    tag   = "issuewild"
    value = "letsencrypt.org"
  }
}
