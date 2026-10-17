# tofu/cloudflare

DNS record and remote tunnel ingress for saimhashmi.xyz. State:
`s3://tofu-state/cloudflare/terraform.tfstate` in Garage.

Garage has no state locking: only one `tofu apply` at a time.

```sh
kubectl -n garage port-forward svc/garage 3900:3900 &
export AWS_ENDPOINT_URL_S3=http://localhost:3900
export AWS_ACCESS_KEY_ID=$(tofu -chdir=../bootstrap output -raw tofu_ci_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(tofu -chdir=../bootstrap output -raw tofu_ci_secret_access_key)
export CLOUDFLARE_API_TOKEN=$(cat ~/cf-token.txt)
tofu init
tofu plan
```
