---
title: "OpenCHAMI K8s Inference"
description: "Build an OpenCHAMI-managed Kubernetes cluster inside an OpenStack project, boot it with Talos Linux, and serve a language model with vLLM."
date: 2026-10-21
lastmod: 2026-10-21
weight: 400
toc: false
draft: false
---

Build an OpenCHAMI-managed Kubernetes cluster inside an OpenStack project, boot it with Talos Linux, and serve a language model with vLLM.

Start with the [Overview](00-overview.md).

- [§1 — Introduction: what we're building and why](01-introduction.md) — What OpenCHAMI is, how a node boots through it, and the three decisions that shape the rest of this tutorial.
- [§2 — The OpenStack CLI](02-openstack-cli.md) — Install the openstack command-line interface (CLI), connect it to your project, and sign in with an application credential.
- [§3 — The OpenStack Project](03-openstack-project.md) — You record the details of your OpenStack project in one shell file, which every later chapter reads.
- [§4 — An OpenStack Primer](04-openstack-primer.md) — A short tour of the OpenStack services this tutorial uses, and the habits that make them easier to work with.
- [§5 — Tech Watch Networking](05-techwatch-networking.md) — You build the two networks the Tech Watch cluster runs on. One lets you reach the head node, and the other belongs to OpenCHAMI alone.
- [§6 — The Tech Watch Head Node](06-techwatch-head-node.md) — You create the head node, the one machine that runs the whole OpenCHAMI control plane. You finish logged in to the head node, with both of its networks working.
- [§7 — OpenCHAMI Installation](07-ochami-installation.md) — You install OpenCHAMI on the head node and start it. You finish with every service running and its two main APIs answering, ready for the nodes.
- [§8 — OpenCHAMI Node Inventory](08-ochami-node-inventory.md) — You tell OpenCHAMI which nodes exist, before any of them are created. You finish with all five nodes in SMD, and CoreDHCP and CoreDNS ready to answer them.
- [§9 — OpenCHAMI Node Boot](09-ochami-node-ipxe-boot.md) — You create the nodes and watch each one network-boot as far as OpenCHAMI. You finish with every node asking BSS what to boot, and getting an answer.
- [§10 — Talos Assets and Machine Config](10-talos-assets-and-config.md) — Put the Talos kernel, its initramfs and two machine configs in a public-read bucket, where a booting node can fetch them.
- [§11 — Boot Parameters](11-boot-parameters.md) — You tell BSS what each node should boot. You finish with the control-plane node and the workers each getting their own Talos boot script.
- [§12 — Booting the Talos Cluster](12-boot-the-cluster.md) — You boot the nodes through the whole OpenCHAMI chain and form a cluster. You finish with three Ready Kubernetes nodes, provisioned by OpenCHAMI on OpenStack.
- [§13 — Kubernetes Cluster Foundations](13-cluster-foundations.md) — You add the parts a fresh Talos cluster leaves out, which §§15–17 depend on.
- [§14 — GitOps with FluxCD](14-fluxcd-gitops.md) — Hand the cluster's software over to Git. FluxCD applies whatever you commit to one repository, infrastructure before apps.
- [§15 — KServe](15-kserve.md) — Install the platform that serves models: the KServe controller without Knative, and a Gateway the head node can reach.
- [§16 — Serving an LLM with vLLM](16-vllm-inference.md) — This is the goal of the whole tutorial. You serve a small language model through KServe, and send it a question over HTTP.
- [§17 — Ray and KubeRay](17-kuberay.md) — You add Ray, the layer that matters most once a cluster has more than one kind of accelerator.
- [§18 — Heterogeneous Hardware](18-heterogeneous-hardware.md) — You see what it takes to add GPUs and other accelerators to this cluster. You finish having rehearsed the scheduling half on the CPU nodes you already have.
- [§19 — Troubleshooting](19-troubleshooting.md) — Finding which layer is broken when you don't yet know. Each chapter's own Common failures table covers problems local to that step.
- [§20 — Teardown](20-teardown.md) — Give the cloud resources back when you aren't using the cluster, deleting them in the order OpenStack needs.
- [§21 — Summary](21-summary.md) — A look back over the whole build: every decision in one place, what this proof of concept doesn't prove, and where to go next.
