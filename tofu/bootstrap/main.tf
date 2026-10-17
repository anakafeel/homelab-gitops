# Bootstrap stack: creates the bucket and key that every other stack's state
# lives in. It can't keep its own state in Garage (chicken and egg), so it uses
# the kubernetes backend: state in a Secret, locking via a Lease (real locks,
# unlike Garage). Run by hand, see README.md.
terraform {
  required_version = ">= 1.10.0"

  backend "kubernetes" {
    config_path    = "~/.kube/config"
    config_context = "pi"
    namespace      = "garage"
    secret_suffix  = "bootstrap" # -> Secret tfstate-default-bootstrap
  }

  required_providers {
    garage = {
      source  = "jkossis/garage"
      version = "1.0.5"
    }
  }
}

# Endpoint and token come from GARAGE_ENDPOINT / GARAGE_TOKEN (README.md).
provider "garage" {}

resource "garage_bucket" "tofu_state" {
  global_alias = "tofu-state"
  max_size     = 1073741824 # 1 GiB
}

resource "garage_key" "tofu_ci" {
  name = "tofu-ci"
}

# Read/write on tofu-state only; not owner, so it can't change bucket settings.
resource "garage_bucket_permission" "tofu_ci_state" {
  bucket_id     = garage_bucket.tofu_state.id
  access_key_id = garage_key.tofu_ci.id
  read          = true
  write         = true
  owner         = false
}

output "tofu_ci_access_key_id" {
  value = garage_key.tofu_ci.id
}

output "tofu_ci_secret_access_key" {
  value     = garage_key.tofu_ci.secret_access_key
  sensitive = true
}
