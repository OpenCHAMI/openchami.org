---
title: "§18 — Heterogeneous Hardware"
description: "You see what it takes to add GPUs and other accelerators to this cluster. You finish having rehearsed the scheduling half on the CPU nodes you already have."
slug: "18-heterogeneous-hardware"
date: 2026-10-21
lastmod: 2026-10-21
weight: 180
toc: true
draft: false
---
> ⏱ **About 30 minutes, mostly reading** · a few commands on the head node in Step 18.3 · labels and taints one node, then undoes it
>
> - **What this chapter is for.** You see what it takes to add GPUs and other accelerators to this cluster. You finish having rehearsed the scheduling half on the CPU nodes you already have.
>
> - **What you will learn.** The four mechanisms that make an accelerator usable, why the first one is a boot-image change that OpenCHAMI already handles, and how labels and taints keep workloads in the right place.
>
> - **Skip it if** you have no accelerators planned. Nothing later depends on this chapter. Come back to it when real hardware is on the way.

---

## Introduction

### Real inference clusters mix hardware

An inference cluster often spans several accelerator families at once, especially when evaluating hardware across vendors:

| Family | Typical shape | What it needs from the cluster |
|---|---|---|
| **NVIDIA** | 2–8 datacentre GPUs per node, tens of GB of VRAM each | The `nvidia` Talos extensions, NVIDIA's device plugin, `nvidia.com/gpu` |
| **AMD** | 2–4 Instinct accelerators per node, HBM | The `amdgpu` kernel module, AMD's device plugin, `amd.com/gpu` |
| **Intel Gaudi** | 4× accelerators per node, on-package networking | Habana's driver stack and device plugin, `habana.ai/gaudi` |
| **CPU only** | No accelerator; general compute | Nothing beyond what §§13–16 already installed |

You may end up with several vendors, more than one CPU architecture and more than one interconnect under a single Kubernetes cluster. Rather than focusing on specific cards, this chapter covers the mechanisms: what has to be true of the boot image, the node and the scheduler before an accelerator is usable.

⚠ **Take per-node throughput and cost-per-token figures only from your own measurements.** Published estimates for the same accelerator on the same model vary widely depending on batch size, precision, sequence length and engine version. Use the `tok/s` measurement method from §16 on your own nodes so the numbers are yours.

### This build has no accelerators, so it rehearses the mechanisms

Four mechanisms make an accelerator usable in Kubernetes, each resting on the one below. Although this OpenStack build has no physical accelerators, you can set up and rehearse the mechanisms now so that adding real hardware later is a configuration change rather than a research project.

![Four layers, each resting on the one below. Layer 1, at the bottom, is the image: a Talos Image Factory schematic becomes the kernel and initramfs that BSS serves, so this layer loops back to the Talos assets of section 10 and is the only one OpenCHAMI serves. Layer 2 is drivers: Talos system extensions, baked into that boot image. Layer 3 is advertisement: a device plugin tells Kubernetes, for example, that a node has four nvidia.com/gpu. Layer 4, at the top, is scheduling: Ray resources, node selectors, and taints and tolerations decide which workload lands where. This proof of concept has no accelerators; what it establishes is the mechanisms, so that adding hardware is a configuration change rather than a research project.](diagrams/18-four-mechanisms.svg)

*The four mechanisms, read from the bottom up. Blue is the one layer OpenCHAMI serves.*

<details>
<summary>ASCII version</summary>

```
  4. Scheduling      ← Ray resources, node selectors, taints/tolerations
  3. Advertisement   ← device plugin: "this node has 4 × nvidia.com/gpu"
  2. Drivers         ← Talos system extensions, baked into the boot image
  1. The image       ← Talos Image Factory schematic → the assets BSS serves
```

</details>

Layer 1 is the place to start because it connects directly back to §10.

### What you will do

- **Read how drivers reach a Talos node** (Step 18.1). They come in the boot image, so OpenCHAMI serves them like any other boot file.

- **Read how Kubernetes learns about the hardware** (Step 18.2), through a device plugin.

