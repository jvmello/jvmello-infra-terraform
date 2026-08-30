# Terraform strategy

Based exclusively on the inventory in
[`infrastructure-inventory.md`](infrastructure-inventory.md). Nothing here
was invented: wherever a concrete value doesn't exist in the
`jvmello-infra` repository, it's left as a variable with no default (or
with an explicit TODO), never as a plausible example value.

## Providers chosen

| Provider | Reason |
|---|---|
| `digitalocean/digitalocean` (`~> 2.100`) | Only identified cloud provider — hosts the Droplet. |
| `cloudflare/cloudflare` (`~> 5.24`) | DNS and proxy/CDN for the `jvmello.dev` zone. **Note:** v5 reworked several resources compared to v4 (e.g. `cloudflare_record` became `cloudflare_dns_record`, with a different schema). This project starts directly on v5. |

Versions pinned with `~>` (pessimistic constraint) in the `.tf` files and
locked exactly by `.terraform.lock.hcl`, which **is versioned** (unlike
`.terraform/`).

## Split between Terraform and application configuration

Follows directly from the "What stays out of Terraform" table in the
inventory: Terraform here only handles **cloud resources** (the VPS and
the DNS records — there's no DigitalOcean Cloud Firewall on this account,
see "Risks" below). Everything that's container orchestration, Caddy
configuration, deploy scripts, host ufw, and secrets keeps living in
`jvmello-infra` exactly as it is — this new repository **doesn't replace**
`jvmello-infra`, it complements it.

Practical reason: `jvmello-infra` itself already documents this
separation ("this repo doesn't contain any app's code") — we're just
extending the same principle one layer up, separating "cloud
infrastructure" from "orchestration on the VPS".

## Resources that will be imported (in the future)

See full details, with address and suggested command, in
[`terraform/imports.md`](../terraform/imports.md). Summary:

1. `digitalocean_droplet.vps` — the existing VPS (real ID `581957249`).
2. `cloudflare_dns_record.sites["..."]` (7 records, via `for_each`) —
   `jvmello.dev`, `www.jvmello.dev`, `worldcup.jvmello.dev`,
   `api.worldcup.jvmello.dev`, `analytics.jvmello.dev`, `weplay.jvmello.dev`,
   `worldcup-match-ratings.jvmello.dev` (this last one turned out to
   already exist — see the note below).

`data.cloudflare_zone.jvmello_dev` **is not imported** — it's a data
source, read-only; it resolves the real `zone_id` from the domain name,
without ever creating or modifying the zone.

## Resources that will not be managed (for now)

- **DigitalOcean Cloud Firewall**: a direct dashboard check (2026-08-29)
  confirmed there's no cloud firewall created on this account
  ("Looks like you haven't assigned a firewall"). This document's initial
  assumption, based only on the text of the `jvmello-infra` README, was
  incorrect — corrected after checking the real dashboard. No
  `digitalocean_firewall` resource was declared in the code. See
  "Migration risks" below.
- Cloudflare zone "Full (strict)" SSL mode and any other zone
  configuration (Page Rules, WAF, etc.): kept manual for now, to avoid
  expanding the scope of this first migration beyond what the inventory
  confirms exists and is simple to verify.
- Everything listed in the inventory's "out of Terraform" table (Docker
  Compose, Caddyfile, ufw, secrets, backups, certificates).

## Dependencies modeled in the code

```
digitalocean_droplet.vps
        │ (ipv4_address)
        ▼
cloudflare_dns_record.sites[*]  ← data.cloudflare_zone.jvmello_dev (zone_id)
```

Terraform infers these dependencies automatically from the references
between resources (`digitalocean_droplet.vps.ipv4_address`, `.id`) — no
explicit `depends_on` is needed in either case.

## Future state strategy

See [`docs/state.md`](state.md) in detail. Summary: at this stage, **local**
state (`terraform.tfstate`, outside git). Future migration recommended to
a remote backend (`digitalocean_spaces` or Terraform Cloud) once more than
one person/machine operates this code, or once you want to run `apply`
from CI.

