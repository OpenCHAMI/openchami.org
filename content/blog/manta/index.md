---
title: "Introducing Manta: A Cutting-Edge CLI for HPC Infrastructure Management"
date: 2023-10-05T00:00:00Z
draft: false
weight: 12
description: "Discover Manta, a CLI for CSM and OpenCHAMI based HPC systems."
tags: ["Manta", "Introduction", "Productivity"]
categories: ["Development"]
contributors: ["Manuel Sopena Ballesteros", "Miguel Gila", "Matteo Chesi"]
---

# Introducing Manta: A Cutting-Edge CLI for HPC Infrastructure Management

Managing High-Performance Computing (HPC) infrastructure efficiently requires a tool that is both flexible and powerful. **Manta** is a next-generation Command Line Interface (CLI) designed to streamline HPC management for external developers by integrating multiple backend technologies and simplifying complex workflows. Whether you're managing thousands of compute nodes or configuring a single system, Manta provides a seamless and intuitive experience.

## Why Choose Manta?

HPC infrastructures often involve a mix of backend technologies, requiring smooth interactions between components like system management, authentication, configuration, and monitoring. Manta acts as the bridge between these complexities, offering a unified, developer-friendly interface to manage HPC resources effortlessly across diverse environments.

## Key Features of Manta

Manta is designed with flexibility and scalability in mind, featuring an extensive set of capabilities to make HPC management more efficient and accessible.

### **1. Polyglot Architecture for Seamless Backend Interaction**

Manta is built on a **polyglot architecture**, enabling interaction with multiple backend technologies. Currently, it supports:

- **CSM (Cray System Management)**
- **OpenCHAMI (OCHAMI)**

Each backend is encapsulated within an independent library, and the CLI intelligently directs user operations to the appropriate backend, ensuring a smooth and efficient experience.

### **2. Multi-Backend Support for Distributed Environments**

Manta allows users to configure and manage multiple backend instances within a single configuration file. Each backend:

- Can be powered by **CSM or OpenCHAMI**
- Manages different compute nodes or servers
- Operates independently, even if geographically distributed
- Enables seamless switching between backends as needed

This feature makes Manta ideal for organizations with multiple data centers and heterogeneous computing environments.

### **3. Deep Integration with Key HPC Components**

Manta enhances infrastructure management by integrating with critical HPC services:

#### **Get cluster or nodes summary**

The command below will show most common information (groups, nid, power status, CFS configuration used to build boot/rootfs image, boot/rootfs image id, runtime CFS configuration, etc) related to a list of xnames

```
manta get nodes x1001c1s0b0n0,x1001c1s0b0n1
+---------------+-----------+------------+--------------+-------------------------------------------+----------------------+---------+-------------+---------------------+--------------------------------------+
| XNAME         | NID       | HSM        | Power Status | Runtime Configuration                     | Configuration Status | Enabled | Error Count | Image Configuration | Image ID                             |
+===============================================================================================================================================================================================================+
| x1001c1s0b0n1 | nid001289 | alps,      | READY        | fora-mc-compute-config-cscs-24.8.0.r0-0.2 | configured           | true    | 0           | Not found           | d39fedce-82e3-48d5-bd83-534f37c74c0c |
|               |           | fora,      |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_cn,   |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_nc,   |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_test2 |              |                                           |                      |         |             |                     |                                      |
|---------------+-----------+------------+--------------+-------------------------------------------+----------------------+---------+-------------+---------------------+--------------------------------------|
| x1001c1s0b0n0 | nid001288 | alps,      | READY        | fora-mc-compute-config-cscs-24.8.0.r0-0.2 | configured           | true    | 0           | Not found           | d39fedce-82e3-48d5-bd83-534f37c74c0c |
|               |           | fora,      |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_ns,   |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_uan   |              |                                           |                      |         |             |                     |                                      |
+---------------+-----------+------------+--------------+-------------------------------------------+----------------------+---------+-------------+---------------------+--------------------------------------+
```

Note: If CFS session is deleted, then manta won't be able to find the CFS configuration used to build the image.

#### **Boot Configuration Management**

- **Integration with BSS (Boot Script Service)** to define and configure node boot settings efficiently.
- **Sanitization and management of kernel parameters** to ensure a consistent and secure runtime environment across nodes.
- **Support for modifying kernel parameters dynamically** to adapt to specific workload requirements or security policies.

##### Example Usage:

Assume we want to change the kernel parameters for two nodes: `nid001288` and `nid001289`.

```
manta get kernel-parameters -n 'nid00128[8-9]'
```

This command lists and groups nodes based on shared kernel parameters, making it easier to manage configurations across multiple  nodes.

```
+---------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| XNAME         | Kernel Params                                                                                                                                                                                          |
+========================================================================================================================================================================================================================+
| x1001c1s0b0n0 | console=ttyS0,115200                                                                                                                                                                                   |
| x1001c1s0b0n1 | nmd_data=url=s3://boot-images/d39fedce-82e3-48d5-bd83-534f37c74c0c/rootfs,etag=89a5bd99d9c940ffa992308dc68c53a3-646 quiet                                                                              |
|               | root=craycps-s3:s3://boot-images/d39fedce-82e3-48d5-bd83-534f37c74c0c/rootfs:89a5bd99d9c940ffa992308dc68c53a3-646:dvs:api-gw-service-nmn.local:300:nmn0,hsn0:true spire_join_token=${SPIRE_JOIN_TOKEN} |
+---------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
```

