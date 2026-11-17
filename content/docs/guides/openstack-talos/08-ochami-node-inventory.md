---
title: "§8 — OpenCHAMI Node Inventory"
description: "You tell OpenCHAMI which nodes exist, before any of them are created. You finish with all five nodes in SMD, and CoreDHCP and CoreDNS ready to answer them."
slug: "08-ochami-node-inventory"
date: 2026-10-21
lastmod: 2026-10-21
weight: 80
toc: true
draft: false
---
> ⏱ **About 5 minutes** · on the head node, plus one check from the devbox · writes the node inventory and loads it into SMD
>
> - **What this chapter is for.** You tell OpenCHAMI which nodes exist, before any of them are created. You finish with all five nodes in SMD, and CoreDHCP and CoreDNS ready to answer them.
>
> - **What you will learn.** Why SMD is the one list everything else is built from, what an xname is, and why each node's MAC address must match in three places.
>
> - **Don't skip it.** CoreDHCP only gives a real address to a MAC address that SMD knows. Without this chapter, no node gets past its first DHCP request.

---

## Introduction

### SMD is the inventory

Everything OpenCHAMI tells a node comes from SMD (State Management Database). DHCP leases, DNS names and boot scripts are all generated from what SMD knows. So adding a node to the cluster means putting a record for it in SMD.

You register **five** nodes here, even though you may only boot two or three. Extra records cost nothing, and having them ready lets you bring up more nodes later without coming back to this chapter.

### Every node needs an xname

An xname is a node's name in the Cray naming scheme that OpenCHAMI inherited. `x1000c0s0b0n0` reads as cabinet 1000, chassis 0, slot 0, BMC (baseboard management controller) 0, node 0. SMD uses the xname as each node's key, so even a virtual node needs one. On real hardware, the xname says where the node physically sits.

⚠ **The xnames in this tutorial are invented.** `x1000c0s0` has the right *shape*, but it does not describe a real cabinet. On physical hardware, whoever builds the cluster chooses the numbering scheme. Here, treat each xname simply as a stable ID in the format SMD expects.

### You describe the nodes in a file

On real hardware, OpenCHAMI can find the nodes for you. A tool called Magellan scans the management network and asks each BMC what it is, over Redfish. This is *dynamic* discovery.

Our nodes are OpenStack instances, and they have no BMCs. So we use *static* discovery instead. You give SMD a YAML file that describes the nodes you are about to create. It gives the same result every time, and you can review it and keep it in git.

🔀 **Deviation: static discovery instead of Magellan.** This is the biggest single difference between this tutorial and a standard OpenCHAMI cluster. There, Magellan fills SMD *from the hardware itself*. That brings concerns this chapter never meets: BMC credentials, a management network that reaches every BMC, and power control over Redfish. It is how OpenCHAMI is designed to be used, and how most deployments you read about work.

📌 Static discovery isn't only a shortcut. Plenty of real clusters fill SMD from a file too, either written by hand or generated. If a site already records its inventory somewhere else, a file is often the better choice.

🔀 **Deviation: the new file format.** The upstream *guide* shows the flat format from before `ochami` v0.6.0, with `bmc_mac:` and `bmc_ip:` on each node. Current `ochami` expects separate `bmcs:` and `nodes:` lists. The data is the same, but the guide's version is rejected outright.

The BMC entries here are placeholders. Their MAC addresses and IPs are invented, just to satisfy the file's schema.

### One MAC address, three places

Each node's MAC address is copied into three places, and they have to agree. You chose the values once, in the node map in `och-vars-env.sh`:

![One MAC address copied into three files: the node map in och-vars-env.sh decides each node's name, xname, NID, MAC, IP, role and Neutron port name; the Neutron port of §5.4 pins the MAC and belongs to OpenStack; the SMD inventory of §8.1 maps that MAC to an IP and an xname for CoreDHCP and CoreDNS; the BSS payload of §11.1 maps the same MAC to a kernel, initrd and command line for iPXE. The port names are offset by one from the node names, so the MAC is the only value that reliably connects the three. Neutron and OpenCHAMI cannot see each other's copy, so a mismatch is never reported — a MAC missing from SMD gives a silent bootloop, and a MAC in the wrong BSS payload boots the node as the wrong role.](diagrams/08-three-way-contract.svg)

