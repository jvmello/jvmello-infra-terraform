# Import plan (NOT EXECUTED)

This file documents, for each resource that already exists, the
corresponding Terraform address and the suggested command to import it.
**None of these commands have been run.** All the real IDs below have
been confirmed (Droplet via `doctl`/dashboard on 2026-08-29, DNS records
via the Cloudflare API on 2026-08-29) — run the commands manually, one at
a time, only after:

1. Filling in `terraform.tfvars` with the real values (copy from
   `terraform.tfvars.example`) — already done for the VPS fields at the
   time of writing.
2. Reading the risks in `docs/terraform-design.md` ("Migration risks"
   section) — especially `ssh_keys`, `user_data`, and the DNS records'
   type/proxied status (two of the records below turned out to differ
   from the original assumption — see the notes under each table).
3. Running `terraform init -backend=false` and `terraform plan` **before**
   the import just to confirm the code compiles (it will show "to be
   created" for everything, which is expected — this doesn't create
   anything, it only validates the code).

After each `terraform import`, run `terraform plan` again: ideally it
shows no change for the resource you just imported. If it does, adjust
the code (never the real resource) until the plan is clean, or document
the reason for the residual diff.

## 1. VPS (Droplet)

| Field | Value |
|---|---|
| Terraform resource address | `digitalocean_droplet.vps` |
| Type | `digitalocean_droplet` |
| Real resource | The DigitalOcean Droplet hosting `jvmello-infra`'s `docker-compose.yml` |
| ID | `581957249` |

```bash
terraform import digitalocean_droplet.vps 581957249
```

## 2. DNS records (Cloudflare)

Zone: `jvmello.dev`, zone ID `9d24076d0c7fb69fe9cf0243002f350d` (confirmed
via the Cloudflare API — this is what `data.cloudflare_zone.jvmello_dev`
resolves at plan time, no need to hardcode it anywhere).

All records use the same resource type, with `for_each`; each address
includes the key from the `local.dns_records` map (`terraform/locals.tf`)
in brackets.

| Terraform resource address | Real host | Real type | Real `proxied` | Record ID |
|---|---|---|---|---|
| `cloudflare_dns_record.sites["apex"]` | `jvmello.dev` | A | true | `3c1833e101872a36efda13df007588a1` |
| `cloudflare_dns_record.sites["www"]` | `www.jvmello.dev` | **CNAME** (→ `jvmello.dev`) | true | `cefe83f3a9d8cf3c7ddcf17c4d88bb0f` |
| `cloudflare_dns_record.sites["worldcup"]` | `worldcup.jvmello.dev` | A | true | `2c8e840a426fb859500faa828b666dfb` |
| `cloudflare_dns_record.sites["worldcup_api"]` | `api.worldcup.jvmello.dev` | A | **false** | `29b927fc30b3eb4f410e2d94407d085c` |
| `cloudflare_dns_record.sites["analytics"]` | `analytics.jvmello.dev` | A | true | `fb1e9a4096c00cda1bdafa0253a49154` |
| `cloudflare_dns_record.sites["weplay"]` | `weplay.jvmello.dev` | A | true | `eec0936d176fdead150b50209cdfc59a` |
| `cloudflare_dns_record.sites["worldcup_match_ratings"]` | `worldcup-match-ratings.jvmello.dev` | A | true | `368ce188b89cf7c4162ef8f0c75eb700` |

**Bold** values are the two spots where reality differed from the
inventory's original assumption (both already fixed in `terraform/locals.tf`
and `terraform/main.tf` before this table was written):

- `www` is a **CNAME to the apex** (`jvmello.dev`), not an A record
  pointing at the Droplet's IP.
- `worldcup_api` has **`proxied = false`** in reality — every other host
  here is proxied.
- `worldcup_match_ratings` **already exists** — the `jvmello-infra`
  README said this record hadn't been created yet, but the API confirms
  it has (A, proxied), so it's included in the import batch and in
  `terraform/locals.tf`'s `for_each`, unlike what
  `docs/terraform-design.md` originally assumed.

All records currently share Droplet IP `68.183.104.27` as content (except
`www`, per the CNAME above) — that's also the `PublicIPv4` you'd see for
Droplet `581957249` via `doctl`.

Import commands (`<zone_id>/<record_id>` format for the
`cloudflare/cloudflare` v5 provider):

```bash
terraform import 'cloudflare_dns_record.sites["apex"]' 9d24076d0c7fb69fe9cf0243002f350d/3c1833e101872a36efda13df007588a1
terraform import 'cloudflare_dns_record.sites["www"]' 9d24076d0c7fb69fe9cf0243002f350d/cefe83f3a9d8cf3c7ddcf17c4d88bb0f
terraform import 'cloudflare_dns_record.sites["worldcup"]' 9d24076d0c7fb69fe9cf0243002f350d/2c8e840a426fb859500faa828b666dfb
terraform import 'cloudflare_dns_record.sites["worldcup_api"]' 9d24076d0c7fb69fe9cf0243002f350d/29b927fc30b3eb4f410e2d94407d085c
terraform import 'cloudflare_dns_record.sites["analytics"]' 9d24076d0c7fb69fe9cf0243002f350d/fb1e9a4096c00cda1bdafa0253a49154
terraform import 'cloudflare_dns_record.sites["weplay"]' 9d24076d0c7fb69fe9cf0243002f350d/eec0936d176fdead150b50209cdfc59a
terraform import 'cloudflare_dns_record.sites["worldcup_match_ratings"]' 9d24076d0c7fb69fe9cf0243002f350d/368ce188b89cf7c4162ef8f0c75eb700
```

(Use single quotes around the address in the shell, because of the
brackets and quotes in the `for_each` index.)

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
import` manually one by one. **These were not added to this project** —
even with the real IDs now known, running the imports one command at a
time (as above) makes it easy to check `terraform plan` after each one
individually. If you'd rather do it in one shot, you can create a file
like `terraform/imports_generated.tf` (suggested name, not created here)
with a block per resource:

```hcl
import {
  to = digitalocean_droplet.vps
  id = "581957249"
}

import {
  to = cloudflare_dns_record.sites["apex"]
  id = "9d24076d0c7fb69fe9cf0243002f350d/3c1833e101872a36efda13df007588a1"
}
# ... one block per remaining DNS record, same IDs as the table above
```

With `import` blocks, a single `terraform apply` imports everything at
once (you'd still need to run `apply`, which this project deliberately
doesn't do at this stage). If you go this route, remove the blocks after
importing — they don't need to stay in the code.
