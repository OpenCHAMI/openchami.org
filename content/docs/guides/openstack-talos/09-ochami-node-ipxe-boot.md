---
title: "§9 — OpenCHAMI Node Boot"
description: "You create the nodes and watch each one network-boot as far as OpenCHAMI. You finish with every node asking BSS what to boot, and getting an answer."
slug: "09-ochami-node-ipxe-boot"
date: 2026-10-21
lastmod: 2026-10-21
weight: 90
toc: true
draft: false
---
> ⏱ **About 20 minutes** · all on the devbox · creates the iPXE boot image and three node instances
>
> - **What this chapter is for.** You create the nodes and watch each one network-boot as far as OpenCHAMI. You finish with every node asking BSS what to boot, and getting an answer.
>
> - **What you will learn.** Why a cloud instance can't network-boot, how an iPXE root disk gets round that, and how to read a node's console to see which earlier chapters worked.
>
> - **Don't skip it.** This is how the nodes get onto OpenCHAMI's boot path at all. It is also the first test of §§5, 7 and 8 together.

---

## Introduction

### A cloud has no network-boot button

A real server can boot from the network. Its firmware knows how to use the network card. At power-on it asks for an address over DHCP, downloads a small bootloader and runs it. The bootloader then asks a server which operating system to boot, downloads it and starts it. Nothing comes off the machine's own disk. Its whole identity arrives over the network.

Nova can't do that first step. It boots an instance from an image or a volume, and there is no way to say "try the network card first". Nova only ever puts *storage* in a guest's boot order. Because this limit is built into how Nova constructs the virtual machine definition below the API, no API version, image property, or policy setting can bypass it. On the reference cloud, the guest firmware has no network-boot support at all.

🔀 **Deviation: this whole chapter.** Upstream OpenCHAMI has no equivalent, because real hardware doesn't need one. It exists only because clouds don't network-boot.

### So iPXE becomes the node's root disk

We stop trying to fetch the bootloader over the network, and hand it to the machine on a disk instead. iPXE is an open-source network-boot program, and it is what OpenCHAMI's boot chain expects to talk to. `ipxe.usb` is the image you would write to a USB stick to make any computer network-boot. We give it to Nova as each node's **root disk**.

