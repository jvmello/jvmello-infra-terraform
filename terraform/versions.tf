# Minimum Terraform version supported by this project.
# 1.9+ guarantees stable, widely available behavior in 2026; adjust the
# ceiling if you ever need to pin a specific maximum version.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.24"
    }
  }

  # No "backend" block for now: local state, on purpose.
  # See docs/state.md for how and when to migrate to a remote backend.
}
