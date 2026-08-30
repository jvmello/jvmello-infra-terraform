# Hosts that exist today on Cloudflare and point to the VPS (see
# docs/infrastructure-inventory.md, "DNS / Domains" section, and the
# jvmello-infra Caddyfile, which already routes each of these hosts to the
# right service). Confirmed against the real zone via the Cloudflare API on
# 2026-08-29 — see terraform/imports.md for the actual record IDs.
#
# Notes from that confirmation (do NOT assume all records look alike):
#   - "www" is a CNAME to the apex, not an A record — content is set
#     explicitly below instead of falling back to the Droplet's IP.
#   - "worldcup_api" has proxied = false in reality, unlike every other
#     host here.
#   - "worldcup_match_ratings" already exists (the jvmello-infra README
#     said it didn't yet — that turned out to be outdated).
#
# "content = null" means "fall back to the Droplet's IPv4" (see main.tf).
locals {
  dns_records = {
    apex = {
      name    = var.cloudflare_zone_name
      type    = "A"
      proxied = true
      content = null
    }
    www = {
      name    = "www.${var.cloudflare_zone_name}"
      type    = "CNAME"
      proxied = true
      content = var.cloudflare_zone_name
    }
    worldcup = {
      name    = "worldcup.${var.cloudflare_zone_name}"
      type    = "A"
      proxied = true
      content = null
    }
    worldcup_api = {
      name    = "api.worldcup.${var.cloudflare_zone_name}"
      type    = "A"
      proxied = false
      content = null
    }
    analytics = {
      name    = "analytics.${var.cloudflare_zone_name}"
      type    = "A"
      proxied = true
      content = null
    }
    weplay = {
      name    = "weplay.${var.cloudflare_zone_name}"
      type    = "A"
      proxied = true
      content = null
    }
    worldcup_match_ratings = {
      name    = "worldcup-match-ratings.${var.cloudflare_zone_name}"
      type    = "A"
      proxied = true
      content = null
    }
  }
}
