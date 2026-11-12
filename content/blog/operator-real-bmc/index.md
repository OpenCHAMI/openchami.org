+++
title = "From a Real BMC to a Boot Script with the OpenCHAMI Operator"
description = "A hands-on walkthrough of deploying OpenCHAMI locally, discovering a physical server with Magellan, inspecting SMD inventory, and generating an iPXE script."
date = 2026-11-12T00:00:00+00:00
lastmod = 2026-11-12T00:00:00+00:00
draft = false
weight = 10
categories = ["HPC", "Operations", "Development"]
tags = ["OpenCHAMI", "Operator", "Magellan", "Redfish", "SMD", "BSS"]
contributors = ["Ben McDonald"]
include_toc = true
+++

What does it actually look like to connect OpenCHAMI to a physical server?

I wanted a demo that answered that question with real hardware, not a collection of invented node records. Starting with a BMC at `172.24.0.3`, I deployed an OpenCHAMI control plane, collected the server's inventory with Magellan, queried that information through SMD, and generated an iPXE script for the discovered node.

The useful connection is between two questions: **what hardware is this, and what should it boot?** Discovery answers the first. Boot configuration answers the second. This walkthrough shows how the pieces fit together without requiring an operating system to be installed on the server first.

It is intended for HPC and bare-metal administrators evaluating OpenCHAMI, platform engineers exploring the operator, and developers learning the service APIs. The end result is a generated boot script, not a claim that the physical server has completed a PXE boot.

## The Pieces We Are Connecting

| Component | Job in this demo |
| --- | --- |
| OpenCHAMI operator | Reconcile a Kubernetes control-plane resource into services and their dependencies |
| Magellan | Read the physical server's BMC through Redfish |
| SMD | Store and return hardware inventory |
| TokenSmith | Issue tokens authorizing our API requests |
| Boot Service | Register the node and turn its boot configuration into iPXE instructions |

