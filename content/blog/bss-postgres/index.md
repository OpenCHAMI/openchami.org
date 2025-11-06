+++
title = "BSS: Moving from etcd to PostgreSQL for Small Clusters"
description = "Why and how to run the Boot Script Service with PostgreSQL in smaller HPC setups, plus a safe cutover plan."
summary = "A practical guide to switch BSS storage to Postgres with minimal risk."
slug = "bss-postgres"
tags = ["BSS", "PostgreSQL", "boot", "HPC", "OpenCHAMI"]
categories = ["HPC", "Operations"]
contributors = ["Devon T. Bautista (LANL)"]
date = 2023-10-30T16:19:35-06:00
lastmod = 2025-11-06
draft = false
canonical = "/blog/bss-postgres/"
+++

The Boot Script Service (BSS) stores what each node should boot: kernel, initrd, and parameters. In big systems, etcd works well. In small clusters, etcd can be heavy to run and manage. PostgreSQL is a good fit here. It is simple to operate, widely known, and easy to back up.

This post explains why PostgreSQL is a good choice for smaller sites and shows a safe, short cutover. The goal is less overhead without changing how nodes boot.

Why Postgres for small sites
Etcd shines at large scale with strong quorum features. For a lab or a small production cluster, you often want fewer moving parts. Postgres gives you one service to run with built‑in durability and tools you already use.

What changes
Nothing about how nodes request boot scripts. Only the BSS persistence changes. APIs stay the same. Your DHCP flow and iPXE script generation do not change.

Repos
- BSS: https://github.com/OpenCHAMI/bss
- SMD (inventory): https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

Safe cutover plan (≤4 commands)
Always test on a canary group first. This plan backs up etcd data, migrates to Postgres, and verifies on one node before switching the rest.

```bash
# 1) Back up your current etcd data (site-specific)
etcdctl snapshot save bss-etcd.snap

# 2) Start Postgres and set BSS to use it (env or config)
docker compose up -d postgres && export BSS_DB_URL=postgres://bss:pass@localhost:5432/bss?sslmode=disable

# 3) Migrate BSS schema and import data (tooling varies by version)
bss migrate up && bss import --from-etcd bss-etcd.snap

# 4) Point a canary node/group at the new BSS and reboot one node
curl -X POST http://bss.api.cluster/v1/groups/compute-canary/refresh
```

Operational notes
- Backups: schedule Postgres dumps. Keep at least one off-host copy.
- Rollback: keep the etcd snapshot until you are happy with the cutover.
- Audit: store your boot config changes in Git to track who changed what.
- Perf: for images and large files, keep using HTTP servers or object storage; do not put binaries into Postgres.

Verification
After the canary boots, check:
- The node fetched an iPXE script from BSS.
- The kernel and initrd URLs look correct.
- The BSS logs show Postgres connections and no errors.

Common questions
Does Postgres change my API?
No. BSS continues to serve the same endpoints and script format.

Is etcd still supported?
Yes. Use the backend that fits your scale and ops model.

Can I group nodes?
Yes. Use groups to keep configs DRY. Store the mapping in inventory (SMD) and let BSS generate scripts from that.

Wrapping up
If you run a small HPC cluster, running BSS on Postgres lowers your ops load without changing how boots work. Take a snapshot, migrate, test on a canary, and then roll out.

References
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

{{< blog-cta >}}

{{< blog-cta >}}
