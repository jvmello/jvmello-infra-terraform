# Import plan (COMPLETED — 2026-08-30)

This file originally documented, for each resource that already existed,
the Terraform address and the command used to import it. **All 8
resources listed below have since been imported**, and `terraform plan`
confirmed a clean `No changes` afterward — this repo's Terraform state
now fully describes the real infrastructure.

The real IDs (Droplet ID, Cloudflare zone ID, DNS record IDs) have been
**intentionally redacted** from this file, since it's committed to a
public repository and those IDs aren't needed here anymore — they're
already in the local (gitignored) `terraform.tfstate`. If you ever need
one again:

```bash
terraform state show digitalocean_droplet.vps
terraform state show 'cloudflare_dns_record.sites["apex"]'
# ... or just:
terraform show
```

This file stays as a reference for the **process and command format**,
useful if you ever need to import a similar resource again (e.g. after a
lost/reset local state, or when adding a new DigitalOcean/Cloudflare
resource elsewhere).

## 1. VPS (Droplet)

| Field | Value |
|---|---|
| Terraform resource address | `digitalocean_droplet.vps` |
| Type | `digitalocean_droplet` |
| Real resource | The DigitalOcean Droplet hosting `jvmello-infra`'s `docker-compose.yml` |
| Status | ✅ Imported on 2026-08-30 |

Command format used (real ID redacted here — see `terraform state show
digitalocean_droplet.vps` for the actual one):

```bash
terraform import digitalocean_droplet.vps <DROPLET_ID>
```

## 2. DNS records (Cloudflare)

Zone: `jvmello.dev`. All records use the same resource type, with
`for_each`; each address includes the key from the `local.dns_records` map
(`terraform/locals.tf`) in brackets.

| Terraform resource address | Real host | Real type | Real `proxied` | Status |
|---|---|---|---|---|
| `cloudflare_dns_record.sites["apex"]` | `jvmello.dev` | A | true | ✅ Imported |
| `cloudflare_dns_record.sites["www"]` | `www.jvmello.dev` | **CNAME** (→ `jvmello.dev`) | true | ✅ Imported |
| `cloudflare_dns_record.sites["worldcup"]` | `worldcup.jvmello.dev` | A | true | ✅ Imported |
| `cloudflare_dns_record.sites["worldcup_api"]` | `api.worldcup.jvmello.dev` | A | **false** | ✅ Imported |
| `cloudflare_dns_record.sites["analytics"]` | `analytics.jvmello.dev` | A | true | ✅ Imported |
| `cloudflare_dns_record.sites["weplay"]` | `weplay.jvmello.dev` | A | true | ✅ Imported |
| `cloudflare_dns_record.sites["worldcup_match_ratings"]` | `worldcup-match-ratings.jvmello.dev` | A | true | ✅ Imported |

**Bold** values above are the two spots where reality differed from the
inventory's original assumption (both fixed in `terraform/locals.tf` and
`terraform/main.tf` before the import): `www` is a CNAME to the apex, not
a plain A record; `worldcup_api` has `proxied = false`, unlike every
other host. `worldcup_match_ratings` was also a discovery of its own —
the `jvmello-infra` README claimed it hadn't been created yet, but it
already existed.

All records shared the Droplet's IP as content (except `www`, per the
CNAME above).

Command format used, `<zone_id>/<record_id>` (real IDs redacted — see
`terraform state show 'cloudflare_dns_record.sites["<key>"]'` for the
actual ones):

```bash
terraform import 'cloudflare_dns_record.sites["apex"]' <ZONE_ID>/<RECORD_ID>
terraform import 'cloudflare_dns_record.sites["www"]' <ZONE_ID>/<RECORD_ID>
terraform import 'cloudflare_dns_record.sites["worldcup"]' <ZONE_ID>/<RECORD_ID>
terraform import 'cloudflare_dns_record.sites["worldcup_api"]' <ZONE_ID>/<RECORD_ID>
terraform import 'cloudflare_dns_record.sites["analytics"]' <ZONE_ID>/<RECORD_ID>
terraform import 'cloudflare_dns_record.sites["weplay"]' <ZONE_ID>/<RECORD_ID>
terraform import 'cloudflare_dns_record.sites["worldcup_match_ratings"]' <ZONE_ID>/<RECORD_ID>
```

How to get a record's ID, if you ever need to import a new one: Cloudflare
dashboard → DNS → click the record (the URL/API shows the ID), or via API:

```bash
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/dns_records?name=<HOSTNAME>"
```

(Use single quotes around the resource address in the shell, because of
the brackets and quotes in the `for_each` index.)

## Not included in the import plan

- **DigitalOcean Cloud Firewall**: confirmed in the dashboard that it
  doesn't exist on this account ("Looks like you haven't assigned a
  firewall"). The restriction of 80/443 to Cloudflare IPs exists today
  only via ufw on the host. No `digitalocean_firewall` was declared in the
  code — see the comment in `terraform/main.tf`. If you ever want to add
  this layer, that's a decision to create something new, not an import.
- **Email DNS records** (3x MX + 2x TXT — SPF and a DKIM key, all on the
  zone apex): found while listing every record on the zone via the
  Cloudflare API, but unrelated to the sites/VPS this migration covers.
  Not represented in `terraform/locals.tf` and not part of this import
  batch — they're Cloudflare Email Routing configuration, out of scope
  for `jvmello-infra`.
- **Docker Compose, Caddyfile, ufw, secrets, backups**: out of scope for
  Terraform — see `docs/infrastructure-inventory.md`.

## Alternative: `import` blocks (Terraform 1.5+)

Terraform also supports declaring imports as code (an `import {}` block),
processed during `terraform plan`/`apply`, instead of running `terraform
import` manually one by one. This project used individual `terraform
import` commands instead (as above), which made it easy to check
`terraform plan` after each one. For a future import batch, a file like
this would let a single `terraform apply` import everything at once:

```hcl
import {
  to = digitalocean_droplet.vps
  id = "<DROPLET_ID>"
}

import {
  to = cloudflare_dns_record.sites["apex"]
  id = "<ZONE_ID>/<RECORD_ID>"
}
# ... one block per resource
```

Remove the blocks after importing — they don't need to stay in the code.