- **Rehearse labels and taints on your CPU nodes** (Step 18.3). This is the one part you can run today, and its checkpoint shows the constraint taking effect.

- **Read what else changes on real hardware** (Step 18.4).

📌 The Talos and Kubernetes documentation goes into more detail:

- [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory), for building a Talos image with extra drivers.

- [Talos system extensions](https://github.com/siderolabs/extensions), the official list of extensions, including the GPU drivers.

- [Device plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/), how Kubernetes learns about hardware it can't see by itself.

- [Taints and tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/), the mechanism Step 18.3 rehearses.

- [Node Feature Discovery](https://kubernetes-sigs.github.io/node-feature-discovery/), the automatic alternative to labelling nodes by hand.

---

## Step 18.1 — Layer 1–2: Talos system extensions

Talos has no package manager, so you can't install a driver on a running node. Instead, drivers arrive as *system extensions* baked into the boot image. Adding GPU support means changing the image the node network-boots—specifically, what Step 10.4 uploads to S3 and what §11 points BSS (Boot Script Service) at.

This works in your favour: one immutable boot image describes the node's entire software state, and OpenCHAMI already knows how to serve it.

A **schematic** declares what goes into the image:

```yaml
# nvidia-schematic.yaml — do not apply today; this is the §18 shape.
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/nonfree-kmod-nvidia-production   # the kernel module
      - siderolabs/nvidia-container-toolkit-production
  extraKernelArgs:
    - talos.platform=metal
```

Register the schematic with Image Factory to get an ID:

```
head$ curl -X POST --data-binary @nvidia-schematic.yaml https://factory.talos.dev/schematics
{"id":"<SCHEMATIC_ID>"}
```

From there, only the files you fetch in Step 10.4 change:

```
head$ curl -sL "https://factory.talos.dev/image/<SCHEMATIC_ID>/${OCH_TALOS_VERSION}/kernel-amd64" \
        -o /tmp/vmlinuz-nvidia
head$ curl -sL "https://factory.talos.dev/image/<SCHEMATIC_ID>/${OCH_TALOS_VERSION}/initramfs-amd64.xz" \
        -o /tmp/initramfs-nvidia.xz
head$ s3cmd put /tmp/vmlinuz-nvidia     s3://boot-images/talos/vmlinuz-nvidia-amd64
head$ s3cmd put /tmp/initramfs-nvidia.xz s3://boot-images/talos/initramfs-nvidia-amd64.xz
```

The installer image in the machine config must also use the same schematic ID so the extensions survive installation to disk:

```yaml
machine:
  install:
    image: factory.talos.dev/installer/<SCHEMATIC_ID>:v1.13.0
```

⚠ **The installer image and the boot files must come from the same schematic.** If you network-boot a Factory kernel but install the standard installer image, the extensions disappear on the first reboot—which is confusing to debug because the node works until it restarts.

Next, add a BSS payload and OpenCHAMI handles the rest. This is where §8, §11 and this chapter come together: node *groups* in SMD (State Management Database) represent hardware classes, and each class gets its own boot payload.

```
head$ cat << EOF | sudo tee /etc/openchami/data/boot/bss/talos-worker-nvidia.yaml
---
kernel: 'http://${OCH_OBJ}/boot-images/talos/vmlinuz-nvidia-amd64'
initrd: 'http://${OCH_OBJ}/boot-images/talos/initramfs-nvidia-amd64.xz'
params: 'talos.platform=metal slab_nomerge pti=on console=tty0 console=${OCH_CONSOLE} talos.config=http://${OCH_OBJ}/boot-images/talos/worker-nvidia.yaml'
macs:
  - <the accelerator nodes' MACs>
EOF
head$ ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/bss/talos-worker-nvidia.yaml
```

That is all provisioning mixed hardware requires. Each hardware class gets its own boot payload, keyed by MAC address and served by the same BSS. OpenCHAMI itself doesn't change—you just add rows. This is also why setting the `groups:` field in §8 was worthwhile: groups such as `talos-worker-nvidia`, `talos-worker-amd` and `talos-worker-gaudi` are the natural way to target each class.

| Vendor | Talos extension | Notes |
|---|---|---|
| NVIDIA | `nonfree-kmod-nvidia-production` + `nvidia-container-toolkit-production` | The best-supported path. Production and LTS (long-term support) variants exist, so match your kernel |
| AMD | `amdgpu` / ROCm driver support | ROCm's user-space libraries come from the container image, not the extension |
| Intel Gaudi | Vendor stack (`habanalabs`) | **The least-travelled path on Talos.** Check with the vendor and the Talos community that it works, before you commit a Gaudi node to a Talos cluster |

🛑 **Check driver support before the hardware arrives.** A driver that can't be delivered as a Talos extension may require a conventional OS on that node. OpenCHAMI provisions Rocky Linux just as easily, so that is workable, but it changes your cluster design—find out early.

---

## Step 18.2 — Layer 3: device plugins

Having a driver in the kernel isn't enough on its own; Kubernetes also has to be *told* the hardware exists. A **device plugin** handles this. It runs as a DaemonSet (one pod on every matching node) and advertises an extended resource such as `nvidia.com/gpu: 1` so the scheduler can place pods that request it.

| Hardware | Plugin | Advertises |
|---|---|---|
| NVIDIA | NVIDIA GPU Operator, or the standalone `k8s-device-plugin` | `nvidia.com/gpu` |
| AMD | ROCm `k8s-device-plugin` | `amd.com/gpu` |
| Intel Gaudi | Habana device plugin | `habana.ai/gaudi` |

⚠ **On Talos, use the standalone device plugin rather than the GPU Operator's driver mode.** The GPU Operator's default job is compiling and loading drivers on the host. Talos doesn't allow that—and doesn't need it, because the system extension already loaded the driver. Either install the GPU Operator with driver installation *disabled*, or deploy the standalone device plugin DaemonSet.

With Flux, this is just another manifest in `infrastructure/controllers/`, scoped to the nodes that have the hardware:

```yaml
# infrastructure/controllers/nvidia-device-plugin.yaml — the §18 shape
      nodeSelector:
        example.org/accelerator: nvidia-datacentre-gpu
```

---

## Step 18.3 — Layer 4: labels, taints and scheduling

Label each node to describe its hardware. You can set these labels in two ways:

- **The Talos machine config.** Declarative and set per hardware class. Prefer this approach since you already maintain one config per class.

- **The Node Feature Discovery operator.** Automatic, but adds another component to run.

```yaml
machine:
  nodeLabels:
    example.org/accelerator: nvidia-datacentre-gpu
    example.org/accelerator-count: "4"
    example.org/cpu-vendor: amd
    example.org/interconnect: roce
```

Taint the accelerator nodes so CPU-only workloads don't consume them:

```yaml
machine:
  nodeTaints:
    - key: example.org/accelerator
      value: intel-gaudi3
      effect: NoSchedule
```

With that taint in place, only workloads that explicitly tolerate it can land there. Without it, general-purpose pods can fill up your accelerator nodes and leave the cards idle.

You can rehearse all of layer 4 today without physical accelerators. The scheduling mechanism is identical; only the label value is pretend:

```
head$ kubectl get nodes                # och-w1 and och-w2 are nid0002 and nid0003
head$ kubectl label node nid0002 example.org/accelerator=none-cpu-only
head$ kubectl label node nid0003 example.org/accelerator=pretend-gpu
head$ kubectl taint node nid0003 example.org/accelerator=pretend-gpu:NoSchedule
```

⚠ **`kubectl` doesn't use your Nova instance names.** In Kubernetes the nodes are named `nid0001`, `nid0002` and so on, because Talos gets its hostname from CoreDHCP (which reads SMD, as §12's checkpoint showed). Run `kubectl get nodes` and use the names it prints.

Now add a `nodeSelector` and `tolerations` block to §16's `InferenceService` and watch the predictor pod move to `nid0003` (or stay `Pending` if the toleration doesn't match):

