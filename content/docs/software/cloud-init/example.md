---
title: "🔧 Dynamic Cloud-Init Configuration in OpenCHAMI"
description: "How OpenCHAMI uses Cloud-Init to provision nodes dynamically with security, automation, and flexibility."
date: 2025-02-03T00:00:00+00:00
lastmod: 2025-02-03T00:00:00+00:00
draft: false
categories: ["Cloud-Init", "HPC", "Infrastructure", "Automation"]
tags: ["Cloud-Init", "Provisioning", "WireGuard", "Security"]
contributors: ["Alex Lovell-Troy"]
---

## **Introduction: Automating Node Bootstrapping with Cloud-Init**

Managing a High-Performance Computing (HPC) cluster requires **automated, secure, and scalable provisioning**. OpenCHAMI leverages **Cloud-Init** to dynamically configure compute and IO nodes at boot, ensuring each node receives the right software, security policies, and storage setup.

This post walks through a **real-world example** using **Cloud-Init's group-based configurations** to set up **two different node types**, each with its own **automated bootstrapping**.

---

## **🔹 The Use Case: Multi-Group Node Provisioning**

We’ll configure **two nodes**, each belonging to **different Cloud-Init groups**:

- **Node 1: Compute Node**  
  - **Groups:** `slurm`, `tenant-foo`  
  - **Config:** Installs **Slurm from OpenHPC**, adds a `root-foo` user with sudo and SSH.

- **Node 2: IO Node**  
  - **Groups:** `tenant-foo`, `ephemeral-storage`  
  - **Config:** Adds `root-foo` with SSH, ensures `/dev/sda1` is partitioned and formatted, then mounts it to `/opt/ephemeral`.

Each group contributes **specific configurations**, and nodes receive the combined settings from all groups they belong to.

---

## **1️⃣ Setting Up Group-Based Cloud-Init Configurations**

### **📝 Slurm Group: Installing OpenHPC's Slurm Client**

```bash
SLURM_CLOUD_CONFIG_CONTENT=$(cat <<EOF
#cloud-config
package_update: true
package_upgrade: true
yum_repos:
  OpenHPC:
    baseurl: https://repos.openhpc.community/OpenHPC/3/EL_9/
    enabled: true
    gpgcheck: false
    name: OpenHPC
packages:
  - ohpc-slurm-client
EOF
)

SLURM_JSON_PAYLOAD=$(cat <<EOF
{
  "name": "slurm",
  "description": "Nodes in this group install Slurm from OpenHPC",
  "file": {
    "content": "$(echo "$SLURM_CLOUD_CONFIG_CONTENT" | base64 -w 0)",
    "encoding": "base64"
  }
}
EOF
)

curl -X PUT http://localhost:27777/cloud-init/admin/groups/slurm      -H "Content-Type: application/json"      -d "$SLURM_JSON_PAYLOAD"
```

---

### **📝 Tenant-Foo Group: Adding a Privileged User with SSH Access**

```bash
TENANT_FOO_CLOUD_CONFIG_CONTENT=$(cat <<EOF
#cloud-config
users:
  - name: root-foo
    gecos: "Tenant Foo User"
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    ssh_authorized_keys:
      - "ecdsa-sha2-nistp256 AAAAE2...user@domain.com"
EOF
)

TENANT_FOO_JSON_PAYLOAD=$(cat <<EOF
{
  "name": "tenant-foo",
  "description": "Adds root-foo with sudo and SSH key",
  "file": {
    "content": "$(echo "$TENANT_FOO_CLOUD_CONFIG_CONTENT" | base64 -w 0)",
    "encoding": "base64"
  }
}
EOF
)

curl -X PUT http://localhost:27777/cloud-init/admin/groups/tenant-foo      -H "Content-Type: application/json"      -d "$TENANT_FOO_JSON_PAYLOAD"
```

---

### **📝 Ephemeral Storage Group: Formatting and Mounting `/dev/sda1`**

```bash
EPHEMERAL_STORAGE_CLOUD_CONFIG_CONTENT=$(cat <<EOF
#cloud-config
disk_setup:
  /dev/sda:
    table_type: gpt
    layout: true
    overwrite: false

fs_setup:
  - label: ephemeral-storage
    filesystem: xfs
    device: /dev/sda1
    partition: auto

mounts:
  - [ "/dev/sda1", "/opt/ephemeral", "xfs", "defaults,nofail", "0", "2" ]
EOF
)

EPHEMERAL_STORAGE_JSON_PAYLOAD=$(cat <<EOF
{
  "name": "ephemeral-storage",
  "description": "Ensures /dev/sda1 is partitioned, formatted as XFS, and mounted at /opt/ephemeral",
  "file": {
    "content": "$(echo "$EPHEMERAL_STORAGE_CLOUD_CONFIG_CONTENT" | base64 -w 0)",
    "encoding": "base64"
  }
}
EOF
)

curl -X PUT http://localhost:27777/cloud-init/admin/groups/ephemeral-storage      -H "Content-Type: application/json"      -d "$EPHEMERAL_STORAGE_JSON_PAYLOAD"
```

---

## **2️⃣ What Happens at Boot?**

At boot, each node requests cloud-init information in a **standard order**:

1. **Requests `/meta-data`**:  
   - Retrieves **inventory information**, including a unique **instance-id** for each boot.  
   - Includes **hostname, location, and other identity details** when available.  

2. **Requests `/user-data`**:  
   - Reserved for future use, currently empty in OpenCHAMI.  

3. **Requests `/vendor-data`**:  
   - Returns a **list of cloud-config YAML files**, one for each group the node belongs to.  
   - Example: If a node is part of `io` and `tenant-foo`, it receives a list of:
     ```yaml
     /io.yaml
     /tenant-foo.yaml
     ```

4. **Processes Cloud-Config Files**:  
   - The cloud-init client **fetches each listed YAML file**, parses them, and applies configurations.  

5. **Sends `phone-home` Confirmation**:  
   - After processing all `#cloud-config` files, the node sends a **status update** to the cloud-init server indicating **it has fully booted**.  

### **🚀 Example Boot Configurations**
- **Compute Node (Groups: `slurm`, `tenant-foo`)**  
  ✅ Installs **Slurm**  
  ✅ Adds **root-foo** user with **SSH and sudo access**  

- **IO Node (Groups: `tenant-foo`, `ephemeral-storage`)**  
  ✅ Adds **root-foo** user with **SSH access**  
  ✅ **Partitions and formats `/dev/sda1` if necessary**  
  ✅ **Mounts `/dev/sda1` to `/opt/ephemeral`**  

---

## **🔗 Next Steps**
- **Explore OpenCHAMI’s Cloud-Init Repo** → [GitHub: OpenCHAMI/cloud-init](https://github.com/OpenCHAMI/cloud-init)
- **Learn About Secure Bootstrapping with WireGuard** → [Security Docs](/blog/2025/02/a-new-approach-to-security-how-openchami-eliminates-hardcoded-ssh-keys/)
- **Define Custom Configurations for Your Nodes** 🚀

---

## **💡 Why This Matters**
✔️ **Uses OpenCHAMI’s API correctly** (Base64-encoded JSON).  
✔️ **Automates cluster-wide provisioning** without manual intervention.  
✔️ **Ensures each node gets exactly what it needs based on its role**.  

By leveraging **Cloud-Init with OpenCHAMI**, HPC admins can **securely and automatically configure compute and IO nodes at scale**—without managing per-node configurations manually.

🚀 **Want to see more Cloud-Init examples?** Join the OpenCHAMI community and help shape the future of HPC automation!

