---
title: "§5 — Tech Watch Networking"
description: "You build the two networks the Tech Watch cluster runs on. One lets you reach the head node, and the other belongs to OpenCHAMI alone."
slug: "05-techwatch-networking"
date: 2026-10-21
lastmod: 2026-10-21
weight: 50
toc: true
draft: false
---
> ⏱ **About 20 minutes** · on the devbox · creates two networks, a router, seven ports and two security groups
>
> - **What this chapter is for.** You build the two networks the Tech Watch cluster runs on. One lets you reach the head node, and the other belongs to OpenCHAMI alone.
>
> - **What you will learn.** Why the provisioning network must be silent, why OpenCHAMI needs fixed MAC addresses, and how Neutron's port security can quietly break it.
>
> - **Don't skip it.** This is the first chapter that creates anything, and everything after it plugs into these networks. Read Step 5.3 before you run Step 5.4, because one flag there decides whether §12 works.

---

## Introduction

### From here on, we build the cluster

With the OpenStack groundwork complete, this chapter starts building the Tech Watch cluster itself. While you are still running `openstack` commands, every networking choice here is designed to give OpenCHAMI a dedicated provisioning network that it fully controls.

### Two networks, for two jobs

The cluster uses two separate networks with very different configurations. [The full network map](diagrams/full-network-map.svg) shows both networks along with every port and IP address created in this chapter:

- **The external network, `och-ext`, is for SSH access and internet downloads.** It is attached to a router so instances on it can reach the internet, and a floating IP on this network lets you SSH (Secure Shell) into the head node. Neutron runs its normal DHCP (Dynamic Host Configuration Protocol) server here, just like on any standard cloud network.

- **The provisioning network, `och-prov`, belongs exclusively to OpenCHAMI.** The compute nodes network-boot over this wire, so we turn off Neutron's built-in services to keep them out of OpenCHAMI's way.

### A silent provisioning network

When a node network-boots on `och-prov`, the DHCP reply tells it where to fetch its boot script, so OpenCHAMI must be the only service answering on that network. To make sure of that, we disable three things Neutron would normally provide:

- **No DHCP from Neutron.** OpenCHAMI's CoreDHCP on the head node must be the sole DHCP server. Having two DHCP servers on the same network causes a race on every boot, depending on which server answers first.

- **No Neutron router or default gateway.** Only the head node routes traffic off `och-prov` (acting as a NAT (network address translation) router in §7.12). Keeping Neutron out of the routing makes `och-prov` behave like an isolated management VLAN (virtual LAN).

- **No port security.** Neutron's default anti-spoofing rules block DHCP server replies coming from an instance. Step 5.3 explains why we disable port security on `och-prov`.

### Why we fix the MAC addresses

OpenCHAMI identifies every node by its MAC (media access control) address: CoreDHCP looks up a requesting MAC in SMD (State Management Database) to assign the right IP, and BSS (Boot Script Service) uses that same MAC to serve the node's boot script.

Because Neutron lets you create ports with explicit MAC addresses before any instance exists, we pre-create all of our ports with known MACs and attach them to instances later. Those MAC addresses come from the node map in `och-vars-env.sh` and must match the SMD inventory in §8 and the boot parameters in §11 — **three places sharing the same values**.

### What you will do

- **Create the external network** (Step 5.1). Create `och-ext`, a subnet with DHCP enabled, and a router connected to your cloud's external network.

- **Create the provisioning network** (Step 5.2). Create `och-prov` and a subnet with `--no-dhcp`, `--gateway none`, and allocation pools that leave room for CoreDHCP.

- **Understand port security** (Step 5.3). Review why Neutron's anti-spoofing filters must be disabled on `och-prov` ports.

- **Create the ports** (Step 5.4). Pre-create two ports for the head node and five for the worker nodes, each with a pinned MAC address.

- **Create the security groups** (Step 5.5). Lock down SSH on the head node's external port to your IP address, and optionally create a group for cluster APIs.

