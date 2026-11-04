+++
title = "Managing OpenCHAMI Hostnames"
description = "Use custom node names with CoreSMD DHCP rules, CoreDNS records, and cloud-init while keeping xname and NID lookups."
summary = "A practical guide to keeping DHCP, DNS, and cloud-init in agreement when your nodes need names like gpu-worker-01."
date = 2026-11-04T00:00:00-05:00
lastmod = 2026-11-04T00:00:00-05:00
draft = false
weight = 10
categories = ["HPC", "Operations", "Services"]
tags = ["CoreSMD", "CoreDHCP", "CoreDNS", "Cloud-Init"]
+++

You might know a node as `gpu-worker-01`, even though its inventory ID is `x3000c0s0b1n0`. Both names are useful. The inventory ID identifies the hardware, while the friendly name tells people what they are working with.

OpenCHAMI can accommodate those names through configuration. The trick is keeping three things in agreement: the hostname offered through DHCP, the name resolved through DNS, and the hostname applied by cloud-init. Setting one does not automatically set the others.

This post walks through that separation using CoreSMD v0.7.0, the version included in the OpenCHAMI v0.2.0 release configuration. The examples use documentation addresses and `cluster.example`; replace them with your own inventory and domain, and try the change in a lab first.

## Start with a DHCP rule

CoreSMD's CoreDHCP plugin supports rules that match a component's inventory attributes and set DHCP options. A hostname can be a literal string. It does not have to contain an xname or a numeric NID.

Inside your existing `coresmd` configuration block, add a rule for each custom name before the general naming rule:

```text
domain=cluster.example
rule=id:x3000c0s0b1n0,hostname:gpu-worker-01
rule=id:x3000c0s0b1n1,hostname:storage-node-a
rule=type:Node,hostname:nid{03d}
```

Keep the rest of your CoreDHCP configuration, including the service URL, boot URL, lease time, routers, and netmasks. These lines only show the naming settings.

With this configuration, `x3000c0s0b1n0` receives `gpu-worker-01.cluster.example` in DHCPv4 option 12. The second node receives `storage-node-a.cluster.example`. Other nodes use the NID pattern.

Order matters. A matching rule stops evaluation by default, so put specific node rules before the catch-all rule. The [CoreSMD rich-rule guide](https://github.com/OpenCHAMI/coresmd/blob/v0.7.0/examples/coredhcp/rules.md) covers the other match keys and options.

## Give DNS the same names

A DHCP hostname option does not create a DNS record. CoreSMD's DNS plugin reads SMD inventory and constructs xname and NID-based names independently of the DHCP rules.

You can add custom forward records using the standard CoreDNS `hosts` plugin, which is included in the CoreSMD DNS binary. Add this separate server block alongside your existing root block in the Corefile:

```text
gpu-worker-01.cluster.example:53 storage-node-a.cluster.example:53 {
    hosts /dev/null {
        192.0.2.101 gpu-worker-01.cluster.example
        192.0.2.102 storage-node-a.cluster.example
        ttl 60
        no_reverse
        reload 0
    }
}
```

Use each node's actual SMD-assigned address. Match the port and any `bind` settings used by your existing DNS listener. `/dev/null` keeps the example's records separate from the container's own `/etc/hosts`; the mappings are supplied inline.

Queries for these custom names select this block. Queries for the existing NID names and xnames continue to use the original root block. The `no_reverse` setting leaves reverse DNS with the existing configuration, so adding a friendly forward name does not also change the node's PTR name. Add IPv6 address entries if your cluster needs them.

There is a detail worth getting right here: Corefile text order does not determine plugin execution order. In the [CoreSMD v0.7.0 binary](https://github.com/OpenCHAMI/coresmd/blob/v0.7.0/build/coredns/main.go), `forward` runs before `hosts`. Putting both in the usual root block can send a custom-name query upstream before `hosts` gets a chance to answer. The separate block above avoids that forwarding chain.

The block also owns DNS names below each listed name. Keep those names distinct from existing DNS zones and records. See the [CoreDNS configuration guide](https://coredns.io/manual/configuration/) for server-block selection and the [hosts plugin documentation](https://coredns.io/plugins/hosts/) for record options.

## Keep cloud-init in agreement

The DHCP client may accept the offered hostname, but cloud-init can apply another one later in boot. Make sure the node's metadata and cloud-config agree with the name you chose.

For example, a node-specific cloud-config can contain:

```yaml
#cloud-config
preserve_hostname: false
hostname: gpu-worker-01
fqdn: gpu-worker-01.cluster.example
```

If you use shared templates, supply these values from your node configuration rather than putting the same literal hostname into a template used by every node. Check the rendered metadata and user-data as well as the hostname on the running system. Our [cloud-init introduction]({{< relref "/blog/cloudinit/index.md" >}}) explains how that configuration fits into node provisioning.


## Keep one naming map and test one node

For a few custom names, maintaining the configuration directly may be enough. As the list grows, keep one site-owned mapping of component IDs, friendly names, and addresses, then generate the DHCP rules and DNS records from it. Use that same naming map for cloud-init inputs. Regenerate the DNS records when inventory addresses change.

If you already operate an authoritative DNS service, maintaining the friendly names there is another option. CNAME records pointing at generated names can avoid repeating node addresses, but need a suitable zone configuration; the `hosts` plugin serves address records rather than CNAMEs.

Before rolling the change out, check one node through the whole flow:

1. Inspect its DHCP response for the expected hostname.
2. Query the DNS server directly for the friendly name, NID name, and xname.
3. Check reverse DNS and an unrelated upstream lookup.
4. Boot the node and confirm its hostname after cloud-init finishes.
5. Change a test address, regenerate the configuration, and verify that the records follow it.

Use direct DNS queries so that a local `/etc/hosts` entry does not hide a missing record. For example, with your DNS server's address substituted:

```bash
dig @192.0.2.53 gpu-worker-01.cluster.example A +short
dig @192.0.2.53 x3000c0s0b1n0.cluster.example A +short
```

These names can coexist without changing the component's SMD identity. You get a name that makes sense to your operators while keeping the inventory identifiers and generated lookups that existing tools use.

## Where naming goes next

The configuration approach above lets us support custom hostnames without extending SMD. The longer-term direction is being worked through in three related Requests for Discussion:

- [RFD #10: Managing Unique Names in ochami Microservices](https://github.com/OpenCHAMI/roadmap/issues/10) explores how different identifiers can refer to the same component, including the needs of systems that do not use location-based xnames.
- [RFD #112: Hardware Inventory API and Data Model Proposal](https://github.com/OpenCHAMI/roadmap/issues/112) proposes a device model with permanent identifiers, parent relationships, and properties for additional attributes.
- [RFD #134: Replacing SMD — inventory-service, TypeID, and the Path Forward](https://github.com/OpenCHAMI/roadmap/issues/134) proposes bringing that model into `inventory-service`, separating stable hardware identity from location, and providing a compatibility path for existing SMD consumers.

A resource identifier and a hostname serve different purposes. As [clarified in the inventory-service discussion](https://github.com/OpenCHAMI/roadmap/issues/134#issuecomment-5060365800), a TypeID would identify the resource; it would not become the node's hostname. Operators would still have hostnames and location information available separately.

These RFDs remain open discussions, rather than a released naming feature. For an existing SMD-based deployment, the DHCP, DNS, and cloud-init configuration described here provides a way to use friendly names today while that work develops.

{{< blog-cta >}}
