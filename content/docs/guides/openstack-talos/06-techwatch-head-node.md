---
title: "§6 — The Tech Watch Head Node"
description: "You create the head node, the one machine that runs the whole OpenCHAMI control plane. You finish logged in to the head node, with both of its networks working."
slug: "06-techwatch-head-node"
date: 2026-10-21
lastmod: 2026-10-21
weight: 60
toc: true
draft: false
---
> ⏱ **About 15 minutes, plus a few minutes' first boot** · on the devbox and the head node · creates an SSH key pair, the head node instance and a floating IP, plus a data volume only if you need one
>
> - **What this chapter is for.** You create the head node, the one machine that runs the whole OpenCHAMI control plane. You finish logged in to the head node, with both of its networks working.
>
> - **What you will learn.** How the head node sets itself up on first boot, why you record one interface name, and how to check the path to the head node one hop at a time.
>
> - **Don't skip it.** Every chapter from §7 onwards runs on this machine, and §7 needs the interface name you record in Step 6.6.

---

## Introduction

### The head node is where OpenCHAMI lives

Everything OpenCHAMI does for this cluster runs on a single instance named `och-head`. In §7, you will install OpenCHAMI's services there — roughly a dozen small containers including SMD (State Management Database), BSS (Boot Script Service) and CoreDHCP. When the worker nodes boot, they never talk to OpenStack; they talk solely to `och-head`.

The head node itself is a standard Rocky Linux 9 instance. Because the LLM inference workloads run on the Talos worker nodes later, the head node doesn't need heavy compute resources — just a modest flavor with enough disk space for container images and boot artifacts.

### One instance, two network interfaces

The head node has a NIC (network interface card) on each of the two networks you created in §5. This chapter attaches those pre-created ports to the new instance:

| NIC | Network | Address | Purpose |
|---|---|---|---|
| First | `och-ext` | `192.168.200.x` (DHCP) plus a floating IP | Inbound SSH, outbound internet downloads |
| Second | `och-prov` | `172.16.0.254` (static) | Serves DHCP, TFTP, DNS and boot files to the nodes |

`172.16.0.254` is the key address in the cluster: every OpenCHAMI configuration file in §§7–11 points to it, because to the worker nodes it *is* the head node.

![The path from your laptop to the head node: Lima devbox VM, macOS NAT, the VPN tunnel utun10, the shared external network, och-router and its floating IP, the routed och-ext network, and the och-head instance with its two Neutron ports — one filtered on och-ext, one with port security disabled on the silent och-prov wire.](diagrams/06-head-node-path.svg)

*The network path from the devbox to the head node's two ports (using example addresses from our reference run). [The full network map](diagrams/full-network-map.svg) continues the picture onto the worker nodes.*

### You write one file, and OpenStack does the rest

The head node configures itself on first boot using `cloud-init`, the standard bootstrapping tool built into Linux cloud images. In Step 6.3, you write a single `head-user-data.yaml` file containing your user account, SSH public key, and package list, which OpenStack passes to the instance at first boot.

You don't need to write any network configuration file: OpenStack already knows each port's MAC and IP address from §5 and passes them to `cloud-init` automatically, bringing up the provisioning NIC at `172.16.0.254`.

### One name to write down

In Step 6.6, you will check the Linux interface name of the provisioning NIC (for example, `eth1` or `enp4s0`) and save it to `och-vars-env.sh`. CoreDHCP binds to that interface by name in §7 — and if the name is wrong, CoreDHCP will silently fail to answer DHCP requests.

### What you will do

- **Create an SSH key pair** (Step 6.1). Generate an Ed25519 key pair and upload the public key to Nova.

- **Check the head node's flavor** (Step 6.2). Confirm its CPU, RAM and disk size before launching the instance.

- **Write the cloud-init user-data** (Step 6.3). Configure the `rocky` user, base packages, and permissive SELinux mode.

- **Create the head node** (Step 6.4). Boot `och-head` attached to the two ports from §5.4.

- **Attach a floating IP** (Step 6.5). Give the head node an externally reachable IP address for SSH.

- **Log in to the head node** (Step 6.6). SSH in and record the provisioning interface name for §7.

- **Add disk space, only if you need it** (Step 6.7). Check free space on `/` and attach a Cinder volume only if your flavor's root disk is under 40 GB.

- **Check the whole path** (Step 6.8). Verify each hop from the devbox to the head node.

📌 The OpenStack, cloud-init and OpenCHAMI documentation goes into more detail:

- The CLI commands used here: [keypair](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/keypair.html), [flavor](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/flavor.html), [server](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/server.html), [floating IP](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/floating-ip.html) and [volume](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/volume.html).

