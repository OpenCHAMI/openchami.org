---
title: "Magellan: Automated BMC Discovery with OpenCHAMI"
description: "How OpenCHAMI's Magellan simplifies Redfish-based BMC discovery, inventory collection, and integration with the System Management Database (SMD)."
date: 2025-02-03T00:00:00+00:00
lastmod: 2025-02-03T00:00:00+00:00
draft: false
weight: 500
categories: ["Magellan", "BMC", "Infrastructure", "Automation"]
toc: true
tags: ["Redfish", "BMC", "OpenCHAMI", "Hardware Discovery"]
contributors : ["Alex Lovell-Troy"]
---

## **1️⃣ How Magellan Works**

Magellan simplifies the process of discovering and managing BMCs by **automating discovery, data collection, and system integration.**

### **🛠 Example Workflow**

1. **Scan a Subnet for BMC Nodes**
   Magellan automatically discovers **all BMC nodes** in a given subnet.

   ```bash
   ./magellan scan --subnet 172.16.0.0 --subnet-mask 255.255.255.0 --format json --cache data/assets.db
   ```

2. **List Discovered Hosts**
   View a **list of discovered nodes** stored in the cache.

   ```bash
   ./magellan list --cache data/assets.db
   ```

3. **Collect System Information**
   Query **hardware details, firmware versions, and system state** from discovered nodes.

   ```bash
   ./magellan collect --cache data/assets.db --timeout 5 --username $USERNAME --password $PASSWORD --host https://example.openchami.cluster:8443 --output logs/ --cacert cacert.pem
   ```

   *Note: Replace `$USERNAME` and `$PASSWORD` with your BMC credentials.*

---

## **2️⃣ What Happens at Boot?**

When a node boots up, Magellan **automates hardware discovery and inventory collection** in a structured sequence:

1. **Discovery Phase**
   - Magellan scans the network for **active BMCs** using Redfish API queries.
   - Identifies hardware based on **IPMI, Redfish, and manufacturer data.**

2. **Inventory Collection**
   - Queries **CPU, memory, firmware, and system state information** from each discovered node.
   - Stores the data in **JSON format for structured processing.**

3. **SMD Integration**
   - Sends collected data **directly to OpenCHAMI’s System Management Database (SMD)** for centralized tracking.
   - Ensures inventory information is **always up to date** across the cluster.

4. **Firmware Auditing** *(Optional)*
   - Verifies **firmware versions** and flags outdated components.
   - Supports **automated firmware updates** through Redfish when enabled.

---

## **🔗 Next Steps**

- **Explore OpenCHAMI’s Magellan Repo** → [GitHub: OpenCHAMI/magellan](https://github.com/OpenCHAMI/magellan)
- **Learn About Redfish-Based Discovery** → [DMTF Redfish Documentation](https://redfish.dmtf.org/)
- **Automate Your Hardware Inventory with OpenCHAMI** 🚀

---

## **💡 Why Magellan Matters**

✔️ **Eliminates manual inventory tracking** – Automates BMC discovery at scale.
✔️ **Integrates directly with OpenCHAMI’s SMD** – Ensures real-time hardware inventory updates.
✔️ **Reduces operational overhead** – No need for manual node registration.
✔️ **Leverages industry-standard Redfish APIs** – Works seamlessly across multiple vendors.

By using **Magellan**, OpenCHAMI administrators can **simplify BMC discovery, automate system inventory, and improve infrastructure visibility**—all with a single command-line tool.

🚀 **Want to learn more?** Join the OpenCHAMI community and contribute to the future of automated hardware discovery!
