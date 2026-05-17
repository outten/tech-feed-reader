# Private DO Space for nightly SQLite backups. The backup script on
# the Droplet uses sqlite3's online .backup command + s3cmd to push
# the dump file here. See scripts/backup.sh (added in Phase 4).
#
# Retention: configured via the bucket's lifecycle rule so we don't
# accumulate forever (current cap 7 daily + 4 weekly + 12 monthly).

resource "digitalocean_spaces_bucket" "backups" {
  name   = var.backups_bucket_name
  region = var.region
  acl    = "private"

  versioning {
    enabled = false
  }

  # Block order here matches the order DO returns them in (alphabetical
  # by id, as of the provider version we're on). The provider compares
  # lifecycle_rule blocks positionally, so a mismatched order shows up
  # as a perpetual in-place "update" on every plan even though the
  # rules themselves are identical.
  lifecycle_rule {
    id      = "expire-daily-backups"
    enabled = true
    prefix  = "daily/"
    expiration {
      days = 14
    }
  }

  lifecycle_rule {
    id      = "expire-monthly-backups"
    enabled = true
    prefix  = "monthly/"
    expiration {
      days = 400
    }
  }

  lifecycle_rule {
    id      = "expire-weekly-backups"
    enabled = true
    prefix  = "weekly/"
    expiration {
      days = 60
    }
  }
}
