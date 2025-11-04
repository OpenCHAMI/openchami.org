---
title: "Using Fabrica to Generate a Hardware Inventory API"
description: "Learn how Fabrica works, what it can do, and create a fully functional Hardware Inventory API in minutes."
date: 2025-11-04T00:00:00+00:00
lastmod: 2025-11-04T00:00:00+00:00
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

To see how Fabrica works, let's build a real-world API. We'll use it to create an `inventory-api` for tracking hardware assets, based on the OpenCHAMI data model (see [RFD 112](https://github.com/OpenCHAMI/roadmap/issues/112)).

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

## Extending Beyond CRUD Operations

What if you need an endpoint that isn't simple CRUD? For example, what if we want a custom endpoint `/devices/summary` that returns a simple report, like `{"total_devices": 5, "types": {"Node": 3, "Rack": 2}}`?

To make this change, we can modify the file that waas generated at `cmd/server/main.go`.

### How it Works

Inside your `main.go` file, the `runServer` function sets up the router. Fabrica's generated routes are plugged in with a single call to `RegisterGeneratedRoutes(r)`.

To add your custom endpoint, you just add your own route handler to the same router, right after Fabrica's routes are registered.

Your `runServer` function already looks like this:

```go
func runServer(cmd *cobra.Command, args []string) error {
    // ... setup logging and storage ...

    // Setup router
    r := chi.NewRouter()

    // Add middleware
    r.Use(middleware.Logger)
    // ... other middleware ...

    // Register routes - generated by 'fabrica generate'
    RegisterGeneratedRoutes(r)
    r.Get("/health", healthHandler)

    // ... start server ...
}
```

To add your new endpoint, you simply add one line and one new function:

```go
func runServer(cmd *cobra.Command, args []string) error {
    // ... setup logging and storage ...

    // Setup router
    r := chi.NewRouter()

    // Add middleware
    r.Use(middleware.Logger)
    // ... other middleware ...

    // Register routes - generated by 'fabrica generate'
    RegisterGeneratedRoutes(r)
    r.Get("/health", healthHandler)

    // === ADD YOUR CUSTOM ROUTE HERE ===
    r.Get("/devices/summary", GetDeviceSummary)
    // ==================================

    // ... start server ...
}

// GetDeviceSummary is your new custom handler.
// It can re-use the generated storage logic from the
// "internal/storage" package, which is already initialized.
func GetDeviceSummary(w http.ResponseWriter, r *http.Request) {
    devices, err := storage.LoadAllDevices(r.Context())
    if err != nil {
        // 'respondError' is a helper in main.go
        respondError(w, http.StatusInternalServerError, err)
        return
    }

    summary := map[string]interface{}{}
    types := map[string]int{}
    for _, dev := range devices {
        types[dev.Status.DeviceType]++
    }

    summary["total_devices"] = len(devices)
    summary["types"] = types

    // 'respondJSON' is a helper in main.go
    respondJSON(w, http.StatusOK, summary)
}
```

So, using Fabrica doesn't limit you to just CRUD operations; if you want to do something else, you just add new routes and handlers, re-using the generated storage and helper functions as needed.

So, now time to test your new function by rerunning the server and hitting the endpoint!

```bash
curl http://localhost:8080/devices/summary | jq
```

---

## What’s Next?

Here we just highlighted the basic features of Fabrica and how you can extend it to do what you'd like. For more advanced features, such as reconciliation, event generation, and such, please see the main **[Fabrica Repository](https://github.com/OpenCHAMI/fabrica)**

Your feedback is valuable! If you'd like to try out this workflow, contribute ideas, or report issues, we invite you to check out the inventory API repository with a complete population script on GitHub: **[https://github.com/bmcdonald3/inventory](https://github.com/bmcdonald3/inventory)**.