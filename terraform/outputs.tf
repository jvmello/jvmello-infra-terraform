output "vps_id" {
  description = "ID of the DigitalOcean Droplet managed by this project."
  value       = digitalocean_droplet.vps.id
}

output "vps_ipv4_address" {
  description = "Public IPv4 of the Droplet — used as content in the DNS records."
  value       = digitalocean_droplet.vps.ipv4_address
}

output "cloudflare_zone_id" {
  description = "Cloudflare zone ID resolved from var.cloudflare_zone_name."
  value       = data.cloudflare_zone.jvmello_dev.zone_id
}

output "dns_record_ids" {
  description = "IDs of the managed DNS records, by logical key (see locals.dns_records)."
  value       = { for key, record in cloudflare_dns_record.sites : key => record.id }
}