📌 The OpenStack and OpenCHAMI documentation goes into more detail:

- [OpenStack networking](https://docs.openstack.org/neutron/latest/admin/intro-os-networking.html) and [NAT in Neutron](https://docs.openstack.org/neutron/latest/admin/intro-nat.html), for the concepts behind this chapter.

- The CLI commands used here: [network](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/network.html), [subnet](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/subnet.html), [router](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/router.html), [port](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/port.html), [security group](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/security-group.html) and [security group rule](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/security-group-rule.html).

- [Port security](https://docs.openstack.org/api-ref/network/v2/index.html#port-security) and [allowed address pairs](https://docs.openstack.org/api-ref/network/v2/index.html#allowed-address-pairs) in the Neutron API (application programming interface) reference, for Step 5.3.

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/) for SMD, BSS and CoreDHCP.

---

## Step 5.1 — Create the external network

Start in `~/och` with your environment variables loaded:

```
devbox$ cd ~/och && source ~/och/och-env.sh
```

Create the `och-ext` network and its subnet:

```
devbox$ openstack network create ${OCH_PREFIX}-ext

devbox$ openstack subnet create ${OCH_PREFIX}-ext-subnet \
    --network ${OCH_PREFIX}-ext \
    --subnet-range ${OCH_EXT_SUBNET_CIDR} \
    --dns-nameserver 1.1.1.1 --dns-nameserver 8.8.8.8
```

By default, a new subnet gets a DHCP server and a gateway at its first address (`192.168.200.1`), which is what we want here. The head node's external NIC (network interface card) will pick up its IP address, default route and DNS (Domain Name System) servers automatically, just like any regular cloud VM.

🔀 **Deviation — subnet range.** The upstream OpenCHAMI guide uses `192.168.122.0/24`, which is libvirt's built-in `default` subnet and can collide on hosts running libvirt locally. We use `192.168.200.0/24` instead to avoid any overlap.

Now create a router to connect `och-ext-subnet` to your cloud's external network:

```
devbox$ openstack router create ${OCH_PREFIX}-router
devbox$ openstack router set ${OCH_PREFIX}-router --external-gateway ${OCH_EXT_NET}
devbox$ openstack router add subnet ${OCH_PREFIX}-router ${OCH_PREFIX}-ext-subnet
```

These three commands create the router, connect its upstream gateway to `${OCH_EXT_NET}` (which you recorded in §3.6), and attach `och-ext-subnet` to it. The router now performs source NAT for `192.168.200.0/24` so the head node can reach the internet.

🛑 **`${OCH_EXT_NET}` is the only shared resource this tutorial touches.** We attach our router to it, but we never modify the external network itself — never run `openstack network set` or `openstack subnet set` against `${OCH_EXT_NET}`.

---

## Step 5.2 — Create the provisioning network

```
devbox$ openstack network create ${OCH_PREFIX}-prov

devbox$ openstack subnet create ${OCH_PREFIX}-prov-subnet \
    --network ${OCH_PREFIX}-prov \
    --subnet-range ${OCH_PROV_CIDR} \
    --no-dhcp \
    --gateway none \
    --allocation-pool start=172.16.0.1,end=172.16.0.199 \
    --allocation-pool start=172.16.0.254,end=172.16.0.254
```

Key flags:

- **`--no-dhcp`** disables Neutron's built-in DHCP server on this subnet. Without this flag, Neutron's `dnsmasq` and OpenCHAMI's CoreDHCP race to answer every booting node, causing intermittent boot failures that are difficult to diagnose.

- **`--gateway none`** leaves the subnet without a Neutron default gateway. Instead, CoreDHCP hands each node its default route pointing at the head node (`172.16.0.254`).

- **The two `--allocation-pool` flags** keep Neutron's IP address management (IPAM) out of CoreDHCP's dynamic range. Even with `--no-dhcp`, Neutron tracks fixed IPs on ports. In §7.7, CoreDHCP's `bootloop` plugin is configured to lease `172.16.0.200–250` to unknown MAC addresses; leaving `.200–.253` outside Neutron's allocation pools ensures Neutron never assigns those addresses. The second single-IP pool (`172.16.0.254`) reserves the head node's address.

![The address plan for och-prov's subnet, in four ranges. 172.16.0.1 to .199 is a Neutron allocation pool for the node ports, where every IP is named by us when the port is created. 172.16.0.200 to .250 is CoreDHCP's bootloop range, leased to MAC addresses CoreDHCP does not recognise (section 7.7). 172.16.0.251 to .253 is unused. 172.16.0.254 is a second, single-address Neutron pool, reserved for the head node (section 6). Because Neutron may only allocate inside its two pools, it can never hand out an address in the range CoreDHCP leases. A to-scale strip underneath shows how small the last three ranges are.](diagrams/05-prov-address-plan.svg)

<details>
<summary>ASCII version</summary>

```
   172.16.0.1 ────── .199   Neutron pool: node ports, assigned by us
   172.16.0.200 ──── .250   CoreDHCP "bootloop" range for unknown MACs (§7.7)
   172.16.0.251 ──── .253   unused
   172.16.0.254             the head node (§6)
```

</details>

⚠ **Some OpenStack clouds reject multiple `--allocation-pool` flags on a single subnet.** If that happens, pass a single pool (`--allocation-pool start=172.16.0.1,end=172.16.0.254`) so Step 5.4 can still assign `.254` to the head node. Because we specify an explicit IP on every port we create, Neutron will not allocate into the `.200–.250` bootloop range in practice.

---

## Step 5.3 — Understand port security

⚠ **Read this before creating any ports on `och-prov`.** If port security is left enabled, nodes will never receive an IP address and no error will be logged.

By default, Neutron applies **anti-spoofing rules** to every port to prevent tenants from hijacking shared networks: a port may only send packets matching its assigned MAC and IP addresses, and it is **blocked from sending DHCP server replies**.

On `och-prov`, those default filters break two things our cluster relies on:

1. **CoreDHCP cannot answer nodes.** The head node's port silently drops outgoing DHCP replies before they reach the wire. In §12, nodes will network-boot and wait forever for an IP address without logging an error.

2. **The head node cannot NAT traffic for the worker nodes.** In §7.12, the head node forwards traffic between the worker nodes (`172.16.0.0/24`) and the internet. Anti-spoofing drops packets whose source IP doesn't belong to the port itself, causing Talos to hang at `downloading installer`.

There are two ways to handle this in Neutron, and we use the first:

| | `--disable-port-security` (what we use) | `--allowed-address-pair` |
|---|---|---|
| What it does | Disables all packet filtering on the port, including anti-spoofing and security groups | Keeps filtering enabled, but permits specified extra MAC and IP ranges |
| On the head node's `och-prov` port | Works cleanly | `--allowed-address-pair ip-address=172.16.0.0/24` permits NAT traffic, but still blocks DHCP server replies on many deployments |
| Security | Unfiltered, which is safe because `och-prov` is an isolated private network with no external router | More restrictive |
| Verdict | **Use this.** `och-prov` is completely isolated, and we need the head node to act as both a DHCP server and a router | Only try if your cloud policy forbids `--disable-port-security` |

🛑 **Only disable port security on `och-prov`, never on `och-ext`.** The head node's external port sits on a routed network with a floating IP and must keep its security group filtering enabled.

---

## Step 5.4 — Create the ports

First, create the head node's external port on `och-ext`. This is a standard filtered port that receives its private IP via Neutron DHCP:

```
devbox$ openstack port create ${OCH_PREFIX}-head-ext \
    --network ${OCH_PREFIX}-ext \
    --mac-address 52:54:00:c0:fe:01
```

⚠ **We attach the security group in Step 5.5 rather than passing `--security-group` here.** Because `och-sg-head` doesn't exist yet, passing it now would fail with `No SecurityGroup found for och-sg-head`. Until Step 5.5 replaces it, Neutron attaches your project's `default` security group (which blocks all inbound traffic from outside). **Do not skip Step 5.5**, as that is what enables inbound SSH access.

Next, create the head node's provisioning port on `och-prov` with a fixed IP, a pinned MAC, and **port security disabled**:

```
devbox$ openstack port create ${OCH_PREFIX}-head-prov \
    --network ${OCH_PREFIX}-prov \
    --mac-address 52:54:00:be:ef:ff \
    --fixed-ip subnet=${OCH_PREFIX}-prov-subnet,ip-address=${OCH_HEAD_PROV_IP} \
    --disable-port-security \
    --no-security-group
```

You must pass `--no-security-group` alongside `--disable-port-security`: Neutron does not allow security groups on a port with port security disabled, and the CLI will otherwise try to attach the `default` group automatically.

The MAC addresses `52:54:00:c0:fe:01` (external) and `52:54:00:be:ef:ff` (provisioning) match the upstream OpenCHAMI tutorial, making it easy to compare configs between the two guides.

Now create five node ports on `och-prov`, using the MAC and IP addresses from the node map:

```
devbox$ for i in 1 2 3 4 5; do
    openstack port create ${OCH_PREFIX}-node${i}-prov \
      --network ${OCH_PREFIX}-prov \
      --mac-address 52:54:00:be:ef:0${i} \
      --fixed-ip subnet=${OCH_PREFIX}-prov-subnet,ip-address=172.16.0.${i} \
      --disable-port-security \
      --no-security-group
  done
```

⚠ **`node1`–`node5` are port slot numbers, not the final node names in [§8](08-ochami-node-inventory.md).** Because node roles aren't assigned until §8, the ports are simply numbered `node1` through `node5`. In §8, `node1` becomes the control-plane node `och-cp1`, and `node2`–`node5` become workers `och-w1`–`och-w4` (so each worker's port number is one higher than its worker number). §8's checkpoint shows the full mapping table, and §9 attaches the right port to each instance.

