---
title: "Overview"
description: "Welcome! This is a hands-on tutorial that builds a complete OpenCHAMI-managed cluster inside an OpenStack project."
slug: "00-overview"
date: 2026-10-21
lastmod: 2026-10-21
weight: 5
toc: true
draft: false
---
Welcome! This is a hands-on tutorial that builds a complete **OpenCHAMI**-managed cluster inside an **OpenStack** project. From there, you will network-boot **Talos Linux** nodes to form a **Kubernetes** cluster, and use **FluxCD**, **KServe**, **vLLM** and **KubeRay** to serve an LLM over an OpenAI-compatible API.

Every step gives the **full command or config file**, then explains **what it does and why it is done that way**.

**Who is this for?** Anyone with access to an OpenStack cloud who wants to explore an **OpenCHAMI → Talos → Kubernetes → KServe** stack for LLM inference. No prior knowledge of OpenCHAMI, Talos or Kubernetes is assumed, and §4 provides a short primer if you are new to OpenStack.

### What you will meet, by layer

You will work across three layers of software, **with OpenCHAMI at the heart**. OpenCHAMI provisions and manages the nodes that everything above it runs on.

| Layer | Components | What they do here |
|---|---|---|
| **OpenStack** | **Keystone** (identity), **Nova** (compute instances), **Neutron** (networks and ports), **Glance** (images), Cinder (volumes) | OpenStack's services stand in for bare-metal hardware: instead of physical servers and cables, you use virtual machines and virtual networks for quick experimentation. |
| **OpenCHAMI** | **SMD**, **BSS**, **CoreSMD** (CoreDHCP + CoreDNS), **cloud-init**, Magellan | Manages the cluster's inventory, DHCP, DNS, and the boot scripts each node uses to network-boot — the exact same services you would run on real hardware. |
| **Talos and Kubernetes** | Talos Linux, FluxCD, KServe, vLLM, KubeRay | The node operating system and the inference stack that runs on top of it. |

By the end of the tutorial, you will have configured every layer by hand, including Talos machine configs, GitOps with FluxCD, and CPU-only LLM inference over an OpenAI-compatible API.

---

## About this work — Inference Tech Watch at the University of Bristol

