# Both providers also accept configuration via environment variable
# (DIGITALOCEAN_TOKEN and CLOUDFLARE_API_TOKEN), which avoids needing to
# put the token in terraform.tfvars even as a variable reference. See the
# README for the recommended flow.

provider "digitalocean" {
  token = var.do_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