Even though the nodes will actually obtain their IP addresses from CoreDHCP at boot, we still pass `--fixed-ip` on each port so Neutron reserves the address and `openstack port list` serves as a readable IP map of the cluster.

🔀 **Deviation — if `--mac-address` is refused.** Some OpenStack clouds restrict custom MAC addresses to administrators. If `openstack port create --mac-address` fails with a policy error, create the ports without `--mac-address` and list the MACs Neutron generated:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov -c Name -c 'MAC Address' -c 'Fixed IP Addresses'
```

Record those Neutron-assigned MACs in `och-vars-env.sh` and use them in §8 and §11 instead of `52:54:00:be:ef:01`–`05`. Everything works the same way — and it mirrors physical hardware, where you read existing MAC addresses rather than inventing your own.

---

## Step 5.5 — Create the security groups

First, verify that `${OCH_ADMIN_CIDR}` is set from §3.7 before building firewall rules around it:

```
devbox$ echo ${OCH_ADMIN_CIDR}          # an address/mask, not <YOUR_ADMIN_CIDR>
```

Create the `och-sg-head` security group allowing inbound SSH and ICMP (ping) from `${OCH_ADMIN_CIDR}`:

```
devbox$ openstack security group create ${OCH_PREFIX}-sg-head \
    --description "OpenCHAMI lab head node: SSH and ICMP from admin only"

