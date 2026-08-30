# jvmello-infra-terraform

Terraform reimplementation of the cloud infrastructure currently described
and operated manually from the [`jvmello-infra`](https://github.com/jvmello/jvmello-infra)
repository. This is a **new** project, treated as a migration to
Infrastructure as Code — it doesn't replace `jvmello-infra`, which remains
responsible for all container orchestration (Docker Compose, Caddy, app
deployment).

**Current state: nothing has been imported and no `apply` has been run.**
This repository describes, in code, the infrastructure that already
exists — the goal is to reach a clean `terraform plan` after importing the
real resources, not to recreate anything from scratch.

## Goal

1. Represent in Terraform the VPS and the DNS records that today sustain
   the sites (`jvmello.dev`, `worldcup.jvmello.dev`,
   `weplay.jvmello.dev`, etc.), currently managed manually through the
   DigitalOcean and Cloudflare dashboards.
2. Import those resources into Terraform's state without recreating
   anything.
3. After the import, manage future changes to those resources via
   Terraform instead of the dashboard.
4. Validate the code via CI on every change.
5. Later evolve toward modules and remote state, if/when it makes sense.

This project is also Terraform study material — that's why the code is
deliberately explicit, without premature abstractions.

## Identified architecture

See the full survey in
[`docs/infrastructure-inventory.md`](docs/infrastructure-inventory.md).
Summary:

```
Cloudflare (DNS + proxy + "Full strict" SSL)
        │
        ▼
DigitalOcean Droplet (1 VPS)
        │ protected by
        └─ ufw on the host (out of Terraform — no DigitalOcean Cloud
                             Firewall on this account, confirmed in the dashboard)
        │
        └─ runs, via Docker Compose (jvmello-infra repo, outside this project):
             Caddy, World Cup Analytics, World Cup Match Ratings, Umami,
             2x Postgres, pipeline/backup jobs, static sites.
```

This Terraform repository only handles the cloud layer: the VPS
(`digitalocean_droplet`) and the DNS records (`cloudflare_dns_record`).
There's no DigitalOcean Cloud Firewall on this account (see
`docs/terraform-design.md`, risks), so no firewall resource is managed
here for now. Everything that's container orchestration, application
configuration, and secrets stays in `jvmello-infra`. The full rationale
for each decision is in
[`docs/terraform-design.md`](docs/terraform-design.md).

## Prerequisites

- Terraform >= 1.9 (see [`terraform/versions.tf`](terraform/versions.tf)).
- DigitalOcean account with access to the existing VPS.
- Cloudflare account with access to the `jvmello.dev` zone.
- API tokens for both accounts (see "Secrets and credentials" below) —
  only needed for real `plan`/`apply`, not for `validate`.

### Installing Terraform

```bash
# Linux/macOS, via the official binary install script:
curl -O https://releases.hashicorp.com/terraform/<VERSION>/terraform_<VERSION>_linux_amd64.zip
unzip terraform_<VERSION>_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Or, if you'd rather manage versions (recommended in the medium term):
# tfenv install latest   (https://github.com/tfutils/tfenv)
```

Confirm with `terraform version`.

## Directory structure

```
.
├── README.md
├── .gitignore
├── .github/workflows/terraform.yml   # CI: fmt -check, init -backend=false, validate
├── docs/
│   ├── infrastructure-inventory.md   # what exists today, and what stays out of Terraform
│   ├── terraform-design.md           # why the code is structured this way
│   └── state.md                      # local state today, how to evolve to remote
└── terraform/
    ├── versions.tf                   # required_version + required_providers
    ├── providers.tf                  # provider configuration
    ├── variables.tf                  # inputs, with description/validation
    ├── locals.tf                     # map of DNS records
    ├── main.tf                       # the actual resources
    ├── outputs.tf
    ├── terraform.tfvars.example      # copy to terraform.tfvars (gitignored)
    ├── imports.md                    # address → real ID → import command (not executed)
    └── .terraform.lock.hcl           # versioned — locks the exact provider versions
```

No `modules/` for now — there's no real repetition that justifies it (see
`docs/terraform-design.md`, "Why no modules yet").

