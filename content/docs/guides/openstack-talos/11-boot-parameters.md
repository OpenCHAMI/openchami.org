---
title: "§11 — Boot Parameters"
description: "You tell BSS what each node should boot. You finish with the control-plane node and the workers each getting their own Talos boot script."
slug: "11-boot-parameters"
date: 2026-10-21
lastmod: 2026-10-21
weight: 110
toc: true
draft: false
---
> ⏱ **About 10 minutes** · on the head node, with a fresh token · writes two boot payloads and loads them into BSS
>
> - **What this chapter is for.** You tell BSS what each node should boot. You finish with the control-plane node and the workers each getting their own Talos boot script.
>
> - **What you will learn.** What BSS stores and how iPXE asks for it, what each part of the Talos kernel command line does, and how to check BSS's answer before any node asks.
>
> - **Don't skip it.** Without a payload, BSS hands a node an empty retry script. The node then waits and asks again, for ever.

---

## Introduction

### BSS answers one question

BSS (Boot Script Service) answers one question: what should a machine with MAC address X boot? For each MAC address, BSS stores a kernel URL, an initrd (initial RAM disk) URL, and a kernel command line. When iPXE asks for a boot script, BSS replies with one built from those three parts.

### The last of the three copies

This chapter writes the third copy of each node's MAC address. As §8 explained, every MAC address must match across three places:

![The node map in och-vars-env.sh decides each node's name, xname, NID, MAC address, IP address and role once. Those values are then copied by hand into three places. The Neutron port created in section 5.4 pins the MAC and is owned by OpenStack. The SMD inventory loaded in section 8.1 maps that same MAC to an IP address and an xname, and CoreDHCP and CoreDNS read it. The BSS payload written in section 11.1 maps the same MAC to a kernel, an initrd and a command line, and iPXE reads it. The MAC address is the join key because it is the only thing a node knows about itself at power-on — and the Neutron port names do not match the node names, being offset by one, so the MAC is the only value that reliably connects the three. Neutron cannot see OpenCHAMI's copies and OpenCHAMI cannot see Neutron's, so a disagreement is never detected automatically: a MAC missing from SMD produces a silent bootloop, and a MAC in the wrong BSS payload boots the node successfully as the wrong role.](diagrams/08-three-way-contract.svg)

<details>
<summary>ASCII version</summary>

```
   §5.4   Neutron port    MAC 52:54:00:be:ef:01   ← the instance's NIC
   §8.1   SMD inventory   MAC → 172.16.0.1        ← CoreDHCP leases this
   §11.1  BSS payload     MAC → controlplane.yaml ← this node's role
```

</details>

### Two roles, so two payloads

The nodes have two roles, so BSS stores two payloads:

- **`och-cp1`** (`…:be:ef:01`) runs the **Kubernetes control plane**, and fetches `controlplane.yaml`.

- **`och-w1` to `och-w4`** (`…:02` to `…:05`) are **workers**, and fetch `worker.yaml`.

To move a node to the other role later, move its MAC to the other payload and run `set` again.

### The Talos kernel command line

| Token | Meaning |
|---|---|
| `talos.platform=metal` | Tell Talos it is on bare metal (PXE), not a cloud — **required** |
| `slab_nomerge pti=on` | Kernel hardening Talos requires on metal — **required** |
| `console=tty0 console=ttyS0,115200` | Serial console, so `openstack console log show` gives you the Talos dashboard |
| `talos.config=http://…/worker.yaml` | Where Talos fetches its machine config — this is what replaces cloud-init |

PXE (Preboot Execution Environment) is the standard way a machine boots from the network.

🔀 **Deviation: `talos.platform=metal`, on a cloud.** Talos does have an `openstack` platform, which reads its configuration from Nova's metadata service. We don't use it, because the point of this tutorial is that **OpenCHAMI** provisions the nodes. If Nova handed Talos its config, we would learn nothing about OpenCHAMI, and nothing that carries over to real hardware. `metal` keeps BSS in the path.

🔀 **Deviation: none of the Rocky command line is here.** There is no `root=live:…`, no `overlayroot=…`, no `cloud-init=…` or `ds=nocloud-net`, and no `apparmor=0 selinux=0 nomodeset`. Talos isn't a dracut live image. Its initramfs *is* the operating system.

### What you will do

- **Write the two payloads** (Step 11.1). One YAML file for the control-plane node, one for the workers.

- **Load them into BSS** (Step 11.2). Two `ochami` commands, with a fresh token.

- **Pretend to be each node** (the checkpoint). You ask BSS exactly what iPXE will ask, and check all three copies of each MAC agree.

📌 The OpenCHAMI documentation goes into more detail:

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/), Part 2.5. This chapter follows it, with the changes marked 🔀.

