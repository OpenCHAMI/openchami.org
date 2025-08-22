---
title: "May 2025: OpenCHAMI Newsletter – Q1 Recap & Inaugural Edition"
date: 2025-05-31
summary: "Partnership with HPSF, first production deployment, strong security features, and growing community engagement."
---

# OpenCHAMI Newsletter – Q1 2025 Recap & Updates

Hello and welcome to the OpenCHAMI Monthly Update and Q1 Recap! This edition highlights major developments from the past quarter (Q1 2025) and the past month, including a new foundation partnership, key technical milestones, and community growth.

We’ve seen OpenCHAMI join forces with broader open-source initiatives, achieve its first production deployment, introduce important security and management features, and engage with the HPC community. Read on for all the details and ways to get involved with OpenCHAMI’s journey.

---

## 🚀 Project News & Highlights

### 🤝 OpenCHAMI Joins the High Performance Software Foundation (HPSF)

OpenCHAMI is now part of the [High Performance Software Foundation (HPSF)](https://hpsf.io), a new Linux Foundation initiative for open-source HPC projects. This affiliation:

- Activates a broader HPC developer community
- Provides a neutral open-source governance model
- Reinforces OpenCHAMI’s commitment to collaborative innovation in HPC

This also marks OpenCHAMI’s formal integration into the [Linux Foundation](https://www.linuxfoundation.org/), providing it with a stable, globally recognized open-source home.

---

### 🧪 First Production Deployment at LANL

In February 2025, LANL successfully integrated OpenCHAMI to provision and manage a new HPC cluster using Dell and NVIDIA hardware, as part of LANL’s Institutional Commitment to AI.

> OpenCHAMI is now production-ready for mission-critical AI and HPC workloads.

LANL, a founding consortium member (alongside NERSC, CSCS, HPE, and University of Bristol), demonstrated OpenCHAMI’s real-world value and institutional backing.

---

### ⚙️ Improving Operational Efficiency

One early adopter used OpenCHAMI’s cloud-init based service and WireGuard tunnels to reduce cluster boot times:

> Boot time reduced from **8+ minutes** to **~40 seconds** (after POST) for a 650-node cluster.

This highlights OpenCHAMI’s modern, composable architecture for cloud-inspired HPC infrastructure management.

---

## 🛠️ New Features & Development Progress

### 🔐 Stronger Boot Security

- Replaced static SSH keys with machine-verified identity
- Nodes authenticate via ephemeral WireGuard VPN
- No hard-coded credentials — a zero-trust model for provisioning

[Details here](https://github.com/OpenCHAMI/magellan/issues?q=boot+security)

---

### 🔐 Encrypted BMC Credential Management

Magellan v0.2.0 introduces a `secrets` command to:

- Securely store BMC/IPMI credentials
- Encrypt credentials with AES-GCM
- Enable seamless reuse without re-entry

[Read more](https://github.com/OpenCHAMI/magellan/releases)

---

### ⚡ Faster Provisioning at Scale

- Cloud-native provisioning via cloud-init + microservices
- Optional fallback to Ansible post-boot config
- Supports Podman + systemd, Docker Compose, Kubernetes
- Inventory-driven DHCP/DNS, secure machine identity features

All of this is laying the foundation for the first stable release.

---

## 🌐 Community Highlights & Events

### 🧵 May Events

- **Cray User Group (CUG) 2025** — OpenCHAMI maintainers shared progress in secure, cloud-like cluster management.
- **5th HPC Security Workshop (NIST)** — Discussed OpenCHAMI’s cybersecurity innovations.
- **ISC High Performance 2025** — Tutorials and co-organized workshops on supercomputing/cloud interoperability.

🗓 [Details on future events →](https://openchami.org/events)

---

### 💬 Growing Community Engagement

- More activity on Slack and mailing lists
- RFD (Request for Discussion) process thriving on GitHub
- Developers from multiple institutions collaborating on deployment tips and architecture ideas

💡 [Join the conversation on Slack →](https://openchami.org/slack)

---

## 🧭 Roadmap and Releases

OpenCHAMI is preparing for its **first stable public release**, with goals to:

- Include all core services for turnkey HPC management
- Finalize Redfish-based node management and console services
- Run site-spanning integration tests to ensure robustness

🔄 Release cadence: Quarterly, each supported for up to 3 years.

Though the initial 1.0 was expected in Q1 2025, the team is taking additional time to polish features and integrate community feedback.

Early adopters can use deployment playbooks now from the [release-candidate repo](https://github.com/OpenCHAMI/recipes).

---

## 🤝 Get Involved

There are many ways to contribute:

- **🔧 Contribute on GitHub**
  Browse [open issues](https://github.com/OpenCHAMI/openchami.org/issues), suggest features, or submit a PR.

- **💬 Join RFD Design Discussions**
  Propose or comment on architectural designs in the [RFD repo](https://github.com/OpenCHAMI/rfd).

- **💬 Connect with the Community**
  - [Slack Workspace](https://openchami.org/slack) for real-time chat
  - [Subscribe to the Mailing List](/#subscribe)

- **📢 Attend Events & Spread the Word**
  Look for OpenCHAMI talks at ISC, PEARC, and join us at our Dev Summit in September 2025 in Austin, TX.

---

## 🎉 Thank You!

We’re excited about what lies ahead. With a strong foundation, growing contributions, and a feature-rich release coming soon, **2025 is a pivotal year for OpenCHAMI**.

Got questions or feedback? Reach out on [Slack](https://openchami.org/slack) or email us directly.

_Happy clustering!_
— The OpenCHAMI Team

---

> **Sources:** OpenCHAMI Project Website and Blog, HPSF Announcement, Linux Foundation News, GitHub Repositories
