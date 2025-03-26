---
title: "Introducing Manta: A CLI for HPC Infrastructure Management"
date: 2023-10-05T00:00:00Z
draft: false
weight: 12
description: "Discover Manta, a CLI for CSM and OpenCHAMI based HPC systems."
tags: ["Manta", "Introduction", "Productivity"]
categories: ["Development"]
contributors: ["Manuel Sopena Ballesteros"]
---


Managing High-Performance Computing (HPC) infrastructure efficiently requires a tool that is both flexible and powerful. **Manta** is a new Command Line Interface (CLI) designed to streamline HPC management for external developers by integrating multiple backend technologies and simplifying complex workflows.
## Why Manta?
HPC infrastructures often involve multiple backend technologies and require seamless interaction between various components such as system management, authentication, configuration, and monitoring. Manta is designed to bridge these complexities, providing a unified interface for managing HPC resources across different environments.
### Key Features of Manta
Manta is packed with a range of features that make HPC management easier and more efficient:
### **1. Polyglot Architecture**
Manta is built with a **polyglot architecture**, meaning it can interact with multiple backend technologies. Currently, it supports:
- **CSM (Cray System Management)**
- **OpenCHAMI (OCHAMI)**
Each backend is implemented through an independent library, and the CLI intelligently directs user operations to the appropriate backend library.
### **2. Support for Multiple Backend Instances**
Manta allows users to provide a configuration file that can manage multiple backend instances. Each backend:
- Can be powered by **CSM or OpenCHAMI**
- Can manage different compute nodes or servers
- Can be located in geographically distributed data centers
- Supports seamless switching between different backends as needed
### **3. Integration with Key HPC Components**
Manta integrates with several essential HPC components to enhance infrastructure management:
#### **Boot Configuration Management**
- **Integration with BSS (Boot Script Service)** to configure node boot settings.
#### **Hardware and Inventory Management**
- **Integration with HSM (Hardware State Manager)** to manage groups, hardware inventory, and Ethernet interfaces.
- **Translates hardware definitions into a list of nodes** to migrate sets of compute nodes with same hardware components across different management planes.
#### **Authentication and Security**
- **Integration with Keycloak** for user authentication.
- **Integration with HashiCorp Vault** to securely fetch and manage secrets.
#### **Kubernetes Integration**
- Connect to **node consoles** and fetch **CFS logs**.
- Fetch **CFS session logs** via Kubernetes.
#### **Configuration and Version Control**
- **Integration with CFS (Configuration Framework Service)** to build boot images.
- **Integration with Gitea** to fetch CFS configuration layer details (e.g., committer, commit date, and time).
- **CFS configuration layers improvement** by adding support for **git tags**, alongside the existing **git branch** and **git commit** options.
#### **Runtime and Command Execution**
- Manta enables users to **configure nodes during runtime**, providing flexibility in handling on-the-fly configuration updates.
- **Replica of SAT (System Administration Toolkit) operations** for consistency and familiarity with existing tools.
## Conclusion
Manta is built for **HPC administrators, developers, and researchers** who need a powerful yet flexible CLI to manage their infrastructure. By integrating with multiple backend technologies and key HPC components, Manta simplifies complex workflows and provides greater control over compute nodes and servers.