+++
title = "Inventory API in Minutes with Fabrica (OpenCHAMI‑compatible)"
description = "Stand up a clean, OpenCHAMI‑compatible hardware inventory API in minutes using Fabrica’s code generator."
summary = "A practical, ops‑friendly quick start: what you’ll build, how spec/status works, and four commands to get an API running."
slug = "fabrica-inventory"
date = 2025-11-04T00:00:00+00:00
lastmod = 2025-11-06T00:00:00+00:00
draft = false
weight = 10
categories = ["HPC", "Operations"]
tags = ["Fabrica", "Inventory", "API", "OpenCHAMI"]
contributors = ["Ben McDonald"]
canonical = "/blog/fabrica-inventory/"
+++

You often need a small, reliable inventory API long before you need a full CMDB. You want CRUD, a stable schema, OpenAPI, and a storage backend you can swap later. Fabrica gives you that in minutes. It’s a code generator for Go that emits production‑ready HTTP handlers, storage, and OpenAPI. It also follows OpenCHAMI’s resource envelope, so services like SMD or Magellan can consume your data without glue code.

This post walks through a simple “Device” inventory API. You’ll see how the spec/status model works, why it helps operations, and how to get something running with four commands. No framework spelunking. No scaffolding clean‑up.

What you’ll build
You’ll create a tiny service called inventory‑api that:
- Exposes CRUD for Device resources
- Stores data in a simple backend you can replace later
- Publishes OpenAPI and a Swagger UI
- Uses the OpenCHAMI resource envelope (metadata/spec/status)

Why spec/status is useful
Fabrica uses a Kubernetes‑style split between desired state (spec) and observed state (status):
- Spec: what you want. For inventory, you usually don’t “want” the device to change; it already exists.
- Status: what is. This is what your discovery tools report: type, serial, properties.

By keeping spec empty for Device, you signal that inventory is observational. Day‑2 tools can safely update status without worrying about intent. Your UIs and reports get a consistent shape, and you stay aligned with other OpenCHAMI services.

Data shape at a glance
Each Device is wrapped in common metadata (name, uid, labels, createdAt/updatedAt). The spec is empty. The status holds facts your scanners discover: deviceType, manufacturer, partNumber, serialNumber, parent relationships, and a free‑form properties map. Keep properties small and documented; promote stable fields to first‑class keys over time.

Pre‑reqs you likely already have
- Go toolchain and git
- A shell on a dev box or laptop

Quick start (≤4 commands)
This gets you a local API listening on 8080. Replace names to taste.

```bash
fabrica init inventory-api && cd inventory-api
fabrica add resource Device
fabrica generate
go run ./cmd/server
```

Open http://localhost:8080/swagger to explore endpoints and try requests in the browser. You’ll see standard CRUD routes for /devices. Create a resource by name; the server assigns a UID. Update status with facts discovered by your scanners. Retrieve devices with filters to drive reports.

Mapping the model, simply
For a Device resource, keep spec empty and put facts in status:
- deviceType, manufacturer, partNumber, serialNumber
- parentID and children lists if you track hierarchy
- properties map for small, evolving details (firmware, BIOS mode)

Start with the minimal set you need today. Add fields as operational needs harden. Fabrica regenerates handlers and OpenAPI when you evolve the structs.

Operational notes
- Source‑control the schema. Changes to fields are code reviews, not ad‑hoc DB edits.
- Treat generated code as your starting point. You can add custom endpoints (e.g., /devices/summary) right next to the generated routes.
- Keep generated OpenAPI in CI so clients and UIs stay in sync.
- Begin with the file backend for local work. Switch to Postgres/MySQL when you need concurrency and durability.

Integrating with OpenCHAMI
Because the resource envelope matches OpenCHAMI conventions, you can:
- Import devices into SMD later without reshaping everything
- Feed discovery tools (like Magellan) into this API by writing status
- Use labels in metadata for quick filtering (rack, role, owner)

Testing without more commands
From the Swagger UI, POST a Device with a name and labels, then PUT its status with discovered facts. GET it back and confirm the envelope and fields look right. Use browser‑based tools here to keep this guide within four commands.

Hardening next steps
- Add auth in front (reverse proxy or middleware) before exposing widely
- Switch storage to your chosen SQL backend
- Add summaries and reports as custom endpoints
- Wire this into your discovery pipeline and nightly scans

References
- Fabrica: https://github.com/OpenCHAMI/fabrica
- OpenCHAMI org: https://github.com/OpenCHAMI
- OpenCHAMI roadmap RFDs: https://github.com/OpenCHAMI/roadmap

{{< blog-cta >}}