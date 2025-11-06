+++
title = "Bootstrapping Without SSH Keys: OpenCHAMI’s Simple, Safer Path"
description = "Replace embedded SSH keys with short‑lived WireGuard and cloud‑init. A clean way for HPC nodes to prove identity and get configured."
date = 2025-02-03T00:00:00+00:00
lastmod = 2025-02-03T00:00:00+00:00
draft = false
weight = 10
categories = ["Security", "HPC", "Cloud-Init", "WireGuard"]
tags = ["SSH", "WireGuard", "TPM", "HPC Security"]
contributors = ["Alex Lovell-Troy"]
+++

Bootstrapping nodes should be safe and simple. Many clusters still rely on embedded SSH keys in golden images. Those keys linger for years, and anyone with the private key can reach every node. OpenCHAMI removes this risk by switching to short‑lived WireGuard tunnels and cloud‑init. Nodes prove who they are, fetch only what they need, and then the tunnel goes away.

This post explains the flow in plain terms and gives you a small, testable path you can try on a lab node.

What changes
- No embedded SSH keys in images
- Short‑lived WireGuard tunnel during boot
- cloud‑init runs the baseline config and stops when done

How it fits in OpenCHAMI
OpenCHAMI services provide the boot script and inventory. BSS (Boot Script Service) points a node at a cloud‑init data source. SMD tracks node state and attributes. A small web service accepts a node’s WireGuard public key, opens a tunnel, and serves cloud‑init only inside that tunnel.

Repos
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

Minimal try‑it flow (≤4 commands)
The exact endpoints will vary by site. This gives you a safe way to test in a lab. Replace URLs and names for your cluster.

```bash
# 1) Generate a WireGuard key on the node
wg genkey | tee /etc/wireguard/node.key | wg pubkey > /etc/wireguard/node.pub

# 2) Send the public key to your cloud‑init service (opens a short‑lived tunnel)
curl -X POST -H 'Content-Type: application/json' \
    -d "$(jq -n --arg key "$(cat /etc/wireguard/node.pub)" '{pubkey:$key, node:"compute-01"}')" \
    http://cloudinit.local/v1/register

# 3) Reboot the node so it fetches boot params and cloud‑init over the tunnel
reboot
```

Operational details
- Scope: keep cloud‑init small. Install heavy packages in images or via a post‑boot agent.
- Rollouts: use a canary group to test a new cloud‑init blob on one node first.
- Audit: keep cloud‑init blobs and changes in Git for easy review.
- Recovery: keep a known‑good config and switch the group back if needed.

Secrets
Do not put secrets in cloud‑init files. Use a secrets manager or have the node agent fetch credentials after boot. If you must pass a token, keep it short‑lived and scoped.

TPM is next
Today, we accept a node’s public key and network checks. The next step is TPM‑based attestation so nodes can prove identity with hardware‑backed signatures. This adds strong proof while keeping the same boot flow.

Why this helps
The result is lower risk and less toil. No more image rebuilds to rotate SSH keys. No persistent backdoors. Nodes declare themselves, do their work, and the access path closes.

References
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI


{{< blog-cta >}}