At the [Bristol Centre for Supercomputing](https://www.bristol.ac.uk/research/centres/bristol-supercomputing/) (BriCS) we are starting **Inference Tech Watch**, a project to test and evaluate different accelerators for AI inference. It is the technology-watch strand of Concord-AI, a collaboration between BriCS and France's GENCI.

Evaluating several accelerators side by side means managing a **heterogeneous environment**: CPU-only servers and storage alongside NVIDIA, AMD and Intel Gaudi accelerators. Our solution architecture for this has three abstraction layers built on OpenCHAMI:

- **OpenCHAMI** manages the bare-metal nodes and their devices.
- **Talos Linux** on the worker nodes provides a secure, minimal Kubernetes cluster.
- **Kubernetes** — running KServe, vLLM and KubeRay — serves LLM inference across whatever hardware is available.

**Bare metal is the end goal.** While our physical hardware is being provisioned, we built this OpenStack variant to run CPU-only LLM inference. It is a fast, low-cost way to prototype, learn OpenCHAMI and Kubernetes, and test our setup before moving to bare metal. **This tutorial shares that build.** Nothing in it depends on specialised hardware, so anyone with an OpenStack project can follow along.

---

## What you will build

![Everything lives in one OpenStack project, called ochami-lab throughout. There are two Neutron networks, both created in §5. och-ext has DHCP on and is routed; it carries SSH and downloads. och-prov has no DHCP and no router; it is the provisioning wire. The head node, och-head, is a Rocky 9 instance with two ports, one on each network, created in §6. §7 installs on it the OpenCHAMI control plane (SMD, BSS, CoreSMD and the rest), a Versity S3 store on port 7070 and an OCI registry on port 5000, and turns it into a NAT router from och-prov to och-ext. The Talos nodes — och-cp1, which becomes the Kubernetes control plane, and the workers och-w1 to och-wN — have one port each, on och-prov only, and network-boot Talos in §§9–12. On top of them the inference stack is built in order: Kubernetes foundations in §13, FluxCD in §14, KServe in §15, vLLM in §16 and KubeRay in §17.](diagrams/readme-what-you-will-build.svg)

<details>
<summary>ASCII version</summary>

```
An OpenStack project — called ochami-lab throughout
│
├── och-ext          Neutron network, DHCP on, routed         ← §5  SSH + downloads
├── och-prov         Neutron network, NO DHCP, NO router      ← §5  the provisioning wire
│
├── och-head         Rocky 9 instance, 2 ports                ← §6
│     ├── OpenCHAMI control plane (SMD, BSS, CoreSMD, …)     ← §7
│     ├── Versity S3 :7070 + OCI registry :5000              ← §7
│     └── NAT router  och-prov → och-ext                     ← §7
│
├── och-cp1          network-boots Talos → k8s control plane   ← §§9-12
└── och-w1 … och-wN   network-boot Talos → k8s workers          ← §§9-12
      │
      └── Kubernetes ← §13 ─ FluxCD ← §14 ─ KServe ← §15 ─ vLLM ← §16 ─ KubeRay ← §17
```

</details>

---

## Prerequisites

**You need API access to an OpenStack cloud.** Because authentication setups vary between providers, initial account creation is not covered here — please ask your cloud administrator if you need access.

| You need | Why |
|---|---|
| An **OpenStack project** | Everything is built inside one project, and §20 removes it all cleanly. This tutorial calls its project `ochami-lab` and uses ~4 instances, ~22 vCPU, ~40 GB RAM, ~150 GB disk and 2 networks. Use whatever names and sizes suit your environment — you only need enough capacity to run a small CPU inference model. |
| The **`openstack` CLI**, able to reach and authenticate to that cloud's API | Every OpenStack step runs as an `openstack` CLI command. |
| The **right permissions** | You need permission to create and delete standard project resources: instances, networks, ports, images and flavors. Your cloud must also let you pin a port's MAC address and disable port security on a port (§5 relies on both). |
| A **GitHub repository** you can push to | FluxCD uses GitOps and needs a repository to read your cluster configuration from (§14). |

> **NB: These instructions were developed against an OpenStack cluster at the University of Bristol. We are keen to hear about any differences on other clouds.**

---

## Tutorial Contents

| § | File | What it covers |
|---|---|---|
| 1 | [Introduction — what we're building and why](01-introduction.md) | **OpenCHAMI** · The two planes, the boot chain, and the three decisions that shape this build. |
| 2 | [The OpenStack CLI](02-openstack-cli.md) | Install the CLI, configure it with `openrc.sh` or `clouds.yaml`, issue a token, check endpoints, and create an application credential. |
| 3 | [The OpenStack Project](03-openstack-project.md) | **OpenStack** · Record your project's quota, image, flavors, and external network. |
| 4 | [An OpenStack Primer](04-openstack-primer.md) | **OpenStack** · The core OpenStack resources this tutorial uses: compute, networks, subnets and ports. |
| 5 | [Tech Watch Networking](05-techwatch-networking.md) | **Tech Watch** · The two networks, why the provisioning network must be silent, MAC-pinned ports and port security. |
| 6 | [The Tech Watch Head Node](06-techwatch-head-node.md) | **Tech Watch** · Image, flavor, cloud-init, two ports, floating IP, SSH, and an optional data volume. |
| 7 | [OpenCHAMI Installation](07-ochami-installation.md) | **OpenCHAMI** · Quadlets, S3, registry, CoreDHCP/CoreDNS, certificates, and NAT. |
| 8 | [OpenCHAMI Node Inventory](08-ochami-node-inventory.md) | **OpenCHAMI** · SMD as the source of hardware truth, and keeping each MAC address in sync across three places. |
| 9 | [OpenCHAMI Node Boot](09-ochami-node-ipxe-boot.md) | **OpenCHAMI** / **Talos** · How a cloud instance network-boots by using iPXE as its root disk. |
| 10 | [Talos Assets and Machine Config](10-talos-assets-and-config.md) | **Talos** · Uploading the kernel and initramfs to S3, generating machine configs, and selecting the install disk. |
| 11 | [Boot Parameters](11-boot-parameters.md) | **OpenCHAMI** · Configuring BSS boot scripts for each node role. |
| 12 | [Booting the Talos Cluster](12-boot-the-cluster.md) | **OpenCHAMI** · From network boot to a running Kubernetes cluster. |
| 13 | [Kubernetes Cluster Foundations](13-cluster-foundations.md) | **K8s** · CNI, DNS, storage, metrics, and Gateway API. |
| 14 | [GitOps with FluxCD](14-fluxcd-gitops.md) | **K8s** · Why GitOps fits an experiment rig, bootstrapping Flux, and repository layout. |
| 15 | [KServe](15-kserve.md) | **K8s** · Installing and configuring the model-serving control plane. |
| 16 | [Serving an LLM with vLLM](16-vllm-inference.md) | **K8s** · Running the vLLM inference engine and sending a completion request over HTTP. |
| 17 | [Ray and KubeRay](17-kuberay.md) | **K8s** · Distributed scheduling for multi-node workloads. |
| 18 | [Heterogeneous Hardware](18-heterogeneous-hardware.md) | Device plugins, Talos extensions, and what changes on real accelerator hardware. |
| 19 | [Troubleshooting](19-troubleshooting.md) | Layer-by-layer debugging and troubleshooting guide. |
| 20 | [Teardown](20-teardown.md) | Safely remove every resource created in this tutorial. |
| 21 | [Summary](21-summary.md) | What we built, why we built it this way, and what comes next. |

The chapters are designed to be followed in order from §1 to §21. **§§1–12 form the core spine** (the OpenCHAMI and Talos setup) and are worth doing in one or two sittings. §§13–18 layer the inference stack on top and can be done later. Budget **about a day** for §§1–12 on your first run, and **half a day** for §§13–18 (most of which is spent waiting for image and model downloads).

---

## Conventions

- Commands show the prompt of the machine where you should run them:
  - `devbox$` — the machine where you run the `openstack` CLI.
  - `head$` — inside the OpenCHAMI head node over SSH. `talosctl` and `kubectl` also run here, so you drive the entire cluster from one place.
  - There is no `node$` prompt. **Talos Linux has no shell and no SSH** by design, which keeps the worker nodes immutable and secure.
- ⚠ **Don't copy the prompt.** `devbox$` and `head$` just show which machine to use. If you paste the prompt by mistake, you will get `-bash: head$: command not found`. Run multi-line blocks one command at a time so any error stays visible.
- ✅ **Checkpoint** sections show the expected terminal output so you can verify your setup before moving on.
- 🔀 **Deviation** notes highlight where this cloud build differs from the [upstream OpenCHAMI tutorial](https://openchami.org/docs/tutorial/) or from a bare-metal deployment, and explain why.
- ⚠ **Gotcha** notes flag common pitfalls that can cost hours to debug.
- 🛑 **Stop** warnings mark steps where a mistake could affect other users on a shared cloud or cannot be easily undone. Read them before running the command.
- Placeholders look like `<THIS>`. Most come from your own OpenStack project, which you will record in §3; the rest come from earlier steps. If you see a `<…>` placeholder and aren't sure where its value comes from, check §3.

If you spot an error or have a suggestion, please open an issue or pull request on the [OpenCHAMI website repository](https://github.com/OpenCHAMI/openchami.org), or ask on the [OpenCHAMI Slack](https://openchami.org/slack).

Next: [§1 — Introduction](01-introduction.md)
