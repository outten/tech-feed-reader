# STUFF #33B — DigitalOcean Container Registry.
#
# Hosts the versioned Docker image. The local-build pipeline
# (`make publish-image`) pushes amd64-built images here from the
# operator's laptop; the Droplet's `make deploy` pulls from here
# instead of building locally. Tag-pinned rollback becomes a
# one-liner: `IMAGE_TAG=0.9.3 docker compose up -d`.
#
# Basic tier: ~$5/mo, 5 GB storage, 1 free repository. Our image is
# ~150-200 MB; we'll keep ~10 tags before it pinches. Tier can be
# bumped (Professional, Premium) via `subscription_tier_slug`
# without recreating the registry, so it's cheap to upgrade later.
#
# Registry name is GLOBALLY UNIQUE across all of DigitalOcean (not
# per-account, not per-region). A `terraform apply` collision means
# bump `registry_name` in tfvars and retry — no orphan resources to
# clean up.

resource "digitalocean_container_registry" "main" {
  name                   = var.registry_name
  subscription_tier_slug = "basic"
  region                 = var.region
}
