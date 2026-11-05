---
title: "§10 — Talos Assets and Machine Config"
description: "Put the Talos kernel, its initramfs and two machine configs in a public-read bucket, where a booting node can fetch them."
slug: "10-talos-assets-and-config"
date: 2026-10-21
lastmod: 2026-10-21
weight: 100
toc: true
draft: false
---
> ⏱ **About 20 minutes** · on the head node · puts the Talos boot files and both machine configs in the head node's object store
>
> - **What this chapter is for.** You give the nodes something to boot. You finish with the Talos kernel, its initramfs and two machine configs in a public-read bucket, where a booting node can fetch them.
>
> - **What you will learn.** Why Talos needs no image build and no cloud-init, what a machine config is, and which two settings decide whether a node installs once or loops for ever.
>
> - **Don't skip it.** §11 points every node's boot at these files. Without them, iPXE gets an HTTP error and stops.

---

## Introduction

### There is no image to build

Talos publishes a ready-made kernel and initramfs for each architecture. The initramfs *is* the whole operating system, and it can't be changed once booted. So this chapter downloads two files and puts them where booting nodes can fetch them. That place is the head node's object store from §7.5.

🔀 **Deviation: no image build and no cloud-init.** The upstream OpenCHAMI tutorial builds a Rocky compute image at this point, with `image-builder`. It pulls packages from `dnf` repositories into a SquashFS, which takes 30–60 minutes. It then configures each node with cloud-init. Talos needs neither.

### The machine config replaces cloud-init

A Talos node is configured by one declarative YAML file, its machine config. `talosctl gen config` writes three files:

- **`controlplane.yaml`**, for the node that runs the Kubernetes control plane.

- **`worker.yaml`**, for the nodes that run workloads.

- **`talosconfig`**, your own *client* credentials for talking to the cluster.

A node fetches its config at boot, from the URL in its `talos.config` kernel argument. §11 puts that argument into each node's BSS (Boot Script Service) payload.

### Everything here is x86_64

The OpenStack instances are x86_64, so the boot files are `amd64` and the serial console is `ttyS0`. Most server hardware is the same. An arm64 machine would need `arm64` files and a `ttyAMA0` console instead.

⚠ **These two values are the most common cause of a node that boots to a blank console.** With the wrong ones, the files still download and serve without complaint. The kernel then writes to a serial port that isn't there. Both live in `och-vars-env.sh`, as `OCH_ARCH` and `OCH_CONSOLE`. They are tutorial constants rather than answers from §3, so change them only if your nodes aren't x86_64.

### What you will do

- **Load your variables, then get `talosctl` and `kubectl`** (Step 10.1). Both tools run on the head node, the only machine that can reach the nodes.

- **Set up the S3 clients** (Step 10.2). Two command-line tools, pointed at the head node's object store.

- **Make a public-read bucket** (Step 10.3). A booting node has no credentials, so it has to read anonymously.

- **Download the Talos files and upload them** (Step 10.4).

- **Generate the machine configs** (Step 10.5).

- **Patch them** (Step 10.6). Three small patches set the install disk, DNS and certificate names.

- **Publish the configs** (Step 10.7), into the same bucket as the boot files.

- **Check a node could fetch everything** (the checkpoint), and read back the two settings that matter most.

📌 The Talos documentation goes into more detail:

- [Talos releases on GitHub](https://github.com/siderolabs/talos/releases), where Steps 10.1 and 10.4 download from.

- [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory), for building Talos with extra drivers. You need it in §18.

- [The machine config reference](https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config), for every field the patches in Step 10.6 set.

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/), for the image build and cloud-init that this chapter replaces.

---

## Step 10.1 — Get `talosctl` and `kubectl` on the head

First, load your variables from `och-head-env.sh` and verify that all seven values are set. An empty variable in a heredoc produces a config file that looks plausible at a glance but fails to boot:

