# Cloudflare DNS and tunnel routing for saimhashmi.xyz, imported from the live
# account. The tunnel itself (pi-web-server) stays out: its credential lives in
# the cloudflared SOPS secret, and an import mistake could replace the tunnel.
terraform {
  required_version = ">= 1.10.0"

  # State in Garage. Endpoint from AWS_ENDPOINT_URL_S3, credentials from
  # AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (the tofu-ci key), see README.md.
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "cloudflare/terraform.tfstate"
    region                      = "garage"
    use_path_style              = true
    use_lockfile                = true # Garage ignores it (no conditional writes); applies are serialized by hand/CI
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
    }
  }
}

# Token from CLOUDFLARE_API_TOKEN (DNS edit on the zone, Tunnel edit on the account).
provider "cloudflare" {}

locals {
  account_id = "b77f663017155fdffc3ab8f10d770387"
  zone_id    = "a947875ab214b6ab190aeb5669d5fac8"
  tunnel_id  = "678b9f8d-6f32-4578-b438-2687f82a2dc1" # pi-web-server
}

resource "cloudflare_dns_record" "apex" {
  zone_id = local.zone_id
  name    = "saimhashmi.xyz"
  type    = "CNAME"
  content = "${local.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic
}

# Remote tunnel config (config_src = cloudflare): this, not the cloudflared
# ConfigMap, decides where the tunnel sends traffic. Traefik routes by Host.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "pi" {
  account_id = local.account_id
  tunnel_id  = local.tunnel_id
  config = {
    ingress = [
      {
        hostname = "saimhashmi.xyz"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

import {
  to = cloudflare_dns_record.apex
  id = "a947875ab214b6ab190aeb5669d5fac8/a4984c212c2cf4a5f5b0d2313a387c6a"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared_config.pi
  id = "b77f663017155fdffc3ab8f10d770387/678b9f8d-6f32-4578-b438-2687f82a2dc1"
}
