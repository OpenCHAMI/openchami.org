---
title: "🏗️  OpenCHAMI Software Architecture Overview"
description: "A high-level overview of OpenCHAMI's architecture, including its core components and how they interact."
date: 2025-02-03T00:00:00+00:00
lastmod: 2025-02-03T00:00:00+00:00
draft: false
weight: 10
toc: true
---


OpenCHAMI is a modular system management framework designed to support **High Performance Computing (HPC)** environments with **cloud-like scalability and security**. This section provides an overview of its core architecture and how its components interact.

## 🔧 Core Components

- **BSS (Boot Script Service):** Handles customized boot parameters for compute nodes.
- **SMD (State Management Daemon):** Maintains inventory and node health status.
- **Magellan:** Discovers and manages server hardware using Redfish APIs.
- **OPAAL:** Handles authentication and authorization (OIDC-based).
- **Configurator:** Dynamically generates configuration files from templates.

## 🔄 How Components Interact

OpenCHAMI follows a **microservices-based** approach where each service operates independently but communicates through a secure API. Below is a high-level diagram illustrating these interactions:

```mermaid
graph TD;
    User("User/Admin") -->|Access| OPAAL("OPAAL: Authentication & Identity");

    OPAAL -->|Issues Tokens| API("OpenCHAMI API Gateway");
    User -->|Discover Hardware| Magellan("Magellan: Inventory Discovery");


    API -->|Update Boot Config| BSS("BSS: Boot Script Service");
    API -->|Query/Set System State| SMD("SMD: State Management Daemon");
    API -->|Customize Configs| Cloud-Init("Cloud-Init: Config Management");

    
    BSS -->|Provide Boot Parameters| ComputeNodes("Compute Nodes");
    SMD -->|Track System State| ComputeNodes;
    SMD -->|Provide Inventory Details| Cloud-Init;
    SMD -->|Provide Inventory Details| BSS;
    SMD -->|Provide Inventory Details| CoreDHCP;
    Magellan -->|Report Inventory| SMD;
    Cloud-Init -->|Provide Customized Configurations| ComputeNodes;
    CoreDHCP -->|Provide IP Addresses|ComputeNodes; 
```

## 🚀 Key Architectural Benefits

✅ **Security-First Design** – Implements **zero-trust authentication**, fine-grained **access control**, and **OIDC-based authorization**.  
✅ **Composable & Scalable** – Modular microservices allow for flexible deployments across **cloud and on-prem** environments.  
✅ **Microservices-Based** – Each component operates independently, ensuring **fault tolerance and easy upgrades**.  
✅ **Cloud-Like Flexibility** – HPC system management with the **efficiency of cloud platforms**.  

## 📌 Next Steps

- Learn more about **[Early Design Decisions](/architecture/design_decisions/)**.
- Dive deeper into **[Security & Authentication](/architecture/security/)**.
- Explore how to **[Deploy OpenCHAMI](/guides/getting_started/)**.
