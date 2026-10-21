---
title: "§3 — The OpenStack Project"
description: "You record the details of your OpenStack project in one shell file, which every later chapter reads."
slug: "03-openstack-project"
date: 2026-10-21
lastmod: 2026-10-21
weight: 30
toc: true
draft: false
---
> ⏱ **About 25 minutes** · on the devbox · creates nothing in the cloud, unless you create the three flavors yourself
>
> - **What this chapter is for.** You record the details of your OpenStack project in one shell file, which every later chapter reads.
>
> - **What you will learn.** What to check in a project before you build in it: its quota, images, flavors and external network, and the address you connect from.
>
> - **Don't skip it.** Every later chapter uses the values you record here. Step 3.7 also decides who can reach the head node over SSH.

---

## Introduction

### Project values

Every OpenStack project is configured slightly differently. Image names, flavors, networks and regions vary from one cloud to the next — and even between projects on the same cloud.

Rather than hardcoding those names, every command from §5 onwards reads them from `OCH_*` shell variables. In this chapter, you will look up your project's values and record them in `~/och/och-vars-env.sh`. Your shell loads that file on login so every command sees the same settings.

📌 Why shell scripts? Instead of using a full infrastructure-as-code (IaC) tool like OpenTofu or Ansible, we use a few small shell scripts to manage our environment variables. That keeps the focus on the OpenStack and OpenCHAMI commands themselves.

### What you will do

- **Set up `~/och`** (Step 3.1). Copy three template shell files onto the devbox and configure your shell to load them on login.

- **Inspect the project and check your quota** (Steps 3.2 and 3.3). Confirm that the project is clean and has enough capacity for four instances.

- **Choose an image for the head node** (Step 3.4). Select a Rocky Linux 9 image for the OpenCHAMI head node and check whether it boots with BIOS or UEFI (Unified Extensible Firmware Interface).

- **Choose three flavors** (Step 3.5). Pick existing flavors from your cloud, create your own, or ask your cloud administrator to create them.

- **Record the external network** (Step 3.6). Note the network that provides the head node's floating IP.

- **Record the address you connect from** (Step 3.7). Lock down SSH access to the head node so it only accepts connections from your address.

- **Verify nothing is missing** (Step 3.8). Run `och_check` to confirm all placeholders have been filled in.

📌 The OpenStack documentation goes into more detail if anything on your cloud looks different:

- [Image commands](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/image-v2.html) and [useful image properties](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html), including `hw_firmware_type`.

