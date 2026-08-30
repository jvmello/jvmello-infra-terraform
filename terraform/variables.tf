# --- Provider credentials --------------------------------------------------
# Prefer exporting DIGITALOCEAN_TOKEN / CLOUDFLARE_API_TOKEN in the
# environment instead of filling these variables in terraform.tfvars. None
# of them have a default: if not provided via environment variable or
# tfvars, Terraform will prompt interactively (and it's never saved in
# .tf).

variable "do_token" {
  description = <<-EOT
    DigitalOcean API token (read/write scope).
    Recommended alternative: DIGITALOCEAN_TOKEN environment variable.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = <<-EOT
    Cloudflare API token. Recommended: a token scoped to the jvmello.dev
    zone (Zone:DNS:Edit), not the account's global key.
    Recommended alternative: CLOUDFLARE_API_TOKEN environment variable.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

# --- Domain / Cloudflare zone -----------------------------------------------

variable "cloudflare_zone_name" {
  description = "Root domain managed on Cloudflare (identified from the jvmello-infra README)."
  type        = string
  default     = "jvmello.dev"
}

# --- VPS (DigitalOcean Droplet) ---------------------------------------------
# None of these have a default: the real values aren't documented anywhere
# in the jvmello-infra repository. Fill them in by checking the
# DigitalOcean dashboard (or `doctl compute droplet list`) BEFORE importing
# — see terraform/imports.md.

variable "vps_name" {
  description = "TODO: exact name of the existing Droplet, exactly as it appears in the DigitalOcean dashboard."
  type        = string

  validation {
    condition     = length(trimspace(var.vps_name)) > 0
    error_message = "vps_name cannot be empty — fill in the Droplet's real name before importing."
  }
}

variable "vps_region" {
  description = "TODO: slug of the existing Droplet's region (e.g. nyc3, fra1). Confirm in the DigitalOcean dashboard."
  type        = string
}

variable "vps_size" {
  description = "TODO: slug of the existing Droplet's size (e.g. s-1vcpu-2gb). Confirm in the DigitalOcean dashboard."
  type        = string
}

variable "vps_image" {
  description = "TODO: slug or ID of the existing Droplet's image (e.g. ubuntu-22-04-x64). Confirm in the DigitalOcean dashboard."
  type        = string
}

variable "vps_ipv6" {
  description = "Whether the existing Droplet has IPv6 enabled. TODO: confirm in the dashboard — not identifiable from the repository."
  type        = bool
  default     = false
}

variable "vps_tags" {
  description = "Tags applied to the existing Droplet, if any. TODO: confirm in the dashboard (not identified in the repository)."
  type        = list(string)
  default     = []
}

variable "vps_ssh_keys" {
  description = <<-EOT
    IDs or fingerprints of the SSH keys authorized on the Droplet. Ignored
    after the import (see lifecycle.ignore_changes in main.tf) because the
    provider can't manage this field incrementally on an existing Droplet
    — it only matters if the resource ever needs to be recreated from
    scratch. TODO: fill it in with the real values anyway, for that future
    scenario.
  EOT
  type        = list(string)
  default     = []
}

variable "vps_user_data" {
  description = <<-EOT
    Original cloud-init/user_data of the Droplet, if any was used at
    creation time. Ignored after the import (see lifecycle.ignore_changes
    in main.tf) because the DigitalOcean API doesn't return this value for
    an already-created Droplet — there's no way to confirm it from the
    existing infrastructure. TODO: fill it in if you have this value saved
    somewhere else (e.g. an initial provisioning script), for a future
    recreation scenario.
  EOT
  type        = string
  default     = null
}

# --- Cloud firewall ----------------------------------------------------------
# There is no DigitalOcean Cloud Firewall on this account (confirmed in the
# dashboard). No variables here — see the comment in main.tf.
