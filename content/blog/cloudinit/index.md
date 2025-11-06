+++
title = "Cloud-init with OpenCHAMI: Fast, Repeatable Node Boots for HPC"
description = "Use cloud-init in OpenCHAMI to bring up HPC nodes the same way every time, with simple configs, auditability, and quick rollback."
summary = "A practical guide for sysadmins to use cloud-init in OpenCHAMI for predictable boots and easier day-2 ops."
slug = "cloud-init-openchami"
tags = ["cloud-init", "provisioning", "HPC", "OpenCHAMI"]
lastmod = 2025-11-06
date = 2025-01-17
draft = false
canonical = "/blog/cloudinit/"
contributors = ["Alex Lovell-Troy"]
+++

Bringing up HPC nodes should be boring. You want the same outcome every time, with no hand edits, and a clear record of what changed. OpenCHAMI uses cloud-init to do that. It gives you a simple way to describe how a node should boot and configure itself. Then it applies the same steps across the fleet.

In this post, you will see how cloud-init fits into OpenCHAMI, where configs live, and how to test a change on one node before rolling it out. The goal is to help you do less manual work and get to a steady state faster.

Why cloud-init
Cloud-init has been battle-tested in cloud providers for years. It runs early in boot, reads a small config, and applies the steps you define. In OpenCHAMI, we reuse the same idea for HPC. That means you get a standard flow, small configs, and fewer surprises.

How it fits in OpenCHAMI
OpenCHAMI services provide data and templates for node boots. The Boot Script Service (BSS) hands the node the right blob at the right time. Cloud-init on the node reads that blob and does the work. Other services, like SMD (System Management Database), keep track of system state and inventory.

Key repos:
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

Basic flow
1) You define a cloud-init config for a node group (like a partition or rack).
2) You store it in Git and register it with OpenCHAMI.
3) When nodes boot, they pull the config and apply it.
4) You can test changes on one node, then roll them out.

A simple cloud-init example
This example installs packages, writes an agent config, and starts a service. Keep the file small and readable.

```yaml
#cloud-config
package_update: true
packages:
	- htop
	- jq

write_files:
	- path: /etc/myagent/config.yaml
		permissions: '0644'
		content: |
			cluster: ochami-prod
			node_role: compute
			metrics: true

runcmd:
	- systemctl enable --now myagent
```

Register the config
In most clusters, you keep configs in Git and push a reference into BSS. Here is a safe, four-command workflow you can adapt. Replace names to match your environment.

```bash
# 1) Clone your infra repo (holds cloud-init blobs/templates)
git clone https://github.com/OpenCHAMI/cloud-init-configs.git && cd cloud-init-configs

# 2) Add or update the config for a group (e.g., compute-default.yaml)
$EDITOR groups/compute-default.yaml

# 3) Commit and push so others can review/audit
git commit -am "feat(cloud-init): enable myagent on compute defaults" && git push

# 4) Tell BSS to use the new version for the group
curl -X POST http://bss.api.cluster/v1/groups/compute-default/refresh
```

Operational details
- Rollouts: test on one node first. Move the node to a “canary” group that points at the new config. If it passes, switch the main group.
- Audit: use Git history to answer “what changed last Tuesday?” Tie commits to change tickets.
- Recovery: keep a known-good config. If a change misbehaves, point the group back and reboot the nodes in a maintenance window.
- Secrets: avoid plain-text secrets. Use a secrets manager or hand off to your node agent to fetch credentials at runtime.
- Speed: prefer package installs from a local mirror and keep cloud-init jobs short. Heavy work belongs in images or post-boot agents.

Common checks
- Verify a node picked up the expected config:
	- Check /var/log/cloud-init.log on the node.
	- Confirm your files and services exist.
- Check BSS logs for the request and response to the node MAC or xname.
- Validate YAML with a linter before committing.

When to template
For things like NTP servers, sysctls, or agent toggles, use small templates with variables for rack or site. Keep the template simple, and fill variables from inventory in SMD. This keeps the logic in one place and avoids diverging copies.

How this helps day-2
Once cloud-init sets the baseline, your day-2 work gets easier. You have a repeatable starting point and can push small, safe changes when you need them. You also spend less time chasing drift between nodes.

Next steps
- Pick a small group (like 5 compute nodes).
- Add a simple cloud-init config (one service, one file).
- Test a reboot, verify logs, then scale to your wider group.

References
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

{{< blog-cta >}}