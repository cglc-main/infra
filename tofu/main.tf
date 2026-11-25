# Hetzner Cloud and Cloudflare: what exists outside the cluster. Docs: https://github.com/cglc-main/docs
#   nodes.tf     the three servers (read, never created or destroyed here), their network, rDNS, cloud-init
#   network.tf   private network, firewall, placement group
#   dns.tf       bulbashenko.com
#   redirects.tf bulbashenko.dev and cglc.eu -> bulbashenko.com
# Run: sops exec-env secrets.sops.json 'tofu plan' (CI: .github/workflows/tofu.yml).
terraform {
  required_version = ">= 1.10"
  required_providers {
    hcloud     = { source = "hetznercloud/hcloud", version = "1.70.2" }
    cloudflare = { source = "cloudflare/cloudflare", version = "5.29.0" }
  }

  # State in Backblaze B2 (S3 API), encrypted by OpenTofu before it leaves the machine.
  backend "s3" {
    bucket                      = "cglc-bucket"
    key                         = "tofu/terraform.tfstate"
    region                      = "eu-central-003"
    endpoints                   = { s3 = "https://s3.eu-central-003.backblazeb2.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}