This deployment uses the newer **Boot Service**, which exposes legacy BSS-compatible endpoints under `/boot/v1`. I use “BSS” below when referring to those boot-script operations, but the deployed container is `boot-service`, not the original BSS implementation. See [Introduction to the New Boot Service](https://openchami.org/blog/2025/12/introduction-to-the-new-boot-service/) for background.

Magellan runs on the host in this demo. We disable the operator's in-cluster Magellan scheduler and explicitly run discovery ourselves. The BSS node registration also happens explicitly; we are not demonstrating automatic synchronization from SMD into Boot Service.

## Run It Yourself

The code is in two repositories:

- [OpenCHAMI operator](https://github.com/OpenCHAMI/openchami-operator)
- [Demo scripts and walkthrough](https://github.com/bmcdonald3/operator-demo)

You need a working Docker/Kind development environment, the operator's build prerequisites, `kubectl`, Helm, `curl`, `jq`, and a pre-built `magellan` on your PATH. The host running Magellan must be able to reach the BMC's Redfish service. Use your own BMC address and credentials when adapting the example.

```bash
git clone https://github.com/OpenCHAMI/openchami-operator
git clone https://github.com/bmcdonald3/operator-demo
cd openchami-operator
bash ../operator-demo/demo-fresh.sh
```

The guided script shows commands and pauses for Enter, allowing you to explain each stage before executing it. The sections below provide the same operations as a manual walkthrough; run their command blocks in order in the same Bash session rather than running both paths together.

**The fresh-start demo deletes `testcluster` and its namespace, including namespaced demo data.** Run it only against a development environment. It leaves the Kind cluster, Vault, and LocalStack in place and does not reset or power-cycle the physical server.

The captured run used SMD `v2.20.3`, Boot Service `v0.1.6`, and TokenSmith image `pr-24`. These outputs describe that development deployment, not a promise that every version behaves identically. The exact Magellan version was not recorded. Check the repositories' current prerequisites and your installed CLI's help when reproducing the walkthrough.

## 1. Prepare the Environment and Deploy the Operator

The first commands are development-environment shortcuts, not OpenCHAMI API calls:

```bash
make dev-up
make build
make dev-deploy
```

`dev-up` starts Vault and LocalStack, creates or reuses the `openchami-dev` Kind cluster, installs prerequisite controllers, installs the OpenCHAMI CRDs, and seeds development secrets in Vault. Those controllers include cert-manager, CloudNativePG, Vault Secrets Operator, and Envoy Gateway.

`make build` builds host binaries such as `ochami-admin`. `dev-deploy` separately builds the operator container image, loads it into Kind, installs its Kubernetes resources, configures its development endpoints, and waits for the operator rollout.

At this point we have an operator, but have not yet requested an OpenCHAMI control plane. For a fresh demonstration, remove the previous one:

```bash
kubectl delete openchamicontrolplane testcluster -n default --ignore-not-found --wait=true
kubectl delete namespace openchami-testcluster --ignore-not-found --wait=true
```

Then submit the fixture and select host-side discovery:

```bash
kubectl apply -n default -f test/fixtures/minimal-controlplane.yaml
kubectl patch openchamicontrolplane testcluster -n default --type=merge \
  -p '{"spec":{"services":{"magellan":{"enabled":false}}}}'
kubectl wait --for=jsonpath='{.status.phase}'=Ready \
  openchamicontrolplane/testcluster -n default --timeout=300s
kubectl rollout status deployment/boot-service -n openchami-testcluster --timeout=180s
kubectl rollout status deployment/tokensmith -n openchami-testcluster --timeout=180s
kubectl get pods -n openchami-testcluster
```

The operator creates the services and dependencies described by the resource. An excerpt from the running demo showed:

```text
openchamicontrolplane.openchami.openchami.org/testcluster condition met
NAME                               READY   STATUS
boot-service-65bb98b886-mwx8d        1/1     Running
coredhcp-p2v2z                      1/1     Running
metadata-service-685c57bb6-7sljl     1/1     Running
openchami-testcluster-postgres-1    1/1     Running
smd-f6b7d7696-k7dkz                 1/1     Running
tokensmith-5d4fb78df5-7fqb6          1/1     Running
```

Restart counts and ages are omitted here. Pod names will differ in your run. The important result is that the control-plane resource is ready and the services are available.

## 2. Give Our Terminal Access to the Services

The services live inside Kubernetes. Our terminal lives outside it. Port forwarding gives the host temporary local access without first configuring external gateway networking.

For this manual walkthrough, use two separate terminals and leave the forwards running:

```bash
kubectl port-forward -n openchami-testcluster svc/boot-service 37778:27778
```

```bash
kubectl port-forward -n openchami-testcluster svc/smd 37779:27779
```

Wait for each to print `Forwarding from`. Back in the walkthrough shell:

```bash
BSS_URL=http://127.0.0.1:37778
SMD_URL=http://127.0.0.1:37779
```

These are local access addresses, not addresses a physical node would use during PXE boot. The guided script allocates free ports automatically; the fixed ports above simply make the manual examples easier to follow.

### Tokens for Our API Requests

TokenSmith signs JWTs describing who is making a request, which service the token targets, and which operations are allowed. We mint one token with audience `hsm` for SMD, and another with audience `boot-service` for BSS writes:

<details>
<summary>Commands: create the SMD and BSS tokens</summary>

```bash
SMD_JWT=$(kubectl exec -n openchami-testcluster deploy/tokensmith -- \
  /usr/local/bin/tokensmith user-token create \
  --subject demo-admin --audience hsm \
  --scopes node:read,node:write,group:read,group:write \
  --key-file /var/lib/tokensmith/keys/private.pem \
  --enable-local-user-mint | tr -d '\r\n')

BSS_JWT=$(kubectl exec -n openchami-testcluster deploy/tokensmith -- \
  /usr/local/bin/tokensmith user-token create \
  --subject demo-admin --audience boot-service \
  --scopes boot:read,boot:write,node:read,node:write \
  --key-file /var/lib/tokensmith/keys/private.pem \
  --enable-local-user-mint | tr -d '\r\n')
```

</details>

This is a development shortcut using local user-token minting, not a production login recipe. The tokens stay in shell variables; do not print or publish them. A token can authorize multiple requests until it expires, provided its audience and scopes are appropriate. The BMC credentials used next are separate from these tokens.

## 3. Discover the Real Hardware with Magellan

Magellan scans the BMC and follows its Redfish resources to collect hardware information. In this case the address is `172.24.0.3`, and the BMC exposes a server with serial number `QSBP82909087`.

The BMC ID map assigns a location name, `x1000c0s0b0`, to that address. It does not invent the server's UUID, model, or MAC addresses. Those come from Redfish.

<details>
<summary>Commands: scan and collect the BMC inventory</summary>

```bash
umask 077
DEMO_DIR=$(mktemp -d)
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}172.24.0.3,127.0.0.1,localhost"
export no_proxy="${no_proxy:+$no_proxy,}172.24.0.3,127.0.0.1,localhost"
IFS= read -r -p 'BMC username: ' BMC_USERNAME
IFS= read -r -s -p 'BMC password: ' BMC_PASSWORD
printf '\n'

magellan scan https://172.24.0.3:443 --insecure --cache "$DEMO_DIR/assets.db"
magellan collect --cache "$DEMO_DIR/assets.db" --insecure \
  --username "$BMC_USERNAME" --password "$BMC_PASSWORD" \
  --bmc-id-map '{"map_key":"bmc-ip-addr","id_map":{"172.24.0.3":"x1000c0s0b0"}}' \
  --output-format json --output-file "$DEMO_DIR/inventory.json"
unset BMC_PASSWORD
jq '.[].Systems' "$DEMO_DIR/inventory.json"
```

</details>

The proxy exclusions keep private BMC and loopback requests from going through an environment-configured proxy. `--insecure` accommodates the lab BMC certificate; use proper certificate verification in a secured deployment. The scan cache is SQLite, while the collected inventory is JSON.

Here is an excerpt from the actual collected system. Additional NICs and other fields have been omitted for readability:

```json
{
  "uri": "https://172.24.0.3:443/redfish/v1/Systems/QSBP82909087",
  "uuid": "317091ec-8be6-11e8-ab21-a4bf013f6b40",
  "manufacturer": "Intel Corporation",
  "name": "S2600BPB",
  "model": "S2600BPB",
  "serial": "QSBP82909087",
  "ethernet_interfaces": [
    {
      "mac": "a4-bf-01-3f-6b-40",
      "description": "System NIC 1"
    },
    {
      "mac": "a4-bf-01-3f-6b-41",
      "description": "System NIC 2"
    }
  ],
  "power": {"state": "Off"},
  "processor_count": 2,
  "processor_type": "Intel Xeon processor",
  "memory_total": 64,
  "node_id": "QSBP82909087"
}
```

This output is read from Magellan's local inventory file. It is not yet a query of SMD. The UUID identifies the physical system; the NIC MAC provides an identifier we can use for boot requests. The reported power state is a discovery-time observation, not continuous monitoring.

## 4. Send Inventory to SMD and Query It Back

The first request sends one collected BMC object to **`POST /hsm/v2/Inventory/RedfishEndpoints`**. The subsequent **`GET /hsm/v2/Inventory/ComponentEndpoints`** lets us inspect what SMD stored.

```bash
jq -c '.[0]' "$DEMO_DIR/inventory.json" > "$DEMO_DIR/smd-endpoint.json"
curl -sS -i -X POST "$SMD_URL/hsm/v2/Inventory/RedfishEndpoints" \
  -H "Authorization: Bearer $SMD_JWT" \
  -H 'Content-Type: application/json' \
  --data-binary "@$DEMO_DIR/smd-endpoint.json"
```

There was one important version-specific wrinkle in this run. SMD `v2.20.3` returned HTTP `400` with repeated `Invalid CompEthInterface IP Address` errors for system NICs that had no reported IP address, but it still stored the component endpoint. The standalone Ethernet interface inventory contained the BMC interfaces, not those MAC-only system NICs. This was a partial write, not a fully successful import. The guided demo displays the response and continues to BSS registration using Magellan's data directly.

We can still inspect the stored endpoint rather than just display a local file:

```bash
curl -fsS "$SMD_URL/hsm/v2/Inventory/ComponentEndpoints" \
  -H "Authorization: Bearer $SMD_JWT" > "$DEMO_DIR/smd-endpoints.json"
NODE_UUID=$(jq -r '.[0].Systems[0].uuid' "$DEMO_DIR/inventory.json")
BMC_ID=$(jq -r '.[0].ID' "$DEMO_DIR/inventory.json")
jq --arg uuid "$NODE_UUID" --arg bmc "$BMC_ID" '
  .ComponentEndpoints[] |
  select(.UUID == $uuid and .RedfishEndpointID == $bmc)
' "$DEMO_DIR/smd-endpoints.json"
```

An excerpt of the real SMD response contained:

```json
{
  "ID": "x1000c0s0b0n0",
  "Type": "Node",
  "RedfishType": "ComputerSystem",
  "UUID": "317091ec-8be6-11e8-ab21-a4bf013f6b40",
  "OdataID": "/redfish/v1/Systems/QSBP82909087",
  "RedfishEndpointID": "x1000c0s0b0",
  "RedfishSystemInfo": {
    "Name": "S2600BPB",
    "EthernetNICInfo": [
      {
        "Description": "System NIC 1",
        "MACAddress": "a4-bf-01-3f-6b-40"
      }
    ]
  }
}
```

The unchanged UUID and MAC tie this API response back to the physical server. That is the useful demonstration: another service can return information about the hardware Magellan found. It does not require us to pretend every inventory representation was populated successfully.

## 5. Tell Boot Service About the Discovered Node

Boot Service needs its own node record for resolving boot requests. We register it through **`POST /nodes`**, using the location assignment and a MAC from discovery.

For this single-system demo, the node name is the assigned BMC ID followed by `n0`. We select the first reported system NIC and normalize its MAC to colon notation. This is a demo selection, not proof that this NIC is connected to a provisioning network.

<details>
<summary>Commands: build the node record and register it</summary>

```bash
NODE_XNAME=$(jq -r '.[0].ID + "n0"' "$DEMO_DIR/inventory.json")
BOOT_MAC=$(jq -r '
  .[0].Systems[0].ethernet_interfaces[0].mac |
  ascii_downcase | gsub("-"; ":")
' "$DEMO_DIR/inventory.json")

jq -nc --arg node "$NODE_XNAME" --arg mac "$BOOT_MAC" \
  '{apiVersion:"boot.openchami.io/v1",kind:"Node",metadata:{name:$node},spec:{xname:$node,bootMac:$mac}}' \
  > "$DEMO_DIR/node.json"
curl -fsS -X POST "$BSS_URL/nodes" \
  -H "Authorization: Bearer $BSS_JWT" \
  -H 'Content-Type: application/json' \
  -d "@$DEMO_DIR/node.json" | jq .
```

</details>

The observed node response included:

```json
{
  "apiVersion": "v1",
  "kind": "Node",
  "metadata": {
    "name": "x1000c0s0b0n0",
    "uid": "node-95e3bf80"
  },
  "spec": {
    "xname": "x1000c0s0b0n0",
    "bootMac": "a4:bf:01:3f:6b:40"
  },
  "status": {}
}
```

Timestamps are omitted. The UID will differ for a new record. The request used `boot.openchami.io/v1`, while this server returned the resource with `apiVersion: v1`. Most importantly, the node now has the discovered boot MAC rather than a made-up network identity.

## 6. Choose What the Node Should Boot

Hardware discovery cannot decide which operating system we want. That is configuration we supply.

For this example I chose published Alpine Linux 3.22 x86-64 netboot files. We submit them through **`POST /boot/v1/bootparameters`**:

| Field | What we provide |
| --- | --- |
| `hosts` | The registered node's XName |
| `macs` | Its discovered boot MAC |
| `kernel` | Alpine's `vmlinuz-lts` URL |
| `initrd` | The matching `initramfs-lts` URL |
| `params` | DHCP networking, package repository, and module image location |

<details>
<summary>Commands: assign the Alpine boot configuration</summary>

```bash
NETBOOT=https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/netboot
jq -nc --arg node "$NODE_XNAME" --arg mac "$BOOT_MAC" \
  --arg kernel "$NETBOOT/vmlinuz-lts" \
  --arg initrd "$NETBOOT/initramfs-lts" \
  --arg params "ip=dhcp alpine_repo=https://dl-cdn.alpinelinux.org/alpine/v3.22/main modloop=$NETBOOT/modloop-lts" \
  '{hosts:[$node],macs:[$mac],kernel:$kernel,initrd:$initrd,params:$params}' \
  > "$DEMO_DIR/boot-parameters.json"
curl -fsS -X POST "$BSS_URL/boot/v1/bootparameters" \
  -H "Authorization: Bearer $BSS_JWT" \
  -H 'Content-Type: application/json' \
  -d "@$DEMO_DIR/boot-parameters.json" | jq .
```

</details>

The response in our run contained a `boot-parameters` array with `hosts: ["x1000c0s0b0n0"]`, `macs: ["a4:bf:01:3f:6b:40"]`, and the Alpine URLs. Its metadata described the conversion from a modern BootConfiguration. That tells us the legacy endpoint has stored configuration for the node; it has not booted the server.

## 7. Ask for the iPXE Script

Finally, a node can ask **`GET /boot/v1/bootscript`** for its instructions. We demonstrate both supported identifiers used here:

```bash
curl -fsS "$BSS_URL/boot/v1/bootscript?host=$NODE_XNAME"
curl -fsS "$BSS_URL/boot/v1/bootscript?mac=$BOOT_MAC"
```

No bearer token is sent for these requests. This matches the unauthenticated boot-script lookup in the demo: a machine needs its boot instructions before it has user credentials.

Both requests returned a script for the same node. Here is an excerpt of the actual output, with explanatory comments and `echo` lines omitted:

```ipxe
#!ipxe
# Node: x1000c0s0b0n0 (NID: 0)
# Configuration: legacy-x1000c0s0b0n0

dhcp

set kernel https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/netboot/vmlinuz-lts
set initrd https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/netboot/initramfs-lts
set params ip=dhcp alpine_repo=https://dl-cdn.alpinelinux.org/alpine/v3.22/main modloop=https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/netboot/modloop-lts

kernel ${kernel} ${params}
initrd ${initrd}
boot
```

The generated script has no assigned role and shows NID `0` because the minimal node registration did not supply those fields. The result we care about is the association between the discovered MAC, registered node, chosen boot files, and final `boot` instruction.

## What This Demonstrates, and What Comes Next

We have connected a physical server to several independently inspectable results:

1. Magellan reads its actual identity and network interfaces through Redfish.
2. SMD returns a component endpoint matching that discovered UUID and MAC, with the partial-write limitation noted above.
3. Boot Service recognizes the registered node by name and MAC and generates its boot instructions.

The operator handles deploying the control plane. The API calls show how discovery data and administrator-chosen configuration come together. That is more useful than simply seeing pods run: we can trace one real machine from its BMC to the script it would receive during provisioning.

Actually booting the machine is the next integration step. It requires DHCP/iPXE setup, a Boot Service address reachable from the provisioning network, access to the kernel/initrd/module files, and any firmware or boot-policy configuration needed by the server. An HTTPS URL in a generated script also requires an iPXE environment capable of retrieving it. Fetching the script from our terminal does not test those conditions.

When finished with the manual walkthrough, stop the two port-forwards with Ctrl-C in their terminals and clear the local token variables:

```bash
unset SMD_JWT BSS_JWT BMC_PASSWORD
```

The guided script stops its own forwards on exit. It creates its working files in a temporary directory; that script-local `DEMO_DIR` variable does not remain in your parent shell. For repeat presentations without rebuilding or rescanning, the separate `demo.sh` in the demo repository provides a cached Magellan-to-Boot-Service path.

You can explore the exact commands and adapt the walkthrough in [operator-demo](https://github.com/bmcdonald3/operator-demo), or follow development of the control-plane automation in [openchami-operator](https://github.com/OpenCHAMI/openchami-operator).