devbox$ openstack security group rule create ${OCH_PREFIX}-sg-head \
    --protocol tcp --dst-port 22 --remote-ip ${OCH_ADMIN_CIDR} --description SSH

devbox$ openstack security group rule create ${OCH_PREFIX}-sg-head \
    --protocol icmp --remote-ip ${OCH_ADMIN_CIDR} --description ping
```

⚠ **Always restrict SSH to your CIDR (classless inter-domain routing) range, never `0.0.0.0/0`.** Automated scanners find open SSH ports on public clouds within minutes. Remember that `OCH_ADMIN_CIDR` must be the source IP the head node sees you connecting from (§3.7).

⚠ **Your source IP can change over time.** If your VPN (virtual private network) reconnects or your ISP assigns a new DHCP lease, your IP may change and SSH to a healthy head node will suddenly time out. You can check whether the issue is your IP or the head node by running:

```
devbox$ och_vpn
```

`och_vpn` tests the Keystone (identity) endpoint and the head node's SSH port separately so you can tell immediately if the security group rule needs updating (§19). If your IP changes frequently, use your VPN or campus subnet CIDR rather than a single `/32` address.

Now replace the `default` security group on `och-head-ext` with `och-sg-head`:

```
devbox$ openstack port set ${OCH_PREFIX}-head-ext --no-security-group
devbox$ openstack port set ${OCH_PREFIX}-head-ext --security-group ${OCH_PREFIX}-sg-head
```

Because `port set --security-group` **appends** to a port's existing groups rather than replacing them, we clear the port's groups first and then attach `och-sg-head`. Confirm that only one security group ID is attached:

```
devbox$ openstack port show ${OCH_PREFIX}-head-ext -c security_group_ids -f value
```

🛑 **Verify this output before moving on to §6.** If `och-head-ext` still has no security group or only has `default`, inbound SSH will be blocked in §6, which looks just like a broken VM or floating IP.

You can also create an optional second security group for cluster APIs, though **you won't need it if you use SSH tunnels**:

```
devbox$ openstack security group create ${OCH_PREFIX}-sg-api \
    --description "Cluster APIs — attach only if exposing them directly"
