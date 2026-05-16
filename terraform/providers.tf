# DigitalOcean for the droplet + firewall + Spaces bucket;
# Cloudflare for DNS records (the domain is hosted at Cloudflare for
# free DNS + CDN + WAF in front of the origin). See DEPLOYMENT.md.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
}

provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.do_spaces_access_id
  spaces_secret_key = var.do_spaces_secret_key
}

provider "cloudflare" {
  api_token = var.cf_token
}
