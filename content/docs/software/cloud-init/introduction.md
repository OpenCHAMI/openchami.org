---
title: "Cloud-Init Makes It Personal"
description: "Cloud-Init provides each node with identity and individualized post-boot scripts."
summary: ""
date: 2024-03-07T16:13:18+02:00
lastmod: 2024-03-07T16:13:18+02:00
draft: false
weight: 10
toc: true
seo:
  title: "Cloud-Init in OpenCHAMI"
  description: "Cloud-Init in OpenCHAMI brings flexible, automated, and secure configuration to compute nodes."
  canonical: ""
  noindex: false
---

## **🔧 Cloud-Init: Flexible, Automated, Secure**

[Cloud-Init](https://cloud-init.io/) is the de facto standard for customizing cloud instances at boot. OpenCHAMI extends this power to **compute nodes**, ensuring that every system gets the right configuration **at the right time**.

### **🚀 Why Cloud-Init in OpenCHAMI?**
✔️ **Per-node identity** – Dynamically assigns each node an identity and configurations tailored to its role.  
✔️ **Automated bootstrapping** – Ensures all compute nodes start with the correct software, settings, and secrets.  
✔️ **WireGuard integration** – Establishes **secure, encrypted tunnels** between nodes and the cloud-init server.  
✔️ **Group-based configurations** – Assign settings per **node group, hardware type, or workload profile**.  
✔️ **Immutable, stateless provisioning** – Define everything declaratively and keep nodes clean.


---

## **🔗 Learn More & Get Started**
- 📖 **Explore the Cloud-Init repo:** [GitHub: OpenCHAMI/cloud-init](https://github.com/OpenCHAMI/cloud-init)
- 🛠 **Configure your own cloud-init payloads:** [Example Configs](https://github.com/OpenCHAMI/cloud-init/tree/main/demo)
- 🔐 **Read about WireGuard security integration:** [Security Docs](/docs/security/bootstrapping/)
- 💬 **Join the OpenCHAMI community:** [Discussions](https://github.com/OpenCHAMI/community)

With OpenCHAMI, **Cloud-Init isn’t just for cloud instances—it’s for your entire compute fleet.** 🚀