- [Flavors](https://docs.openstack.org/nova/latest/user/flavors.html) in the Nova documentation, for Step 6.2.

- [The metadata service](https://docs.openstack.org/nova/latest/user/metadata.html) and [config drives](https://docs.openstack.org/nova/latest/user/config-drive.html), for how Nova delivers configuration data to `cloud-init`.

- [The cloud-init documentation](https://cloudinit.readthedocs.io/en/latest/), for the `#cloud-config` format in Step 6.3.

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/), which sets up the same head node on local VMs or bare metal.

---

## Step 6.1 — Create an SSH key pair

Start in `~/och` with your variables loaded:

```
devbox$ cd ~/och && source ~/och/och-env.sh
```

Generate a dedicated SSH key pair for this lab and upload the public key to Nova:

```
devbox$ ssh-keygen -t ed25519 -N '' -f ~/.ssh/och_ed25519
devbox$ openstack keypair create --public-key ~/.ssh/och_ed25519.pub ${OCH_PREFIX}-key
```

`-N ''` creates the key without a passphrase for convenience in this lab. `openstack keypair create` registers only the *public* key (`och_ed25519.pub`) with Nova.

---

## Step 6.2 — Check the head node's flavor

Before launching the instance, verify that the head node flavor you selected in §3 has the expected CPU, RAM and disk size:

```
devbox$ openstack flavor show ${OCH_FLAVOR_HEAD} -c name -c vcpus -c ram -c disk
+-------+-----------------+
| Field | Value           |
+-------+-----------------+
| name  | ochami-lab-head |
| vcpus | 4               |
| ram   | 16384           |
| disk  | 60              |
+-------+-----------------+
```

Here is how the head node uses those resources:

| Field | Ours | Why |
|---|---|---|
| `vcpus` | **4** | Runs roughly a dozen lightweight containers (§7), plus `talosctl` and `kubectl`. Heavy inference workloads run on the worker nodes |
| `ram` | **16384** MB | Runs Postgres, the OpenCHAMI services, an OCI (Open Container Initiative) registry and VersityGW S3 (8 GB also works, with less headroom) |
| `disk` | **60** GB | Holds the Talos kernel and initramfs, machine configs, and ~18 container images. **Aim for at least 40 GB** (the upstream tutorial's 20 GB suggestion can fill up during §7) |

If your head flavor has **less than 40 GB** of disk, you can still use it — [Step 6.7](#step-67--add-disk-space-only-if-you-need-it) shows how to attach a Cinder volume once the instance is running.

⚠ **Check `min_disk` on the image as well.** Run `openstack image show $OCH_HEAD_IMAGE -c min_disk` — Nova will refuse to boot an image on a flavor whose disk is smaller than the image's `min_disk`.

---

## Step 6.3 — Write the cloud-init user-data

Generate `~/och/head-user-data.yaml`:

```
devbox$ cat > ~/och/head-user-data.yaml << EOF
#cloud-config

# The admin user. 'rocky' is the Rocky cloud image's conventional name and is
# what every 'head\$' command in this tutorial assumes.
users:
  - name: rocky
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat ~/.ssh/och_ed25519.pub)

# SELinux permissive, not disabled: containers and quadlets in §7 hit enough
# labelling friction that enforcing gets in the way during bring-up, but
# permissive still logs what WOULD have been denied - which is the information
# you want when hardening this later for a production cluster.
write_files:
  - path: /etc/selinux/config
    content: |
      SELINUX=permissive
      SELINUXTYPE=targeted

package_update: true
packages:
  - podman
  - jq
  - git
  - tmux
  - bind-utils
  - nftables

runcmd:
  - setenforce 0 || true
EOF
```

Notice that `EOF` is **unquoted** so your shell expands `$(cat ~/.ssh/och_ed25519.pub)` into the file. Verify that your public key was written into the file before continuing:

```
devbox$ grep -c 'ssh-ed25519' ~/och/head-user-data.yaml     # must print 1
```

A template copy is also available at [`templates/head-user-data.yaml`](templates/head-user-data.yaml).

📌 You don't need to write `network-config` or `meta-data` files — OpenStack generates both automatically from the instance's name and attached Neutron ports.

---

## Step 6.4 — Create the head node

```
devbox$ openstack server create ${OCH_PREFIX}-head \
    --image ${OCH_HEAD_IMAGE} \
    --flavor ${OCH_FLAVOR_HEAD} \
    --key-name ${OCH_PREFIX}-key \
    --port ${OCH_PREFIX}-head-ext \
    --port ${OCH_PREFIX}-head-prov \
    --user-data ~/och/head-user-data.yaml \
    --config-drive true \
    --wait
```

Key flags:

- **`--port` twice, in this exact order (rather than `--network`).** Passing the pre-created ports from §5.4 preserves our pinned MACs and the `172.16.0.254` address. **Order matters:** the first `--port` becomes the primary NIC (`eth0`), so putting `och-head-ext` first ensures the default route goes out through the routed external network.

- **`--user-data`** passes the `head-user-data.yaml` file from Step 6.3.

- **`--config-drive true`** attaches a small read-only configuration disk containing the metadata and user-data, so `cloud-init` can configure both NICs reliably without depending on the network metadata service (`169.254.169.254`).

- **`--wait`** waits until the instance reaches `ACTIVE` before returning.

📌 If your cloud requires an explicit availability zone, add `--availability-zone <zone>` here and use the same zone when launching the worker nodes in §9.

---

## Step 6.5 — Attach a floating IP

Allocate a floating IP on the external network, attach it to `och-head`, and save it to `och-vars-env.sh`:

```
devbox$ openstack floating ip create ${OCH_EXT_NET}
devbox$ openstack server add floating ip ${OCH_PREFIX}-head <FLOATING_IP>
devbox$ echo "export OCH_HEAD_FIP=<FLOATING_IP>" >> ~/och/och-vars-env.sh
devbox$ source ~/och/och-env.sh
```

A floating IP is a public address on the external network that Neutron maps to your instance's private `192.168.200.x` address. The head node itself only ever sees its private IP; `och-router` translates between the two so you can SSH in from outside.

Pass the **`floating_ip_address`** value (or its `id`) from `floating ip create` to `server add floating ip`. In the output table, the `name` column simply repeats the IP address. The `status` starts as `DOWN` and changes to `ACTIVE` (with `port_id` and `router_id` filled in) once you attach it.

⚠ **Check whether your floating IP is a public or private address before connecting.** If it is a private address (such as `10.x`), you are reaching the cloud over a VPN (virtual private network) or campus network, and the head node will see your VPN address rather than your public internet IP (§3.7). If `OCH_ADMIN_CIDR` doesn't match the source IP the head node sees, the security group will silently drop your SSH packets and the connection will time out.

---

## Step 6.6 — Log in to the head node

On first boot, `cloud-init` takes a minute or two to resize the root filesystem and install the packages from Step 6.3. You can watch its progress in the console log:

```
devbox$ openstack console log show ${OCH_PREFIX}-head --lines 40
```

Once it is ready, SSH into the head node:

```
devbox$ ssh -i ~/.ssh/och_ed25519 rocky@${OCH_HEAD_FIP}
```

From here on, commands run on the head node use the `head$` prompt.

Next, find the Linux interface name that holds `172.16.0.254`:

```
head$ ip -brief addr | grep 172.16.0.254
eth1             UP             172.16.0.254/24
```

Back on the devbox, save that interface name to `och-vars-env.sh` so §7.7 can bind CoreDHCP to it:

```
devbox$ echo "export OCH_PROV_IF=eth1" >> ~/och/och-vars-env.sh       # use YOUR value
devbox$ source ~/och/och-env.sh
```

⚠ **If the second interface has no IP address**, `cloud-init` did not receive a static network config for it — usually because `och-prov-subnet` still has DHCP enabled (check the §5 checkpoint). Fix the subnet first, and if needed configure the interface manually for this boot:

```
head$ sudo nmcli con add type ethernet ifname eth1 con-name prov \
        ipv4.method manual ipv4.addresses 172.16.0.254/24 ipv6.method disabled
head$ sudo nmcli con up prov
```

---

## Step 6.7 — Add disk space, only if you need it

> ### 🚦 Run one command, then take one of two branches
>
> ```
> head$ df -h /
> ```
>
> | `Avail` | Branch | What you do |
> |---|---|---|
> | **Above 40 GB** | **A — skip** | **Nothing at all.** Go straight to Step 6.8. `/data` will be an ordinary directory that §7.1 creates on the root disk |
> | Below 40 GB | B — add a volume | Follow the steps below |
>
> Branch A is the standard path when using a 60 GB head flavor. **Do not run the commands in Branch B unless you actually attach a second volume**, as adding an `/etc/fstab` entry for a non-existent `/dev/vdb` will prevent the head node from booting.

Most of the disk usage on the head node goes into `/var/lib/containers` (for Podman images) rather than `/data`:

```
head$ sudo du -sh /var/lib/containers /var/lib/versitygw /opt/workdir /data | sort -rh
2.1G	/var/lib/containers      ← the ~18 container images really live here
6.2M	/opt/workdir             ← three downloaded RPMs; scratch
8.0K	/var/lib/versitygw       ← the S3 buckets; §10's Talos artifacts land here
0	/data                    ← nothing but an empty oci/ directory
```

📌 Note that the `versitygw` container mounts `/var/lib/versitygw/data` on the host to `/data` inside the container (`podman inspect versitygw`), which is separate from `/data` on the host.

### Checking your existing disk layout

In Branch A, your root disk (`vda`) was automatically expanded to the flavor's full size by `cloud-init` on first boot:

| | The root disk, `vda` | A data volume, `vdb` |
|---|---|---|
| Created by | The **flavor's `disk` field** at `server create` (Step 6.4) | `openstack volume create`, explicitly |
| Contents | Populated from the Glance image by Nova | Arrives blank (`mkfs` required) |
| Sizing | `cloud-init` grows `/` to fill the flavor's disk on first boot | Matches the `--size` you requested |
| Mounted at | `/` via the image's built-in `/etc/fstab` | Mounted manually at `/var/lib/containers` |
| Lifetime | Deleted automatically when the instance is deleted | **Persists independently** until explicitly deleted |

On a Branch A head node, `lsblk` shows `vda` grown to 60 GB:

```
head$ lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
NAME    SIZE FSTYPE  MOUNTPOINT
sr0     520K iso9660              ← the config drive from §6.4's --config-drive
vda      60G                      ← the flavor's disk
├─vda2  100M vfat    /boot/efi    ← an ESP is present — but see the warning below
├─vda3 1000M xfs     /boot
└─vda4 58.9G xfs     /            ← grown from the image's ~10 GB by cloud-init
```

If `vda` has 40 GB or more available, **skip ahead to Step 6.8**.

⚠ **Seeing `/boot/efi` mounted does not mean the instance booted via UEFI (Unified Extensible Firmware Interface).** Most Rocky cloud images are hybrid images containing both a BIOS bootloader and an ESP (EFI system partition). Unless the Glance image has `hw_firmware_type=uefi` set (§3.4), Nova boots it with legacy BIOS. You can check which firmware is active on the head node with:

```
head$ [ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
BIOS
```

📌 It is completely fine for the head node to boot with BIOS while the Talos worker nodes boot with UEFI in [§9.2](09-ochami-node-ipxe-boot.md#step-92--upload-it-to-glance).

### Branch B — add a Cinder volume

If your root disk has less than 40 GB free, attach a Cinder volume and mount it at `/var/lib/containers` before starting §7. First check whether you already have an unattached `${OCH_PREFIX}-head-data` volume from an earlier run:

```
devbox$ openstack volume list -c Name -c Size -c Status -c "Attached to"
```

- **If `${OCH_PREFIX}-head-data` already exists and is `available`**, reuse it (skip `volume create` and `mkfs.xfs`, since it already has a filesystem).
- **If no matching volume exists**, create one below.
- 🛑 **Never touch an unattached volume with a different name**, as it may belong to someone else sharing the project.

Create and attach the 40 GB volume:

```
devbox$ openstack volume create --size 40 ${OCH_PREFIX}-head-data
devbox$ openstack server add volume ${OCH_PREFIX}-head ${OCH_PREFIX}-head-data
```

Verify on the head node that `/dev/vdb` has appeared before formatting or editing `/etc/fstab`:

```
head$ lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
…
vdb      40G                            ← the volume you just attached: blank, no FSTYPE
```

🛑 **If `vdb` is not listed, stop here** and check `openstack server show ${OCH_PREFIX}-head -c volumes_attached`. Formatting and mounting `/dev/vdb` at `/var/lib/containers`:

```
head$ sudo mkfs.xfs /dev/vdb
head$ echo '/dev/vdb /var/lib/containers xfs defaults,nofail 0 0' | sudo tee -a /etc/fstab
head$ sudo mkdir -p /var/lib/containers && sudo mount /var/lib/containers
head$ df -h /var/lib/containers
```

⚠ **`mkfs.xfs` erases the volume**, so only run it if `FSTYPE` in `lsblk` is blank. The `nofail` option in `/etc/fstab` ensures the head node can still boot even if the volume is detached later.

---

## Step 6.8 — Check the whole path

If SSH ever hangs, checking each hop in order from the devbox pinpoints where the connection stopped:

| # | Hop | Command | What it must show |
|---|---|---|---|
| 1 | The head node instance | `openstack server show ${OCH_PREFIX}-head -c status -c flavor -f value` | `ACTIVE`, and the flavor you intended |
| 2 | The floating IP | `openstack floating ip list -c "Floating IP Address" -c "Fixed IP Address" -c Port` | Your floating IP mapped to `192.168.200.x`, with a port ID |
| 3 | The security group | `openstack security group rule list ${OCH_PREFIX}-sg-head` | Inbound `tcp/22` and `icmp` from **the address the head node sees** |
| 4 | Route & ICMP | `ping -c2 ${OCH_HEAD_FIP}` | Ping replies, confirming hops 1–3 |
| 5 | SSH | `ssh -i ~/.ssh/och_ed25519 rocky@${OCH_HEAD_FIP}` | A shell prompt as `rocky` |
| 6 | Both NICs | `head$ ip -brief addr` | One `192.168.200.x` address and one `172.16.0.254` address |
| 7 | Outbound NAT | `head$ ping -c1 dl.rockylinux.org` | Replies via `och-router`'s SNAT (source NAT) |

### Confirm the address the head node sees

Hop 3 is the most common culprit when SSH times out. While you are logged in, check `sshd`'s log to see the exact client IP address reaching the head node:

```
head$ sudo journalctl -u sshd | grep Accepted | tail -2
Aug 02 17:03:21 och-head sshd[19317]: Accepted publickey for rocky from 198.51.100.49 port 5601 ssh2: ED25519 SHA256:…
```

The IP after `from` must be covered by `OCH_ADMIN_CIDR`. If your VPN reconnects or your DHCP lease changes later on, run `och_vpn` on the devbox to check whether your source IP moved:

```
devbox$ och_vpn
```

If it did, follow §19 to add the new security group rule before removing the old one.

---

## ✅ Checkpoint

Run this final check on the head node before starting §7:

```
head$ cat /etc/rocky-release
Rocky Linux release 9.6 (Blue Onyx)

head$ uname -m
x86_64

head$ ip -brief addr | grep -v -E 'lo|LOOPBACK'
eth0             UP             192.168.200.91/24 fe80::5054:ff:fec0:fe01/64
eth1             UP             172.16.0.254/24 fe80::5054:ff:febe:efff/64

head$ ping -c1 dl.rockylinux.org > /dev/null && echo internet OK
internet OK

head$ getenforce
Permissive

head$ df -h / | tail -1
/dev/vda4        59G  1.7G   58G   3% /
```

*Captured on the reference cloud, 2 Aug 2026. Your interface names and `192.168.200.x` address will vary, while the rest should match.*

What this confirms:

- **Two active NICs with the right IPs** confirm that the ports from §5.4 are attached in the right order (and the IPv6 link-local suffixes `…fec0:fe01` and `…febe:efff` reflect our pinned MACs `52:54:00:c0:fe:01` and `52:54:00:be:ef:ff`).

- **`internet OK`** confirms outbound routing through `och-router` (§5.1).

- **`x86_64`** confirms the guest architecture needed by the packages and boot images in §§7–10.

- **`Permissive`** confirms that `cloud-init` read the config drive and applied `head-user-data.yaml` (Step 6.3).

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `No valid host was found` | The cloud cannot schedule your chosen flavor right now due to quota, host capacity, or flavor properties. Check `openstack quota show` and `openstack flavor show "$OCH_FLAVOR_HEAD" -c properties`, or ask your cloud administrator |
| Instance enters `ERROR`, and `fault` mentions the flavor | The flavor's disk is smaller than the image's `min_disk` (Step 6.2) |
| SSH times out | Wait another minute for `cloud-init` to finish, then check that the floating IP is attached, `och-sg-head` allows your current IP (`openstack security group rule list ${OCH_PREFIX}-sg-head`), and **the security group is attached to `och-head-ext`** (`openstack port show ${OCH_PREFIX}-head-ext -c security_group_ids -f value`, §5.5) |
| SSH times out even though the security group is attached | `OCH_ADMIN_CIDR` does not match the source IP the head node sees (for example, if you used your public IP while connecting over a VPN, or your VPN address changed). See §3.7 and §19 |
| SSH returns `Permission denied (publickey)` | Make sure you are connecting as `rocky` (not `root` or `ubuntu`) and that `grep -c 'ssh-ed25519' ~/och/head-user-data.yaml` returns `1` (Step 6.3) |
| Only one interface has an IP address | `och-prov-subnet` likely has DHCP enabled (§5.2). Fix the subnet, then run the `nmcli` fallback in Step 6.6 |
| `--port` rejected with `Port … is still in use` | The port is still attached to a previous instance. Check `openstack port show <port> -c device_id` |

Next: [§7 — OpenCHAMI Installation](07-ochami-installation.md)
