#!/usr/bin/env bash
# Scale-to-zero for lab-node, the same two decisions Cluster Autoscaler makes:
# - VM off and a pod that tolerates homelab/lab is unscheduled -> start it.
# - VM on and no workload pods on lab-node for IDLE_MIN minutes -> shut it down.
# Run every minute by lab-autoscale.timer (systemd user unit). Does nothing when
# the cluster is unreachable, so it never acts on stale data.
set -euo pipefail

VM=lab-node
IDLE_MIN=${IDLE_MIN:-15}
STAMP=${XDG_STATE_HOME:-$HOME/.local/state}/lab-autoscale.busy
KUBECTL=(kubectl --context pi --request-timeout=10s)
VIRSH=(virsh -c qemu:///system)

pods=$("${KUBECTL[@]}" get pods -A -o json) || { echo "cluster unreachable, skipping"; exit 0; }
state=$("${VIRSH[@]}" domstate "$VM")
mkdir -p "$(dirname "$STAMP")"

# Unscheduled pods that tolerate the lab taint.
pending=$(jq '[.items[] | select(.status.phase == "Pending" and .spec.nodeName == null)
  | select(any(.spec.tolerations[]?; .key == "homelab/lab" or (.key == null and .operator == "Exists")))] | length' <<<"$pods")
# Workload pods on the VM; DaemonSet pods run on every node and don't count.
busy=$(jq --arg n "$VM" '[.items[] | select(.spec.nodeName == $n)
  | select(.status.phase != "Succeeded" and .status.phase != "Failed")
  | select(all(.metadata.ownerReferences[]?; .kind != "DaemonSet"))] | length' <<<"$pods")

if [[ $state != running ]]; then
  if ((pending > 0)); then
    echo "$pending pending lab pod(s): starting $VM"
    touch "$STAMP" # idle clock starts at boot
    "${VIRSH[@]}" start "$VM"
  fi
  exit 0
fi

if ((busy > 0 || pending > 0)) || [[ ! -e $STAMP ]]; then
  touch "$STAMP"
  exit 0
fi

idle=$((($(date +%s) - $(stat -c %Y "$STAMP")) / 60))
if ((idle >= IDLE_MIN)); then
  echo "$VM idle ${idle}m: shutting down"
  "${VIRSH[@]}" shutdown "$VM"
fi