*The node map, and the three places each MAC address is copied to. §5.4 made the ports, this chapter fills SMD, and §11.1 writes the boot payloads.*

<details>
<summary>ASCII version</summary>

```
                        ┌──── §5.4   Neutron ports   ← MAC is pinned here (Neutron)
                        │
   node map ────────────┼──── §8.1   SMD inventory   ← MAC → IP → xname → group (SMD)
   (och-vars-env.sh)    │
                        └──── §11.1  BSS payloads    ← MAC → boot script, i.e. role (BSS)
```

</details>

Neutron and OpenCHAMI can't see each other's copy, so a mismatch is never reported. A MAC missing from SMD gets a *bootloop* lease instead of its real address. A MAC in the wrong BSS (Boot Script Service) payload boots the node as the wrong role. You check the copies against each other at the end of this chapter, and again in §11.

📌 **Copying MAC addresses by hand is error-prone, which is a good reason to automate the build.** If you generate the ports, SMD inventory, and BSS payloads from a single `nodes.yaml`, they cannot disagree.

### What you will do

- **Write the inventory** (Step 8.1). One YAML file describes the five nodes and their placeholder BMCs.

- **Load it into SMD** (Step 8.2). One `ochami` command, with a fresh token.

- **Check that everything agrees** (the checkpoint). You confirm that SMD has the nodes, that CoreDHCP has picked them up and that the Neutron ports match.

📌 The OpenCHAMI documentation goes into more detail:

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/), Part 2.2. This chapter follows it, with the changes marked 🔀.