Now, we want to add two new kernel parameters: `test=test` and `quiet`.

```
manta add kernel-parameters -n 'nid001288,  nid001289' 'test=test test=test2 quiet'
Add kernel params:
"test=test test=test2 quiet"
For nodes:
"x1001c1s0b0n0, x1001c1s0b0n1"
✔ This operation will add the kernel parameters for the nodes below. Please confirm to proceed · yes
? "x1001c1s0b0n0, x1001c1s0b0n1"
✔ "x1001c1s0b0n0, x1001c1s0b0n1"
The nodes above will restart. Please confirm to proceed? · no
Cancelled by user. Aborting.
```

Manta detects that the kernel parameters have changed and prompts the user for confirmation before applying updates, ensuring controlled modifications.

Also, kernel parameter test is specified twice but manta only stores it once.

To filter specific kernel parameters when inspecting configurations:

```
manta get kernel-parameters -n 'nid00128[8-9]' -f quiet,test
+---------------+---------------+
| XNAME         | Kernel Params |
+===============================+
| x1001c1s0b0n0 | quiet         |
| x1001c1s0b0n1 | test=test2    |
+---------------+---------------+
```

If a kernel parameter already exists, Manta prevents duplication, ensuring sanitized and clean configurations.

To remove a specific kernel parameter:

```
manta delete kernel-parameters -n nid001289 test
```

After executing this command, Manta confirms the operation and removes the specified parameter, maintaining a streamlined and consistent kernel configuration across nodes.

These capabilities allow administrators to maintain consistency across nodes while also offering flexibility for tuning kernel settings dynamically.

#### **Hardware and Inventory Management**

- **Integration with HSM (Hardware State Manager)** to organize compute groups, track hardware inventory, and manage Ethernet interfaces and Redfish endpoints.
- **Automatic translation of hardware definitions into node lists** to migrate compute nodes with identical hardware configurations across different management planes.

##### Example Usage:

Get hardware summary for all nodes in HSM group fora

```
manta get hardware cluster fora
+------------------------------------+----------+
| HW Component                       | Quantity |
+===============================================+
| Memory (GiB)                       | 3072     |
|------------------------------------+----------|
| SS11 200Gb 2P NIC Mezz REV02 (HSN) | 12       |
|------------------------------------+----------|
| AMD EPYC 7742 64-Core Processor    | 24       |
+------------------------------------+----------+
```

Get hardware summary broken down by xname

```
manta get hardware cluster fora -o details
+---------------+-----------+---------------------------------+------------------------------------+
| Node          | 16384 MiB | AMD EPYC 7742 64-Core Processor | SS11 200Gb 2P NIC Mezz REV02 (HSN) |
+==================================================================================================+
| x1001c1s0b0n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s0b0n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s0b1n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s0b1n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b0n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b0n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b1n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b1n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b0n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b0n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b1n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b1n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
+---------------+-----------+---------------------------------+------------------------------------+
```

#### **Authentication and Security**

- **Integration with Keycloak** for centralized user authentication.
- **Integration with HashiCorp Vault** to securely retrieve and manage secrets, improving security best practices.

##### Example Usage:

```
manta auth login --user <username>
```

#### **Kubernetes Integration for Enhanced Observability**

- Direct connectivity to **node consoles**.
- Seamless access to **CFS session logs** via Kubernetes, making debugging and monitoring easier.

##### Example Usage:

```
manta logs fetch --session <session_id>
```

#### **Version Control and Configuration Management**

- **Integration with CFS (Configuration Framework Service)** to build boot images efficiently.
- **Gitea integration** to fetch configuration layer details such as commit metadata (committer, date, and time).
- **Expanded CFS configuration options** by introducing **git tags**, complementing the existing **git branch** and **git commit** functionalities.

##### Example Usage:

```
manta cfs config --layer <layer_name> --git-tag <tag_name>
```

#### **Runtime Configuration and Command Execution**

- Enables **real-time node configuration**, providing agility in handling live infrastructure updates.
- **Replicates SAT (System Administration Toolkit) operations**, ensuring continuity with familiar HPC administration tools.

##### Example Usage:

```
manta node configure --runtime --config-file <file_path>
```

## Why Manta Stands Out

Unlike traditional CLI tools, Manta is designed with **modern HPC workflows in mind**. Its ability to interact with multiple backend technologies, support distributed infrastructure, and provide deep integration with Kubernetes and security services makes it a **game-changer for HPC administrators and developers**.

## Get Started with Manta

Manta is built for **HPC administrators and developers** looking for a powerful yet intuitive CLI for infrastructure management. By abstracting backend complexities and offering a robust set of integrations, Manta **simplifies complex workflows, enhances security, and provides greater control over compute nodes and servers**.

Stay tuned for detailed guides, real-world use cases, and tutorials on how to make the most of Manta. If you're interested in testing or contributing to the project, reach out—we'd love to collaborate!