- [Flavors](https://docs.openstack.org/nova/latest/user/flavors.html), and [managing flavors](https://docs.openstack.org/nova/latest/admin/flavors.html) if you create your own.

- [Quota commands](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/quota.html).

- [OpenStack networking](https://docs.openstack.org/neutron/latest/admin/intro-os-networking.html), for external networks and floating IPs.

- [Security group rule commands](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/security-group-rule.html), for the SSH rule §5.5 builds from your address.

### The three shell files

Your `.bashrc` loads `och-env.sh`, which in turn sources two files alongside it:

- `och-vars-env.sh` — holds your project's configuration values.

- `och-helpers-env.sh` — defines the `och_*` helper functions.

The filename tells you how each script is used: files ending in `-env.sh` are **sourced** into your current shell, while others (such as `och-status.sh`) are **run** as standalone scripts. Files starting with `och-` live on the devbox, and files starting with `och-head-` live on the head node (§7.1).

---

## Step 3.1 — Set up `~/och`

Download the three templates into `~/och` and load them. They are published with this guide, under `https://openchami.org/docs/guides/openstack-talos/templates/`:

```
devbox$ mkdir -p ~/och && cd ~/och
devbox$ OCH_TPL=https://openchami.org/docs/guides/openstack-talos/templates
devbox$ curl -fsSL $OCH_TPL/och-env.sh         -o ~/och/och-env.sh
devbox$ curl -fsSL $OCH_TPL/och-vars-env.sh    -o ~/och/och-vars-env.sh
devbox$ curl -fsSL $OCH_TPL/och-helpers-env.sh -o ~/och/och-helpers-env.sh
devbox$ source ~/och/och-env.sh
```

Then configure your shell to load them automatically on login:

```
devbox$ echo '[ -f ~/och/och-env.sh ] && . ~/och/och-env.sh' >> ~/.bashrc
```

📌 This is the only line the tutorial adds to your devbox `.bashrc`. Later helpers sit alongside these files rather than adding more lines to `.bashrc`. The `[ -f … ] &&` check matters because `.bashrc` also runs for non-interactive sessions like `scp`, where any stray output corrupts the transfer and fails with `protocol error`.

🛑 **`och-vars-env.sh` is yours; the other two belong to the tutorial.** Once you start filling in `och-vars-env.sh`, **never overwrite it with the template again**, or you will lose the values you recorded in this chapter. The other two files hold no custom values and can be re-copied at any time.

Right after the first `source`, most `OCH_*` variables still hold `<PLACEHOLDER>` strings. As you work through the rest of this chapter, you will replace each placeholder with the real value from your cloud.

---

## Step 3.2 — Look at what is already in the project

Your project should be empty, or nearly so:

```
devbox$ openstack server list
devbox$ openstack network list
devbox$ openstack port list
devbox$ openstack volume list
devbox$ openstack security group list
devbox$ openstack keypair list
devbox$ openstack floating ip list
```

`openstack network list` won't be empty because it lists every network visible to your project, including shared and external networks. To see which networks belong to your project, compare the `Project` column against your project ID:

```
devbox$ openstack token issue -c project_id -f value        # your project ID
devbox$ openstack network list --long -c Name -c Project -c Shared -c 'Router Type'
```

The external network usually belongs to an admin project and shows `Shared: True` and `Router Type: External`. You will attach a router to it in §5.1.

⚠ **If the project already contains servers, ports or volumes you didn't create, check with your team before continuing.** Someone else may be sharing the project. Everything this tutorial creates starts with `och-`, making our resources easy to tell apart.

---

## Step 3.3 — Check your quota

```
devbox$ openstack quota show -f table
```

Compare your project's limits against what this tutorial uses. If you plan to add more workers later, the right-hand column is a comfortable target:

| Resource | This tutorial needs | Comfortable |
|---|---|---|
| Instances | 4 (head + cp1 + 2 workers) | Up to 8 |
| vCPU (virtual CPU) | 22 (head 4, cp1 4, workers 2×8… trim to 2×4 if tight) | ~40 |
| RAM | 40 GB (head 8, cp1 8, workers 2×12) | 100 GB+ |
| Disk (local/root) | ~150 GB | 200 GB+ |
| Networks / subnets / ports | 2 / 2 / ~8 | — |
| Security groups | 2 | — |
| Floating IPs | 1 | 1 |

If your quota is tight, §6 and §9 show where you can scale down — starting with the worker nodes rather than the head node. Avoid shrinking the head node's disk, as it stores the S3 boot artifacts and container images.

---

## Step 3.4 — Choose the head node's image, and note its firmware

```
devbox$ openstack image list --status active | grep -i -E 'rocky|ubuntu'
```

Pick a Rocky Linux 9 x86_64 image from the list (such as `Rocky-9.6`), inspect its details, and save its name in `och-vars-env.sh` as `OCH_HEAD_IMAGE`:

```
devbox$ openstack image show Rocky-9.6 \
          -c name -c id -c disk_format -c min_disk -c min_ram -c properties
devbox$ sed -i "s|<ROCKY9_IMAGE_NAME_OR_UUID>|Rocky-9.6|" ~/och/och-vars-env.sh    # then re-source
```

⚠ **If `image show` fails with `More than one Image exists with the name …`, use the image's UUID instead.** Glance (OpenStack's image service) allows multiple images to share a name, which would also cause `server create` to fail in §6.4. Inspect the matching images and pick the UUID of the newest official one:

```
devbox$ openstack image list --name 'Rocky-9.6' -f value -c ID -c Name -c Status
devbox$ for i in $(openstack image list --name 'Rocky-9.6' -f value -c ID); do
    echo "=== $i ==="
    openstack image show $i -c name -c visibility -c owner -c created_at \
      -c min_disk -c properties -f yaml
  done
devbox$ sed -i "s|<ROCKY9_IMAGE_NAME_OR_UUID>|<THE_UUID_YOU_CHOSE>|" ~/och/och-vars-env.sh
```

Using a UUID also guarantees that `OCH_HEAD_IMAGE` always points to the exact same image, even if a newer image with the same name is uploaded later.

Next, check `hw_firmware_type` in the `properties` field. This determines how your cloud boots instances, which §9 uses when preparing the iPXE (network boot loader) image:

| `hw_firmware_type` | Firmware | §9 needs |
|---|---|---|
| Absent, or `bios` | SeaBIOS (legacy) | `ipxe.iso` — legacy BIOS iPXE |
| `uefi` | OVMF/edk2 (UEFI) | `ipxe.efi` wrapped in an ESP (EFI system partition) image |

Record whichever firmware type applies (`#` is used as the `sed` delimiter here because the placeholder contains `|`):

```
devbox$ sed -i 's#<bios|uefi>#bios#' ~/och/och-vars-env.sh            # or uefi
```

If `properties` doesn't mention `hw_firmware_type`, check with your cloud administrator.

---

## Step 3.5 — Choose the flavors

A flavor defines an instance's vCPU, RAM and root disk size. List the flavors available on your cloud:

```
devbox$ openstack flavor list
devbox$ openstack flavor show <FLAVOR> -c name -c vcpus -c ram -c disk -c properties
```

This tutorial uses **three** flavors matched to each role: the head node needs disk space for images, the Kubernetes control plane is lightweight, and the workers need RAM for model inference. Adjust these sizes to fit your quota and available flavors:

| Flavor | vCPU | RAM | Disk | Used by |
|---|---|---|---|---|
| `ochami-lab-head` | 4 | 16 GB | **60 GB** | The OpenCHAMI head (§6) |
| `ochami-lab-cp` | 4 | 16 GB | 30 GB | Talos control plane (§9) |
| `ochami-lab-worker` | 8 | 64 GB | 30 GB | Talos workers (§9, §16) |

If your cloud already offers flavors close to these sizes, use them and skip ahead to the `sed` commands below. Otherwise, create them if your account has permission:

```
devbox$ openstack flavor create ochami-lab-head   --vcpus 4 --ram 16384 --disk 60 --private --project ochami-lab
devbox$ openstack flavor create ochami-lab-cp     --vcpus 4 --ram 16384 --disk 30 --private --project ochami-lab
devbox$ openstack flavor create ochami-lab-worker --vcpus 8 --ram 65536 --disk 30 --private --project ochami-lab
```

If `flavor create` returns a `403` error, your account isn't permitted to create flavors. Pick the closest existing flavors from `openstack flavor list`, or ask your administrator to create the three above.

⚠ **Don't skimp on the head node's disk.** It stores the S3 bucket for the Talos kernel and initramfs (initial RAM file system), plus a local OCI (Open Container Initiative) registry and roughly 18 container images. A 30 GB root disk can fill up during §7; if your largest available flavor has a small root disk, §6.7 shows how to attach a Cinder volume for `/data`.

⚠ **The worker flavor sets your inference speed in §16.** Because CPU inference in vLLM is primarily bound by memory bandwidth and core count, give the workers as much CPU and RAM as your quota permits.

⚠ **Always pass `--private` and `--project` together.** Creating a `--private` flavor without `--project` leaves it invisible to everyone, including your own project. Because flavor names are global across the cloud even for private flavors, we prefix ours with `ochami-lab-`.

Save the three flavor names you chose into `och-vars-env.sh`:

```
devbox$ sed -i "s|<FLAVOR_HEAD>|ochami-lab-head|"     ~/och/och-vars-env.sh
devbox$ sed -i "s|<FLAVOR_CP>|ochami-lab-cp|"         ~/och/och-vars-env.sh
devbox$ sed -i "s|<FLAVOR_WORKER>|ochami-lab-worker|" ~/och/och-vars-env.sh
```

---

## Step 3.6 — Record the external network

Look up the external network that will supply the head node's floating IP:

```
devbox$ openstack network list --external
devbox$ sed -i "s|<EXT_NET>|external|" ~/och/och-vars-env.sh          # the NAME from that listing
```

Replace `external` with the exact `Name` from your output. Leaving `<EXT_NET>` unset will cause router creation in §5.1 to fail with `No Network found for <EXT_NET>`.

---

## Step 3.7 — Record the address you connect from

Step 5.5 restricts SSH access on the head node to `OCH_ADMIN_CIDR`, a CIDR (classless inter-domain routing) range. Keep it as narrow as possible — ideally just the `/32` address you connect from. Make sure you record the source address **the head node sees** when you connect, which depends on whether your cloud's floating IPs are public or private:

```
devbox$ openstack subnet list --network ${OCH_EXT_NET} -c Name -c Subnet -f value
```

| If that subnet is | The address you want | Find it with |
|---|---|---|
| **Publicly routable** | Your public internet IP | `curl -s ifconfig.me`, written as a `/32` |
| **Private**, such as `10.x`, `172.16–31.x` or `192.168.x` | The IP assigned by your VPN (virtual private network) or campus network | Your VPN client, or your network administrator |

Save your address or range into `och-vars-env.sh`:

```
devbox$ sed -i "s|<YOUR_ADMIN_CIDR>|198.51.100.49/32|" ~/och/och-vars-env.sh    # your measured address
```

Once you log in to the head node in §6, you can verify the exact source IP `sshd` sees:

```
head$ sudo journalctl -u sshd | grep -i accepted | tail -3
```

🛑 **Never set `OCH_ADMIN_CIDR` to `0.0.0.0/0`.** This security group rule is what protects the head node's SSH port from the wider network.

---

## Step 3.8 — Check nothing is missing

Reload your environment and run `och_check`:

```
devbox$ source ~/och/och-env.sh
devbox$ och_check                    # anything listed is still unanswered
```

🛑 **Don't start §5 until `och_check` reports `✓ No placeholders left in OCH_* variables`.** Any unfilled placeholder will surface later as an error that rarely points back to `och-vars-env.sh`:

| Variable | Set from | Fails at |
|---|---|---|
| `OCH_EXT_NET` | `network list --external` | §5.1 — `No Network found for <EXT_NET>` |
| `OCH_ADMIN_CIDR` | Step 3.7 | §5.5 — `bash: YOUR_ADMIN_CIDR: No such file or directory` |
| `OCH_HEAD_IMAGE` | `image list --status active` | §6.3 — no image of that name |
| `OCH_FIRMWARE` | `hw_firmware_type`, or ask your cloud administrator | §9 — builds the wrong iPXE file; instance fails to boot |
| `OCH_FLAVOR_HEAD` / `_CP` / `_WORKER` | `flavor list` | §6.3, §9.3 — no valid flavor |

Use `och_check` rather than `grep '<' ~/och/och-vars-env.sh`, since the comments in that file also contain `<` characters.

`och_check` is one of several read-only helper functions defined in `och-helpers-env.sh`. Running `och_help` lists them all:

| Function | What it does |
|---|---|
| `och_help` | Lists all helper functions and config file paths |
| `och_env` | Prints every `OCH_*` variable currently set (showing `OS_PASSWORD` only as set/unset) |
| `och_check` | Verifies that no `<PLACEHOLDER>` remains *and* that the OpenStack API responds |
| `och_config` | Shows which config files exist, which cloud is selected, and any `OS_*` variables in your environment |
| `och_whoami` | Shows your active project, user and token expiry |
| `och_clean_os` | Unsets every `OS_*` variable except `OS_CLOUD` |
| `och_nodes` | Prints the node map as a table |
| `och_unload` | Removes all `OCH_*` variables and `och_*` functions from the current shell |

---

## ✅ Checkpoint

```
devbox$ och_check
✓ No placeholders left in OCH_* variables
✓ Authenticated; project_id 3f2a9c1e5b7d4a8e9f0c1b2d3e4f5a6b
```

📌 Before moving on to §5, confirm three things that `och_check` cannot test automatically:

- You have access to the three flavors you selected.

- Whether your head node image uses BIOS or UEFI firmware (§9).

- Your cloud's Neutron (networking service) policy allows MAC-pinned ports and `--disable-port-security` (§5).

Catching a policy restriction now is much easier than debugging it at §12.

---

## Common failures

| Symptom | Cause / fix |
|---|---|
| A command contains a literal `<…>`, e.g. `openstack image show <ROCKY9_IMAGE>` | Expected while working through this chapter — substitute your own value. From §4 onwards, it means a placeholder was missed; run `och_check` |
| `bash: SOMETHING: No such file or directory` from an `openstack` command | A `<SOMETHING>` placeholder was pasted literally, and bash treated `<` as input redirection. Fill in the variable in `och-vars-env.sh`, re-source, and use `${OCH_…}` |
| `No Network found for <EXT_NET>`, or any `not found` naming a `<…>` value | The variable still holds its template placeholder. Complete Step 3.6 and run `source ~/och/och-env.sh` |
| `No image with a name or ID of 'Rocky-9.6' exists` | The image name on your cloud differs. Check `openstack image list --status active` for the exact name |
| `flavor create` returns `403 … os-flavor-manage:create` | Your account cannot create flavors on this cloud. Use existing flavors or ask your administrator to create them |
| Quota shows 0 for instances or cores | The project's quota hasn't been configured yet. Ask your cloud administrator |

Next: [§4 — An OpenStack Primer](04-openstack-primer.md)
