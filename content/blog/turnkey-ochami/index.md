+++
title = "Turnkey OpenCHAMI: A Weekend Deploy for a Small HPC Cluster"
description = "Spin up a small OpenCHAMI stack with docker-compose, bring up nodes, and see your first jobs. Simple steps, low risk, and easy to extend."
summary = "A practical, short path to try OpenCHAMI on a lab cluster or sandbox."
slug = "turnkey-openchami-weekend"
tags = ["deployment", "docker", "HPC", "OpenCHAMI"]
categories = ["HPC", "Getting Started"]
contributors = ["Alex Lovell-Troy"]
date = 2024-01-24T10:24:44-05:00
lastmod = 2025-11-06
draft = false
canonical = "/blog/turnkey-ochami/"
+++

You want to try OpenCHAMI without a long project. This guide walks you through a small, safe deployment that fits a weekend. You will deploy core services, register a few nodes, and power one on. If it works for you, you can grow from here.

What you get
You will run a handful of services with docker-compose. You will have inventory, boot scripts, and a simple way to control a node. You will also have a clean place to put secrets.

Key repos
- Deployment recipes: https://github.com/OpenCHAMI/deployment-recipes
- SMD (inventory): https://github.com/OpenCHAMI/smd
- BSS (boot scripts): https://github.com/OpenCHAMI/bss
- Magellan (discovery): https://github.com/OpenCHAMI/magellan

Before you start
Pick a small test area. One head node or VM host is enough. A couple of bare-metal nodes or VMs help you test power and boot. Make sure your user can run Docker.

Step 1: get the files
Clone the deployment recipes. They hold compose files and sane defaults.

```bash
git clone https://github.com/OpenCHAMI/deployment-recipes.git && cd deployment-recipes
```

Step 2: bring up services
Use compose to start the core set. This spins up SMD, BSS, and helpers.

```bash
docker compose up -d
```

Step 3: add inventory
Tell SMD about a node or two. You can do this by discovery or by hand.

```bash
curl -X POST http://localhost:27779/v1/nodes -d '{"xname":"x0c0s1b0n0","role":"compute"}' -H 'Content-Type: application/json'
```

Step 4: set a boot config
Point a node at a known-good kernel and initrd. Keep it simple for your first run.

```bash
curl -X POST http://localhost:28080/v1/boot -d '{"xname":"x0c0s1b0n0","kernel":"https://example.org/kernel","initrd":"https://example.org/initrd"}' -H 'Content-Type: application/json'
```

What next
Try a PXE boot on your test node. Watch the BSS logs. If it asks for a boot script, you are close. If not, check DHCP and cabling.

Tips from the field
- Keep your first image small. You can add packages later with cloud-init.
- Use a canary group to test changes before you touch many nodes.
- Store BMC credentials in a secrets store and not in Git. Magellan supports a local encrypted store for quick starts.

When you are ready
Add Magellan to discover BMCs and PDUs and send inventory to SMD. Then wire a power tool that reads from SMD and issues Redfish calls. This gives you a clean loop: discover, record, power, boot.

Where this fits
This weekend deploy is not a full site. It is a small, safe start. It helps you see OpenCHAMI in your environment and find gaps early. From here, you can scale services, move to managed databases, and add auth.

References
- Deployment recipes: https://github.com/OpenCHAMI/deployment-recipes
- SMD: https://github.com/OpenCHAMI/smd
- BSS: https://github.com/OpenCHAMI/bss
- Magellan: https://github.com/OpenCHAMI/magellan
- Org: https://github.com/OpenCHAMI

{{< blog-cta >}}