```
head$ source ~/och-head-env.sh
head$ echo "${OCH_ARCH} ${OCH_OBJ} ${OCH_TALOS_VERSION} ${OCH_CONSOLE} ${OCH_CP_IP}"
amd64 172.16.0.254:7070 v1.13.0 ttyS0,115200 172.16.0.1

head$ echo "${OCH_CLUSTER_FQDN} ${OCH_HEAD_PROV_IP}"
demo.openchami.cluster 172.16.0.254
```

The second pair is easy to overlook, and fails quietly. `OCH_CLUSTER_FQDN` (the cluster's fully qualified domain name) builds the S3 client config in Step 10.2. `OCH_HEAD_PROV_IP` becomes a certificate name in Step 10.6. If it is empty, the config still validates, but you can't reach the Talos API.

`OCH_TALOS_VERSION` is `v1.13.0`, the latest stable v1.13.x. If §7's `.bashrc` line is in place, the `source` does nothing new. Run it anyway, because the `echo` is the part that matters.

Now install `talosctl`. It is the *only* way to manage a Talos node, because there is no SSH, no console login and no shell:

```
head$ curl -sL https://github.com/siderolabs/talos/releases/download/${OCH_TALOS_VERSION}/talosctl-linux-${OCH_ARCH} \
        -o /tmp/talosctl && sudo install -m 0755 /tmp/talosctl /usr/local/bin/talosctl
head$ talosctl version --client
```

Get `kubectl` too, for §12 onwards:

```
head$ curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/${OCH_ARCH}/kubectl" \
        -o /tmp/kubectl && sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
head$ kubectl version --client
```

📌 Why on the head node, not the devbox? The nodes serve the Talos API (port 50000) and the Kubernetes API (port 6443) on the provisioning network. Nothing outside has a route to that network, so the head node is the only machine that can reach them. §13 shows how to tunnel through the head node if you want `kubectl` on your laptop.

---

## Step 10.2 — S3 client credentials

The Versity gateway created S3 (the Amazon object-storage API) credentials in §7.5. Load them into your shell and write the two client configs:

```
head$ sudo dnf install -y epel-release && sudo dnf install -y s3cmd awscli
head$ source <(sudo cat /etc/versitygw/secrets.env)
head$ cat > ~/.s3cfg << EOF
host_base = ${OCH_CLUSTER_FQDN}:7070
host_bucket = ${OCH_CLUSTER_FQDN}:7070
bucket_location = us-east-1
use_https = False
access_key = ${ROOT_ACCESS_KEY}
secret_key = ${ROOT_SECRET_KEY}
signature_v2 = False
EOF
head$ aws configure set aws_access_key_id "${ROOT_ACCESS_KEY}"
head$ aws configure set aws_secret_access_key "${ROOT_SECRET_KEY}"
head$ aws configure set region us-east-1
```

EPEL (Extra Packages for Enterprise Linux) comes first, because that is where `s3cmd` lives. You need the `aws` tool for exactly one ACL (access control list) operation in Step 10.3. Versity's ACL format doesn't work with `s3cmd setacl`, which is a known quirk in the upstream documentation.

---

## Step 10.3 — The `boot-images` bucket, public-read

```
head$ s3cmd mb s3://boot-images
head$ s3cmd setownership s3://boot-images BucketOwnerPreferred
head$ aws s3api put-bucket-acl --bucket boot-images --acl public-read \
        --endpoint-url http://localhost:7070
head$ cat > /opt/workdir/s3-public-read-boot.json << 'EOF'
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":"*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::boot-images/*"]
    }
  ]
}
EOF
head$ s3cmd setpolicy /opt/workdir/s3-public-read-boot.json s3://boot-images \
        --host=${OCH_CLUSTER_FQDN}:7070 --host-bucket=${OCH_CLUSTER_FQDN}:7070
```

A booting node can only read anonymously. It fetches its kernel over plain HTTP, by IP address. At that point in the boot it has no credentials and no DNS, so public-read is the only setting that works.

⚠ **This is a real exposure, and it is acceptable only here.** Anyone on the provisioning network can read this bucket, and Step 10.7 puts *cluster secrets* in it. That network is isolated and holds only our machines, so nobody else can read them. On real hardware, don't do this. The ⚠ in Step 10.6 gives the alternatives.

---

## Step 10.4 — Download the Talos assets and publish them

```
head$ curl -sL https://github.com/siderolabs/talos/releases/download/${OCH_TALOS_VERSION}/vmlinuz-${OCH_ARCH} \
        -o /tmp/vmlinuz-${OCH_ARCH}
head$ curl -sL https://github.com/siderolabs/talos/releases/download/${OCH_TALOS_VERSION}/initramfs-${OCH_ARCH}.xz \
        -o /tmp/initramfs-${OCH_ARCH}.xz
head$ s3cmd put /tmp/vmlinuz-${OCH_ARCH}      s3://boot-images/talos/vmlinuz-${OCH_ARCH}
head$ s3cmd put /tmp/initramfs-${OCH_ARCH}.xz s3://boot-images/talos/initramfs-${OCH_ARCH}.xz
```

📌 Image Factory is another source for these two files, not a replacement for this step. [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory) decides *what is in* the image. The object store decides *where it is served from*. A Factory **schematic** is the Talos base, plus system extensions such as `iscsi-tools`, GPU drivers or `qemu-guest-agent`, plus extra kernel arguments.

When §18 adds accelerator drivers, you build a schematic and download *its* files instead of the GitHub ones. They are at `https://factory.talos.dev/image/<schematic-id>/${OCH_TALOS_VERSION}/kernel-${OCH_ARCH}` and `.../initramfs-${OCH_ARCH}.xz`. The plain schematic, with no extensions, is `376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba`. Then `s3cmd put` them exactly as above.

Nodes can't fetch from Factory directly. iPXE asks CoreDNS for names, and CoreDNS answers only cluster names (§7.8). Its TLS (Transport Layer Security) support is also too limited to talk to Factory's server. So the head node fetches from Factory, and serves the files to the nodes over plain HTTP. That is also why §7.8 says not to add a `forward` to CoreDNS.

---

## Step 10.5 — Generate the machine config

The Kubernetes API endpoint is `och-cp1`'s address from SMD (State Management Database), on port 6443:

```
head$ mkdir -p ~/talos && cd ~/talos
head$ talosctl gen config ochami-talos https://${OCH_CP_IP}:6443 \
        --install-image ghcr.io/siderolabs/installer:${OCH_TALOS_VERSION}
generating PKI and tokens
Created /home/rocky/talos/controlplane.yaml
Created /home/rocky/talos/worker.yaml
Created /home/rocky/talos/talosconfig
```

PKI (public key infrastructure) is the set of certificates and keys the cluster uses.

🔀 **Deviation: no `--install-disk`.** The usual approach is `--install-disk /dev/vda`. Our nodes have exactly one disk, so a fixed name would probably work. But that disk is the one running iPXE (§9). Getting it wrong doesn't fail loudly. It leaves the node booting iPXE for ever.

So Step 10.6 describes the disk with a *selector* instead, and says explicitly that it must be wiped. `gen config` still writes a default `disk: /dev/sda` into the output. That is harmless, and the checkpoint explains why.

---

## Step 10.6 — Patch the config: disk selection, DNS, and the console

There are three patches. Write them all, then apply them together.

The first patch selects the disk, and wipes it. The wipe is the part that matters:

```
head$ cat > ~/talos/install-patch.yaml << 'EOF'
machine:
  install:
    # One disk, 30 GB, and it is the disk currently holding iPXE (§9).
    # Match on size rather than /dev/vda so this survives a bus change.
    diskSelector:
      size: '>= 10GB'
    # MUST be true. This is what erases the iPXE bootloader and ends the
    # network-boot loop. Talos defaults it to true; we set it anyway,
    # because the whole design of §9 rests on it.
    wipe: true
EOF
```

🛑 **`wipe: false` here gives you a node that reinstalls itself for ever.** `ipxe.usb` is a *hybrid* image. It has an MBR (master boot record) with SYSLINUX for BIOS, plus a FAT16 partition holding `/EFI/BOOT/BOOTX64.EFI` for UEFI. Without a wipe, that partition can survive next to Talos's own EFI system partition. The firmware then finds the old `BOOTX64.EFI` first and boots iPXE again. iPXE asks BSS, Talos reinstalls, the node reboots, and the loop repeats. §9's "The install removes the trick" is only true *because of this one field*.

`type:` takes a single value, one of `ssd`, `hdd`, `nvme` or `sd`, not an expression. We leave it out on purpose. A virtio disk's reported type isn't worth depending on when size alone picks the right disk.

The second patch sets the nameservers. Nodes get DNS server `172.16.0.254` from CoreDHCP. But CoreDNS answers only cluster names (§7.8). It won't resolve `ghcr.io` or `registry.k8s.io`, which Talos must reach to pull its installer and the Kubernetes images. So pin public resolvers, reached through the head node's NAT from §7.12:

```
head$ cat > ~/talos/dns-patch.yaml << 'EOF'
machine:
  network:
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
EOF
```

The third patch lets the head node reach the APIs by IP address. It adds two certificate SANs (subject alternative names). There are no kernel arguments here. §11's `console=` and `talos.platform=metal` apply to the boot that BSS serves. The installed system's command line is fixed, as the console section after Step 10.7 explains.

```
head$ cat > ~/talos/extra-patch.yaml << EOF
machine:
  # Let the head node (and only it) reach the Talos API by IP without a
  # certificate name mismatch.
  certSANs:
    - ${OCH_CP_IP}
    - ${OCH_HEAD_PROV_IP}
cluster:
  apiServer:
    certSANs:
      - ${OCH_CP_IP}
      - ${OCH_HEAD_PROV_IP}
EOF
```

Apply all three to both role configs. `--patch` can be repeated, so this is two commands:

```
head$ talosctl machineconfig patch controlplane.yaml \
        --patch @install-patch.yaml --patch @dns-patch.yaml --patch @extra-patch.yaml \
        -o controlplane.yaml.tmp && mv controlplane.yaml.tmp controlplane.yaml

head$ talosctl machineconfig patch worker.yaml \
        --patch @install-patch.yaml --patch @dns-patch.yaml --patch @extra-patch.yaml \
        -o worker.yaml.tmp && mv worker.yaml.tmp worker.yaml
```

Writing to a `.tmp` file and then moving it avoids emptying the file being read.

⚠ **Use YAML patches, not JSON6902 patches (`[{"op":…}]`).** Talos v1.13 writes a machine config with several YAML documents in one file. JSON6902 patches don't support that, and `talosctl` stops with *"JSON6902 patches are not supported for multi-document machine configuration"*. The YAML fragments above are strategic-merge patches, which apply to the matching document.

🛑 **These patches apply once, to a freshly generated config.** Applying `install-patch.yaml` again, to a config that already has it, fails:

```
merge field v1alpha1.InstallDiskSelector.Size: merge field
v1alpha1.InstallDiskSizeMatcher.condition: merge not possible,
left >= 10GB is not settable
```

Talos can read `diskSelector.size`, but it cannot merge a new value onto an existing one. If you need to change a setting later, either **write a new patch containing only the field you are changing** or delete the three generated files and run Step 10.5 again from scratch—do not re-apply the original patches.

⚠ **Generating from scratch creates a new cluster CA (certificate authority).** That invalidates your existing `talosconfig` and any nodes already installed. Re-generating is free before §12, but once nodes are running, a single-field patch is the only safe route.

⚠ **These files contain cluster secrets.** `controlplane.yaml` holds the cluster CA's **private key** and the bootstrap secrets. `talosconfig` is an admin client certificate. Step 10.7 serves the role configs over *public-read* HTTP, so that nodes can fetch them at boot. That is acceptable on this isolated network and **wrong in production**. On real hardware, do one of these instead:

- **Serve each node its config from an endpoint that checks who is asking.**

- **Leave out `talos.config`**, and push each config with `talosctl apply-config` to nodes waiting in maintenance mode.

Never commit these files. The tutorial's `.gitignore` lists all three by name.

---

## Step 10.7 — Publish the machine configs

Nodes fetch their config from the HTTP URL in the `talos.config` kernel argument. So the two role configs go into the same public-read bucket:

```
head$ s3cmd put controlplane.yaml s3://boot-images/talos/controlplane.yaml
head$ s3cmd put worker.yaml       s3://boot-images/talos/worker.yaml
```

### An installed node has no serial console, and you cannot patch one on

🛑 **Expect `openstack console log show` to stop updating the moment Talos installs.** It freezes at `kexec_core: Starting new kernel`, for good. The node is fine, and `talosctl` answers normally. Know this before §12, so it doesn't surprise you while you debug something else.

The installed system's kernel command line is fixed. §11's `console=ttyS0,115200` belongs to the boot that **BSS serves**. Once Talos installs, the node boots a UKI (unified kernel image) with its command line built in: `talos.platform=metal console=tty0 …`. Nothing of ours survives into it.

`machine.install.extraKernelArgs` won't change that. On UEFI x86_64 and arm64, Talos installs **systemd-boot**, and systemd-boot ignores that field. In Sidero's words, "kernel arguments are embedded in the UKI and cannot be modified without upgrading the UKI" ([Sidero](https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/bare-metal-platforms/bootloader), [talos#10339](https://github.com/siderolabs/talos/issues/10339)). Leave `grubUseUKICmdline: true` as `gen config` wrote it. Setting `extraKernelArgs` alongside it fails validation with *"install.extraKernelArgs and install.grubUseUKICmdline can't be used together"*.

An Image Factory schematic would work. Give it `customization.extraKernelArgs: [console=ttyS0,115200]`, and use it as `machine.install.image`. Step 10.4 explains where Factory fits, and §18 needs a schematic anyway.

📌 You lose less than it sounds. The console still covers the *network* boot: iPXE, DHCP, BSS, the kernel download and the install. That is where almost every failure in this tutorial happens, and §11's `console=` still applies there. What goes dark is an installed node, and that is exactly when `talosctl` works. The gap is a node that installs and then fails to come up.

---

## ✅ Checkpoint

First, all four files are present, and anonymous reads work the way a node makes them. This is a 1-byte range request, which should return `206 Partial Content`:

```
head$ for f in vmlinuz-${OCH_ARCH} initramfs-${OCH_ARCH}.xz controlplane.yaml worker.yaml; do
        curl -s -o /dev/null -r 0-0 -w "%{http_code}  http://${OCH_OBJ}/boot-images/talos/${f}\n" \
          "http://${OCH_OBJ}/boot-images/talos/${f}";
      done
206  http://172.16.0.254:7070/boot-images/talos/vmlinuz-amd64
206  http://172.16.0.254:7070/boot-images/talos/initramfs-amd64.xz
206  http://172.16.0.254:7070/boot-images/talos/controlplane.yaml
206  http://172.16.0.254:7070/boot-images/talos/worker.yaml
```

A `403` here means Step 10.3's public-read policy didn't take. Every node would then stop with an HTTP error from iPXE.

Next, the configs are valid:

```
head$ talosctl validate --config controlplane.yaml --mode metal
controlplane.yaml is valid for metal mode

head$ talosctl validate --config worker.yaml --mode metal
worker.yaml is valid for metal mode
```

`--mode metal` is right even though these are cloud instances: as far as Talos knows, it was network-booted onto bare metal, and §11 passes `talos.platform=metal` to match.

Then the endpoint points at the control-plane node:

```
head$ grep -m1 endpoint controlplane.yaml
```

It should print `https://172.16.0.1:6443`, the SMD address of `och-cp1`. The head node's address here would be wrong.

Last, the install settings came through:

```
head$ grep -A2 -B1 'diskSelector\|wipe:' controlplane.yaml
        disk: /dev/sda
        diskSelector:
            size: '>= 10GB'
        image: ghcr.io/siderolabs/installer:v1.13.0
        wipe: true
        grubUseUKICmdline: true
```

Confirm that `wipe: true` is present before moving on. Without it, the node boots, installs, and reboots in an endless loop.

`disk: /dev/sda` is wrong, and it is ignored. `talosctl gen config` writes that default even though we passed no `--install-disk`. Our nodes have a *virtio* disk at `/dev/vda`. It doesn't matter, because the installer uses the selector whenever there is one, and never looks at `disk`. You can see this in the Talos installer source, [`v1alpha1_sequencer_tasks.go`](https://github.com/siderolabs/talos/blob/v1.13.0/internal/app/machined/pkg/runtime/v1alpha1/v1alpha1_sequencer_tasks.go#L1524).

Using `diskSelector` has two helpful consequences in §12:

- **A selector that matches nothing fails loudly**, with `no disks matched the expression`. It doesn't quietly fall back to `/dev/sda`.

- **The installer logs the disk it chose**, after `using disk match expression:`. §12's console shows it.

📌 `size: '>= 10GB'` is shorthand, and the installer prints what it expands to. This was captured from `och-cp1` on 7 Aug 2026:

```
[talos] task install (1/1): using disk match expression: disk.size >= 10000000000u && disk.transport != "" && !disk.readonly && !disk.cdrom
[talos] task install (1/1): installing Talos to disk /dev/vda
```

The installer automatically adds three safeguards—excluding read-only devices, CD-ROMs, and devices without a storage transport—so the size shorthand is safe on its own.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `curl` returns `403` or `AccessDenied` instead of `206` | The bucket isn't public-read. Run Step 10.3 again, including the `aws s3api put-bucket-acl` line |
| `s3cmd` fails with a signature error | The host in `~/.s3cfg` doesn't match how you are connecting. It must be `${OCH_CLUSTER_FQDN}:7070`, and that name must resolve on the head node (§7.2's `/etc/hosts` line) |
| `talosctl validate` errors on `install` | The disk selector syntax changes a little between Talos minor versions. Check the [config reference](https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config) for your `OCH_TALOS_VERSION`. `type` in particular takes one value (`ssd`, `hdd`, `nvme` or `sd`), not an expression |
| The node reinstalls on every reboot (§12) | `wipe` isn't `true`. The iPXE partition survived the install, and the firmware still finds it. Fix the patch, publish again, and `openstack server rebuild` the node |
| `JSON6902 patches are not supported…` | You used an `[{"op":…}]` patch. Use the YAML form in Step 10.6 |
| `talosctl machineconfig patch` empties the file | You sent the output to the file being read. Use the `-o … .tmp && mv` form |
| iPXE error `0x3e11618e` (DNS name does not exist) or `0x410de18f` (server sent a fatal TLS alert) | BSS points straight at `factory.talos.dev`. iPXE can't resolve it through CoreDNS, and can't negotiate TLS with it. Download from Factory onto the head node, and serve the files from S3 as in Step 10.4 |
| Not sure the endpoint is right | `grep -m1 endpoint controlplane.yaml` must show `https://172.16.0.1:6443`. That is the SMD address of `och-cp1`, not the head node |

Next: [§11 — Boot Parameters](11-boot-parameters.md)
