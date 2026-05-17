# Phase 5 / D-PG-4 — DigitalOcean Managed PostgreSQL.
#
# Single-node cluster, smallest tier ($15/mo), in the same region as
# the Droplet so app → DB latency is sub-millisecond. The cluster has
# its own firewall (separate from the Droplet's edge firewall in
# firewall.tf); we open it to the Droplet only.
#
# Don't apply this until D-PG-5 (cutover). `terraform plan` should
# show 3 resources to add: the cluster, the database inside it, and
# the firewall rule. Cost begins the moment the cluster is created.

resource "digitalocean_database_cluster" "pg" {
  name    = "${var.app_subdomain}-pg"
  engine  = "pg"
  version = "16"
  # db-s-1vcpu-1gb is the smallest current tier (~$15/mo). Single
  # node, no HA, no read replicas — appropriate for one-user load.
  size       = "db-s-1vcpu-1gb"
  region     = var.region
  node_count = 1

  tags = ["env:prod", "app:tech-feed-reader"]
}

# Logical database inside the cluster. Cluster bootstraps with a
# default "defaultdb" + a "doadmin" user; we create a dedicated
# database so the connection string is friendly.
resource "digitalocean_database_db" "tfr" {
  cluster_id = digitalocean_database_cluster.pg.id
  name       = "tfr"
}

# Trust-list — only the Droplet can reach the cluster's 25060/tcp.
# DO managed PG ships a public hostname AND a private VPC hostname;
# trusting the Droplet by `droplet` source covers both paths and
# also auto-updates if the Droplet's IP rotates on rebuild.
resource "digitalocean_database_firewall" "pg" {
  cluster_id = digitalocean_database_cluster.pg.id

  rule {
    type  = "droplet"
    value = digitalocean_droplet.app.id
  }
}
