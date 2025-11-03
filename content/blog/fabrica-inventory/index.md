---
title: "Should I use Fabrica? Getting Started and Creating a Hardware Inventory API"
description: "Learn how Fabrica works, what it can do, and create a fully functional Hardware Inventory API with Fabrica."
date: 2025-11-03T00:00:00+00:00
lastmod: 2025-11-03T00:00:00+00:00
draft: false
weight: 10
categories: ["HPC", "Hardware", "Inventory"]
tags: ["Fabrica", "Hardware", "Inventory"]
contributors: ["Ben McDonald"]
---

## What is Fabrica?

Fabrica is a command-line tool designed to accelerate the development of production-ready REST APIs in Go.

At its core, Fabrica is a code generator. The primary workflow involves defining your API's resources as simple Go structs. Once you define these structs, Fabrica generates the complete, surrounding API infrastructure. This generated code includes:

* CRUD (Create, Read, Update, Delete) HTTP handlers.
* A choice of multiple backends, including simple file-based storage (for development) and SQL databases for production.
* Automatically generated OpenAPI 3.0 documentation, which also provides a usable Swagger UI.
* A type-safe Go client for interacting with your new API.

Fabrica is designed to automatically conform to the OpenCHAMI specifications, decided upon by the OpenCHAMI Technical Steering Committee and members of the API working group, so that code will automatically be OpenCHAMI compliant.

A key concept Fabrica uses is its Kubernetes-inspired resource structure. Every resource you create is wrapped in a standard "envelope" that separates the `spec` from the `status`.

* The `spec` is the *desired state* of the resource.
  * e.g., "I want this node to be powered on"
  * can be updated by the user
* The `status` is the  observed state of the resource.
  * e.g., "This node is powered off".
  * this is updated by the system, not the user
  * can be thought of representing what "actually is" at a moment in time

This separation provides a clear and consistent pattern for managing resource state, a pattern common in cloud-native tools.

---

## Let's give it a try... 

The workflow for managing BMCs and PDUs with OpenCHAMI tools involves four key components:

1.  **Magellan**: Our discovery and inventory tool. It scans the network to find hardware and collects detailed component data.
2.  **State Management Database (SMD)**: The central repository, or "single source of truth." Magellan populates SMD with every endpoint it discovers.
3.  **Vault**: A secure secret store. Administrators place the credentials for discovered hardware here.
4.  **Power Control Service (PCS)**: PCS monitors SMD for new hardware. When a new endpoint appears, PCS retrieves its credentials from Vault and begins **actively polling** the device's `Redfish` or `JAWS` interface every 20 seconds to maintain its current power state.

This polling architecture means that PCS isn't just a passive proxy; it's a stateful service that provides a near real-time, cached view of the entire data center's power status.

---

## Step-by-Step Guide: From Discovery to Power-On

Let's walk through the full workflow. This demonstrates how an administrator registers new hardware and then uses PCS to manage it.

### Prerequisite: Mapping IPs to xnames

Before you begin, you will need to know the mapping between your device IP addresses and their corresponding `xname` identifiers (e.g., mapping `10.254.1.26` to `x3000m0`). This demonstration assumes this mapping is known.

### Step 1: Discover and Inventory Hardware with Magellan

First, we use Magellan to discover a PDU and collect its inventory. This information is then sent to SMD.

```bash
# Discover, collect, and send PDU inventory to SMD in one pipe
magellan collect pdu x3000m0 | magellan send http://localhost:27779
```

Next, we do the same for a BMC.

```bash
# Discover, collect, and send BMC inventory to SMD
magellan collect "https://172.24.0.2" | magellan send http://localhost:27779
```

At this point, SMD contains the hardware inventory, but PCS doesn't know how to access it yet.

### Step 2: Store Credentials in Vault

The next step is for the administrator to securely store the credentials for `x3000m0` and the BMCs in a Vault instance that PCS is configured to read from. Once the credentials are in Vault, the lifecycle is complete.

### Step 3: Let PCS Take Over

On its next cycle, PCS will:
1.  Query SMD and see the new endpoints (`x3000m0`, `x1000c1s7b0`, etc.).
2.  Fetch their credentials from Vault.
3.  Begin polling their power state every 20 seconds.

### Step 4: Query and Control Power with PCS

Now, we can interact with PCS. When we query PCS, we get an immediate response from its internal state cache—we don't have to wait for a live poll to the device. This can prevent overloading the hardware with requests, but also means that the current state may need to wait for the next 20 second polling cycle.

Let's check the power status of a management node and a PDU outlet. Note the API call is identical; only the `xname` changes.

```bash
# Get power status of a node managed by a BMC
curl -sS -X GET http://localhost:28007/v1/power-status?xname=x1000c1s7b0n0 | jq '.'

# Get power status of an outlet managed by a PDU
curl -sS -X GET http://localhost:28007/v1/power-status?xname=x3000m0p0v17 | jq '.'
```

Now, let's execute a power `Off` command on the BMC node.

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"operation": "Off", "location": [{"xname": "x1000c1s7b0n0"}]}' \
  http://localhost:28007/v1/transitions
```

PCS receives this command, performs the action on the device, and its next polling cycle will confirm the new "off" state, updating its cache for all future queries. We can do the exact same thing for the PDU outlet using the same consistent API.

---

## What’s Next?

With these enhancements, OpenCHAMI has taken a major step forward in unified, programmatic hardware management. The stateful, polling model we've established could easily be extended to manage other critical data center hardware, such as network switches or smart cooling units, under the same consistent API.

Your feedback is valuable! If you'd like to try out this workflow, contribute ideas, or report issues, we invite you to check out the demo repository on GitHub: **[https://github.com/bmcdonald3/openchami-demo](https://github.com/bmcdonald3/openchami-demo)**.