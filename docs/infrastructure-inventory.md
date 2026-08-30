# Inventory of the existing infrastructure

> Source: analysis of the [`jvmello-infra`](https://github.com/jvmello/jvmello-infra)
> repository (commit `7766e95`, "Add umami and worldcup-match-ratings hosted configurations"),
> on 2026-08-29. No file in that repository was modified during this analysis.
>
> This document describes what **exists today**, according to what is declared in
> the repository. It doesn't replace a direct check in the DigitalOcean and
> Cloudflare dashboards — several concrete values (IDs, IP, region, VPS size) aren't
> versioned anywhere and need to be confirmed manually before
> any `terraform import` (see [`terraform/imports.md`](../terraform/imports.md)).
>
> **Update after checking the dashboard (2026-08-29):** the `jvmello-infra`
> README suggests a DigitalOcean Cloud Firewall is in use, but checking the
> real account's dashboard, the "Firewalls" page shows "Looks like
> you haven't assigned a firewall" — **there is no Cloud Firewall
> created**. The "Firewalls" section below has been updated to reflect this.
>
> **Update after querying the DigitalOcean and Cloudflare APIs
> (2026-08-29):** the Droplet ID (`581957249`), its public IPv4
> (`68.183.104.27`), the Cloudflare zone ID
> (`9d24076d0c7fb69fe9cf0243002f350d`), and every DNS record's real ID,
> type, and `proxied` status are now known — see
> [`terraform/imports.md`](../terraform/imports.md) for the full list. Two
> details turned out to differ from what this document originally assumed:
> `www.jvmello.dev` is a **CNAME** (not an A record), and
> `api.worldcup.jvmello.dev` has **`proxied = false`**. Also,
> `worldcup-match-ratings.jvmello.dev` **already exists** — the
> `jvmello-infra` README's claim that it hadn't been created yet was
> outdated. The "DNS / Domains" section below reflects all of this.

## Architecture summary

A single server (VPS) runs all the services via Docker Compose. Caddy handles
reverse proxy/TLS for every host. DNS and CDN/proxy live on Cloudflare.
There's no load balancer, managed database, managed storage, or
Kubernetes — it's a single low-cost VPS (the README mentions a "2 CPU/4GB VPS").

```
Internet
   │
   ▼
Cloudflare (DNS + orange-cloud proxy + "Full strict" SSL)
   │  (HTTPS, only from Cloudflare's IP range — see firewall)
   ▼
DigitalOcean Droplet (single VPS)
   │
   ├─ ufw (host)  → allows 22 from any origin; 80/443 only from Cloudflare IPs
   │    (no DigitalOcean Cloud Firewall — confirmed absent in the dashboard)
   │
   └─ Docker Compose (docker-compose.yml)
        ├─ caddy              (reverse proxy + automatic TLS via Let's Encrypt)
        ├─ worldcup-web       (FastAPI: SPA + API for World Cup Analytics)
        ├─ worldcup-pipeline  (on-demand/cron job — "jobs" profile)
        ├─ worldcup-db        (Postgres 16 — gold/silver/bronze schemas + match_ratings)
        ├─ worldcup-backup    (daily local pg_dump)
        ├─ match-ratings-api  (FastAPI: only /api/* for World Cup Match Ratings)
        ├─ match-ratings-import (on-demand/cron job — "jobs" profile)
        ├─ umami              (self-hosted analytics)
        ├─ umami-db           (Postgres 16, isolated)
        └─ static sites served via bind mount (no dedicated container):
             ├─ jvmello-dev-dist (Astro portfolio)
             ├─ weplay-dist (Vite SPA)
             └─ worldcup-match-ratings webapp (plain HTML/CSS/JS)
```

## Detailed inventory

### Cloud providers

| Provider | Identified use | Evidence |
|---|---|---|
| **DigitalOcean** | Hosts the VPS (Droplet). The README mentions a "Cloud Firewall", but the real dashboard has none configured — see "Firewalls" section | README: "DigitalOcean Cloud Firewall", "DigitalOcean Spaces" mentioned as future external storage |
| **Cloudflare** | DNS, proxy/CDN, edge termination, "Full (strict)" SSL | README, "Cloudflare" section; IP ranges hardcoded in `scripts/setup-firewall.sh` |

No other cloud provider (AWS, GCP, Azure, Hetzner, etc.) is mentioned in
any file in the repository.

### Servers / VMs

- **1 DigitalOcean Droplet** (single VPS), informally described as a "2
  CPU/4GB VPS" (README, Umami section). This is where the entire Docker
  Compose stack runs. Real ID: `581957249`; public IPv4: `68.183.104.27`
  (both confirmed via `doctl`/dashboard on 2026-08-29 — see
  `terraform/imports.md`).
- **TODO — not identifiable from the repository:** region, size
  slug, image slug/ID, whether IPv6 is enabled,
  VPC, whether `user_data`/cloud-init was used at creation, which SSH
  keys were authorized (tags and the region/size/image slugs have since
  been filled into `terraform/terraform.tfvars` by checking the
  dashboard). None of this data is versioned in `jvmello-infra` — it was
  configured manually in the DigitalOcean dashboard (or via `doctl`)
  outside that repository.

### Regions

- **TODO** — the Droplet's region isn't mentioned anywhere in the repository.

### Networks

- **Docker networks** (container-level, defined in `docker-compose.yml`):
  `edge` (Caddy ↔ apps), `worldcup-data` (internal, no egress — World Cup
  Postgres), `umami-data` (internal, no egress — Umami Postgres). This is
  container orchestration, not a cloud resource — **out of scope for
  Terraform**.
- **DigitalOcean VPC:** not mentioned — likely the account/region's default
  VPC. **TODO** if it ever needs to be referenced explicitly.

### Firewalls

Two complementary, distinct layers (README, "Host firewall" section):

1. **ufw on the host** (`scripts/setup-firewall.sh`, run manually and only
   once on the VPS): default policy denies inbound/allows outbound; allows
   22/tcp (SSH) from any origin; allows 80/tcp and 443/tcp **only** to the
   Cloudflare IP ranges (list embedded in the script, copied from
   <https://www.cloudflare.com/ips/> on 2026-07-08). The script itself and
   the README warn that ports published by Docker (`ports:` in the
   compose file) go through the `DOCKER` chain and **can bypass ufw** —
   that's an operating-system-level configuration, not a cloud resource.
   **Out of scope for Terraform**, though the README itself already
   acknowledges it isn't sufficient on its own.
2. **DigitalOcean Cloud Firewall** — the `jvmello-infra` README mentions
   this layer as the one that "actually" guarantees the 80/443 restriction
   (since it filters traffic before it reaches the VPS, including traffic
   that would come in via Docker's NAT). **A direct check on the
   DigitalOcean dashboard (2026-08-29) confirmed it doesn't exist** — the
   "Firewalls" page shows "Looks like you haven't assigned a firewall". In
   other words: today the 80/443-to-Cloudflare-IPs restriction exists
   **only** in the host's ufw, without the network layer the README itself
   recommends as the one that "actually" protects (ufw alone can be
   bypassed by ports published via Docker — see the script itself).
   **There's nothing to import here** — if this firewall is ever created,
   it will be a new resource, not a migration.

### IPs

- **VPS's public IPv4: `68.183.104.27`** (confirmed via `doctl`/dashboard
  on 2026-08-29). Used implicitly by every DNS record that points to the
  server, but **not written anywhere in the `jvmello-infra` repository**
  (not in `.env.example`, not in scripts).
- No mention of IPv6 being enabled on the Droplet.
- Cloudflare's IP ranges (IPv4 and IPv6) **are** documented, in
  `scripts/setup-firewall.sh` (copied from cloudflare.com/ips on 2026-07-08).

### DNS / Domains

Root domain: `jvmello.dev` (registrar not identified — **TODO** — DNS
hosted on Cloudflare, zone ID `9d24076d0c7fb69fe9cf0243002f350d`, account
ID `9bde415bb0cfad72fc304c90067762e7`, both confirmed via the Cloudflare
API on 2026-08-29). Hosts mentioned in the README's "Cloudflare" section,
confirmed against the real zone (type, `proxied`, and record ID for each
one are in [`terraform/imports.md`](../terraform/imports.md)):

| Host | Serves | Real type | Proxied | Status |
|---|---|---|---|---|
| `jvmello.dev` | Static portfolio (Caddy → `/srv/jvmello-dev`) | A | Yes | Existing |
| `www.jvmello.dev` | Same as above (redirects/serves the same content) | **CNAME** → `jvmello.dev` | Yes | Existing |
| `worldcup.jvmello.dev` | SPA + API for World Cup Analytics (`worldcup-web:8000`) | A | Yes | Existing |
| `api.worldcup.jvmello.dev` | Only `/api/*` for World Cup Analytics | A | **No** | Existing |
| `analytics.jvmello.dev` | Umami (`umami:3000`) | A | Yes | Existing |
| `weplay.jvmello.dev` | WePlay Marketing SPA (Caddy → `/srv/weplay`) | A | Yes | Existing |
| `worldcup-match-ratings.jvmello.dev` | Match Ratings dashboard + API | A | Yes | **Existing** — the `jvmello-infra` README claims this record "doesn't exist yet on Cloudflare", but querying the real zone shows it does. That README note is outdated. |

The original assumption in this document (before checking the API) was
that every record was a plain A record pointing at the Droplet's IP, all
proxied. Two records break that pattern: `www` is a CNAME, and
`api.worldcup` isn't proxied — both corrected here and in the Terraform
code (`terraform/locals.tf`) after the discovery.

The zone also has **3 MX records and 2 TXT records** (SPF + a DKIM key)
on the apex, for Cloudflare Email Routing — unrelated to the sites/VPS
this migration covers, not represented in Terraform (see
`terraform/imports.md`, "Not included in the import plan").

Cloudflare zone SSL/TLS mode: **Full (strict)** (requires a valid origin
certificate — handled by Caddy via Let's Encrypt). This is a Cloudflare
zone-level setting, manual today.

### Storage / Buckets

- **No bucket provisioned today.** The README mentions, as future work not
  yet implemented, syncing `./backups` to external storage (mentions
  DigitalOcean Spaces or Backblaze B2 as options, without deciding
  which). **There's no real resource to inventory here yet** — it
  shouldn't go into Terraform at this stage (that would mean inventing a
  nonexistent resource).

### Databases

Two Postgres 16 instances (`postgres:16-alpine`), each as a **Docker
container**, not as a DigitalOcean managed service:

- `worldcup-db`: `gold`/`silver`/`bronze` schemas (World Cup Analytics) and
  `match_ratings` (World Cup Match Ratings) in the same `worldcup`
  database. Isolated on the internal `worldcup-data` network (no egress
  to Caddy/internet).
- `umami-db`: `umami` database, isolated on the internal `umami-data`
  network.

Since these are containers defined in `docker-compose.yml` (image, volume,
environment variables), **this is application deployment, not cloud
infrastructure** — out of scope for Terraform. If they ever migrate to a
managed DigitalOcean Postgres, that would then be a Terraform resource.

### Volumes

Named Docker volumes (`docker-compose.yml`): `caddy_data`, `caddy_config`,
`worldcup_db_data`, `umami_db_data`. Container/host level, out of scope
for Terraform.

### Containers / Docker

The whole orchestration lives in `docker-compose.yml` in `jvmello-infra`
itself: Caddy, `worldcup-web`, `worldcup-pipeline` (job), `worldcup-db`,
`worldcup-backup`, `match-ratings-api`, `match-ratings-import` (job), `umami`,
`umami-db`. The README is explicit: *"This repo doesn't contain any app's
code"* — the infra repository itself already deliberately separates
container orchestration from application code. **Stays out of Terraform**,
managed by the existing `docker-compose.yml`.

### Reverse proxy

Caddy (`caddy:2-alpine`), configured via `caddy/Caddyfile`: terminates TLS,
applies security headers (HSTS, X-Frame-Options, etc.), and routes by host
to each service/static file. **Application configuration**, out of scope
for Terraform.

### Certificates

Origin TLS issued and automatically renewed by Caddy (Let's
Encrypt/ZeroSSL) — there's no manually managed certificate nor one managed
via Terraform. Out of scope (it's ephemeral and self-managed by Caddy
itself).

### Secrets / configuration

Everything lives in `.env` (never versioned — only `.env.example` exists
with placeholders): World Cup Postgres passwords, public API restricted
roles, Umami credentials (`APP_SECRET`), the TheStatsAPI key, metrics
dashboard credentials. **Must never appear in Terraform code** — they stay
outside this project.

### External services

- **TheStatsAPI** (`api.thestatsapi.com`): third-party football data API,
  consumed by the `worldcup-pipeline` job via an API key
  (`THESTATSAPI_API_KEY`). Referenced only as an external dependency — no
  cloud resource to provision here.
- **Cloudflare**: besides DNS, acts as the proxy/CDN/security edge in
  front of the VPS.

### Managed resources (managed services)

None identified. There's no Managed Database, Managed Kubernetes, managed
Load Balancer, Spaces (object storage), or dedicated DigitalOcean CDN in
use — everything runs inside the single Droplet via Docker Compose.

### Dependencies between resources

- Every DNS record (Cloudflare) depends on the **VPS's public IPv4**
  (DigitalOcean) to point correctly.
- The **"Full (strict)" SSL** mode on the Cloudflare zone depends on
  Caddy, inside the Droplet, always presenting a valid origin
  certificate — a logical dependency between the edge configuration
  (Cloudflare) and the application (Caddy), which isn't modelable as a
  Terraform resource dependency.
- The `worldcup-match-ratings.jvmello.dev` host has routing ready in the
  Caddyfile and its DNS record already exists (see above) — no pending
  dependency here, contrary to what the `jvmello-infra` README says.

## What should be managed by Terraform (at this stage)

- DigitalOcean Droplet (the VPS) — **import**.
- Cloudflare DNS records for the already-existing hosts (`jvmello.dev`,
  `www`, `worldcup`, `api.worldcup`, `analytics`, `weplay`,
  `worldcup-match-ratings`) — **import**.
- Reference (read-only data source) to the `jvmello.dev` Cloudflare zone —
  not created nor imported, only queried.

## What stays out of Terraform (and why)

| Item | Why it stays out |
|---|---|
| `docker-compose.yml` (containers, Docker networks, volumes) | Application deployment, already managed by `jvmello-infra` itself; not a cloud resource. |
| `caddy/Caddyfile` | Application configuration (reverse proxy). |
| `scripts/setup-firewall.sh` (ufw) | Host-level operating-system configuration, not a cloud resource. |
| DigitalOcean Cloud Firewall | **Doesn't exist** — confirmed in the dashboard. No resource to represent; see "Firewalls" section above. |
| `.env` / secrets | Must never be in versioned code, Terraform included. |
| `deploy-portfolio.sh`, `deploy-weplay.sh` | Application deployment (build + rsync + reload). |
| Postgres databases (`worldcup-db`, `umami-db`) | Run as Docker containers, not a managed service — nothing to provision via a cloud provider. |
| Backups (local `pg_dump`) | Internal application/compose mechanism; the external storage destination doesn't even exist yet (it's future TODO for `jvmello-infra` itself). |
| TLS certificates | Issued/renewed automatically by Caddy; ephemeral, not sensibly manageable via Terraform here. |
| Email DNS records (MX + TXT/SPF/DKIM) | Cloudflare Email Routing configuration, unrelated to the sites/VPS this migration covers. |
| Cloudflare zone "Full (strict)" SSL mode | Zone-level configuration, manual today; not included at this first stage to keep the scope minimal (see `docs/terraform-design.md`). |

## Information that couldn't be discovered from the repository

Resolved by checking the dashboards/APIs directly (2026-08-29), listed
here for context — none of this was ever written down anywhere in
`jvmello-infra` itself: Droplet ID, region, size, image, public IPv4,
tags (now in `terraform/terraform.tfvars`); Cloudflare zone and account
ID; and the type/`proxied`/ID of every DNS record (now in
`terraform/imports.md`).

Still unknown, and not discoverable from either the repository or the two
APIs queried so far:

- Whether the Droplet was created with `user_data` (cloud-init) — the
  DigitalOcean API doesn't return this for an existing Droplet regardless.
- Which SSH keys are authorized on the Droplet.
- Whether IPv6 is enabled on the Droplet, and its VPC.
- Registrar of the `jvmello.dev` domain (this lives with the registrar,
  not with Cloudflare, which only hosts the DNS).
- Whether there's any additional resource created manually in the
  DigitalOcean or Cloudflare dashboard that left no trace in either the
  repository or the API calls made so far (automatic DO backups,
  snapshots, account projects/organization, custom Page Rules/WAF on
  Cloudflare, etc.).