```yaml
  predictor:
    nodeSelector:
      example.org/accelerator: pretend-gpu
    tolerations:
      - key: example.org/accelerator
        operator: Equal
        value: pretend-gpu
        effect: NoSchedule
```

✅ **Checkpoint: a scheduling constraint that really takes effect.** First, check where the predictor pod is running:

```
head$ kubectl -n inference get pods -o wide
```

The `NODE` column should show `nid0003`, the tainted node.

Next, change the label on `nid0003` and delete the pod so Kubernetes has to schedule it again:

```
head$ kubectl label node nid0003 example.org/accelerator=none-cpu-only --overwrite
head$ kubectl -n inference delete pod -l serving.kserve.io/inferenceservice=qwen05b
head$ kubectl -n inference get pods
```

The replacement pod should stay `Pending` because no node matches its `nodeSelector` (`kubectl describe pod` will show why in its events). That confirms the scheduling constraint works.

Undo the taint and selector before moving on:

```
head$ kubectl taint node nid0003 example.org/accelerator- 
head$ # then revert the nodeSelector/tolerations commit in Git
```

---

## Step 18.4 — What else changes on real hardware

Beyond those four layers, several parts of a bare-metal build cannot be rehearsed on OpenStack:

| Concern | On real hardware |
|---|---|
| **Discovery** | Magellan, over Redfish, against real BMCs (baseboard management controllers). Not §8's static YAML |
| **BMC credentials** | Real secrets, per chassis, that Magellan and OpenCHAMI need. This is a real design task with nothing equivalent here |
| **Power control** | Redfish on, off and cycle replace `openstack server reboot --hard` and `rebuild`. It is the same idea, with real consequences and real power draw |
| **Firmware** | UEFI settings, boot order, secure boot, and which NIC network-boots. These differ between vendors, and between generations from one vendor. Expect them to take real time |
| **NICs** | A fast fabric (100 GbE and up, RoCEv2 or a vendor interconnect) alongside the management NIC. Which NIC network-boots, and whether the fast fabric is up at provisioning time, are new questions |
| **Storage** | Terabytes of local NVMe per node, and usually a shared array over iSCSI or NFS. local-path (§13.2) still works for caches. Shared model weights want NFS or a CSI (Container Storage Interface) driver. Longhorn or iSCSI on Talos needs the `iscsi-tools` extension, which takes you back to Step 18.1 |
| **The provisioning network** | A real management VLAN on a real switch, where **only CoreDHCP may answer DHCP**. It is the same rule as §5.2, with much higher stakes, and no `--no-dhcp` flag to enforce it |
| **Several control planes** | OpenCHAMI's own contributors run several control planes in VMs, one per developer. The head node here is one such control plane, so that pattern is already half-proven |
| **A second CPU architecture** | `arm64` Talos files, a second set of images, and `OCH_ARCH` in §§10–11 becoming a per-group value rather than a constant |

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| The extensions are present after network boot, then gone after the first reboot | The installer image doesn't match the schematic. Set `machine.install.image` to the Factory installer for the same schematic ID (Step 18.1) |
| The GPU Operator fails trying to build or load a driver | Talos doesn't permit host driver builds. Disable the operator's driver installation, or use the standalone device plugin (Step 18.2) |
| `kubectl label node och-w2 …` says the node isn't found | Kubernetes names nodes `nid000N`, not by their Nova names. Use the names from `kubectl get nodes` |
| The predictor stays `Pending` while the label is still in place | The toleration doesn't match the taint. Check that `key`, `value` and `effect` are exactly the same in both |

---

## What to take from this section

1. **Mixed hardware is a boot-image problem before it is a Kubernetes problem.** The chain from Talos schematic to BSS payload to SMD group (Step 18.1) is the mechanism. OpenCHAMI needs no changes to support it.

2. **You can rehearse layers 3 and 4 today**, with pretend labels and taints, and you should (Step 18.3).

3. **The least-travelled vendor is the open risk.** NVIDIA on Talos is well trodden, AMD less so, and Intel Gaudi least of all. Confirm extension support for your accelerator *before* the hardware joins the cluster.

4. **Capture a CPU baseline now**, with §16's measurement. "N times faster than CPU" means more when you measured the CPU yourself.

Next: [§19 — Troubleshooting](19-troubleshooting.md)
