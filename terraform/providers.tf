# DigitalOcean is the only provider — droplet + firewall + Spaces
# bucket + DNS records all live in DO. The user pointed the
# registrar's NS records at ns{1,2,3}.digitalocean.com and added
# the domain zone in the DO control panel. See DEPLOYMENT.md.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.do_spaces_access_id
  spaces_secret_key = var.do_spaces_secret_key
}