The firmware sees an ordinary bootable disk, which Nova is always happy to boot, and runs it. iPXE starts, and from then on everything happens as it would on real hardware. This is decision 2 in [§1](01-introduction.md#decision-2--network-boot-on-a-cloud-means-putting-ipxe-on-the-nodes-root-disk).

Only the first 8 MB is local. Everything else comes over the network:

| Step | Where it comes from | On real hardware |
|---|---|---|
| iPXE itself | **The local disk.** This is the only part we fake | From the network card's boot ROM, over TFTP |
| "Who am I, and what is my address?" | **The network.** CoreDHCP answers with the address SMD holds for this MAC | The same |
| "What should I boot?" | **The network.** BSS answers over HTTP, going by the MAC | The same |
| The kernel and initramfs | **The network.** They come from the head node's S3 store (§10) | The same |
| The machine config | **The network.** A `talos.config` URL in the kernel arguments points at it (§11) | The same |

Strictly speaking, the nodes never PXE-boot, because they load iPXE from a local disk rather than over the network. Once iPXE starts, however, it asks OpenCHAMI who it is and what to boot, just as it would on physical servers. On hardware with real BMCs, you replace this iPXE disk with a single Redfish call ("set the boot device to PXE, then reset").

### The install removes the trick

The "USB stick" is also the disk Talos installs onto. Talos overwrites it, so from the next boot the node starts Talos from its own disk. It never network-boots again unless you ask it to.

Other workarounds—such as booting from a virtual CD-ROM or rescue image—cannot be overwritten by the installer, so they need extra state to keep a node from reinstalling on every power cycle. Because Talos overwrites the root disk directly, no extra state is needed here.

### The chain you are about to build

![Nova only ever assigns a boot index to storage, so it cannot put a NIC in a guest's boot order — and the limitation is in how it generates the guest's XML, below the API, so no microversion or image property reaches it. The way round it is to make iPXE itself the storage device, which takes three commands: download ipxe.usb, an 8 MB hybrid disk image carrying an MBR bootloader for BIOS and EFI/BOOT/BOOTX64.EFI for UEFI (§9.1); upload it to Glance as a private raw image (§9.2); and create each node from that image on its MAC-pinned port (§9.3), which is itself the PXE button. The firmware then boots what looks to it like an ordinary disk, and from that point the six-step chain is unmodified OpenCHAMI: iPXE starts; CoreDHCP answers with the address SMD holds for that MAC and the lease carries the BSS URL; iPXE fetches the boot script BSS holds for that MAC; the Talos kernel and initramfs come from the head node's S3 store and boot into RAM; Talos enters maintenance mode and fetches its machine config from the talos.config kernel argument; and finally Talos selects its install disk by size rather than device name and writes itself to the root disk, overwriting the iPXE bootloader. That last step is what stops the node network-booting again, with no state held anywhere — so there is no way-back command: the next boot is Talos from disk, re-provisioning is openstack server rebuild, and the single capability given up is network-booting a node without destroying its disk. On real hardware all of it is one Redfish call setting BootSourceOverrideTarget to Pxe, followed by a reset.](diagrams/09-node-boot-chain.svg)

*The three commands in this chapter, in amber, and the unchanged OpenCHAMI boot chain they hand over to, in blue. §§10–12 fill in the rest of the chain.*

<details>
<summary>ASCII version</summary>

```
openstack server create --image och-ipxe-disk  och-cp1      ← §9.3  the whole trick
        │
        ▼
  firmware boots the root disk: EFI/BOOT/BOOTX64.EFI = iPXE
        │
        ▼
  iPXE does DHCP on och-prov  ─────────────► CoreDHCP (§7.7) leases 172.16.0.1
        │                                    and points at BSS
        ▼
  iPXE fetches its boot script  ──────────► BSS (§11), keyed on the MAC
        │
        ▼
  downloads Talos vmlinuz + initramfs from S3 (§10), boots them
        │
        ▼
  Talos installs to the node's own disk — overwriting iPXE — and reboots
        │
        ▼
  the node now boots Talos from disk, by itself, for ever            ← §12
```

Everything from the second line down is the same on real hardware. The first line is the whole of the deviation. In §12, the way to network-boot a node again is `openstack server rebuild --image och-ipxe-disk`, which puts the bootloader back by wiping the disk.

</details>

⚠ **There is no "boot from disk again" command at the bottom of that chain.** Because the Talos install overwrites the iPXE bootloader on the root disk, the node boots straight from disk on every subsequent reboot.

### What you will do

- **Get the iPXE disk image** (Step 9.1). You download `ipxe.usb` and check that it can boot under both BIOS and UEFI.

- **Upload it to Glance** (Step 9.2). It becomes a private image, set to boot with UEFI.

- **Create the node instances** (Step 9.3). You make one control-plane node and two workers, each on its port from §5.4. Each one starts network-booting as soon as it exists.

- **Read the console** (the checkpoint). You check how far each node got, and what that proves about the earlier chapters.

📌 The iPXE and OpenStack documentation goes into more detail:

- [iPXE](https://ipxe.org), its [downloads](https://ipxe.org/download) and its [commands](https://ipxe.org/cmd), for reading boot scripts.

- [Useful image properties](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html) in the Glance documentation, for `hw_firmware_type` and `hw_machine_type`.

- The CLI commands used here: [image](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/image-v2.html), [server](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/server.html) and [console log](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/console-log.html).

- [BSS](https://github.com/OpenCHAMI/bss), the service that answers each node's first request for a boot script.

---

## Step 9.1 — Get the iPXE disk image

Start in `~/och`, with your variables loaded:

```
devbox$ cd ~/och && source ~/och/och-env.sh
```

`boot.ipxe.org` publishes two ready-made images. We want **`ipxe.usb`**, which is a bootable *disk* image. The other one, `ipxe.iso`, is a CD image, and it needs a CD-ROM drive we have no way to give the node.

```
devbox$ curl -fLO https://boot.ipxe.org/ipxe.usb
devbox$ ls -l ipxe.usb
-rw-rw-r-- 1 alice alice 8388608 Aug  4 17:50 ipxe.usb
```

Verify that the image contains bootloaders for both BIOS and UEFI:

```
devbox$ file ipxe.usb
ipxe.usb: DOS/MBR boot sector; partition 4 : ID=0x4, active, start-CHS (0x0,1,1),
          end-CHS (0x7,63,32), startsector 32, 16352 sectors

devbox$ strings -a ipxe.usb | grep -E 'BOOTX64|BOOTAA64|LDLINUX'
LDLINUX SYS'
LDLINUX C32'
BOOTAA64EFI
BOOTX64 EFI
```

- **`DOS/MBR boot sector` and `LDLINUX`** are the **BIOS** half: an MBR bootloader and SYSLINUX.

- **`BOOTX64 EFI`** is the **UEFI** half (`\EFI\BOOT\BOOTX64.EFI` inside the FAT partition at sector 32). That is the standard fallback path where UEFI looks on removable media, which is why the guest firmware boots it without extra configuration.

- **`BOOTAA64EFI`** means the same file covers arm64 too, which matters for §18 and for multi-architecture clusters.

📌 The `.usb` extension describes the image's *layout*—a raw disk image with a partition table—rather than a physical USB device.

⚠ **Check what you downloaded, and know that it runs a script.** iPXE publishes no signatures for its ready-made images. `ipxe.usb` also carries its own 120-byte `autoexec.ipxe`. It is harmless: it offers `Ctrl-B` for two seconds, then carries on booting. But it *does* run, and you will see it in the console log later.

That is acceptable for a throwaway cluster on an isolated network. For a production cluster, build iPXE from source and record its checksum.

---

## Step 9.2 — Upload it to Glance

⚠ **Run this once.** Glance lets two images share a name, and then Nova can't work out which one `--image och-ipxe-disk` means in Step 9.3. If you have already created it, skip to the check below rather than creating a second one.

```
devbox$ openstack image create ${OCH_PREFIX}-ipxe-disk \
    --disk-format raw --container-format bare \
    --file ipxe.usb --private \
    --property hw_firmware_type=uefi \
    --property hw_machine_type=q35
```

- **`--disk-format raw`** because it is a disk image, byte for byte. Nova expands it to the flavor's disk size. The extra space is left unpartitioned, and that is where Talos installs.

- **`hw_firmware_type=uefi` is written out, not taken from `$OCH_FIRMWARE`.** That variable records the *head node's* firmware (§6.7), and it says nothing about an image we build ourselves. UEFI is right here because the trick *is* UEFI's removable-media path, `\EFI\BOOT\BOOTX64.EFI`, and because UEFI is what worked on the reference cloud.

- **If your cloud has no UEFI firmware for guests**, `hw_firmware_type=bios` should work with the same file, through its MBR and SYSLINUX half. We haven't tested it, so please record the result if you try it.

- **`hw_machine_type=q35`** is the modern machine type, and the one UEFI expects.

- **`--private`** makes the image visible only to your project. Never use `--public`, which would publish it to everyone on the cloud.

✅ **Check it uploaded:**

```
devbox$ openstack image show ${OCH_PREFIX}-ipxe-disk -c status -c size -c properties -f value
active
8388608
{'hw_firmware_type': 'uefi', 'hw_machine_type': 'q35', ...}
```

---

## Step 9.3 — Create the node instances

First, check the variables, ports, and flavor disk size that this step relies on:

```
devbox$ echo "$OCH_PREFIX | $OCH_FIRMWARE | $OCH_FLAVOR_CP | $OCH_FLAVOR_WORKER"
och | bios | ochami-lab-cp | ochami-lab-worker

devbox$ for i in 1 2 3; do
    openstack port show ${OCH_PREFIX}-node${i}-prov -c name -c status -c device_id -f value
  done
```

```
devbox$ openstack flavor show ${OCH_FLAVOR_WORKER} -c disk -f value
Failed to get access projects list for flavor 'ochami-lab-worker': ForbiddenException: 403 …
30
```

- **Each port should show its name, `DOWN` and an empty `device_id`.** A port with a `device_id` is still attached to something, most likely a leftover test instance. Delete that instance before you go on.

- **The `403` from `flavor show` is noise, and the value still prints.** An ordinary account can read a flavor, but not list which projects it is shared with. So `openstack flavor show` reports that failure, then gives you the fields anyway. The `30` is the answer, and you don't need admin rights for it.

- **`OCH_FIRMWARE` is the *head node's* firmware, not the nodes'.** `bios` here means Glance has no `hw_firmware_type` on the Rocky image, so Nova uses BIOS. Step 9.2 set the node image to UEFI separately, and the two are allowed to differ. §11's `console=` argument uses `OCH_CONSOLE`, which is a different variable.

Now create one instance for each node, on its MAC-pinned port from §5.4. The image is the only unusual thing about these commands. Start with the Kubernetes control-plane node:

```
devbox$ openstack server create ${OCH_PREFIX}-cp1 \
    --image ${OCH_PREFIX}-ipxe-disk \
    --flavor ${OCH_FLAVOR_CP} \
    --port ${OCH_PREFIX}-node1-prov \
    --wait
```

Then the workers, as many as your quota allows. Two is enough to prove that Kubernetes spreads work across nodes. They are written out, rather than looped, so you can see which port each one takes:

```
devbox$ openstack server create ${OCH_PREFIX}-w1 \
    --image ${OCH_PREFIX}-ipxe-disk \
    --flavor ${OCH_FLAVOR_WORKER} \
    --port ${OCH_PREFIX}-node2-prov \
    --wait

devbox$ openstack server create ${OCH_PREFIX}-w2 \
    --image ${OCH_PREFIX}-ipxe-disk \
    --flavor ${OCH_FLAVOR_WORKER} \
    --port ${OCH_PREFIX}-node3-prov \
    --wait
```

⚠ **The port numbers and the node names don't line up, on purpose.** §5.4 created `node1` to `node5` before the roles existed. §8 then assigned the roles, and the control plane took `node1`. So the mapping is:

| Instance | Port | MAC | Address SMD holds |
|---|---|---|---|
| `och-cp1` | `och-node1-prov` | `52:54:00:be:ef:01` | `172.16.0.1` |
| `och-w1` | `och-node2-prov` | `52:54:00:be:ef:02` | `172.16.0.2` |
| `och-w2` | `och-node3-prov` | `52:54:00:be:ef:03` | `172.16.0.3` |

Get this wrong and the node still boots, but in the *other* role. §11 picks the boot script by MAC, not by the name you typed. Nothing tells you until §12, which is why the commands above are spelled out.

📌 **Each node starts network-booting the moment it is created.** Because you create the nodes before §§10 and 11 configure Talos and BSS, they boot into iPXE, ask BSS what to do, receive an empty retry script, and wait. That is harmless and lets the checkpoint below verify the boot chain early. After §11, a hard reboot (`openstack server reboot --hard`) starts the real installation (§12). If you prefer to boot them only once, complete §§10 and 11 first and come back—neither chapter requires the instances to exist yet.

Notice what these instances don't have:

- **No floating IP and no external network.** They sit only on the provisioning network, just like real compute nodes on a management VLAN (virtual LAN). Their only route out is the head node's NAT (§7.12). You reach them through the head node, never directly.

- **No SSH key.** Talos has no SSH.

- **No user-data.** Talos ignores cloud-init completely and fetches its configuration from the `talos.config` kernel argument served by BSS (§11). This keeps OpenCHAMI—rather than Nova's metadata service—as the single source of truth.

⚠ **The flavor sets the disk size, and container images are what fill it.** On the reference cloud, both the worker and the control-plane flavor have 30 GB of disk. Talos itself is small, and the model this tutorial serves is smaller: `Qwen2.5-0.5B-Instruct`, about 1 GB. But each node also holds either the Kubernetes control plane, on `cp1`, or the vLLM CPU image and KServe's initialiser, on the workers. Those are several GB each.

We expect 30 GB per node to be enough for §§9–18 as written. Note that the kubelet starts evicting images well before the disk is full. 30 GB stops being enough if you swap §16's model for a large multi-billion-parameter one, or keep several versions on a node at once. If your flavor is much smaller, or you plan bigger models, use a bigger flavor or attach a data volume.

🛑 **If you do attach a volume, Talos must still install to the *root* disk.** iPXE lives there, and overwriting it is what stops the node network-booting for ever. If Talos installs anywhere else, iPXE survives and wins the next boot. The node then reinstalls on every power cycle. §10.6's `diskSelector` controls this, so check it before the first reboot.

🔀 **Deviation: no disk size and no boot order.** On a hypervisor you run yourself, one command creates a node's disk and sets its boot order to "disk first, then network". Nova offers neither. The root disk comes from the flavor, and the boot order is what this whole chapter works around.

---

## ✅ Checkpoint

First, the instances exist, on the right network:

```
devbox$ openstack server list -c Name -c Status -c Networks
```

`och-head` should be `ACTIVE` on both networks. `och-cp1`, `och-w1` and `och-w2` should be `ACTIVE` on `och-prov` only, at `172.16.0.1`, `.2` and `.3`.

Next, check that the boot chain reached OpenCHAMI. One console log here tests five earlier chapters at once:

```
devbox$ sleep 30 && openstack console log show ${OCH_PREFIX}-cp1 --lines 40
```

```
BdsDxe: loading  Boot0001 "UEFI Misc Device" from PciRoot(0x0)/Pci(0x2,0x2)/Pci(0x0,0x0)
BdsDxe: starting Boot0001 "UEFI Misc Device" from PciRoot(0x0)/Pci(0x2,0x2)/Pci(0x0,0x0)
iPXE initialising devices...
file:autoexec.ipxe... Not found (https://ipxe.org/7f4de18e)
file:/autoexec.ipxe... ok

iPXE 2.0.0+ (ga1992) -- Open Source Network Boot Firmware -- https://ipxe.org
Features: DNS HTTP HTTPS iSCSI TFTP VLAN SRP AoE EFI Menu

net0: 52:54:00:be:ef:01 using virtio-net on 0000:03:00.0 (Ethernet) [open]
Configuring (net0 52:54:00:be:ef:01)...... ok
net0: 172.16.0.1/255.255.255.0 gw 172.16.0.254
Next server: 172.16.0.254
Filename: http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
Root path: 172.16.0.254
Ignoring unsupported root path
http://172.16.0.254:8081/boot/v1/bootscript... ok
bootscript : 127 bytes [script]
```

📌 `Ignoring unsupported root path` isn't an error. CoreDHCP sends DHCP option 17 (`root-path`), which iSCSI clients use. iPXE has no use for a bare IP there, and says so. Every node prints it on every boot, including the ones that work.

| Line | What it proves |
|---|---|
| `starting Boot0001 "UEFI Misc Device"` | The firmware booted `ipxe.usb` as a plain root disk, so Steps 9.1 and 9.2 are right |
| `iPXE 2.0.0+` | iPXE is running, with no rescue image, CD-ROM or Cinder volume |
| `net0: 52:54:00:be:ef:01` | The MAC you pinned in §5.4 is the node's network card |
| `Configuring … ok`, `172.16.0.1` | **CoreDHCP answered**, with the address SMD holds for this MAC. So Neutron's DHCP really is off (§5.2), port security really is off (§5.4), and §8's inventory loaded |
| `Filename: http://172.16.0.254:8081/…` | `coresmd` handed out the BSS URL, not a `172.16.0.2xx` bootloop lease (§7.7) |
| `bootscript … [script]` | **BSS answered** |

If you see that last line, §§5, 7, 8, and 9 are all working together, and §§10–12 should be straightforward.

Then check the two workers, because `server list` can't prove this. The addresses it prints are Neutron's own records. Only the console shows what CoreDHCP actually handed out from SMD:

```
devbox$ openstack console log show ${OCH_PREFIX}-w1 --lines 20 | grep -E 'net0:|Filename'
devbox$ openstack console log show ${OCH_PREFIX}-w2 --lines 20 | grep -E 'net0:|Filename'
```

You want `52:54:00:be:ef:02` paired with `172.16.0.2`, and `…:03` with `172.16.0.3`. If a MAC and IP disagree here, Neutron and SMD have different records for that port. Fix any mismatch now rather than in §12, where it will boot the node into the wrong role.

⚠ **Before §11 the boot can't finish, and what happens instead tells you whether Step 7.9b worked.** BSS has no boot parameters for this MAC yet. So it serves that 127-byte script, which only says "wait, then ask me again". There are two possible endings.

**Expected, with Step 7.9b done.** The node loops quietly, for ever:

```
bootscript : 127 bytes [script]
http://172.16.0.254:8081/boot/v1/bootscript... ok
bootscript : 127 bytes [script]
…
```

The whole 127 bytes is a `sleep` and a `chain` back to the same URL. You can read it yourself with the `curl` in §11's checkpoint.

That is the retry loop working as designed. It costs nothing, and it stops as soon as §11 gives BSS a real payload. §12's hard reboot then picks that up.

**If you skipped Step 7.9b**, the retry URL has no hostname in it, because BSS is advertising the literal text `${SYSTEM_URL}`. The node drops out of iPXE altogether:

```
https:///apis/bss/boot/v1/bootscript... Error 0x3e11618e (https://ipxe.org/3e11618e)
BdsDxe: failed to start Boot0001 … Not Found
Shell>
```

That is the `${SYSTEM_URL}` fault that Step 7.9b fixes. Go back and fix it at [§7.9b](07-ochami-installation.md#step-79b--point-bss-at-an-address-a-node-can-reach), even though §11 replaces this particular script. **The same `chain` line ends every *working* boot script too**, so a node whose real boot fails would have no way back either. Either way, the node waits harmlessly, holding its port.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `No bootable device`, or an `EFI Shell>` prompt with no iPXE banner at all | The firmware wouldn't boot `ipxe.usb`. Check that the image's `hw_firmware_type` suits your cloud. Stricter UEFI firmware may need the image rebuilt with a properly typed EFI system partition |
| Instance `ERROR` with `Invalid disk_format 'raw'` | Some clouds limit which image formats projects may upload. Run `qemu-img convert -f raw -O qcow2 ipxe.usb ipxe.qcow2`, then upload that with `--disk-format qcow2` |
| `No valid host was found` | The cloud can't place this flavor right now. It may be quota, a lack of capacity, or a flavor property no host can satisfy. Try fewer workers, check `openstack quota show`, then ask whoever runs your cloud |
| The console log is empty | The instance stopped before writing anything, or the console device doesn't suit the firmware. Wait 60 seconds, then try again with `--lines 200` |
| iPXE starts, but `Configuring (net0 …)` fails or times out | CoreDHCP isn't answering. Check in this order: is `coresmd-coredhcp` active? Is `enable_dhcp` false on the subnet? Is `port_security_enabled` false on the node's port? Is the MAC in SMD? |
| iPXE gets a `172.16.0.2xx` address | It's a bootloop lease, because SMD doesn't know the MAC. See §8 |
| `https:///apis/bss/…  Error 0x3e11618e` | Expected before §11. Fix it at [Step 7.9b](07-ochami-installation.md#step-79b--point-bss-at-an-address-a-node-can-reach) |
| The node installs Talos, then network-boots and reinstalls for ever | Talos installed to a disk other than the one holding iPXE. Check §10.6's `diskSelector` |
| `openstack server create` rejects `--port` | The port is already attached to something, most likely a leftover test instance. Check with `openstack port show <port> -c device_id` |
| `More than one Image exists with the name 'och-ipxe-disk'` | Step 9.2 was run twice. List the IDs with `openstack image list --private -c ID -c Name`, then `openstack image delete <id>` for the extra one. Use the ID, because the name is ambiguous |
| `Invalid image metadata`, or instance `ERROR`, after setting `hw_firmware_type=uefi` | Your cloud has no UEFI firmware for guests, or limits `hw_machine_type`. Create the image again with `hw_firmware_type=bios` and no `hw_machine_type`. The same `ipxe.usb` boots that way, through its MBR half |

Next: [§10 — Talos assets and machine config](10-talos-assets-and-config.md)