devbox$ for p in 6443 50000 8265 8000; do
    openstack security group rule create ${OCH_PREFIX}-sg-api \
      --protocol tcp --dst-port $p --remote-ip ${OCH_ADMIN_CIDR}
  done
```

Those four ports correspond to the Kubernetes API (**6443**), the Talos API (**50000**), the Ray dashboard (**8265**) and vLLM's OpenAI-compatible API (**8000**). Because those services run on `och-prov` (which is not routed to the outside world), the simplest and safest way to reach them from your devbox is over an **SSH tunnel through the head node**:

```
devbox$ ssh -L 6443:172.16.0.1:6443 -L 8000:172.16.0.1:8000 rocky@<HEAD_FLOATING_IP>
```

---

## ✅ Checkpoint

Check that both networks exist and each has one subnet:

```
devbox$ openstack network list -c Name -c Subnets
```

Inspect `och-prov-subnet` in JSON format:

```
devbox$ openstack subnet show ${OCH_PREFIX}-prov-subnet \
          -c enable_dhcp -c gateway_ip -c allocation_pools -c cidr -f json
{
  "cidr": "172.16.0.0/24",
  "enable_dhcp": false,
  "gateway_ip": null,
  "allocation_pools": [
    {"start": "172.16.0.1", "end": "172.16.0.199"},
    {"start": "172.16.0.254", "end": "172.16.0.254"}
  ]
}
```

Confirm that `"enable_dhcp": false` and `"gateway_ip": null` are both set — fixing either one now is much easier than troubleshooting failed boots in §12.

Next, list the ports on `och-prov`:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov \
          -c Name -c 'MAC Address' -c 'Fixed IP Addresses'
```

You should see the six ports from Step 5.4: `och-head-prov` at `172.16.0.254`, and `och-node1-prov` through `och-node5-prov` at `.1` through `.5`.

Now verify `port_security_enabled` across every port on `och-prov`:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov -c ID -f value | while read -r id; do
    eval "$(openstack port show $id -f shell \
              -c name -c mac_address -c device_owner -c port_security_enabled)"
    printf '%-16s %-18s %-22s security=%s\n' \
      "${name:-<unnamed>}" "$mac_address" "${device_owner:-<none>}" "$port_security_enabled"
  done
