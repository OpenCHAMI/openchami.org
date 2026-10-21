---
title: "§12 — Booting the Talos Cluster"
description: "You boot the nodes through the whole OpenCHAMI chain and form a cluster. You finish with three Ready Kubernetes nodes, provisioned by OpenCHAMI on OpenStack."
slug: "12-boot-the-cluster"
date: 2026-10-21
lastmod: 2026-10-21
weight: 120
toc: true
draft: false
---
> ⏱ **About 30–40 minutes**, most of it Talos pulling images on first boot · two `openstack` commands on the devbox, the rest on the head node · turns three node instances into a Kubernetes cluster
>
> - **What this chapter is for.** You boot the nodes through the whole OpenCHAMI chain and form a cluster. You finish with three `Ready` Kubernetes nodes, provisioned by OpenCHAMI on OpenStack.
>
> - **What you will learn.** How to read a node's boot from its console log, why a Talos node network-boots only once, and how to re-provision a node when you need to.
>
> - **Don't skip it.** Everything from §13 on runs on this cluster.

---

## Introduction

### The whole chain, end to end

Everything is now in place, and booting a node walks the whole chain:

1. The instance powers on and boots its **root disk**, which is iPXE (§9).

2. iPXE asks for an address over DHCP. **CoreDHCP** leases the IP address SMD (State Management Database) holds for its MAC, and points iPXE at BSS (§7, §8).

3. iPXE asks **BSS** (Boot Script Service), which returns §11's Talos script.

4. iPXE fetches the Talos `vmlinuz` and `initramfs.xz` from the head node's S3 store (§10), and boots them **into RAM**.

5. With no operating system on disk, Talos enters **maintenance mode**. It then fetches its machine config from the `talos.config` URL.

6. Talos pulls its **installer** image, which needs the head node's NAT (network address translation) from §7.12. It selects the disk by size (§10.6), **overwrites iPXE with itself**, and reboots into Talos.

Steps 2–6 are ordinary OpenCHAMI, the same as on real hardware. Step 1 is the only cloud-specific part. It isn't even a command, just what happens when the instance powers on.

### Nothing has to stop the network boot

There is no "stop network-booting" step, by design. Talos writes over the disk it booted from, so nothing has to remember which nodes are done. The node stops network-booting because there is nothing left to network-boot *from*.

⚠ **Installing Talos is one-way.** Once Talos writes itself to the root disk, the iPXE bootloader is gone. To network-boot the node again, you have to restore iPXE with `openstack server rebuild` (§12.7).

### Your nodes are already waiting

📌 Your nodes are already at the start of this chain. §9 created them and they booted iPXE, but BSS had no payload for them yet. Where they stopped depends on when you fixed §7.9b:

| If §7.9b was already applied at §9 | If you fixed it afterwards |
|---|---|
| The node is still in iPXE, asking BSS again every few seconds | The node fell out of iPXE and is waiting at `Shell>` |
| It would pick up §11's payload on its own eventually | It will never retry, because it isn't running iPXE any more |

Either way you reboot it, for the same reason. A reboot is instant and predictable, and it gives you one clean boot to read, not a log with two attempts in it. **Both states leave one iPXE banner in the console log.** That is the baseline Step 12.2 asks you for.

### What you will do

- **Boot the control-plane node** (Step 12.1), and watch its console as it installs.

- **Confirm it came back as Talos** (Step 12.2), not as iPXE.

- **Point `talosctl` at it** (Step 12.3), and make that setting survive new shells.

- **Bootstrap etcd** (Step 12.4), exactly once.

- **Bring up the workers** (Step 12.5), one at a time.

- **Get the kubeconfig** (Step 12.6).

- **Check the cluster** (the checkpoint). Three `Ready` nodes, and Talos's own view of the members.

- **Reboot a node through its firmware, and learn to re-provision** (Step 12.7).

📌 The documentation goes into more detail:

- [The Talos documentation](https://docs.siderolabs.com/), for `talosctl`, bootstrapping and maintenance mode.

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/), for the boot chain on real hardware.

---

## Step 12.1 — Boot the control-plane node

This is the first chapter that needs **both** shells at once. Open them now and check each one is the shell you think it is. A `reboot --hard` typed on the head node, or a `talosctl` typed on the devbox, fails in a confusing way:

