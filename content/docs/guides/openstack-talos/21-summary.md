---
title: "§21 — Summary"
description: "A look back over the whole build: every decision in one place, what this proof of concept doesn't prove, and where to go next."
slug: "21-summary"
date: 2026-10-21
lastmod: 2026-10-21
weight: 210
toc: true
draft: false
---
> ⏱ **About 10 minutes** · reading only · nothing to run
>
> - **What this chapter is for.** It looks back over the whole build. You finish with every decision in one place, what this proof of concept doesn't prove, and where to go next.
>
> - **What you will learn.** Which choices made the build work, which of them would change on real hardware, and which questions to settle before you buy any.
>
> - **Skip it if** you only wanted a working endpoint. Everything here is already in the chapters it points to.

---

## What you built

![Everything sits in one OpenStack project, ochami-lab. It has two Neutron networks, one routed and one deliberately silent. The head node, och-head, runs Rocky 9 and carries the OpenCHAMI control plane, an S3 store, an OCI registry and NAT. och-cp1 is Talos, and is the Kubernetes control plane; och-w1 and och-w2 are Talos, and are the Kubernetes workers. On top of the cluster, Flux drives two chains: KServe in Standard mode, then vLLM, serving an LLM over HTTP; and KubeRay, running a RayCluster. The result is an OpenCHAMI-provisioned Kubernetes cluster serving a language model over an OpenAI-compatible API, with every layer above the machines declared in Git.](diagrams/21-what-you-built.svg)

<details>
<summary>ASCII version</summary>

```
An OpenStack project — ochami-lab
├── two Neutron networks — one routed, one deliberately silent
├── och-head        Rocky 9: the OpenCHAMI control plane + S3 + registry + NAT
├── och-cp1         Talos → Kubernetes control plane
└── och-w1, och-w2   Talos → Kubernetes workers
                   └── Flux → KServe (Standard) → vLLM → an LLM on HTTP
                       Flux → KubeRay → a RayCluster
```

</details>

You built an OpenCHAMI-provisioned Kubernetes cluster serving a language model over an OpenAI-compatible API, with every layer above the machines declared in Git.

---

## Every decision, and why

Each row links to the chapter where the decision is made and explained in full.

**Architecture**

| Decision | Why |
|---|---|
| One Nova instance per node, no nesting (§1) | Many production clouds turn off nested virtualisation. The flat model is also closer to real hardware |
| **iPXE as the node's root disk** (§1, §9) | Nova can't put a network card in a guest's boot order, but it will always boot a disk. So iPXE becomes the disk. It needs no special policy or extra volume, and Talos overwrites it on install, which ends the network-boot loop |
| `openstack server rebuild` to re-provision a node (§12.7) | It puts iPXE back on the root disk, which restarts the whole boot chain. No state is held anywhere |
| `talos.platform=metal`, not `openstack` (§11) | It keeps **OpenCHAMI** as the source of truth. If Nova's metadata configured Talos, the build would prove nothing about OpenCHAMI |
| x86_64 throughout (§10) | It matches most server hardware, such as Intel Xeon and AMD EPYC |

**OpenStack substrate**

| Decision | Why |
|---|---|
| Provisioning subnet `--no-dhcp --gateway none` (§5.2) | Only CoreDHCP may answer DHCP on that network. Real hardware keeps the same rule on its management VLAN (virtual LAN) |
| Port security **disabled** on the provisioning network (§5.3) | Neutron's anti-spoofing rules stop an instance serving DHCP or forwarding other machines' traffic. The head node must do both. It is safe because the network is isolated and holds only our machines |
| MAC-pinned Neutron **ports**, created before the instances (§5.4) | OpenCHAMI identifies a node by its MAC address, so we must choose the MACs. It also means `server delete` leaves the ports in place (§20) |
| Allocation pools that avoid `.200–.250` (§5.2) | That range stays free for CoreDHCP's bootloop leases |
| Nodes get **no** floating IP, no SSH key and no user-data (§9.3) | They are compute nodes on a management network. Everything reaches them through the head node |
| Application credentials, with an expiry date (§2.5) | They work in one project only, and you can revoke them without touching your account |

**Talos and Kubernetes**

