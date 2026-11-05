---
title: "§4 — An OpenStack Primer"
description: "A short tour of the OpenStack services this tutorial uses, and the habits that make them easier to work with."
slug: "04-openstack-primer"
date: 2026-10-21
lastmod: 2026-10-21
weight: 40
toc: true
draft: false
---
> ⏱ **About 20 minutes** · on the devbox · reading plus a few read-only commands, creates nothing
>
> - **What this chapter is for.** A short tour of the OpenStack services this tutorial uses, and the habits that make them easier to work with.
>
> - **What you will learn.** Which service owns which resource, how Neutron divides a network, five behaviours that catch people out, and where to look when something fails.
>
> - **Skip it if** you already know OpenStack. Even then, read "Five things that will surprise you", because the first one breaks §12 if you miss it.

---

## Introduction

### A family of services

OpenStack is a collection of independent services. Each service manages one type of resource, exposes its own API (application programming interface), and has its own subcommands in the `openstack` CLI (command-line interface). This tutorial uses five of them:

| Service | Owns | CLI |
|---|---|---|
| **Keystone** | Identity: users, projects, roles, tokens | `openstack token`, `… application credential` |
| **Nova** | Compute: instances, flavors, power state, rescue | `openstack server`, `… flavor` |
| **Neutron** | Networking: networks, subnets, ports, routers, security groups | `openstack network`, `… subnet`, `… port`, `… router`, `… security group` |
| **Glance** | Images: bootable disk templates | `openstack image` |
| **Cinder** | Block storage: persistent volumes you can attach and detach | `openstack volume` |

You already met Keystone in §2 and Glance in §3. Together, these five services handle everything we build in §§5–6 and §9.

### Networks, subnets and ports

Neutron splits networking into three distinct objects, and §5 relies on this separation:

- A **network** is a layer-2 broadcast domain with no IP addresses of its own — think of it as a virtual switch.

- A **subnet** adds layer-3 addressing to a network. It defines a CIDR (classless inter-domain routing) range, an optional default gateway, and **an optional DHCP (Dynamic Host Configuration Protocol) server**. That is where `--no-dhcp` lives — the most important networking flag in this tutorial.

- A **port** is a virtual NIC (network interface card). It belongs to a network, holds a MAC (media access control) address and any fixed IP addresses, and plugs into an instance. Crucially, **a port can be created before any instance uses it**, which is how we pin each node's MAC address in advance.

![The provisioning network och-prov, broken into the three things Neutron makes you name. The network itself is layer 2 only: a wire, with no addresses. The subnet 172.16.0.0/24 attaches layer 3 to it: a CIDR, created with --no-dhcp and no gateway. Three ports hang off the same network, each a virtual NIC with its MAC address fixed in advance: the one ending be:ef:ff holds 172.16.0.254 and is the head node's second NIC; the one ending be:ef:01 has no IP and is och-cp1's NIC, which CoreDHCP will address; the one ending be:ef:02 is och-w1's NIC. A port can exist before any instance uses it, which is how the MAC addresses are pinned.](diagrams/04-network-subnet-port.svg)

<details>
<summary>ASCII version</summary>

```
  network  "och-prov"                     ← layer 2: a wire, no addresses
     │
     ├── subnet 172.16.0.0/24            ← layer 3: CIDR, --no-dhcp, no gateway
     │
     ├── port  mac=…:be:ef:ff ip=.254    ← the head's second NIC
     ├── port  mac=…:be:ef:01 ip=(none)  ← och-cp1's NIC; CoreDHCP will address it
     └── port  mac=…:be:ef:02 ip=(none)  ← och-w1's NIC
```

</details>

### What you will do

- **Explore the project read-only** (Step 4.1). List existing resources and inspect the raw JSON output rather than the summary table.

- **Learn where errors hide** (Step 4.2). Run the three diagnostic commands that show why an instance failed, what it printed to the console, and what actions were requested.

📌 The OpenStack documentation goes into more detail if you want to explore further:

- [OpenStack's conceptual architecture](https://docs.openstack.org/install-guide/get-started-conceptual-architecture.html), for how the services fit together.

- The documentation for each service: [Keystone](https://docs.openstack.org/keystone/latest/), [Nova](https://docs.openstack.org/nova/latest/), [Neutron](https://docs.openstack.org/neutron/latest/), [Glance](https://docs.openstack.org/glance/latest/) and [Cinder](https://docs.openstack.org/cinder/latest/).

- [OpenStack networking](https://docs.openstack.org/neutron/latest/admin/intro-os-networking.html), and the [port commands](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/port.html).

- [Server concepts](https://docs.openstack.org/api-guide/compute/server_concepts.html), for instance states such as `BUILD` and `ACTIVE`.

- The [console log](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/console-log.html) and [server event](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/server-event.html) commands used in Step 4.2.

---

## Five things that will surprise you

**1. Port security rules will silently block your DHCP server.** By default, Neutron applies *anti-spoofing* filters to every port: a port can only send traffic from its assigned MAC and IP addresses, and it **cannot send DHCP server replies**. While that rule prevents rogue DHCP servers on shared networks, it also blocks OpenCHAMI's CoreDHCP service. Step 5.3 disables port security on our isolated provisioning network; forgetting that flag is the single most common cause of nodes failing to boot in §12.

**2. There is no "boot from network" option.** §1 explains why Nova has no PXE boot flag, and §9 works around it using an iPXE disk image.

**3. Flavors are a fixed menu.** Rather than choosing arbitrary CPU, RAM and disk numbers for each VM, you pick a named flavor. When a cloud's flavors have small root disks, §6.7 shows how to attach a Cinder block volume for extra storage.

**4. Deleting an instance deletes its root disk.** Instances created with `openstack server create --image` use an *ephemeral* root disk that disappears when the instance is deleted. That works well for our Talos nodes (which can be reprovisioned in minutes), but always double-check the instance name before running `server delete`.

**5. Operations are asynchronous.** Commands like `openstack server create` and `openstack server reboot --hard` return as soon as the request is accepted, before the VM has finished booting or restarting. Later chapters include explicit wait loops, and you can check progress at any time with `openstack server show -c status`.

---

## Step 4.1 — Look around, read-only

You ran most of the basic listing commands in §3. Two more flags are worth knowing:

```
devbox$ openstack --help | head -40
devbox$ openstack server list --long
```

When debugging on OpenStack, ask for the raw JSON record (`-f json`) rather than the default summary table:

```
devbox$ openstack image show $OCH_HEAD_IMAGE -f json | jq .
```

`-f json` works on every `show` and `list` command. While the table view often hides or truncates nested fields (such as `hw_firmware_type` in §3 or `port_security_enabled` in §5), the JSON output shows every field returned by the API.

---

## Step 4.2 — Learn where the errors hide

When an instance misbehaves, check these three commands in order:

```
devbox$ openstack server show <name> -c fault -f json     # why an instance failed
devbox$ openstack console log show <name> --lines 100     # what the guest printed
devbox$ openstack server event list <name>                # what was requested, and when
```

`openstack server event list` is especially handy: it logs every lifecycle action (create, reboot, rebuild, stop) with a timestamp and status. When you hard-reboot nodes in §12, this command confirms that Nova actually carried out the reboot.

---

## ✅ Checkpoint

Verify that you can query an image record in JSON format with `jq`:

```
devbox$ openstack image show $OCH_HEAD_IMAGE -f json | jq -r '.name, .disk_format'
```

It should print two lines: the image name you selected in §3, followed by its disk format (such as `qcow2` or `raw`).

Next: [§5 — Tech Watch Networking](05-techwatch-networking.md)