## Basic workflow

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in with the real values (see TODOs)
export DIGITALOCEAN_TOKEN=...                  # or fill in do_token in terraform.tfvars
export CLOUDFLARE_API_TOKEN=...                # or fill in cloudflare_api_token in terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan
```

**Stop at `plan` for now.** Before any `apply`, the existing resources
need to be imported — see the next section.

## How the migration of the current infrastructure works

1. Fill in `terraform.tfvars` with the VPS's real values (name, region,
   size, image — none have a default on purpose, because they aren't
   documented anywhere; confirm them in the DigitalOcean dashboard).
2. Run `terraform init` and `terraform plan` **before** importing, just to
   confirm the code compiles (it will show "to be created" for
   everything — that's expected and creates nothing).
3. Follow [`terraform/imports.md`](terraform/imports.md): one `terraform
   import` per resource, in the suggested order (VPS → DNS records).
4. After each import, run `terraform plan` again. The goal is a plan with
   **no changes** for that resource. If a diff shows up, adjust the code
   (never the real resource) until the plan is clean — see the risks
   documented in `docs/terraform-design.md` (mainly the Droplet's
   `ssh_keys`, `user_data`, and the DNS records' `type`/`content`).
5. Only once every resource has been imported and the plan is clean does
   it make sense to consider an `apply` — and even then, always review
   the plan first.

## Why not run `apply` before importing

A `terraform apply` without the imported state would try to **create new
resources** with the names/addresses declared in the code — at best,
duplicating an already-existing VPS/DNS; at worst, colliding with them and
failing in confusing ways, or worse, causing downtime for production sites
(jvmello.dev, worldcup.jvmello.dev, etc. depend on these DNS records and
this Droplet). Importing first ensures Terraform starts **describing**
what already exists, instead of trying to recreate it.

## How to add new resources in the future

1. Confirm the resource genuinely belongs to the cloud infrastructure
   layer (not application configuration — see the criteria in
   `docs/infrastructure-inventory.md`).
2. Declare the `resource`/`data` in `terraform/main.tf` (or a new file, if
   the project grows enough to justify it), with variables in
   `variables.tf` only where there's configuration that actually varies.
3. Run `terraform plan` and confirm only the new resource shows up as "to
   be created" — nothing existing should change because of an addition.
4. Only after reviewing the plan, run `terraform apply` manually. There's
   no automatic `apply` via CI in this project (and there shouldn't be,
   without deliberate human review).

## Secrets and state precautions

- **Never** put tokens, passwords, or keys in `.tf` files — use
  `terraform.tfvars` (gitignored) or environment variables
  (`DIGITALOCEAN_TOKEN`, `CLOUDFLARE_API_TOKEN`), which is the preferred
  option.
- `terraform.tfstate` can also contain sensitive data in plain text
  (Terraform doesn't encrypt local state) — it's in `.gitignore` and must
  not be versioned or shared informally. See
  [`docs/state.md`](docs/state.md) for how to evolve to a remote backend
  with more security/locking.
- Application secrets (Postgres passwords, Umami's `APP_SECRET`, the
  TheStatsAPI key, etc.) **don't belong in this repository** — they stay
  in `jvmello-infra`'s `.env`, outside any version control.

## CI

`.github/workflows/terraform.yml` runs on pull requests and pushes to
`main` that touch `terraform/`: `terraform fmt -check`, `terraform init
-backend=false`, and `terraform validate`. Only operations that don't
touch real infrastructure and don't require credentials. There's no
`terraform plan` or `apply` in CI — a real `plan` requires real
credentials (the `cloudflare_zone` data source queries the real
Cloudflare API) and doesn't make sense to run without them; automatic
`apply` isn't appropriate for production infrastructure managed by a
single person.

---

## Learning notes

Concepts that show up in this project, for anyone learning Terraform
alongside it.

- **provider** — the plugin that knows how to talk to an external
  service's API (here, `digitalocean` and `cloudflare`). Configured in
  `providers.tf`, versioned in `versions.tf`.
- **resource** — a piece of real infrastructure that Terraform creates/
  updates/destroys (e.g. `digitalocean_droplet.vps`). Declared with
  `resource "<type>" "<local_name>" { ... }`.
- **data source** — a **read-only** query for something that already
  exists and that Terraform doesn't manage (here,
  `data.cloudflare_zone.jvmello_dev` — we read the `zone_id` of the
  `jvmello.dev` zone, without creating or modifying the zone). Declared
  with `data "<type>" "<local_name>" { ... }`.
- **variable** — a parameterizable input for the module (e.g.
  `var.vps_region`). Gets its value via `terraform.tfvars`, an
  environment variable (`TF_VAR_name`), `-var` on the command line, or an
  interactive prompt if nothing is provided and there's no `default`.
- **local** — a value computed/derived within the code itself (e.g.
  `local.dns_records`, the map used in the DNS records' `for_each`). It's
  neither an input nor an output, just a shortcut to avoid repeating
  expressions.
- **output** — a value Terraform exposes after `apply` (e.g.
  `vps_ipv4_address`), useful to quickly check (`terraform output`) or
  for another piece of Terraform code to consume.
- **state** — the file (`terraform.tfstate`) where Terraform keeps track
  of what it believes really exists, mapping each `resource` in the code
  to its real cloud ID. Without state, Terraform wouldn't know whether a
  resource already exists or needs to be created. See `docs/state.md`.
- **terraform init** — downloads the declared providers (and locks their
  versions in `.terraform.lock.hcl`), prepares the working directory.
  First command to run in any new checkout.
- **terraform plan** — computes and shows the difference between the code
  and the current state (what would be created/changed/destroyed),
  **without applying anything**. Always safe to run.
- **terraform apply** — actually applies the changes shown in `plan`
  (creates/changes/destroys real resources). Not run in this project yet.
- **terraform destroy** — the opposite of `apply`: destroys everything
  Terraform manages in the current state. Extremely destructive — never
  run in this project.
- **terraform import** — associates a resource that **already exists** in
  the cloud with a `resource` address already declared in the code,
  without recreating it. This is what lets you adopt existing
  infrastructure with no downtime. See `terraform/imports.md`.
- **drift** — when the real resource changes outside of Terraform
  (someone edits it through the dashboard) and the state becomes
  outdated. `terraform plan` is how you detect drift. See `docs/state.md`.
- **lifecycle** — a meta-argument inside a `resource` to adjust
  Terraform's default behavior for that resource — for example,
  `ignore_changes` (used on `digitalocean_droplet.vps` for `ssh_keys` and
  `user_data`, with the justification in `docs/terraform-design.md`)
  tells Terraform not to propose changes to those fields even if they
  diverge from the code.
- **dependency graph** — Terraform automatically builds a dependency
  graph from the references between resources (e.g.
  `cloudflare_dns_record.sites` references
  `digitalocean_droplet.vps.ipv4_address`, so the Droplet is always
  created/read before the DNS records). That's why the order of blocks in
  a `.tf` file doesn't matter — what matters is who references whom.