```
devbox$ cd ~/och && source och-vars-env.sh
devbox$ echo "${OCH_PREFIX}"
och

head$ source ~/och-head-env.sh
head$ echo "${OCH_CP_IP} ${OCH_HEAD_PROV_IP}"
172.16.0.1 172.16.0.254
```

Then reboot the control-plane node:

```
devbox$ openstack server reboot --hard ${OCH_PREFIX}-cp1
```

⚠ **`--hard` matters here.** A soft reboot asks the guest operating system to shut down politely, over ACPI (Advanced Configuration and Power Interface). There is no operating system on this node, only iPXE or a firmware prompt, and neither will answer. `--hard` resets the instance the way the power button would.

Watch it. Until the Talos API comes up, the console log is your only view, because there is no shell to log in to and no SSH:

```
devbox$ watch -n 10 "openstack console log show ${OCH_PREFIX}-cp1 --lines 30"
```

You are looking for this progression, over roughly 5–10 minutes. The `…` marks lines left out. The first six lines are the ones §9's checkpoint already showed you, and they should look the same, **except one**:

```
iPXE 2.0.0+ (ga1992) -- Open Source Network Boot Firmware -- https://ipxe.org
net0: 52:54:00:be:ef:01 using virtio-net on 0000:03:00.0 (Ethernet) [open]
Configuring (net0 52:54:00:be:ef:01)...... ok
net0: 172.16.0.1/255.255.255.0 gw 172.16.0.254
Filename: http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.0.254:8081/boot/v1/bootscript... ok
bootscript : 549 bytes [script]                       ← NOT 127. see below
http://172.16.0.254:7070/boot-images/talos/vmlinuz-amd64... ok
http://172.16.0.254:7070/boot-images/talos/initramfs-amd64.xz... ok
[    0.000000] Linux version …
…
[talos] task startAllServices …
[talos] machine is running in maintenance mode
[talos] downloading config from http://172.16.0.254:7070/…/controlplane.yaml
[talos] using disk match expression: …
[talos] downloading installer image ghcr.io/siderolabs/installer:v1.13.0
[talos] installing Talos to disk /dev/vda
[talos] … installation successful, rebooting
```

Five of those lines each prove an earlier chapter worked:

| Line | Proves |
|---|---|
| `net0: 172.16.0.1/…gw 172.16.0.254` | §5 (no Neutron DHCP, no port security), §7.7 (CoreDHCP), §8 (SMD) |
| `bootscript : 549 bytes` — **anything but `127`** | §11's payload is what BSS served. **127 bytes is the empty retry script**, the same one §9 got before §11 existed, and it means this MAC still has no boot parameters. The exact size depends on your URLs; the distinction that matters is 127 vs several hundred |
| `downloading config from …controlplane.yaml` | §10.7 (published, public-read) and §11 (BSS gave the right role) |
| `using disk match expression:` **naming the node's real disk** | §10.6's selector resolved. Expect `/dev/vda` on virtio; the device name doesn't matter, a name appearing does. If this says `no disks matched the expression`, stop — see Common failures |
| `downloading installer image ghcr.io/…` **and getting past it** | §7.12's NAT and §10.6's nameservers |

⚠ **The byte count is the cheapest early warning in this chapter.** A 127-byte script sleeps 30 seconds and asks again, for ever. The console then looks like a node that is *nearly* working. If you see it, go back to §11's checkpoint, and run `bss boot params set` again for that MAC before anything else.

⚠ **A node stuck at `downloading installer` is the most common failure, and it has two causes.** Either the head node isn't forwarding and masquerading traffic (§7.12), or DNS can't resolve `ghcr.io` (§10.6's nameserver patch didn't apply). For the first, also check that port security is off on the head node's provisioning port. Test forwarding from the head node:

```
head$ sudo nft list chain ip nat postrouting      # or: sudo firewall-cmd --query-masquerade
head$ sysctl net.ipv4.ip_forward
```

---

## Step 12.2 — Confirm it came back as Talos, not as iPXE

This step creates nothing. It is a check. Talos rebooted itself at the end of Step 12.1, and this is where you find out whether §10.6's `wipe: true` worked.

The evidence is in the log you already have. Read it **before** bootstrapping, because the failure it rules out is silent and costs a rebuild. This was captured from `och-cp1` on 7 Aug 2026:

```
devbox$ openstack console log show ${OCH_PREFIX}-cp1 \
          | grep -E 'GRUB:|sd-boot|Unsigned PE|kexec_core'
[talos] GRUB: BOOT partition not found, skipping probing
[talos] sd-boot: found UKI files: [Talos-v1.13.0.efi]
[talos] found sd-boot bootloader on "/dev/vda"
PEFILE: Unsigned PE binary
kexec_core: Starting new kernel
```

| Line | Meaning |
|---|---|
| `GRUB: BOOT partition not found` **and** `found sd-boot bootloader on "/dev/vda"` | ✅ The disk holds Talos's UKI (unified kernel image) and nothing else. `wipe: true` worked. No iPXE EFI system partition is left for the firmware's removable-media fallback to find. Talos 1.10 and later install systemd-boot rather than GRUB on UEFI |
| Either of those naming a disk that is **not** the one iPXE was on | 🛑 Talos installed to the wrong disk. iPXE survives, wins the next boot, and the node reinstalls for ever. Fix §10.6's selector, publish again (§10.7), and `openstack server rebuild` |
| `PEFILE: Unsigned PE binary` | Harmless. Talos tried to `kexec` the UKI directly, and the kernel declined to load an unsigned PE (Portable Executable) file. Talos then took the kernel and initrd out of the UKI instead, as the next line shows |

⚠ **`kexec_core: Starting new kernel` means this reboot never touched the firmware.** Talos jumps straight into the installed kernel. The firmware, the boot order and the disk's bootloader are all bypassed. So counting iPXE banners across this reboot proves nothing either way. **The firmware path is still untested at this point.** The first thing that really tests it is the plain `openstack server reboot` in Step 12.7. To rule out the reinstall loop now, rather than at teardown, do Step 12.7's soft-reboot test before Step 12.4.

🛑 **That is the last line this node writes to the console.** The installed system's kernel command line comes from the UKI, which does not include `console=ttyS0,115200`, so nothing further—neither the Talos dashboard nor a kernel panic—reaches Nova's serial log (see the console note in Step 10.7). **From here on, `talosctl` is your only view into the node.**

📌 Unlike most logs, `reboot --hard` empties the console log rather than appending to it. Nova's libvirt driver recreates the guest and reopens the serial log from scratch, so you see *only* this boot and §9's 127-byte boot script is gone.

---

## Step 12.3 — Point `talosctl` at the node

On the head node, where the `talosconfig` from §10.5 lives:

```
head$ cd ~/talos
head$ export TALOSCONFIG=$PWD/talosconfig
head$ talosctl config endpoint ${OCH_CP_IP}
head$ talosctl config node ${OCH_CP_IP}
```

Both are `172.16.0.1`. That is the control-plane node's address from SMD, the same one §10.5 put into the cluster endpoint. `endpoint` is the node `talosctl` *connects to*, and `node` is the node it *acts on*. They are the same machine here. They won't be once there is more than one control-plane node.

🛑 **Make both settings permanent now.** `TALOSCONFIG` and `KUBECONFIG` are shell variables, and every `ssh` back to the head node loses them. §§13–19 assume both are set. When they aren't, the errors don't say "unset variable". They look like a broken cluster:

| Symptom | Actually |
|---|---|
| `talosctl` → `error constructing client: failed to determine endpoints` | `TALOSCONFIG` unset |
| `kubectl` → `The connection to the server localhost:8080 was refused` | `KUBECONFIG` unset — `localhost:8080` is kubectl's default when it has no config |

Write the `~/och-head-talos-env.sh` companion file that §7's `och-head-env.sh` already sources on login. Creating the file is all you need—there is no `.bashrc` hook to add:

```
head$ cat > ~/och-head-talos-env.sh << 'EOF'
# Talos + Kubernetes client context. Created in §12; sourced by och-head-env.sh.
export TALOSCONFIG=$HOME/talos/talosconfig
export KUBECONFIG=$HOME/talos/kubeconfig
EOF
head$ source ~/och-head-env.sh
head$ echo "$TALOSCONFIG"
/home/rocky/talos/talosconfig
```

`kubeconfig` doesn't exist until Step 12.6. Naming it early does no harm, because a missing file only matters when `kubectl` runs. **The quoted `<< 'EOF'` is required here.** `$HOME` must reach the file as written, and be expanded when the file is *sourced*, not now.

📌 If you added those exports to `~/.bashrc` by hand, remove them with `sed -i '/talos\/talosconfig/d;/talos\/kubeconfig/d' ~/.bashrc`. That leaves one place that sets them. This file also survives `och-head-vars-env.sh` being regenerated from the devbox, because it is a separate file.

