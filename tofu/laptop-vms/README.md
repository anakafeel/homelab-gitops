# tofu/laptop-vms

A scale-to-zero k3s agent VM on the laptop (libvirt/KVM), joined to the Pi's
cluster over Tailscale. Nothing to start or stop by hand.

- 2 vCPU, 2 GiB RAM (free pages go back to the laptop), 20 GiB thin disk.
- `lab-autoscale.sh`, run every minute by a systemd user timer, starts the VM
  when a pod that tolerates `homelab/lab` is Pending and shuts it down after
  15 minutes with no workload pods (DaemonSets don't count). It rejoins on its
  own: the Tailscale node is non-ephemeral and the k3s join token never
  expires. While it's off, `lab-node` is NotReady.
- To use it: give a pod `nodeSelector: {homelab/lab: "true"}` and a
  toleration for `homelab/lab=true:NoSchedule`. It runs ~1 min later.
- Tainted `homelab/lab=true:NoSchedule`: only pods that tolerate it run there.
- State: `s3://tofu-state/laptop-vms/terraform.tfstate` in Garage.

## Prerequisites (one time)

- Autoscaler: `install -m755 lab-autoscale.sh ~/.local/bin/ && cp
  systemd/lab-autoscale.* ~/.config/systemd/user/ && systemctl --user
  daemon-reload && systemctl --user enable --now lab-autoscale.timer`.
  Logs: `journalctl --user -u lab-autoscale`.
- libvirt + qemu installed, `libvirtd.socket` enabled, user in group
  `libvirt`, network `default` active. CachyOS needs
  `TimeoutStartSec=120` for libvirtd (its 15s default is too short for the
  first start).
- ufw (on by default in CachyOS) drops the VM's DHCP/DNS on `virbr0`:
  `sudo ufw allow in on virbr0 && sudo ufw route allow in on virbr0 && sudo ufw route allow out on virbr0`.
- Tailnet policy: `tag:lab-node` grants (VM -> Pi tcp:6443, udp:8472;
  Pi -> VM tcp:10250, udp:8472).
- `~/ts-lab-authkey.txt`: Tailscale auth key, tag `tag:lab-node`,
  pre-approved, **not** ephemeral.
- `~/k3s-lab-token.txt`: `ssh anakafeel-pi sudo k3s token create --data-dir
  /mnt/docker-root/k3s --ttl 0 --description lab-node-always-on > ~/k3s-lab-token.txt`.

## Apply (only when this config changes)

```sh
kubectl -n garage port-forward svc/garage 3900:3900 &
export AWS_ENDPOINT_URL_S3=http://localhost:3900
export AWS_ACCESS_KEY_ID=$(tofu -chdir=../bootstrap output -raw tofu_ci_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(tofu -chdir=../bootstrap output -raw tofu_ci_secret_access_key)
export TF_VAR_tailscale_authkey=$(cat ~/ts-lab-authkey.txt)
export TF_VAR_k3s_token=$(cat ~/k3s-lab-token.txt)
tofu init
tofu apply          # ~3 min until `kubectl get node lab-node` is Ready
```

`tofu destroy` removes the VM and its Node for good.
