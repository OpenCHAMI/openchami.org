---
title: "§1 — Introduction: what we're building and why"
description: "What OpenCHAMI is, how a node boots through it, and the three decisions that shape the rest of this tutorial."
slug: "01-introduction"
date: 2026-10-21
lastmod: 2026-10-21
weight: 10
toc: true
draft: false
---
> ⏱ **About 15 minutes** · reading only · creates nothing
>
> - **What this chapter is for.** It explains what OpenCHAMI is and how a node boots. You finish knowing the three decisions that shape the rest of the tutorial.
>
> - **What you will learn.** What each OpenCHAMI service does, the chain a node follows from power-on to a running OS, and why a cloud changes three parts of it.
>
> - **Don't skip it.** You will have to re-make all three decisions on real hardware. Later chapters refer back to them by number.

---

## What OpenCHAMI is

**OpenCHAMI** (Open Composable Heterogeneous Adaptive Management Infrastructure) is an open-source toolkit for provisioning and booting HPC (high-performance computing) clusters. Instead of one monolithic cluster manager, it is built as a set of small, cooperating services that run in containers on a management ("head") node. The compute nodes have no operating system installed beforehand: they network-boot a shared image at power-on and configure themselves from a metadata server.

OpenCHAMI was founded by Los Alamos National Laboratory (LANL), the National Energy Research Scientific Computing Center (NERSC), the Swiss National Supercomputing Centre (CSCS), Hewlett Packard Enterprise (HPE) and the University of Bristol. It is heading towards being an established Linux Foundation project.

**What it does.** OpenCHAMI takes a rack of powered-off machines and turns them into a booted, inventoried, network-configured cluster. It tracks every node in an inventory, answers DHCP requests, and serves each node its kernel, initramfs (initial RAM filesystem) and configuration. On physical hardware, it discovers nodes by querying each machine's BMC (baseboard management controller) over Redfish, the standard server-management API.

**What it does not do.** OpenCHAMI is not a container platform or a workload scheduler. It provisions the machines that a scheduler then runs on — Slurm on a traditional HPC cluster, or Kubernetes in this tutorial.

**Where it comes from.** OpenCHAMI descends from the system-management software of Cray's Shasta platform (now part of HPE), which is why a few services and settings still carry Cray-era names (§7). What OpenCHAMI changes is the packaging: each service is small, exposes its own API, and can be swapped out independently. The entire control plane installs on a single head node from one RPM (Red Hat Package Manager) release package, so it fits just as easily on a single cloud VM as on a bare-metal server.

**Why that matters here.** Because the services are small and API-driven, the OpenCHAMI half of this tutorial (§§7–12) is identical to what you would run on physical hardware. Only the underlying infrastructure (the substrate) changes, which brings us to the three design decisions below.