`talosctl config endpoint` and `… node` persist without any of this. They are written into the `talosconfig` **file**, so you never repeat them, however often you reconnect.

Wait for the Talos API to answer, a minute or two after the reboot:

```
head$ talosctl version
```

You should see both a `Client` and a `Server` section. A `Server` section means the Talos API (port 50000) is up on the node. If it never answers, `talosctl -n 172.16.0.1 dmesg` or the console log will say why.

---

## Step 12.4 — Bootstrap etcd

🛑 **Run this exactly once, on this one control-plane node.** Running `bootstrap` twice, or on a worker, corrupts etcd. You would have to start the cluster again.

```
head$ talosctl bootstrap
```

Then watch the Kubernetes control plane start. It takes 2–5 minutes to pull `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` and `etcd`:

```
head$ talosctl health --nodes ${OCH_CP_IP}
```

It runs a series of checks, and should end by reporting the cluster healthy.

📌 If `health` hangs or fails on node discovery, the problem is the check, not the cluster. By default `talosctl health` runs *on the node*. It asks Talos's discovery service, `discovery.talos.dev`, over the internet, which nodes are members. Name the nodes yourself instead, which needs nothing outside:

```
head$ talosctl health --server=false --control-plane-nodes ${OCH_CP_IP} --worker-nodes ""
```

The workers really are absent at this point. They don't boot until Step 12.5.

A different error—`dial tcp 172.16.0.1:6443: connect: connection refused`—simply means the API server is still starting up rather than failing discovery. Wait a couple of minutes and try again.

---

## Step 12.5 — Bring up the workers

Workers need no bootstrap. They read `worker.yaml`, find the control-plane endpoint in it, and join. The first time, do them one at a time, so you know which one any failure belongs to:

```
devbox$ openstack server reboot --hard ${OCH_PREFIX}-w1
devbox$ watch -n 10 "openstack console log show ${OCH_PREFIX}-w1 --lines 20"
# … wait for "installation successful", then for the log to stop at
#   "kexec_core: Starting new kernel". That is the end of the console (§10.7).
#   Confirm the worker is really up with talosctl, not by watching:
head$   talosctl -n 172.16.0.2 version
```

Then the second:

```
devbox$ openstack server reboot --hard ${OCH_PREFIX}-w2
# … same wait …
```

📌 For the second worker, do Step 12.6 first, and watch Kubernetes instead. Once the kubeconfig exists, `watch -n 10 "kubectl get nodes"` on the head node shows progress far better than the console log. The worker goes from absent, to `NotReady`, to `Ready` as it joins. It never freezes the way the console does at `kexec_core`. The console route comes first only because it works before there is a cluster to ask.

Once you trust the sequence, you can reboot every worker at once. BSS serves them all the same payload.

---

## Step 12.6 — Get the kubeconfig

```
head$ cd ~/talos
head$ talosctl kubeconfig .
head$ kubectl get nodes -o wide
```

`talosctl kubeconfig <dir>` writes `<dir>/kubeconfig`. Running it from `~/talos` puts the file exactly where Step 12.3's `~/och-head-talos-env.sh` already points `KUBECONFIG`. No export is needed. If you find yourself typing one, `och-head-talos-env.sh` isn't being sourced, and §13 onwards will keep breaking.

---

## ✅ Checkpoint — the one that matters

```
head$ kubectl get nodes
NAME      STATUS   ROLES           AGE     VERSION
nid0001   Ready    control-plane   3d11h   v1.36.0
nid0002   Ready    <none>          3d11h   v1.36.0
nid0003   Ready    <none>          3d10h   v1.36.0
```

This was captured on 10 Aug 2026, three days after the nodes booted. On a fresh run, the `AGE` column reads minutes. `v1.36.0` is the Kubernetes version that Talos v1.13.0 ships, not something you chose.

Seeing all three nodes `Ready` proves the entire chain worked: each instance booted iPXE from its root disk, received its IP from CoreDHCP via SMD, fetched its role-specific Talos payload from BSS, installed Talos over the root disk, pulled Kubernetes images through the head node's NAT, and joined the cluster.

You now have a Kubernetes cluster provisioned by OpenCHAMI on OpenStack.

Two more checks are worth keeping in your run log. **First, Talos's own list of members:**

