+++
title = "Introduction to the Inventory service: A replacement for SMD"
description = "A brief overview of setting up and using the inventory service."
date = 2026-04-24T00:00:00+00:00
lastmod = 2026-04-24T00:00:00+00:00
draft = false
weight = 10
categories = ["HPC", "Operations", "Services"]
tags = ["OpenCHAMI", "Inventory", "inventory-service", "Fabrica"]
contributors = ["Shane Unruh"]
+++

1. [Inventory Service Overview](#inventory-service-overview)
    1. [IDs in the Inventory Service](#ids-in-the-inventory-service)
1. [Running the Service](#running-the-service)
    1. [Run in a Quadlet](#run-in-a-quadlet)
    1. [Run from local binary](#run-from-local-binary)
    1. [Run using docker image](#run-using-docker-image)
        1. [Example building locally](#example-building-locally)
    1. [Run in the quickstart](#run-in-the-quickstart)
    1. [Test With SMD](#test-with-smd)
1. [REST Endpoints](#rest-endpoints)


## Inventory Service Overview

[Inventory service](https://github.com/OpenCHAMI/inventory-service) is a replacement for the older [SMD service](https://github.com/OpenCHAMI/smd).
It is an OpenCHAMI service developed using [Fabrica](https://github.com/OpenCHAMI/fabrica).

Inventory service implements enough of the APIs on SMD to be a drop in replacement for SMD in OpenCHAMI.
The goal is to support enough of the original SMD APIs,
such that exiting clients of SMD do not need to change.
For example, [PCS](https://github.com/OpenCHAMI/power-control) should work with either SMD or Inventory service.
Inventory service is not 100% backward compatible with SMD.

The primary way that Inventory service differs from SMD is that SMD supports discovering nodes.
i.e. it makes the redfish calls to the Node's Management processor and collects all the information about the node.
Inventory service does not do this.

The rationales for creating Inventory service are as follows:
1. To be more flexible in the data that is stored. For example, to allow IDs other than xnames.
2. To support the OpenCHAMI style REST API
3. To make it easier to add new APIs and capabilities.
3. To have a service that is less complex then the current SMD.
   - It does this by not bringing forward the discovery capabilities.

### IDs in the Inventory Service

Fabrica based services assign a UID to each resource when it is created.
SMD allows the user to pick the ID for each resource, with the exception that the ID is limited to the xname format.
Inventory assigns UIDs at creation time in the same way as any other fabrica based service.
It also enforces uniqueness for the fields that were IDs in SMD; however, it does not require that these IDs be xnames.

| Resource            | Unique Spec field                                        |
|---------------------|----------------------------------------------------------|
| Component           | Spec.ID                                                  |
| ComponentEndpoint   | Spec.ID                                                  |
| EthernetInterface   | Spec.ID                                                  |
| Group               | Spec.Label                                               |
| Hardware            | Spec.ID                                                  |
| RedfishEndpoint     | Spec.ID                                                  |
| ServiceEndpoint     | Spec.RedfishType + "-" + Spec.RedfishEndpointID          |

The uniqueness of these fields are enforced in the Database schema.

## Running the Service

The service can be run in multiple ways

### Run in a quadlet

This shows to how to run as a quadlet as is done in the [OpenCHAMI Tutorial](https://openchami.org/docs/tutorial/)

Create the file `inventory-service.container` in `/etc/containers/systemd` with the following contents

```
[Unit]
Description=The inventory service container
PartOf=openchami.target

# Don’t start until the network has started
Requires=openchami-internal-network.service openchami-jwt-internal-network.service
After=openchami-internal-network.service openchami-jwt-internal-network.service

# Don’t start until JWKS is ready:
Wants=hydra-gen-jwks.service
After=hydra-gen-jwks.service

[Container]
ContainerName=inventory-service
HostName=inventory
Image=localhost/inventory-service:latest

# Environment Variables
EnvironmentFile=/etc/openchami/configs/openchami.env

# Secrets
# Secret=

# Networks for the Container to use
Network=openchami-internal.network

# Unsupported by generator options
# Proxy settings
PodmanArgs=--http-proxy=false

[Service]
Restart=always
```

### Run from local binary

```
make build
```
```
mkdir -p data
```
```
./bin/inventory-service-server serve --database-url "file:data/inventory-service.db?_fk=1"
```

See the learn by example section in [Fabrica](https://github.com/OpenCHAMI/fabrica?tab=readme-ov-file#-learn-by-example)

### Run using docker image
```
make build image
```
```
mkdir -p data
```
```
docker run --rm --name inventory-service -d -p 8080:8080 -v $(pwd)/data:/data inventory-service:latest
```

#### Example building locally
```
make build image
```
```
mkdir -p data
```
```
docker run --rm --name inventory-service -d -p 8080:8080 -v $(pwd)/data:/data inventory-service:latest
```
SMD style request for the component resource
```
curl -s -X GET http://localhost:8080/hsm/v2/State/Components | jq
```
```
{
  "Components": []
}
```


Fabrica (OpenCHAMI) style request for the same resource.
```bash
curl -s -X GET http://localhost:8080/components | jq
```
```json
null
```

Post a Component using the SMD style API
```bash
curl -s -X POST http://localhost:8080/hsm/v2/State/Components \
  -H "Content-Type: application/json" \
  -d '{ "Components": [{
      "ID": "x3000c0s19b1",
      "Type": "NodeBMC",
      "State": "Ready",
      "Flag": "OK",
      "Enabled": true,
      "NetType": "Sling",
      "Arch": "X86",
      "Class": "River"
  }]}'

```

```bash
curl -s -X GET http://localhost:8080/components | jq
```
```json
[
  {
    "apiVersion": "v1",
    "kind": "Component",
    "metadata": {
      "name": "x3000c0s19b1",
      "uid": "component-673d2bde",
      "createdAt": "2026-04-23T18:20:11.798823051Z",
      "updatedAt": "2026-04-23T18:20:11.798823051Z"
    },
    "id": "x3000c0s19b1",
    "spec": {
      "ID": "x3000c0s19b1",
      "Type": "NodeBMC",
      "State": "Ready",
      "Flag": "OK",
      "Enabled": true,
      "NetType": "Sling",
      "Arch": "X86",
      "Class": "River"
    },
    "status": {
      "ready": false
    }
  }
]
```

```bash
curl -s -X GET http://localhost:8080/hsm/v2/State/Components | jq
```
```json
{
  "Components": [
    {
      "ID": "x3000c0s19b1",
      "Type": "NodeBMC",
      "State": "Ready",
      "Flag": "OK",
      "Enabled": true,
      "NetType": "Sling",
      "Arch": "X86",
      "Class": "River"
    }
  ]
}
```

POSTing the same resource again

```bash
curl -s -X POST http://localhost:8080/hsm/v2/State/Components   -H "Content-Type: application/json"   -d '{ "Components": [{
      "ID": "x3000c0s19b1",
      "Type": "NodeBMC",
      "State": "Ready",
      "Flag": "OK",
      "Enabled": true,
      "NetType": "Sling",
      "Arch": "X86",
      "Class": "River"
  }]}' | jq
```
```json
{
  "error": "failed to save Component: failed to create Component: ent: constraint failed: UNIQUE constraint failed: resources.resource_type, resources.resource_id",
  "code": 500
}
```
The error comes directly from the Database and refers to fields in the database not in the json.
In the future we may improve this.
`resource_type` is the `Kind` field in the fabrica style API's output.
`resource_id` is an internal field. For Components this contains the same value as the ID field.


```
docker stop inventory-service
```

### Run in the quickstart

This shows how to run in the [quickstart guide](https://github.com/OpenCHAMI/deployment-recipes/tree/main/quickstart)

Replace the `SMD Init and Server Containers` with the following

```
services:
###
# Inventory Service Container
###
  inventory-service:
    image: inventory-service:latest
    container_name: inventory-service
    hostname: inventory
    networks:
      - internal
```

### Test With SMD

Running `make test-compare-to-smd` starts a docker compose environment with both SMD and the Inventory Service.
It also starts a few instances of the [Redfish Interface Emulator (RIE)](https://github.com/Cray-HPE/csm-redfish-interface-emulator).
This does does the following
1. Starts a compose environment with the Inventory Service, SMD, and RIE.
2. Makes requests to SMD to discover the Redfish endpoints emulated by RIE.
3. Makes REST calls to SMD to get the Resources and POSTs those to the Inventory Service.
4. Compares the Resources in SMD to the Inventory Service.
5. Stops the compose environment.


Here is an example of running the parts of this test

```
make all
make start-inventory-and-smd
```
```
docker ps --no-trunc --format "table {{.Names}}\t{{.Status}}\t{{.Command}}"
```
```
NAMES               STATUS                    COMMAND
smd                 Up 9 seconds (healthy)    "/sbin/tini -- /smd"
postgres            Up 22 seconds (healthy)   "docker-entrypoint.sh postgres"
rf-x0c0s2b0         Up 22 seconds             "python3 emulator.py"
rf-x0c0s1b0         Up 22 seconds             "python3 emulator.py"
rf-x0c0s3b0         Up 22 seconds             "python3 emulator.py"
rf-x0c0s4b0         Up 22 seconds             "python3 emulator.py"
inventory-service   Up 22 seconds             "/usr/local/bin/inventory-service serve --port 8080 --database-url file:/data/inventory.db?_fk=1"
```
Run the tests. SMD will discover the nodes, the resources will be POSTed to the Inventory Service, and then the Resources in SMD and Inventory Service will be compared
```
docker run --rm -it --network inventory_internal inventory-test:latest
```
```
=========================================================== test session starts ============================================================
platform linux -- Python 3.14.2, pytest-9.0.2, pluggy-1.6.0
rootdir: /app
collected 1 item

test_compare_to_smd.py .                                                                                                             [100%]

============================================================ 1 passed in 20.05s ============================================================
```

The `inventory-test:latest` image can be used to make curl calls to the Inventory Service and to SMD.


SMD style REST call to Inventory

```
docker run --rm -t --network inventory_internal inventory-test:latest sh -c 'curl -s -X GET http://inventory:8080/hsm/v2/State/Components' | jq -c '.Components[] | { "ID": .ID, "Type": .Type }'
```
```
{"ID":"x0c0s1e0","Type":"NodeEnclosure"}
{"ID":"x0c0s1b0n0","Type":"Node"}
{"ID":"x0c0s1b0","Type":"NodeBMC"}
{"ID":"x0c0s3e0","Type":"NodeEnclosure"}
{"ID":"x0c0s3b0n0","Type":"Node"}
{"ID":"x0c0s3b0n1","Type":"Node"}
{"ID":"x0c0s3b0","Type":"NodeBMC"}
{"ID":"x0c0s4e0","Type":"NodeEnclosure"}
{"ID":"x0c0s4b0n0","Type":"Node"}
{"ID":"x0c0s4b0n1","Type":"Node"}
{"ID":"x0c0s4b0","Type":"NodeBMC"}
{"ID":"x0c0s2e0","Type":"NodeEnclosure"}
{"ID":"x0c0s2b0n0","Type":"Node"}
{"ID":"x0c0s2b0n1","Type":"Node"}
{"ID":"x0c0s2b0","Type":"NodeBMC"}
```

OpenCHAMI (Fabrica) style REST call to Inventory
```
docker run --rm -t --network inventory_internal inventory-test:latest sh -c 'curl -s -X GET http://inventory:8080/components' | jq -c '.[] | { "kind": .kind, "metadata": { "name": .metadata.name }, "spec" : {"ID": .spec.ID, "Type": .spec.Type} }'
```
```
{"kind":"Component","metadata":{"name":"x0c0s1e0"},"spec":{"ID":"x0c0s1e0","Type":"NodeEnclosure"}}
{"kind":"Component","metadata":{"name":"x0c0s1b0n0"},"spec":{"ID":"x0c0s1b0n0","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s1b0"},"spec":{"ID":"x0c0s1b0","Type":"NodeBMC"}}
{"kind":"Component","metadata":{"name":"x0c0s3e0"},"spec":{"ID":"x0c0s3e0","Type":"NodeEnclosure"}}
{"kind":"Component","metadata":{"name":"x0c0s3b0n0"},"spec":{"ID":"x0c0s3b0n0","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s3b0n1"},"spec":{"ID":"x0c0s3b0n1","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s3b0"},"spec":{"ID":"x0c0s3b0","Type":"NodeBMC"}}
{"kind":"Component","metadata":{"name":"x0c0s4e0"},"spec":{"ID":"x0c0s4e0","Type":"NodeEnclosure"}}
{"kind":"Component","metadata":{"name":"x0c0s4b0n0"},"spec":{"ID":"x0c0s4b0n0","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s4b0n1"},"spec":{"ID":"x0c0s4b0n1","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s4b0"},"spec":{"ID":"x0c0s4b0","Type":"NodeBMC"}}
{"kind":"Component","metadata":{"name":"x0c0s2e0"},"spec":{"ID":"x0c0s2e0","Type":"NodeEnclosure"}}
{"kind":"Component","metadata":{"name":"x0c0s2b0n0"},"spec":{"ID":"x0c0s2b0n0","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s2b0n1"},"spec":{"ID":"x0c0s2b0n1","Type":"Node"}}
{"kind":"Component","metadata":{"name":"x0c0s2b0"},"spec":{"ID":"x0c0s2b0","Type":"NodeBMC"}}
```

REST call to SMD
```
docker run --rm -t --network inventory_internal inventory-test:latest sh -c 'curl -s -X GET http://smd:27779/hsm/v2/State/Components' | jq -c '.Components[] | { "ID": .ID, "Type": .Type }'
```

```
make stop-inventory-and-smd
```

## REST Endpoints

| Resource           | Inventory (Fabrica Style) | Inventory (SMD Style)                 |
|--------------------|---------------------------|---------------------------------------|
| Component          | /components               | /hsm/v2/Status/Components             |
| ComponentEndpoint  | /componentendpoints       | /hsm/v2/Inventory/ComponentEndpoints  |
| EthernetInterface  | /ethernetinterfaces       | /hsm/v2/Inventory/EthernetInterfaces  |
| Group              | /groups                   | /hsm/v2/groups                        |
| Hardware           | /hardwares                | /hsm/v2/Inventory/Hardware            |
| RedfishEndpoint    | /redfishendpoints         | /hsm/v2/Inventory/RedfishEndpoints    |
| ServiceEndpoint    | /serviceendpoints         | /hsm/v2/Inventory/ServiceEndpoints    |
| health             | /health                   | /hsm/v2/service/ready                 |
| liveness           |                           | /hsm/v2/service/liveness              |


