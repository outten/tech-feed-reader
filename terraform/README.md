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
- **Cloudflare DNS records** for the apex + `www`, proxied through
  Cloudflare (orange cloud), plus CAA records pinning cert issuance
  to Let's Encrypt.

Total monthly cost: roughly **$12 Droplet + $5 Spaces = $17/mo**.

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

Wipes the Droplet (and its SQLite DB volume — make sure you've got a
recent backup in the Space first). The Space bucket itself is
preserved unless you delete its contents first (DO refuses to delete
non-empty buckets via terraform).