```
head$ talosctl -n ${OCH_CP_IP} get members
NODE         NAMESPACE   TYPE     ID        VERSION   HOSTNAME   MACHINE TYPE   OS                ADDRESSES
172.16.0.1   cluster     Member   nid0001   1         nid0001    controlplane   Talos (v1.13.0)   ["172.16.0.1"]
172.16.0.1   cluster     Member   nid0002   1         nid0002    worker         Talos (v1.13.0)   ["172.16.0.2"]
172.16.0.1   cluster     Member   nid0003   1         nid0003    worker         Talos (v1.13.0)   ["172.16.0.3"]
```

Talos builds this list on its own, separately from Kubernetes. It confirms three things that `kubectl get nodes` can't:

- **`MACHINE TYPE`** is `controlplane` on `nid0001` and `worker` on the other two. That is BSS's per-MAC payload from Step 11.2 working. Each node fetched `controlplane.yaml` or `worker.yaml`, according to the payload its MAC is in. If that mapping is wrong, you find out here, not from `kubectl`.

- **`ADDRESSES`** are the `172.16.0.x` addresses from SMD. So CoreDHCP answered from SMD, rather than handing out a bootloop lease (§8).

- **`HOSTNAME`** is `nid000x`, matching the Kubernetes node names. That shows the names come from the provisioning chain, not from Kubernetes.

`VERSION` is the version of the member record, not of anything you installed. `1` means it was written once and hasn't changed since.

📌 This list is the one thing here that needs the internet. Talos builds it through `discovery.talos.dev`, which the nodes reach through the head node's NAT from §7.12. So a cluster with no internet access shows an empty list while being perfectly healthy. Nothing else in this tutorial depends on it. If it *is* empty, trust `kubectl get nodes`, and leave the discovery settings alone.

**Second, the system pods:**

```
head$ kubectl get pods -A
NAMESPACE     NAME                              READY   STATUS    RESTARTS        AGE
kube-system   coredns-6dc87b5c58-4fpgp          1/1     Running   0               3d11h
kube-system   coredns-6dc87b5c58-rq2r7          1/1     Running   0               3d11h
kube-system   kube-apiserver-nid0001            1/1     Running   0               3d11h
kube-system   kube-controller-manager-nid0001   1/1     Running   5 (3d11h ago)   3d11h
kube-system   kube-flannel-59d4z                1/1     Running   0               3d11h
kube-system   kube-flannel-8w294                1/1     Running   0               3d11h
kube-system   kube-flannel-km2wl                1/1     Running   0               3d11h
kube-system   kube-proxy-66n59                  1/1     Running   0               3d11h
kube-system   kube-proxy-7cxbl                  1/1     Running   0               3d11h
kube-system   kube-proxy-jmp2p                  1/1     Running   0               3d11h
kube-system   kube-scheduler-nid0001            1/1     Running   5 (3d11h ago)   3d11h
```

Read it in three groups:

- **One of each per node.** `kube-flannel` and `kube-proxy` are DaemonSets, so there are three of each.

- **One of each control-plane component.** `kube-apiserver`, `kube-controller-manager` and `kube-scheduler` carry the name of the node they run on.

- **Two CoreDNS replicas.**

📌 `RESTARTS 5` on the controller-manager and the scheduler is expected, but only on the first bootstrap. Talos starts all three control-plane pods together. The controller-manager and the scheduler can do nothing until the API server answers. So they crash and restart for the 90 seconds or so it takes to come up. `(3d11h ago)` means the last restart was at bootstrap, with none since. That is the number to look at, not the count. A restart count that is still *climbing* is a real fault. See Common failures.

🛑 **The Kubernetes node names are `nid0001`, `nid0002` and so on, not `och-cp1` and `och-w1`.** This is expected, so don't work around it.

The Nova instance name is only a label in OpenStack, and it never reaches the guest. Talos takes its hostname from **DHCP**. The DHCP server is OpenCHAMI's CoreDHCP, which answers from SMD. So Kubernetes gets a name based on the node's SMD identity (`x1000c0s0b0n0`, NID 1), not on what you typed at `server create`. **That is the correct behaviour.** OpenCHAMI is meant to be the source of truth for node identity. If the nodes were named after the Nova instances, Nova would be that source instead.

The practical effects are all small:

- **`kubectl` commands take `nid0001`, and `openstack` commands take `och-cp1`.** Keep the mapping to hand. It is `172.16.0.1` → `nid0001` → `och-cp1`, in SMD, Kubernetes and Nova order.

- **§18's node labels use the `nid…` names.**