- [SMD](https://github.com/OpenCHAMI/smd), the inventory service, and [Magellan](https://github.com/OpenCHAMI/magellan), the discovery tool used on real hardware.

- [The `ochami discover` manual page](https://github.com/OpenCHAMI/ochami/blob/main/man/ochami-discover.1.sc), for the file format in Step 8.1.

- [Component names (xnames)](https://cray-hpe.github.io/docs-csm/en-12/operations/component_names_xnames/) in the Cray System Management documentation, where the naming scheme comes from.

---

## Step 8.1 — Write the inventory

```
head$ sudo mkdir -p /etc/openchami/data
head$ sudo tee /etc/openchami/data/nodes.yaml > /dev/null << 'EOF'
bmcs:
- xname: x1000c0s0b0
  mac: de:ca:fc:0f:fe:e1
  ip: 172.16.0.101
- xname: x1000c0s0b1
  mac: de:ca:fc:0f:fe:e2
  ip: 172.16.0.102
- xname: x1000c0s0b2
  mac: de:ca:fc:0f:fe:e3
  ip: 172.16.0.103
- xname: x1000c0s0b3
  mac: de:ca:fc:0f:fe:e4
  ip: 172.16.0.104
- xname: x1000c0s0b4
  mac: de:ca:fc:0f:fe:e5
  ip: 172.16.0.105

nodes:
- name: och-cp1
  nid: 1
  xname: x1000c0s0b0n0
  bmc: x1000c0s0b0
  groups:
  - compute
  - talos-controlplane
  interfaces:
  - mac_addr: 52:54:00:be:ef:01
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.1
- name: och-w1
  nid: 2
  xname: x1000c0s0b1n0
  bmc: x1000c0s0b1
  groups:
  - compute
  - talos-worker
  interfaces:
  - mac_addr: 52:54:00:be:ef:02
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.2
- name: och-w2
  nid: 3
  xname: x1000c0s0b2n0
  bmc: x1000c0s0b2
  groups:
  - compute
  - talos-worker
  interfaces:
  - mac_addr: 52:54:00:be:ef:03
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.3
- name: och-w3
  nid: 4
  xname: x1000c0s0b3n0
  bmc: x1000c0s0b3
  groups:
  - compute
  - talos-worker
  interfaces:
  - mac_addr: 52:54:00:be:ef:04
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.4
- name: och-w4
  nid: 5
  xname: x1000c0s0b4n0
  bmc: x1000c0s0b4
  groups:
  - compute
  - talos-worker
  interfaces:
  - mac_addr: 52:54:00:be:ef:05
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.5
EOF
```

For each node, the file gives:

- **A `name`** for people to read, matching the Nova instance name you use in §9.

- **A `nid`**, the node's number (node ID).

- **The `xname`**, and the placeholder BMC it belongs to.

- **Its groups**, explained just below.

- **Its management interface, as MAC → IP.** This pair is the link to §5.4. The instance holding the port with MAC `52:54:00:be:ef:01` *will* get `172.16.0.1` from CoreDHCP, because CoreDHCP asks SMD.

📌 Two groups for each node. Every node is in `compute`. Each is also in `talos-controlplane` or `talos-worker`, because the roles really differ here. One node runs the Kubernetes control plane, and the rest are workers. Later `ochami` commands use groups to pick out sets of nodes, and §11 uses the same split for the boot payloads.

⚠ **If §5.4 refused `--mac-address`** and Neutron picked its own MAC addresses, use *those* values here instead. Read them back with:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov \
          -c Name -c 'MAC Address' -c 'Fixed IP Addresses' -f value
```

There is a copy of this file at [`templates/nodes.yaml`](templates/nodes.yaml).

---

## Step 8.2 — Load it into SMD

Tokens last an hour, so the first line gets a fresh one:

```
head$ export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
head$ ochami discover static -f yaml -d @/etc/openchami/data/nodes.yaml
```

No output means success. "Discover" here just means "fill SMD as if these nodes had been discovered".

⚠ **Gotcha: running it twice fails.** A second `discover static` stops with `409 Conflict` ("same FQDN or xname ID"). It *adds* records, and it won't update ones that exist. That does no harm. To really start again, delete the components first, with `ochami smd component delete …`.

---

## ✅ Checkpoint

First, SMD has the five nodes:

```
head$ ochami smd component get | jq '[.Components[] | select(.Type == "Node")] | length'
5

head$ ochami smd component get | jq '.Components[] | select(.ID == "x1000c0s0b0n0")'
{
  "Enabled": true,
  "ID": "x1000c0s0b0n0",
  "NID": 1,
  "Role": "Compute",
  "State": "On",
  "Type": "Node"
}
```

Next, check that CoreDHCP and CoreDNS have picked them up. Both services refresh from SMD every 30 seconds whether anything changed or not, so wait half a minute and look for the **change** in the count:

```
head$ journalctl -u coresmd-coredhcp | tail -6
Aug 04 09:38:00 och-head coresmd-coredhcp[28420]: … msg="initiating cache refresh" prefix="plugins/coresmd"
Aug 04 09:38:00 och-head coresmd-coredhcp[28420]: … msg="Cache updated with 0 EthernetInterfaces and 0 Components" prefix="plugins/coresmd"
Aug 04 09:38:30 och-head coresmd-coredhcp[28420]: … msg="initiating cache refresh" prefix="plugins/coresmd"
Aug 04 09:38:30 och-head coresmd-coredhcp[28420]: … msg="Cache updated with 10 EthernetInterfaces and 10 Components" prefix="plugins/coresmd"
```

Ten of each means 5 nodes plus 5 BMCs. **If this line doesn't appear**, CoreDHCP isn't talking to SMD, and no node will ever boot. Read the certificate gotcha in Step 7.10 before going on.

📌 Seeing `0 EthernetInterfaces and 0 Components` before Step 8.2 is normal. CoreDHCP has polled SMD every 30 seconds since §7 started it, logging zeroes while the inventory was empty. The line that matters is the first non-zero update within 30 seconds of your `discover static` command.

Last, check the three copies against each other by eye:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov -c Name -c 'MAC Address' -f value | sort
 fa:16:3e:1a:2b:3c
och-head-prov 52:54:00:be:ef:ff
och-node1-prov 52:54:00:be:ef:01
och-node2-prov 52:54:00:be:ef:02
och-node3-prov 52:54:00:be:ef:03
och-node4-prov 52:54:00:be:ef:04
och-node5-prov 52:54:00:be:ef:05

head$   ochami smd component get | jq -r '.Components[] | select(.Type=="Node") | .ID'
x1000c0s0b0n0
x1000c0s0b1n0
x1000c0s0b2n0
x1000c0s0b3n0
x1000c0s0b4n0
```

You should see five node ports with `52:54:00:be:ef:0…` MACs, and five node components. The other two lines in the port list are expected, and neither is a node:

- **`och-head-prov`** is the head node's own second NIC from §6. Its MAC ends `…:ff`, deliberately outside the node range.

- **The unnamed `fa:16:3e:…` port** belongs to Neutron itself. [§5's checkpoint](05-techwatch-networking.md#-checkpoint) shows how to confirm it is *not* a `network:dhcp` port, which is the one case that is fatal.

The third copy, the boot payloads, arrives in §11.

⚠ **The port names are off by one from the node names.** Use this table rather than going by the numbers in the names:

| MAC | Neutron port (§5.4) | SMD and Nova name (§8.1, §9) | IP |
|---|---|---|---|
| `52:54:00:be:ef:01` | `och-node1-prov` | **`och-cp1`** | 172.16.0.1 |
| `52:54:00:be:ef:02` | `och-node2-prov` | **`och-w1`** | 172.16.0.2 |
| `52:54:00:be:ef:03` | `och-node3-prov` | **`och-w2`** | 172.16.0.3 |
| `52:54:00:be:ef:04` | `och-node4-prov` | **`och-w3`** | 172.16.0.4 |
| `52:54:00:be:ef:05` | `och-node5-prov` | **`och-w4`** | 172.16.0.5 |

§5.4 numbers the ports `node1` to `node5`, because the roles don't exist yet at that point. This chapter assigns the roles, and the control-plane node takes `node1`. So **`och-node2-prov` is the port for `och-w1`, not `och-w2`**, and `och-w4` uses `och-node5-prov`.

§9's commands already allow for this, with `--port ${OCH_PREFIX}-node${i}-prov` for `w$((i-1))`. The risk comes when you attach ports by hand and match numbers that look alike.

📌 **Why use a table instead of renaming the ports?** §5 runs before the node roles exist, so naming the ports `och-cp1-prov` and `och-w1-prov` there would put things in the wrong order (though it is the right fix if you automate the build). Be careful if you attach ports manually: attaching the wrong port fails silently. The node still boots with a valid IP and role because SMD and BSS both match on the MAC address, so SMD, DNS, and Kubernetes will call the node by the identity tied to its MAC rather than the Nova instance name you typed.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `500 Internal Server Error` | SMD started before hydra's signing keys existed (Step 7.10). Run `sudo systemctl restart smd` |
| `401 Unauthorized` | The token has expired. Run the `gen_access_token` line in Step 8.2 again |
| `409 Conflict` | The file is already loaded. See the gotcha in Step 8.2 |
| `unable to read data from file: open … no such file or directory` | The path is mistyped, and `ochami` shows exactly what it tried to open. Compare it letter by letter with the `tee` in Step 8.1. `nodes.yam` for `nodes.yaml` is the usual one, because the path is long and you type it twice |
| `Cache updated with 0 …` in the coresmd log | SMD is reachable but empty, so the discover didn't land. Check the checkpoint again |
| The YAML is rejected with a schema error | You used the old flat `bmc_mac:` format from the upstream guide. Use the `bmcs:` and `nodes:` shape in Step 8.1 |

Next: [§9 — OpenCHAMI Node Boot](09-ochami-node-ipxe-boot.md)