For the full background, read the [OpenCHAMI documentation](https://openchami.org/docs/). The [upstream tutorial](https://openchami.org/docs/tutorial/) builds the same control plane on local VMs or bare metal, and the [OpenCHAMI blog](https://openchami.org/blog/) covers the individual services in depth.

---

## OpenCHAMI services

OpenCHAMI consists of a set of _services_. You'll meet these in §7:

| Service | Job |
|---|---|
| **SMD** (State Management Database) | Inventory database: which nodes exist, their MACs, IPs, groups |
| **BSS** (Boot Script Service) | Hands each node its boot script (kernel, initial RAM disk, kernel args) |
| **CoreSMD** (CoreDHCP + CoreDNS plugins) | DHCP leases and DNS names *derived from SMD*, plus TFTP (Trivial File Transfer Protocol) for PXE (Preboot Execution Environment) network boot |
| **cloud-init Server** | Per-node configuration served at boot |
| **Magellan** | Discovers real hardware by asking BMCs over Redfish |
| step-ca, haproxy, postgres, OpenID Connect (OIDC) via hydra/opaal | Certificates, API gateway, storage, auth tokens |

The core design principle is that **SMD is the single source of truth**. Everything else — DHCP leases, DNS records, boot scripts and node configuration — is *derived from SMD on demand*. Once you add a node to SMD, the rest of the stack automatically knows about it.

Magellan is the only service we don't use in this tutorial, because cloud instances don't have BMCs to scan (Decision 3 below).

---

## Control plane and worker plane

Nodes in the cluster are split into two planes: the _Control Plane_ and the _Worker Plane_ (also called the _Data Plane_ or _Compute Plane_):

- **Control plane / substrate** — the head node and the two networks running the OpenCHAMI services. This layer *does the provisioning*. The *substrate* is the underlying platform (OpenStack in §§5–6, or physical hardware in a machine room), while the *control plane* is the OpenCHAMI software running on top of it.

- **Worker plane / bare metal** — the compute nodes that *get provisioned* and run your workloads. Here they are Nova instances (OpenStack virtual machines, §9); on bare metal they are physical servers.

The dividing line is **who provisions whom**. OpenStack stands up the head node and networks, and OpenCHAMI then provisions the worker nodes (§§7–12).

⚠ **Do not confuse the two uses of "control plane".** From §12 onward, you will also work with the **Kubernetes** control plane running on the Talos node `och-cp1`. OpenCHAMI's control plane provisions the machines; the Kubernetes control plane schedules containers on them. Whenever it could be ambiguous, we write "OpenCHAMI control plane" or "Kubernetes control plane" in full.

---

## How a node boots (the chain we'll build)

![A node's boot, from power-on to a Kubernetes cluster, in eight steps. Step one, power on and network-boot, is the only step that has to be faked on a cloud: OpenStack has no boot-from-network option, so §9 makes iPXE the node's root disk. Steps two to six are identical to what happens on a real HPC cluster and are unmodified OpenCHAMI: CoreDHCP looks the node's MAC up in SMD and leases it the IP SMD holds (§7, §8); the firmware or iPXE asks BSS for this node's boot script (§11); it downloads the Talos kernel and initramfs from the head node's S3 store (§10); Talos boots into RAM and enters maintenance mode (§12); and it fetches its machine config from the talos.config URL on its kernel command line (§10, §11). Steps seven and eight are Talos's own, after OpenCHAMI has handed over: Talos pulls its installer, writes itself to disk and reboots, then joins or forms a Kubernetes cluster (§12).](diagrams/01-boot-chain.svg)

<details>
<summary>ASCII version</summary>

```
power on → firmware network-boots                                    (§9)
        → DHCP: CoreDHCP looks the MAC up in SMD, leases its IP      (§7, §8)
        → the firmware / iPXE asks BSS for this node's boot script    (§11)
        → downloads Talos kernel + initramfs from the S3 store        (§10)
        → Talos boots into RAM, enters maintenance mode               (§12)
        → fetches its machine config from the `talos.config` URL      (§10, §11)
        → pulls its installer, writes itself to disk, reboots         (§12)
        → joins/forms a Kubernetes cluster                            (§12)
```

</details>

Steps 2 to 6 are *identical* to what happens on a physical HPC cluster. Only step 1 ("power on and network-boot") has to be adapted for the cloud, which is Decision 2 below.

---

## Decision 1 — one instance per node, no nesting

There are two ways to model a cluster inside OpenStack, though on most production clouds only one of them is available.

**The nested way.** You can launch one large OpenStack instance, install libvirt/KVM (Kernel-based Virtual Machine) inside it, and run the head node and compute nodes as nested VMs. This is how HPE's [vTDS](https://github.com/Cray-HPE/vtds-core) (virtual Test and Development System) works, as presented by Stig Telfer (StackHPC) at the OpenCHAMI Developer Summit. Because you control the virtual hardware inside that outer VM, PXE booting and Redfish emulation are straightforward.

However, this approach requires **nested virtualisation** (`/dev/kvm` inside the guest), which **many production OpenStack clouds disable** for operational and security reasons. Because a regular tenant cannot turn it on, this tutorial uses a flat layout instead:

**The flat way — what this tutorial does.** Every node is its own Nova instance on a shared Neutron network. The head node is one instance, and each compute node is a separate instance, with no nested virtualisation required.

![Two ways to model a cluster inside an OpenStack project, side by side. On the left, the nested way, which is what HPE's vTDS does: one large OpenStack instance runs Ubuntu with libvirt and KVM, and the management node and compute nodes are VMs inside it. That gives full control of the virtual hardware, so PXE and Redfish emulation are easy, but it needs /dev/kvm inside the guest — nested virtualisation — which many production clouds switch off. On the right, the flat way, which this tutorial uses: every node is its own Nova instance — och-head, och-cp1, och-w1 and och-w2 — all siblings on one Neutron network, och-prov. There is no libvirt anywhere and nothing needs /dev/kvm inside a guest. It is also closer to real hardware, where each node is a separate machine on a shared provisioning network; what it gives up is control of the virtual firmware, which is decision 2.](diagrams/01-nested-vs-flat.svg)

<details>
<summary>ASCII version</summary>

```
    the nested way (vTDS)                    the flat way (this tutorial)
    — needs nested virt —                    — needs nothing special —

    ┌─ OpenStack instance ────────┐          ┌─ instance ─┐  ┌─ instance ─┐
    │  Ubuntu + libvirt/KVM       │          │  och-head   │  │  och-cp1    │
    │  ┌────────┐  ┌───────────┐  │          └────────────┘  └────────────┘
    │  │ mgmt   │  │ compute-1 │  │          ┌─ instance ─┐  ┌─ instance ─┐
    │  │ VM     │  │ VM        │  │          │  och-w1     │  │  och-w2     │
    │  └────────┘  └───────────┘  │          └────────────┘  └────────────┘
    └─────────────────────────────┘          all siblings on one Neutron wire
```

</details>

The flat model is also **closer to real hardware**, where each node is a separate machine on a shared provisioning network. What we give up is direct control over the virtual firmware, which leads to Decision 2.

🔀 **Most of this tutorial stays the same on real hardware.** §§5–6 create the virtual networks and head node, and §9 sets up network booting. On physical servers, cabling and BMCs handle those jobs, while the OpenCHAMI configuration in §§7–12 stays the same.

---

## Decision 2 — "network boot" on a cloud means putting iPXE on the node's root disk

OpenStack has no "boot from network" button. Nova always boots an instance from an image or a volume, with no equivalent of a physical server's "PXE first" BIOS setting.

📌 This limitation is built into Nova's source code (verified 4 Aug 2026). The internal class Nova uses to configure guest NICs (network interface cards) has no boot-order field, and only accepts `hd`, `cdrom` or `fd` as boot devices. Because this is hardcoded below the API, no API microversion, image property or policy setting can override it.

**What we do about it.** `boot.ipxe.org` publishes `ipxe.usb`, a bootable *disk* image of the open-source iPXE network bootloader that includes both BIOS and UEFI (Unified Extensible Firmware Interface, `EFI/BOOT/BOOTX64.EFI`) bootloaders. We upload it to Glance (OpenStack's image service) and attach it as each node's **root disk**. Nova happily boots the disk, iPXE starts up, and every step from that point on is standard OpenCHAMI ([§9](09-ochami-node-ipxe-boot.md)).

**Does the node then reinstall itself on every boot?** No. When Talos installs, it writes itself to that same root disk and overwrites the iPXE bootloader. On every subsequent reboot, the node boots straight into Talos — matching how a physical server behaves when set to boot from disk first and network second.

| | Cost |
|---|---|
| Extra OpenStack resources | None — no Cinder (block storage) volume, no second image, no boot-order API |
| Extra permissions | None — no special policy, nothing to ask your administrator for, no microversion |
| Firmware support needed | BIOS **or** UEFI, from the same 8 MB file |
| What you give up | The ability to network-boot a node *without* wiping its disk. Re-provisioning uses `openstack server rebuild`, just like OVB (OpenStack Virtual Baremetal) |

### On real hardware, all of this is one Redfish call

On a physical server, you tell the BMC to "set boot device to PXE, then reset" over Redfish. Because a cloud instance has no BMC, the iPXE root disk stands in for that operation:

| What you want | This tutorial's command | On real hardware (Redfish, to the node's BMC) |
|---|---|---|
| Network-boot next | *Nothing* — the node PXEs whenever its disk is not yet Talos | `BootSourceOverrideTarget = Pxe` then `Reset` |
| Re-provision from scratch | `openstack server rebuild --image och-ipxe-disk och-cp1` | `BootSourceOverrideTarget = Pxe` then `Reset` |
| Boot from disk | *Nothing* — Talos overwrote iPXE when it installed | `BootSourceOverrideTarget = Hdd` then `Reset` |
| Power on / off / cycle | `openstack server start` / `stop` / `reboot` | `Reset` with `On`/`ForceOff`/`ForceRestart` |

⚠ **The one thing you cannot do is network-boot a node without wiping its disk.** While that can be handy for diagnostics on physical hardware, this tutorial never needs it.

One consequence you will meet in §10:

- **Talos must select its install disk by size, not by device name.** §10 matches the root disk by size rather than hardcoding `/dev/vda`. If Talos installed onto a secondary disk by mistake, the iPXE bootloader on the root disk would remain intact and the node would reinstall itself in an endless loop.

---

## Decision 3 — tell SMD about the nodes, rather than discover them over Redfish

On physical hardware, Magellan scans the management network, queries each server's BMC over Redfish, and writes the discovered inventory into SMD. Because Nova instances have no BMCs, there is nothing for Magellan to query.

While we could run a virtual BMC service like `sushy-emulator` to translate Redfish calls into OpenStack API calls, we skip it here to keep the setup simple. Instead, we define each node's MAC, IP and xname (its Cray-style hierarchical name, §8) up front in a single node map, apply those values to the Neutron ports (§5), and load them directly into SMD (§8).

Doing this by hand also makes it clear what Redfish discovery normally does behind the scenes. The static inventory file in §8 contains the exact records Magellan would have written to SMD, while `openstack server start` and `stop` stand in for Redfish power commands. On physical hardware, you swap both out for Redfish and nothing downstream of SMD changes.

---

## What else changes from real hardware

The remaining differences are minor:

| | Real hardware | This tutorial |
|---|---|---|
| Node MACs | Burned into each NIC | Chosen by us and pinned onto **Neutron ports** (OpenStack's virtual network ports, §5) |
| Node IPs on the wire | CoreDHCP only | CoreDHCP only. Neutron's built-in DHCP must be **disabled** along with its anti-spoofing rules, or CoreDHCP's replies will be silently dropped (§5) |
| Power control | A BMC, over Redfish | `openstack server start` / `stop` |
| Blast radius | Dedicated hardware | **Often a cloud shared with other tenants** |

The last row is the most important. On dedicated hardware, a mistake only affects your own lab. On a shared cloud, your instances share hypervisors and networks with other users. Every resource in this tutorial uses an `och-` prefix so that §20 can remove them cleanly without touching anything else.

---

## Why Talos, and why Kubernetes at all

Inference Tech Watch's bare-metal cluster will be used mainly to test and benchmark LLM (large language model) **inference** across different accelerators. While traditional OpenCHAMI clusters usually run Slurm (the standard HPC workload manager), we chose Kubernetes because it is what AI engineers commonly use in the cloud and what most inference frameworks are built for.

Our target stack runs a bare-metal Kubernetes control plane with hardware device plugins for NVIDIA, AMD and Intel Gaudi accelerators, and uses KServe, KubeRay and vLLM to serve models. That means our compute nodes need to run Kubernetes, and OpenCHAMI needs to install it on them.

**Talos Linux** is an operating system built exclusively to be a Kubernetes node. It has no shell, no SSH, no package manager and no console login; you administer it entirely through an API using `talosctl`. Because nothing on the node can be modified by hand, nodes stay identical to one another — the same reason HPC clusters traditionally boot stateless, diskless images. Talos can also boot directly from a kernel and initramfs served over the network, which fits right into OpenCHAMI's boot pipeline.

Talos differs in a few important ways from the stateless Rocky Linux image used in the [upstream OpenCHAMI tutorial](https://openchami.org/docs/tutorial/):

| Rocky diskless image | Talos |
|---|---|
| Built with OpenCHAMI `image-builder` into a SquashFS | Prebuilt `vmlinuz` + `initramfs.xz`, downloaded directly — **no image build needed** |
| Stateless, rebuilt in RAM on every boot | **Installs to disk** on first boot and boots from disk thereafter |
| Configured by cloud-init | Configured by a declarative **machine config** fetched via a kernel argument |
| Console login, SSH, `dnf`, a shell | None of those — managed purely via `talosctl` and `kubectl` |
| Needs nothing beyond the head node | **Needs internet access** to pull its installer and Kubernetes container images (§7.12 configures the head node as a network address translation (NAT) router) |

What stays the same is the OpenCHAMI plumbing: SMD remains the single source of truth, and **BSS still serves each MAC address a kernel, an initramfs and a kernel command line**.

---

## Where this is going

The end goal is an experimental rig where you can plug in new accelerator hardware, tweak the software stack, and measure performance across different inference engines and schedulers. §§13–18 build the Kubernetes and inference software stack, and §18 walks through what changes when physical accelerators arrive.

Next: [§2 — The OpenStack CLI](02-openstack-cli.md)