- **In Step 12.7, `kubectl drain` and `kubectl delete node` take `nid…`.** The `openstack server rebuild` on the next line takes `och-…`. That command block shows both on purpose.

---

## Step 12.7 — The reboot difference, and how to re-provision

Do this once. It shows what makes Talos different from diskless nodes, which network-boot every time.

🛑 **Do the plain reboot before §13, not after.** It is the only step in the tutorial that boots a node through its **firmware**. Every boot so far ended in a `kexec` (§10.7). That jumps straight into the new kernel, and skips the firmware, the boot order and the disk's bootloader. So until you do this, nothing has shown that an installed node survives a power cycle. You don't want to find that out in §16.

A plain reboot keeps everything:

```
devbox$ openstack server reboot ${OCH_PREFIX}-cp1
head$   kubectl get nodes
NAME      STATUS     ROLES           AGE     VERSION
nid0001   NotReady   control-plane   3d11h   v1.36.0
nid0002   Ready      <none>          3d11h   v1.36.0
nid0003   Ready      <none>          3d11h   v1.36.0
```

This was captured on 10 Aug 2026, about 30 seconds after the reboot. `nid0001` returns to `Ready` a minute or so later, and the workers never notice.

Read the `AGE` column. It still says `3d11h`. This is the **same node**, not a new one. Nova didn't re-image anything, and Kubernetes didn't register it again. `kube-apiserver` and the two controllers show an `AGE` of seconds, because Talos restarted those pods. The node object, etcd and the machine config are all as they were.

Two more things are worth checking while it comes back:

```
head$ kubectl get pods -A | grep -v '  0  '
kube-system   coredns-6dc87b5c58-4fpgp          1/1   Running   1 (2m9s ago)    3d11h
kube-system   kube-controller-manager-nid0001   1/1   Running   2 (36s ago)     19s
kube-system   kube-flannel-km2wl                1/1   Running   1 (2m14s ago)   3d11h
kube-system   kube-proxy-jmp2p                  1/1   Running   1 (2m14s ago)   3d11h

head$ talosctl -n ${OCH_CP_IP} get members
172.16.0.1   cluster   Member   nid0001   2   nid0001   controlplane   Talos (v1.13.0)   ["172.16.0.1"]
172.16.0.1   cluster   Member   nid0002   1   nid0002   worker         Talos (v1.13.0)   ["172.16.0.2"]
```

Only the pods on the rebooted node restarted. That is one flannel, one kube-proxy, and CoreDNS, because a replica happened to run there. The other nodes' DaemonSet pods still read `0`. `nid0001`'s member `VERSION` has gone from `1` to `2`, because the record was rewritten when the node rejoined.

📌 For the first minute, `kubectl` says `The connection to the server 172.16.0.1:6443 was refused`. That is the API server on the rebooting node. It is the *other* meaning of that message, not the missing `KUBECONFIG` from Step 12.3. `talosctl` keeps working throughout, because it talks to Talos on port 50000, not to Kubernetes.

Unlike diskless nodes that rebuild themselves from an image on every boot, Talos keeps its state on disk—its OS image is immutable, but its machine config and etcd data persist across reboots.

✅ This proves the last untested link in the chain. The install in Step 12.1 really did replace iPXE on `/dev/vda` and leave a bootable system behind: the firmware found systemd-boot, systemd-boot found the UKI, and the node came back as itself. And because a real OS is now running on the node to answer the ACPI shutdown request, a *soft* reboot works here where Step 12.1 needed `--hard`.

To re-provision a node, put iPXE back on its root disk. That is what `rebuild` does:

```
head$   kubectl drain nid0002 --ignore-daemonsets --delete-emptydir-data
head$   kubectl delete node nid0002
devbox$ openstack server rebuild ${OCH_PREFIX}-w1 --image ${OCH_PREFIX}-ipxe-disk --wait
```

The instance comes back with the 8 MB iPXE image where Talos was. It boots it, and goes through Step 12.1 again by itself. BSS still has its payload and SMD still has its MAC, so nothing on the OpenCHAMI side changes. **The console works again while it installs**, because a rebuilt node is network-booting. It goes quiet again at `kexec_core`. Wait for `installation successful`, then confirm with `talosctl -n 172.16.0.2 version` and `kubectl get nodes`.

