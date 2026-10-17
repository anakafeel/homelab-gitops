# tofu/laptop-vms

A throwaway k3s agent VM on the laptop (libvirt/KVM), joined to the Pi's
cluster over Tailscale. Use it for a lab session, then destroy it.

- 2 vCPU, 2 GiB RAM, 20 GiB thin disk. Never autostarts; powers off 2h after
  every boot. After an auto power-off, run `tofu destroy` (it won't rejoin
  cleanly: the Tailscale node is ephemeral and the k3s token short-lived).
- Tainted `homelab/lab=true:NoSchedule`: only pods that tolerate it run there.
- State: `s3://tofu-state/laptop-vms/terraform.tfstate` in Garage.

## Prerequisites (one time)

- libvirt + qemu installed, `libvirtd.socket` enabled, user in group `libvirt`,
  network `default` active. CachyOS needs `TimeoutStartSec=120` for libvirtd
  (its 15s default is too short for the first start).
- Tailnet policy: `tag:lab-node` grants (VM -> Pi tcp:6443, udp:8472;
  Pi -> VM tcp:10250, udp:8472).

## Lab session

```sh
kubectl -n garage port-forward svc/garage 3900:3900 &
export AWS_ENDPOINT_URL_S3=http://localhost:3900
export AWS_ACCESS_KEY_ID=$(tofu -chdir=../bootstrap output -raw tofu_ci_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(tofu -chdir=../bootstrap output -raw tofu_ci_secret_access_key)
# Ephemeral, pre-approved, tag:lab-node key from the Tailscale admin console:
export TF_VAR_tailscale_authkey=$(cat ~/ts-lab-authkey.txt)
# Short-lived join token; expires on its own:
export TF_VAR_k3s_token=$(ssh anakafeel-pi sudo k3s token create --ttl 24h)
tofu init
tofu apply          # ~3 min until `kubectl get node lab-node` is Ready
tofu destroy        # when done: frees RAM and disk, removes the Node
```
