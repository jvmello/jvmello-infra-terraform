# ---------------------------------------------------------------------------
# Existing Cloudflare zone — read-only. Does not create or modify the zone,
# it only resolves the real zone_id from the domain name.
# ---------------------------------------------------------------------------
data "cloudflare_zone" "jvmello_dev" {
  filter = {
    name = var.cloudflare_zone_name
  }
}

# ---------------------------------------------------------------------------
# Existing VPS (DigitalOcean Droplet). Represents the single VPS that today
# runs the entire jvmello-infra docker-compose.yml (Caddy, apps, Postgres,
# Umami).
#
# region/size/image/name have no default (see variables.tf) — fill them in
# with the real values confirmed in the DigitalOcean dashboard BEFORE
# running the import (see terraform/imports.md). A wrong value here doesn't
# change anything by itself (no apply has been or should be run before the
# import), but it will make the post-import "terraform plan" show incorrect
# diffs.
# ---------------------------------------------------------------------------
resource "digitalocean_droplet" "vps" {
  name       = var.vps_name
  region     = var.vps_region
  size       = var.vps_size
  image      = var.vps_image
  ipv6       = var.vps_ipv6
  tags       = var.vps_tags
  monitoring = var.vps_monitoring
  backups    = var.vps_backups

  ssh_keys  = var.vps_ssh_keys
  user_data = var.vps_user_data

  lifecycle {
    # ssh_keys: the provider doesn't manage incremental add/remove after the
    # Droplet is created ("modifying this field will prompt you to destroy
    # and recreate the Droplet", per the provider docs) — comparing against
    # the real value would only create a risk of accidentally recreating a
    # production VPS.
    #
    # user_data: changing this field always forces Droplet recreation, and
    # the DigitalOcean API doesn't return the original user_data for an
    # already-created Droplet — there's no way for Terraform to validate
    # this field against reality after the import.
    #
    # See docs/terraform-design.md, "Migration risks" section, item 1.
    ignore_changes = [ssh_keys, user_data]
  }
}

# ---------------------------------------------------------------------------
# There is no DigitalOcean Cloud Firewall on this account (confirmed in the
# dashboard: "Looks like you haven't assigned a firewall"). The restriction
# of ports 80/443 to Cloudflare IPs exists today only via ufw on the host
# (jvmello-infra/scripts/setup-firewall.sh), which is out of scope for
# Terraform — see docs/infrastructure-inventory.md. No digitalocean_firewall
# resource is declared here: creating one now would mean provisioning
# something new, not migrating something that already exists. If you decide
# to add this security layer in the future, that's a deliberate step,
# separate from this migration.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Existing DNS records on Cloudflare (see docs/infrastructure-inventory.md
# and the jvmello-infra Caddyfile, which routes each of these hosts to the
# right service inside the VPS). Most point straight at the VPS's IP, but
# not all — see the notes in locals.tf (the "www" CNAME and
# "worldcup_api" not being proxied were both confirmed via the Cloudflare
# API, not assumed).
# ---------------------------------------------------------------------------
resource "cloudflare_dns_record" "sites" {
  for_each = local.dns_records

  zone_id = data.cloudflare_zone.jvmello_dev.zone_id
  name    = each.value.name
  type    = each.value.type
  content = coalesce(each.value.content, digitalocean_droplet.vps.ipv4_address)

  # ttl = 1 is the value Cloudflare requires for "automatic", mandatory
  # when proxied = true.
  ttl     = 1
  proxied = each.value.proxied

  # No "comment" here on purpose: none of these records had one in
  # reality (confirmed via a real terraform plan after import — every
  # single record showed "+ comment", nothing else). Adding one now would
  # be a real, deliberate change to production DNS, not a migration of
  # what already exists — see docs/terraform-design.md, "Migration
  # risks". If you want a "managed by Terraform" label on these records,
  # add it later as its own reviewed change.
}
