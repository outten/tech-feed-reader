# The single Droplet that runs the whole stack via docker-compose.
# Cloud-init handles first-boot prep: docker install, deploy user,
# unattended-upgrades, SSH hardening. The actual app deploy (git
# clone, .env population, docker compose up) is done manually once
# in Phase 3 — see DEPLOYMENT.md.

locals {
  ssh_pub_key = file(pathexpand(var.ssh_public_key_path))
}

resource "digitalocean_droplet" "app" {
  name     = "tech-feed-reader"
  region   = var.region
  size     = var.droplet_size
  image    = "ubuntu-24-04-x64"
  ssh_keys = [var.ssh_key_fingerprint]

  tags = ["app:tech-feed-reader", "env:prod"]

  user_data = <<-CLOUDINIT
    #cloud-config
    package_update: true
    package_upgrade: true

    packages:
      - ca-certificates
      - curl
      - gnupg
      - git
      - ufw
      - unattended-upgrades
      - apt-listchanges

    # Set timezone to UTC so logs + crons are unambiguous.
    timezone: Etc/UTC

    # Create the deploy user with the same SSH key as root so we never
    # need to log in as root after first boot.
    users:
      - name: deploy
        groups: [sudo, docker]
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        shell: /bin/bash
        ssh_authorized_keys:
          - "${chomp(local.ssh_pub_key)}"

    write_files:
      - path: /etc/apt/sources.list.d/docker.list
        content: |
          deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable

    runcmd:
      # Docker repo + install (docker-ce + compose plugin).
      - install -m 0755 -d /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      - chmod a+r /etc/apt/keyrings/docker.gpg
      - apt-get update
      - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      - systemctl enable --now docker

      # /opt/app holds the cloned repo + .env. deploy user owns it.
      - install -d -o deploy -g deploy -m 0755 /opt/app

      # SSH hardening: key auth only, no root login, no password.
      - sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
      - sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
      - systemctl restart ssh

      # Unattended security upgrades, weekly autoremove.
      - dpkg-reconfigure -fnoninteractive unattended-upgrades
  CLOUDINIT
}