| Decision | Why |
|---|---|
| Talos, not Rocky, on the compute nodes | The workload is Kubernetes, and Talos contains nothing else |
| `diskSelector` by size **with `wipe: true`** (§10.6) | Talos installs onto the disk iPXE is running from. Wiping it ends the network-boot loop. The default `disk: /dev/sda` from `gen config` is wrong here, but the selector overrides it |
| Public-read S3 for the boot files *and* the machine configs (§10.3) | A booting node has no credentials, no DNS and no TLS (Transport Layer Security). This is acceptable only because the network is isolated. §10 marks it as wrong for production |
| Public resolvers in the machine config (§10.6) | CoreDNS answers only cluster names, and Talos must reach `ghcr.io`. The fix goes in the node config, so CoreDNS stays as it is |
| Head node as a NAT (network address translation) router (§7.12) | Talos needs the internet. It pulls its installer and all of Kubernetes |
| `local-path-provisioner` for storage (§13.2) | It works the same on real hardware and needs no credentials. Cinder CSI (Container Storage Interface) would have to be removed later |

**Inference stack**

| Decision | Why |
|---|---|
| FluxCD (§14) | Git records what ran, so experiments can be repeated. The same repository can drive a bare-metal cluster later |
| KServe in **Standard** mode, no Knative (§15) | Scale-to-zero does harm when a cold start means reloading gigabytes of weights. Real inference nodes are dedicated anyway |
| Envoy Gateway rather than Istio (§13.4) | We want ingress, not a service mesh |
| A custom `ServingRuntime` for vLLM on CPU (§16.1) | KServe's built-in runtimes assume GPUs (graphics processing units). On real hardware you define one for each accelerator family anyway |
| `Qwen2.5-0.5B-Instruct` (§16) | It is small, instruction-tuned and **not gated**. So there is no Hugging Face token, and no secret in Git |
| KubeRay installed but lightly used (§17) | It is the layer that schedules across different hardware, and there is nothing different here to schedule yet |

---

## What this POC does *not* prove

A proof of concept (POC) leaves things out by design. Be clear about these boundaries when you report what you built:

- **Nothing about performance.** It runs on CPU-only flavors with a 0.5 B model. §16 captures a baseline so you have something concrete to compare accelerator numbers against later.

- **Nothing about Redfish, BMC (baseboard management controller) credentials or physical power control.**

- **Nothing about server firmware.** Real server UEFI settings, boot order and NIC selection are all absent here, and will take real time on physical hardware.

- **Nothing about high-speed interconnects.** A 100 GbE RoCEv2 (RDMA over Converged Ethernet) fabric has no equivalent in a standard Neutron network.

- **Nothing about accelerator drivers on Talos.** NVIDIA is well supported; the further your hardware is from that path, the less of §18.1 has been battle-tested.

---

## Open questions, ranked

Settle these questions before taking this design to physical hardware:

1. **Can your accelerator's drivers be delivered as a Talos system extension?** If not, that node needs a conventional operating system and the cluster design changes. Confirm this before committing hardware to the cluster (§18.1).

2. **Where does the OpenCHAMI control plane live on real hardware?** It can run in a VM (virtual machine), as it does here, or on dedicated bare metal. OpenCHAMI's own contributors run multiple control planes in VMs—one per developer—and this build is a working example of that pattern.

3. **How is the provisioning network protected on real hardware?** A physical switch has no `--no-dhcp` flag. Ensuring that only CoreDHCP answers on the management VLAN requires switch configuration agreed with your network team.

4. **Where do the model weights live?** `local-path` works well for per-node caches, but a shared storage array or NFS (Network File System) server requires a CSI decision, and iSCSI on Talos requires a system extension.

5. **Control-plane HA (high availability), SELinux in enforcing mode, and step-ca or a site PKI (public key infrastructure).** All three were left out of scope for this lab.

6. **Will KServe's newer `LLMInferenceService` and llm-d path replace §§15–16?** That is where KServe is heading, and it makes a good follow-on experiment.

---

## What to do next

**Straight after finishing:**

- **Record what your cloud did differently.** Note whether `--mac-address` was allowed, whether the firmware was BIOS or UEFI, and which Gateway implementation you used. Any automation you write later will need all three.

- **Note the vLLM baseline numbers from §16.**

**Then:**

1. **Write it as Infrastructure-as-Code.** Rebuild the same cluster with OpenTofu and Ansible, and compare it with what you did by hand. Having built it manually first, you know exactly what the automation should produce.

2. **Add more control-plane nodes.** Scaling to three `och-cp` nodes changes only §8, §11 and the Talos config.

3. **Swap the inference engine.** Deploying a second `InferenceService` on llama.cpp to serve the same model takes a single commit, giving you a direct comparison between two engines.

---

## In short

We ran OpenCHAMI on OpenStack instead of bare metal, and Talos on the compute nodes instead of Rocky Linux. Because Nova can't network-boot an instance directly, iPXE became each node's root disk and creating the instance became the power button. The OpenCHAMI layer in the middle didn't have to change at all.
