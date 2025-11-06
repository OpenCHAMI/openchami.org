+++
title = "OpenCHAMI Mini Bootcamp: Stand Up a Local Stack in an Afternoon"
description = "A short, practical on‑ramp to deploy OpenCHAMI locally, verify services, and boot your first node—without getting lost in details."
summary = "Clone, configure a few fields, run two playbooks, and confirm the core services. Clear steps with ≤4 commands."
slug = "mini-bootcamp"
date = 2024-11-13
lastmod = 2025-11-06
draft = false
weight = 10
categories = ["HPC", "Operations"]
tags = ["OpenCHAMI", "deployment", "ansible", "podman"]
contributors = ["Travis Cotton", "Alex Lovell-Troy"]
canonical = "/blog/mini-bootcamp/"
+++

You want to see OpenCHAMI running today, not next month. This mini bootcamp is the shortest path we use to get new operators hands‑on: deploy the core services on a single host, confirm they’re healthy, and prep for your first node boot. We’ll keep concepts light, steps clear, and commands under four.

What you’ll accomplish
- Deploy OpenCHAMI’s core microservices locally using Podman quadlets
- Confirm the stack is up and responding
- Understand where to edit cluster‑specific settings
- Know what to do next to boot a node

What you need
- A RHEL‑like host with Podman and Ansible installed
- Root or sudo access
- A hostname you control (the recipes default to your local hostname)

Key pieces you’re bringing up
- SMD: system inventory and state
- BSS: bootscripts for iPXE and cloud‑init
- Auth (local dev settings): tokens for services talking to each other
- Support services (DB, proxy, etc.) managed by quadlets

Configure once, then run
The deployment recipes use a small, readable inventory and a few group_vars files. You’ll set your hostname, cluster shortname, and one or two items like an SSH pubkey if you plan to use cloud‑init to inject keys later. Everything else is sane defaults for a local install.

The only commands you need (≤4)
We keep this tight. Clone the recipes, apply configs, then bring everything up.

```bash
git clone https://github.com/OpenCHAMI/deployment-recipes.git && cd deployment-recipes/lanl/podman-quadlets
ansible-playbook -l $HOSTNAME -c local -i inventory -t configs ochami_playbook.yaml
ansible-playbook -l $HOSTNAME -c local -i inventory ochami_playbook.yaml
podman ps --format '{{.Names}}' | sort
```

What just happened
- The first playbook wrote quadlet configs, secrets, and service files for your host
- The second playbook started the services and enabled them to survive reboots
- The final command lists the containers so you can spot obvious misses fast

If you prefer not to use the final command, browse the systemd journal for quadlet units or hit the service health endpoints in your browser; the point is to confirm your stack is alive.

Where to edit configuration
- inventory/01-ochami: add your local hostname
- inventory/group_vars/ochami/cluster.yaml: set cluster name and shortname; optionally set an SSH public key for cloud‑init
- inventory/group_vars/ochami/*.yaml: knobs for ports, storage, and dev credentials

Common checks after bring‑up
- Auth: can services fetch tokens and talk to each other? Look for 401s in logs
- SMD: API answers on the expected port and returns an empty list of nodes
- BSS: bootscript endpoint responds; template variables look sane for your hostname
- Logs: no crash loops; backoffs settle down within a minute of start

How this fits into the bigger picture
OpenCHAMI is modular and API‑first. The mini bootcamp brings up a minimal yet realistic stack so you can:
- Try cloud‑init flows for node boots (see our separate post)
- Point a discovery tool at SMD and start populating inventory
- Test access tokens between services without a full enterprise IdP

Next steps: first node boot
Once the stack is healthy:
- DHCP/TFTP: make sure your lab network routes PXE requests to your boot host
- Cloud‑init: use a small, auditable config; test on one node first
- Power control: verify you can cycle the test node (Redfish or your PDU)

If you don’t want to touch network services yet, you can still exercise BSS and SMD with curl or a browser to see the request/response shapes and verify templates render.

Troubleshooting quick hits
- Nothing starts: check systemd units for quadlet errors; a missing env file or port collision is common
- One service flaps: read its container logs; auth or DB connection strings are the usual suspects
- Can’t reach APIs: confirm the bind address and firewall settings on your host
- Template looks wrong: fix group_vars, rerun the configs task, and restart the affected service

What this bootcamp is not
This isn’t image building or full cluster operations. It’s the shortest path to a working local stack so you can learn the APIs, explore the logs, and integrate with your tooling. From here, add a scheduler, build images, and wire up your PXE path.

References
- Recipes: https://github.com/OpenCHAMI/deployment-recipes
- Org: https://github.com/OpenCHAMI
- Docs: https://openchami.org/docs

{{< blog-cta >}}