```

This loop queries port IDs (rather than names) and uses `-f shell` so each `port show` populates all four shell variables in a single API call, including any unnamed ports created by Neutron itself.

Every port **you** created on `och-prov` (`och-head-prov` and `och-node1-prov` to `och-node5-prov`) must show `security=False`.

⚠ **An extra unnamed port with a `fa:16:3e:…` MAC address is normal on OVN (Open Virtual Network) clouds.** That prefix belongs to Neutron's internal ports; check its `device_owner` column to see what it is:

| `device_owner` | What it is | Action |
|---|---|---|
| `network:distributed`, `network:metadata` | OVN's internal metadata port | Leave it alone — `security=True` on this port is normal and does not affect your nodes |
| `network:dhcp` | A Neutron DHCP server port | 🛑 **Stop.** Neutron DHCP is still active on `och-prov-subnet` and will break §12. Re-check the subnet with `--no-dhcp` |
| Empty | An leftover port from an earlier run | If `device_id` is empty, delete it |

Finally, confirm that `och-head-ext` has port security **enabled** (`true`) and carries only your `och-sg-head` security group:

```
devbox$ openstack port show ${OCH_PREFIX}-head-ext \
          -c port_security_enabled -c security_group_ids -f json
```

You should see `port_security_enabled: true` and a single security group ID matching `openstack security group show ${OCH_PREFIX}-sg-head -c id -f value`. If you see two IDs, `default` is still attached; if the list is empty, Step 5.5's `port set --security-group` was skipped.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `Invalid input for operation: Requested subnet with cidr … overlaps` | Another network in the project already uses `172.16.0.0/24`. Check `openstack subnet list`, pick a free range, and update `OCH_PROV_CIDR` **and** the OpenCHAMI configs in §7 |
| `IP address 172.16.0.254 is not a valid IP for the specified subnet` | Your subnet's allocation pools don't include `.254`. See the single-pool note in Step 5.2 |
| `Unable to create the port … policy` on `--mac-address` | Only administrators can pin MAC addresses on your cloud. Follow the 🔀 fallback in Step 5.4 |
| `Security group … cannot be applied to port with port security disabled` | Remove `--security-group` and pass `--no-security-group` alongside `--disable-port-security` |
| `No SecurityGroup found for och-sg-head` | The port command referenced `och-sg-head` before Step 5.5 created it. Create the port first, then attach the security group in Step 5.5 |
| `bash: YOUR_ADMIN_CIDR: No such file or directory` | A literal `<YOUR_ADMIN_CIDR>` was pasted and bash treated `<` as input redirection. Set `OCH_ADMIN_CIDR` in `och-vars-env.sh` (§3.7), re-source, and use `${OCH_ADMIN_CIDR}` |
| `No Network found for <EXT_NET>` | `OCH_EXT_NET` still holds its template placeholder. Set it in §3.6 and run `source ~/och/och-env.sh` |
| `router set --external-gateway` fails with `not found` | `${OCH_EXT_NET}` is misnamed or not shared with your project. Re-run `openstack network list --external` (§3.6) |
| An extra unnamed port on `och-prov` with a `fa:16:3e:…` MAC | Neutron's internal OVN metadata port. Check its `device_owner` against the checkpoint table — harmless unless it is `network:dhcp` |
| The port-security loop prints blank or misaligned columns | The loop iterated over port names instead of IDs and tripped over an unnamed Neutron port. Loop over `-c ID -f value` as shown in the checkpoint |
| Later, in §12, nodes never get an IP | Almost always traced back to this chapter: either `enable_dhcp` is `true` on `och-prov-subnet`, or a port on `och-prov` still has `port_security_enabled: True` |

Next: [§6 — The Tech Watch Head Node](06-techwatch-head-node.md)
