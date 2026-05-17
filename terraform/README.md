# terraform/

Infrastructure-as-code for the DigitalOcean deploy. See
[../DEPLOYMENT.md](../DEPLOYMENT.md) for the full phased plan; this
README is just the operator's runbook for the apply step.

## What this provisions

- **1× DigitalOcean Droplet** (Ubuntu 24.04, s-1vcpu-2gb by default)
  with cloud-init that installs Docker, sets up a `deploy` user,
  hardens SSH, enables unattended-upgrades.
- **1× DigitalOcean cloud firewall** allowing SSH only from your
  CIDRs, HTTP/HTTPS from anywhere.
- **1× DigitalOcean Space** (private) for nightly SQLite backups,
  with lifecycle rules (14d daily, 60d weekly, 400d monthly).
- **1× DigitalOcean DNS A record** at `<app_subdomain>.<domain>`
  (default `feeder.tmoneystuff.com`) pointing at the Droplet's
  IPv4. The zone itself is read-only via `data` — the user added
  the domain to DO control panel before `apply`. Other subdomains
  (apex, www, future apps) stay outside this Terraform's scope.
- **1× DigitalOcean Managed PostgreSQL** cluster (single-node,
  db-s-1vcpu-1gb, PG 16) in the same region as the Droplet, with a
  logical `tfr` database inside it and a database-firewall rule
  trusting only the Droplet. Sub-millisecond latency over the
  shared VPC, and DO handles backups + point-in-time recovery so
  the Spaces nightly-SQLite job goes away after D-PG-5 cutover.

Caddy on the Droplet mints its own Let's Encrypt cert via HTTP-01
on first request — no CDN / WAF in front for v1.

Total monthly cost: roughly **$12 Droplet + $5 Spaces + $15 PG = $32/mo**.

## Bootstrap

1. Install Terraform:
   ```
   brew install terraform
   ```

2. Populate `terraform.tfvars`:
   ```
   cp terraform.tfvars.example terraform.tfvars
   $EDITOR terraform.tfvars
   ```
   Fill in the tokens you generated in DEPLOYMENT.md Phase 0.

3. Initialise + apply:
   ```
   terraform init
   terraform plan    # sanity check what's about to change
   terraform apply
   ```

4. Take the outputs and proceed to Phase 3 (deploy):
   ```
   terraform output
   ```

## State

State is stored locally in `terraform.tfstate` (gitignored). Fine for
a single operator. If multiple people start touching the infra, move
state to a DO Space backend — one config block, no code change.

## Destroying

```
terraform destroy
```

Wipes the Droplet **and the Managed PG cluster** — make sure you've
exported a logical dump (`pg_dump`) or have DO's automated backup
window covered before running this. The Space bucket itself is
preserved unless you delete its contents first (DO refuses to delete
non-empty buckets via terraform).

## Phase 5 — managed PostgreSQL (D-PG-4)

`database.tf` is staged but **not yet applied** in production. The
plan output should show 3 new resources:

- `digitalocean_database_cluster.pg`
- `digitalocean_database_db.tfr`
- `digitalocean_database_firewall.pg`

Apply happens during D-PG-5 cutover, paired with running the
`scripts/dump_sqlite_to_postgres.rb` migration and flipping
`DATABASE_URL` in `/opt/app/.env`. See [../DEPLOYMENT.md](../DEPLOYMENT.md)
Phase 5 for the full sequence.

After apply, `terraform output -raw db_connection_string` prints the
sensitive URI (postgresql://doadmin:…@<private-host>:25060/tfr?sslmode=require)
to paste into `/opt/app/.env` as `DATABASE_URL`.
