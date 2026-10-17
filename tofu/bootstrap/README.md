# tofu/bootstrap

Creates the `tofu-state` bucket and the `tofu-ci` access key in Garage.
State: Secret `garage/tfstate-default-bootstrap` (kubernetes backend, Lease lock).

Run from the laptop (kube context `pi`):

```sh
kubectl -n garage port-forward svc/garage 3903:3903 &
export GARAGE_ENDPOINT=http://localhost:3903
export GARAGE_TOKEN=$(kubectl -n garage get secret garage-secrets -o jsonpath='{.data.admin-token}' | base64 -d)
tofu init
tofu plan
tofu apply
```

`tofu output -raw tofu_ci_secret_access_key` prints the CI secret. Pipe it
straight into where it's needed; never paste it anywhere.