- [BSS](https://github.com/OpenCHAMI/bss), the Boot Script Service.

---

## Step 11.1 — Write the two payloads

The heredocs below read three variables, which come from §7's `och-head-vars-env.sh`. Check they aren't empty before writing any boot script:

```
head$ source ~/och-head-env.sh
head$ echo "${OCH_ARCH} ${OCH_OBJ} ${OCH_CONSOLE}"
amd64 172.16.0.254:7070 ttyS0,115200
```

Control-plane node:

```
head$ sudo mkdir -p /etc/openchami/data/boot/bss
head$ cat << EOF | sudo tee /etc/openchami/data/boot/bss/talos-controlplane.yaml
---
kernel: 'http://${OCH_OBJ}/boot-images/talos/vmlinuz-${OCH_ARCH}'
initrd: 'http://${OCH_OBJ}/boot-images/talos/initramfs-${OCH_ARCH}.xz'
params: 'talos.platform=metal slab_nomerge pti=on console=tty0 console=${OCH_CONSOLE} talos.config=http://${OCH_OBJ}/boot-images/talos/controlplane.yaml'
macs:
  - 52:54:00:be:ef:01
EOF
```

Workers:

```
head$ cat << EOF | sudo tee /etc/openchami/data/boot/bss/talos-worker.yaml
---
kernel: 'http://${OCH_OBJ}/boot-images/talos/vmlinuz-${OCH_ARCH}'
initrd: 'http://${OCH_OBJ}/boot-images/talos/initramfs-${OCH_ARCH}.xz'
params: 'talos.platform=metal slab_nomerge pti=on console=tty0 console=${OCH_CONSOLE} talos.config=http://${OCH_OBJ}/boot-images/talos/worker.yaml'
macs:
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
EOF
```

⚠ **The heredocs are unquoted on purpose**, so that `${OCH_OBJ}`, `${OCH_ARCH}` and `${OCH_CONSOLE}` expand into the files. **Check they did.** An unset variable writes a file that looks right but has a broken URL. The failure then shows up much later, as an unhelpful iPXE error:

```
head$ cat /etc/openchami/data/boot/bss/talos-controlplane.yaml
head$ grep -c '172.16.0.254:7070' /etc/openchami/data/boot/bss/*.yaml
/etc/openchami/data/boot/bss/talos-controlplane.yaml:3
/etc/openchami/data/boot/bss/talos-worker.yaml:3
```

Three lines in each file carry `${OCH_OBJ}`: `kernel:`, `initrd:`, and the `talos.config=` URL inside `params:`. A lower count means an expansion failed.

There are copies in [`templates/bss-talos-controlplane.yaml`](templates/bss-talos-controlplane.yaml) and [`templates/bss-talos-worker.yaml`](templates/bss-talos-worker.yaml).

---

## Step 11.2 — Load them into BSS

```
head$ export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
head$ ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/bss/talos-controlplane.yaml
head$ ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/bss/talos-worker.yaml
head$ ochami bss boot params get -F yaml
```

Unlike §8's `discover static`, `bss boot params set` replaces existing entries, so you can re-run it safely whenever you change a payload.

📌 **No "boot from local disk" payload is needed.** Because iPXE lives on the node's root disk (§9) and Talos overwrites it during installation, an installed node stops network-booting automatically. BSS is never asked again after installation, so it never needs a third payload telling installed nodes to boot from disk.

---

## ✅ Checkpoint — pretend to be each node

First, ask BSS what it would tell each MAC. This is the exact HTTP request iPXE makes:

```
head$ curl -s "http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01" \
        | grep -o 'talos.config=[^ ]*'
talos.config=http://172.16.0.254:7070/boot-images/talos/controlplane.yaml

head$ curl -s "http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:02" \
        | grep -o 'talos.config=[^ ]*'
talos.config=http://172.16.0.254:7070/boot-images/talos/worker.yaml
```

Different answers for the two MACs mean the role split works.

Next, read a whole script. This is exactly what `och-cp1` will run:

```
head$ curl -s "http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01"
#!ipxe
kernel --name kernel http://172.16.0.254:7070/boot-images/talos/vmlinuz-amd64 initrd=initrd talos.platform=metal slab_nomerge pti=on console=tty0 console=ttyS0,115200 talos.config=http://172.16.0.254:7070/boot-images/talos/controlplane.yaml xname=x1000c0s0b0n0 nid=1 ds=nocloud-net;s=localhost/ || goto boot_retry
initrd --name initrd http://172.16.0.254:7070/boot-images/talos/initramfs-amd64.xz || goto boot_retry
boot || goto boot_retry
:boot_retry
sleep 30
chain http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01&retry=1
```

Three things in there come from BSS, not from us. All three are harmless:

- **`xname=x1000c0s0b0n0 nid=1`** are BSS's own names for the node, its xname and NID (node ID). Talos ignores kernel arguments it doesn't know.

- **`ds=nocloud-net;s=localhost/`** is added by BSS every time, for the cloud-init systems it was written for. We never put it on the command line, and Talos never reads it. `talos.platform=metal` decides where the config comes from.

- **`sleep 30` and `chain …&retry=1`** are the retry loop. A node that can't get a usable script waits here for ever, rather than failing. §12's Common failures turns that symptom back into a cause.

⚠ **The `xname` tells you BSS matched the *right* node.** `x1000c0s0b0n0` is `och-cp1`'s SMD (State Management Database) component ID from §8. If a MAC comes back with another node's xname, SMD and BSS disagree, and §12 will boot the wrong role.

Last, check all three copies of each MAC at once. The first command runs on the **devbox**, and the other two back on the **head node**. Coming back over `ssh` loses `DEMO_ACCESS_TOKEN`, so export it again when you land:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov -c Name -c 'MAC Address' -f value | sort
 fa:16:3e:1a:2b:3c
och-head-prov 52:54:00:be:ef:ff
och-node1-prov 52:54:00:be:ef:01
och-node2-prov 52:54:00:be:ef:02
och-node3-prov 52:54:00:be:ef:03
och-node4-prov 52:54:00:be:ef:04
och-node5-prov 52:54:00:be:ef:05

head$   ochami smd component get | jq -r '.Components[]|select(.Type=="Node")|.ID'
x1000c0s0b0n0
x1000c0s0b1n0
x1000c0s0b2n0
x1000c0s0b3n0
x1000c0s0b4n0

head$   ochami bss boot params get -F json | jq -r '.[].macs[]' | sort
52:54:00:be:ef:01
52:54:00:be:ef:02
52:54:00:be:ef:03
52:54:00:be:ef:04
52:54:00:be:ef:05
```

You should see five node MACs on ports, five node components, and five MACs across the two BSS payloads. The node MACs run from `…:be:ef:01` to `05`. If any list is short, fix it *now*. Every failure in §12 traces back to these three lists disagreeing.

The port list has two extra rows, `och-head-prov` and the unnamed `fa:16:3e:…` port. Both are expected, and neither is a node. §8's checkpoint explains both. Count the `be:ef:0…` rows, not the lines.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| The boot script shows an empty `kernel:` or blank params | The heredoc variables were unset. Run `source ~/och-head-env.sh`, then the `echo` in Step 11.1 to confirm all three are set. Then write the files again |
| `set` fails with `401` | The token has expired. Run the `gen_access_token` export again |
| `ochami` says `Environment variable DEMO_ACCESS_TOKEN unset` | The token hasn't expired. The variable is gone, because it lives in one shell and you opened a new one. Any `ssh` back to the head node loses it. Run the export again |
| The boot script is empty for a MAC | That MAC isn't in any payload, or isn't in SMD. Check both |
| `curl … :8081` gives connection refused | BSS isn't running. Run `systemctl is-active bss`, then read the gotchas in Step 7.10 |
| The node later boots but stays in maintenance mode | The `talos.config` URL is wrong or not public-read. See §10's checkpoint |

Next: [§12 — Booting the Talos Cluster](12-boot-the-cluster.md)