## Migration risks

Concrete risks, specific to this infrastructure — not generic ones:

1. **The Droplet's `ssh_keys` and `user_data` force recreation if they
   diverge from reality.** Per the provider's documentation: changing
   `user_data` always forces a new resource; changing `ssh_keys` "prompts
   you to destroy and recreate the Droplet". The DigitalOcean API also
   doesn't return the original `user_data` when querying an existing
   Droplet — there's no way to "discover" the right value after the fact.
   **Mitigation adopted:** `ssh_keys` and `user_data` go into
   `digitalocean_droplet.vps`'s `lifecycle.ignore_changes` (see the
   comment in `main.tf` itself). This isn't a "generic ignore_changes to
   hide diffs" — it's the only documented way to prevent Terraform from
   proposing to recreate a production VPS because of a field the provider
   itself can't manage incrementally after creation.
2. **`image` may show a diff after the import.** DigitalOcean sometimes
   returns an existing Droplet's `image` as a numeric ID even if it was
   created from a slug (e.g. `ubuntu-22-04-x64`). If this happens, the
   first post-import `terraform plan` may show a change in this field.
   We did **not** preemptively add `ignore_changes` for `image` —
   confirm first whether the diff actually shows up; if it does and it's
   exactly this format mismatch (slug vs. ID, with no destroy/recreate
   proposal), then consider adding `image` to `ignore_changes`.
3. **DNS records' type/value needs to be exact — this actually happened.**
   If a Cloudflare record's real type is `CNAME` and the code declares
   `A` (or vice versa), the provider treats that as a type change — it
   normally forces the DNS record to be recreated. Since DNS has
   propagation and caching, an unnecessary recreation can cause temporary
   instability. This risk wasn't hypothetical here: querying the real
   zone via the Cloudflare API (2026-08-29) showed `www.jvmello.dev` is a
   **CNAME** to the apex, not an A record as this document originally
   assumed, and `api.worldcup.jvmello.dev` has **`proxied = false`**,
   unlike every other host. Both are already fixed in
   `terraform/locals.tf` and `terraform/main.tf` — this item stays here as
   a reminder that "confirm before importing" isn't optional caution, it's
   how these two mismatches were actually caught before any `apply`.
4. **TTL on proxied records.** Records with `proxied = true` on
   Cloudflare require `ttl = 1` ("automatic"). We use `ttl = 1` for every
   record in the `for_each` regardless of `proxied` status — the
   unproxied `api.worldcup` record was also confirmed to already have
   `ttl = 1` in reality, so this didn't turn out to be a mismatch, but
   double-check if you add a record with a different TTL in the future.
5. **There is no DigitalOcean Cloud Firewall on this account.** Confirmed
   directly in the dashboard (2026-08-29): the "Firewalls" page shows
   "Looks like you haven't assigned a firewall". The 80/443-to-Cloudflare-IPs
   restriction exists today **only** via ufw on the host — which, per
   `jvmello-infra`'s own README, can be bypassed by ports published via
   Docker. No `digitalocean_firewall` was declared in the code; creating
   one now would mean provisioning something new, not importing something
   that exists — a deliberate decision, out of scope for this migration
   (see the comment in `terraform/main.tf`).
6. **API token with broad privileges.** Both the DigitalOcean and
   Cloudflare tokens, when used in a real `terraform plan`/`apply`, have
   read/write access to the entire account (unless you create tokens with
   restricted scope). No write command has been run during this
   migration, but when setting up credentials for future use, prefer
   tokens with the smallest possible scope (e.g. a Cloudflare token
   restricted to the `jvmello.dev` zone; a DigitalOcean token with
   restricted scope, if the account supports it).

## Why no modules yet

There are only two providers and two "families" of resources (Droplet and
DNS records), with no real repetition beyond the DNS records themselves —
which already use `for_each` inside a single resource, with no need for a
module. A module would make sense if, for example, this code needed to
describe multiple VPSes following the same pattern, or were reused by
another repository. Neither is the case today.
