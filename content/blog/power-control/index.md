+++
title = "Power Control for HPC with OpenCHAMI: Safe, Scriptable, Auditable"
description = "How to use OpenCHAMI services and Redfish to power nodes on and off safely, with logs you can trust."
summary = "Practical steps to integrate Redfish-based power control into day-to-day operations."
slug = "power-control-openchami"
tags = ["power", "Redfish", "operations", "HPC", "OpenCHAMI"]
lastmod = 2025-11-06
date = 2025-07-22T00:00:00+00:00
draft = false
categories = ["HPC", "Operations"]
contributors = ["Ben McDonald"]
canonical = "/blog/power-control/"
+++

Power events should be predictable. When you turn a node off, you want it to go off. When you turn it on, you want it to boot the same way every time. You also want logs to show who asked for it and when. OpenCHAMI gives you these basics using standard Redfish calls and small services that fit into your ops flow.

In this post, you will learn the common patterns for power control, where to plug in Redfish credentials, and how to use a simple API call for one node or a small group.

Why Redfish
Redfish is a vendor-neutral API for out-of-band management. Most modern BMCs support it. By standardizing on Redfish, you avoid vendor lock-in and keep your scripts simple. OpenCHAMI uses this to send the right command to each BMC based on inventory.

Where it lives in OpenCHAMI
Inventory lives in SMD (System Management Database). It tracks nodes, BMC IPs, racks, roles, and more. A small power service (often part of site tooling) uses SMD to map a node to its BMC information, then issues a Redfish command. In many sites, this is exposed through a tiny REST API and a CLI wrapper.

Key repos:
- SMD: https://github.com/OpenCHAMI/smd
- Example power tooling and references: https://github.com/OpenCHAMI/magellan
- Org: https://github.com/OpenCHAMI

Credentials
Store BMC credentials outside Git. Use your secret manager (Vault, AWS Secrets Manager, or your platform’s native tool). The power service reads them at runtime. You can scope credentials by rack or chassis if needed.

Common tasks

Single node power cycle
This example cycles one node. Replace placeholders with your node ID or xname. The URL shown is an example for a site-local power API that wraps Redfish calls.

```bash
# Power cycle one node through your site power API
curl -X POST "http://power.api.cluster/v1/nodes/compute-23/actions/power-cycle"
```

Group power off
For draining a partition, target a group. The service expands the group using SMD inventory and sends Redfish to each BMC with a safe delay between calls.

```bash
# Power off a group (e.g., a partition or rack)
curl -X POST "http://power.api.cluster/v1/groups/partition-a/actions/power-off?delayMs=500"
```

Status check
After a change, confirm state. Your API can proxy a quick Redfish read on each node.

```bash
# Check current power state on a node
curl "http://power.api.cluster/v1/nodes/compute-23/power-state"
```

Operational details
- Coordination with scheduler: always drain nodes before power off. Tie your power tool into Slurm reservations, or require a drain flag.
- Rate limits: stagger calls (e.g., 250–1000 ms) so you do not overload chassis controllers.
- Retries: retry a few times on BMC timeouts. Log both the request and the final outcome.
- Audit: log who called the API. Forward logs to your collector so you can search by user, node, or window.

Change management
Keep your power API thin and versioned. Put the mapping logic (node to BMC) in SMD and keep the Redfish bits small. This keeps changes local and easy to reason about. If you migrate racks or renumber BMCs, update SMD and the rest just works.

When things go wrong
If a node does not respond, try a BMC reboot through Redfish. If that fails, the issue is likely physical. Your logs will show the sequence and help you triage faster.

Closing the loop
With OpenCHAMI, power control becomes a clean, scriptable building block. You can drain, power off, patch, and power on with the same simple patterns. The result is less time in vendor UIs and more time on clear runbooks.

References
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

{{< blog-cta >}}