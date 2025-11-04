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

To see how Fabrica works, let's build a real-world API. We'll use it to create an `inventory-api` for tracking hardware assets, based on the OpenCHAMI data model (see [RFD #112](https://github.com/OpenCHAMI/roadmap/issues/112)).

### 1. Understanding the Inventory Model

Our goal is to create a "Device" resource. This resource needs to capture a hardware asset's complete, observed state, including:
* Core identifiers like `deviceType`, `manufacturer`, `partNumber`, and `serialNumber`.
* Relational data, such as its `parentID`.
* A flexible `properties` field for arbitrary key-value data.

### 2. Mapping the Model to Fabrica

To map this model to Fabrica's `spec` and `status` pattern, because our API represents the state of hardware as it actually exists, it all belongs in the `DeviceStatus`. The `DeviceSpec` (the desired state) remains empty, as a user never requests a change to these attributes directly.

From the Fabrica root directory, run the commands to initialize your project:

```bash
fabrica init inventory-api
cd inventory-api
fabrica add resource Device
```

This creates `pkg/resources/device/device.go`. We open it and edit the two generated structs.

**`DeviceSpec`**

We want this struct to be empty. The system, not the user, populates the device data.

```bash
// DeviceSpec defines the desired state of a Device
// This should be empty for our inventory-API, as all data
// is observed state populated by the system.
type DeviceSpec struct {
}
```

**`DeviceStatus`**

We fill the `status` struct with all the fields from our data model. This is the data our system will discover and report back to the user.

```go
// DeviceStatus represents the observed state of a Device
type DeviceStatus struct {
    // Core fields from our data model
    DeviceType   string `json:"deviceType,omitempty"`
    Manufacturer string `json:"manufacturer,omitempty"`
    PartNumber   string `json:"partNumber,omitempty"`
    SerialNumber string `json:"serialNumber,omitempty"`
    ParentID     string `json:"parentID,omitempty"`

    // The arbitrary key-value store
    Properties   map[string]interface{} `json:"properties,omitempty"`
    
    // A read-only list calculated by the system
    ChildrenDeviceIDs []string `json:"childrenDeviceIds,omitempty"`
}
```

### 3. What About the Other Fields?

You may have noticed the data model also requires standard fields like `id`, `apiVersion`, `kind`, `createdAt`, and `updatedAt`.

In OpenCHAMI, these fields are considered part of the standard as decided by the TSC and API working group and Fabrica will automatically generate those for you as part of the "metdata" section of the device. This means that developers only have to think about the data they actually want to store, without needing to know what is required to conform with OpenCHAMI standards.

### 4. Generating and Running the API

Now that our `Device` resource is defined, we can generate and run the API.

**Generate the code:**
Run `fabrica generate` from the project root. Fabrica reads the structs we defined and generates all the handlers, storage, and client code.

```bash
fabrica generate
```

**Install dependencies:**
Next, tidy the Go modules to pull in any new dependencies.

```bash
go mod tidy
```

**Run the server:**
Finally, run the server. It will be live on `localhost:8080`.

```bash
go run ./cmd/server
```

**Test the API:**
**Step 1: Create the "Device" resource envelope.**
A user or system registers a new device by name. 

```bash
# Create a new "Device" resource named "compute-node-01"
curl -X POST http://localhost:8080/devices \
  -H "Content-Type: application/json" \
  -d '{
    "name": "compute-node-01",
    "labels": {"role": "compute", "rack": "r10"}
  }'
```

**Step 2: Simulate an external service updating the device's status.**
An inventory tool discovers the device's properties and populates its `status` by making a `PUT` request to the `/status` endpoint.

```bash
# Update the status for "compute-node-01"
curl -X PUT http://localhost:8080/devices/<uid-from-last-cmd>/status \
  -H "Content-Type: application/json" \
  -d '{
    "deviceType": "Node",
    "manufacturer": "HPE",
    "partNumber": "SYS-1234",
    "serialNumber": "SN-ABC123",
    "properties": {
      "bios_boot_mode": "uefi",
      "dns_domain": "cluster.local"
    }
  }'
```

**Step 3: Get the complete device resource.**
Now, when we query the device, we'll see a device populated with the data from the previous steps:

```bash
curl http://localhost:8080/devices/<uid-from-last-cmd> | jq
```

Output:
```json
{
  "apiVersion": "v1",
  "kind": "Device",
  "schemaVersion": "v1",
  "metadata": {
    "name": "compute-node-01",
    "uid": "dev-f63ead62",
    "labels": {
      "rack": "r10",
      "role": "compute"
    },
    "createdAt": "2025-11-04T09:20:41.897902-08:00",
    "updatedAt": "2025-11-04T09:27:50.092668-08:00"
  },
  "spec": {},
  "status": {
    "deviceType": "Node",
    "manufacturer": "HPE",
    "partNumber": "SYS-1234",
    "serialNumber": "SN-ABC123",
    "properties": {
      "bios_boot_mode": "uefi",
      "dns_domain": "cluster.local"
    }
  }
}
```

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