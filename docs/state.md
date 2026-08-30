# State — today and future evolution

## Today: local state

This project uses **local state** (`terraform/terraform.tfstate`), the
Terraform default when no `backend` is configured in `versions.tf`.
Adequate for learning and for this first stage (one person, one machine,
no CI applying changes).

`.gitignore` already prevents `terraform.tfstate*` from being versioned.
**This is deliberate and important:** the state can contain sensitive
values in plain text (for example, attributes the provider marks as
sensitive can still appear in the state file, even though they're hidden
from the CLI output) — never commit the state.

While the state is local:

- Only run `terraform plan`/`apply` from the same machine that holds the
  current `terraform.tfstate` — there's no synchronization between
  machines.
- Manually back up the state file before risky operations
  (`cp terraform.tfstate terraform.tfstate.backup.$(date +%s)`), in
  addition to the automatic `.tfstate.backup` Terraform already keeps.
- There's no **locking**: if you accidentally run two `terraform apply`
  commands at the same time (two terminal tabs, for example), both will
  try to write to the same state file and can corrupt it. With local
  state, the only protection is discipline (don't run in parallel).

## Drift

"Drift" is when the real resource changes outside of Terraform (someone
edits something through the DigitalOcean/Cloudflare dashboard, or a script
hits the API directly) and the state becomes outdated relative to reality.
In this infrastructure that's a concrete risk: today **everything** is
managed manually through the dashboards, so it's easy to keep making
manual changes after importing only part of it into Terraform, causing
immediate drift.

To detect drift without applying anything:

```bash
terraform plan
```

If `plan` shows changes you didn't make in this code, it's a sign that
something changed outside Terraform (or that the import didn't correctly
capture the real state — see the risks in `docs/terraform-design.md`).

## Future evolution: remote backend

Once it makes sense (more than one person/machine operating this code, or
`apply` running via CI), migrate to a remote backend. Two options
consistent with the providers already used in this project:

### Option 1 — DigitalOcean Spaces (S3-compatible)

Terraform's `s3` backend works with any S3-API-compatible storage,
including DigitalOcean Spaces. Example (not applied in this project — just
a reference for when you migrate):

```hcl
terraform {
  backend "s3" {
    bucket                      = "YOUR-SPACE-HERE"          # TODO: Space name
    key                         = "jvmello-infra/terraform.tfstate"
    region                      = "YOUR-REGION-HERE"          # TODO: Space's region
    endpoints                   = { s3 = "https://YOUR-REGION-HERE.digitaloceanspaces.com" }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }
}
```

Pros: same provider (DigitalOcean) already in use, low cost, easy to
justify since `jvmello-infra` itself considers using Spaces for backups.
Cons: **no native locking** — Terraform's `s3` backend supports locking
via DynamoDB (AWS) but there's no direct equivalent on Spaces; locking
would rely on discipline/manual coordination, unless you configure
locking through another mechanism.

### Option 2 — Terraform Cloud / HCP Terraform (free tier)

```hcl
terraform {
  cloud {
    organization = "YOUR-ORG-HERE"   # TODO
    workspaces {
      name = "jvmello-infra"
    }
  }
}
```

Pros: native locking, run history, VCS integration (can run `plan`
automatically on PRs), free tier covers personal use. Cons: state lives on
a third-party service (albeit encrypted), workflow changes a bit (runs can
happen remotely).

### State security, on any backend

- The state can contain sensitive data (even attributes marked
  `sensitive = true` in the code get written in plain text in the state
  file — `sensitive` only hides it from the CLI output, not from the
  file). Treat the state's backend with the same care as credentials:
  restricted access, and encryption at rest whenever the backend offers it
  (Spaces and Terraform Cloud do).
- Never version the state in git, local or remote.
- When migrating from a local backend to a remote one, use
  `terraform init -migrate-state` (interactive, asks for confirmation) —
  don't copy the file manually.