⚠ **`rebuild` destroys the root disk.** That is what re-provisioning a compute node requires, and why it is dangerous on any other instance: running it on the **head node** would erase OpenCHAMI, the S3 bucket, and your machine configs. Double-check the instance name before pressing return.

🛑 **Never rebuild or `reset` the control-plane node while it is the only one.** That destroys etcd, and the cluster with it. To rebuild the whole cluster, rebuild all three nodes and start again from Step 12.1. The OpenCHAMI side needs no changes at all.

📌 Why `rebuild` and not `talosctl reset`? `reset` wipes Talos's own partitions and reboots. On a node whose root disk holds only Talos, that leaves nothing bootable, and no way to network-boot back in. `rebuild` puts back the thing that starts the chain. Use `reset` only when you mean to reinstall with `talosctl` from maintenance mode.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `openstack server reboot` appears to do nothing | You left out `--hard`, and there is no operating system to answer the ACPI request (Step 12.1) |
| iPXE never gets an address | §5 (Neutron DHCP or port security still on), or §7.7 (CoreDHCP not listening on the right interface) |
| iPXE gets a `172.16.0.2xx` address | A bootloop lease. The MAC is unknown to SMD (§8), or the coresmd cache is broken (the certificate gotcha in Step 7.10) |
| iPXE errors fetching the boot script | BSS is down, or the MAC has no payload (§11) |
| `bootscript : 127 bytes`, then a sleep and a retry, for ever | BSS has **no boot parameters** for that MAC. This is the retry loop working as designed, and §9's checkpoint shows the same thing. Check that Step 11.2's `bss boot params set` covered this MAC |
| iPXE errors fetching the kernel (`403`) | The `boot-images` bucket isn't public-read (Step 10.3) |
| Talos stays in **maintenance mode** | The `talos.config` URL is unreachable or wrong. Check §10's `206` checkpoint, then §11's boot script checkpoint |
| `no disks matched the expression` | §10.6's `diskSelector` found nothing of 10 GB or more. Check the flavor really gave this node a root disk. Then loosen the selector and publish again |
| Talos stuck at `downloading installer` | NAT and forwarding (§7.12), or DNS (§10.6). This is the most common failure |
| A blank console, with no output at all | The wrong `console=` for the platform. It must be `ttyS0,115200` on x86_64 (§11). Fix the payload and run `bss boot params set` again |
| **The node installs, then network-boots and installs again, for ever** | `wipe` isn't `true` in §10.6, so the iPXE EFI partition survived the install. Fix the patch, publish again (§10.7), then `openstack server rebuild` the node |
| `talosctl version` shows only a Client | The node's API isn't up. Check the console log first. Then check the node really rebooted from disk |
| `talosctl bootstrap` → `etcd is already bootstrapped` | It ran twice. That is harmless if the cluster is healthy. Check with `talosctl health` |
| `talosctl health` hangs, or fails discovering nodes | By default, the health check needs `discovery.talos.dev` over the internet. Use the `--server=false` form in Step 12.4. The cluster itself is probably fine |
| `talosctl` → `error constructing client: failed to determine endpoints`, even with `-n 172.16.0.1` | `TALOSCONFIG` is unset. `-n` names the node to *act on*. The endpoint to *connect to* comes from the talosconfig file, which `talosctl` can't find. See Step 12.3 |
| `kubectl` → `The connection to the server localhost:8080 was refused` | `KUBECONFIG` is unset. It has the same cause, and the two go together. Step 12.3's `~/och-head-talos-env.sh` fixes both for good. Exporting one of them doesn't |
| `talosctl` → `certificate signed by unknown authority`, or connection refused on port 50000 | The wrong `talosconfig`, or `TALOSCONFIG` isn't exported in *this* shell. Run `echo $TALOSCONFIG` first |
| Controller-manager or scheduler `RESTARTS` still **climbing** hours after bootstrap | This isn't the bootstrap crash loop the checkpoint describes. Run `talosctl -n 172.16.0.1 logs kube-scheduler`. The usual cause is the API server restarting, or the node running out of memory |
| Workers never appear in `kubectl get nodes` | They can't reach `https://172.16.0.1:6443`. Check the worker got its address from SMD, and that `grep endpoint worker.yaml` points at `172.16.0.1` |
| `kubectl` → `x509: certificate is valid for …, not 172.16.0.1` | §10.6's `certSANs` patch didn't apply. Patch again, publish again, and rebuild the node |

Next: [§13 — Kubernetes Cluster Foundations](13-cluster-foundations.md)
