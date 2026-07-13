---
title: "WireGuard Integration"
description: "Secure node bootstrapping with WireGuard tunnels for cloud-init traffic."
date: 2026-06-29T00:00:00+00:00
lastmod: 2026-06-29T00:00:00+00:00
draft: false
weight: 500
toc: true
categories: ["Cloud-Init", "WireGuard", "Security"]
tags: ["Cloud-Init", "WireGuard", "VPN", "Security", "Networking"]
---

## Overview

OpenCHAMI's cloud-init server supports **WireGuard** to encrypt and isolate cloud-init traffic between compute nodes and the cloud-init server. This ensures that sensitive metadata, user data, and vendor data exchanged during node provisioning are transmitted over an encrypted tunnel.

The cloud-init server embeds a WireGuard server that dynamically assigns VPN IPs to compute nodes, manages peer configurations, and can optionally restrict cloud-init data access to only those nodes connected via the WireGuard tunnel. This helps protects against users making HTTPS requests directly to the API endpoints to obtain secrets delivered by the cloud-init-server.

## Architecture

The WireGuard integration works in two phases:

1. **Tunnel establishment** — At boot, the compute node calls the unprotected `/cloud-init/wg-init` endpoint to request a WireGuard IP and peer configuration. This happens before cloud-init itself runs.
2. **Secure data fetch** — Once the tunnel is up, cloud-init fetches `/meta-data`, `/user-data`, `/vendor-data`, and group YAML files over the encrypted WireGuard link.

```text
┌──────────────┐     WireGuard Tunnel       ┌──────────────────┐
│  Compute     │ ◄────────────────────────► │  cloud-init      │
│  Node        │     wg0: 100.97.0.x/32     │  Server          │
│              │                            │  wg0: 100.97.0.1 │
└──────────────┘                            └──────────────────┘
       │                                           │
       │ 1. POST /cloud-init/wg-init               │
       │    (before cloud-init starts)             │
       │                                           │
       │ 2. GET /meta-data, /vendor-data           │
       │    (over WireGuard tunnel)                │
       └───────────────────────────────────────────┘
```

## Server-Side Configuration

### Environment Variables

| Variable | Description | Default |
| --- | --- | --- |
| `WIREGUARD_SERVER` | WireGuard server IP and network CIDR (e.g. `100.97.0.1/16`) | (none) |
| `WIREGUARD_ONLY` | Only serve cloud-init data to clients in the WireGuard subnet | `false` |
| `DEBUG` | Enable debug logging | `false` |

### WIREGUARD_ONLY Behavior

When `WIREGUARD_ONLY=true` is set, the cloud-init server restricts access to data-bearing endpoints (`/meta-data`, `/user-data`, `/vendor-data`, `/{group}.yaml`) to clients whose IP falls within the WireGuard subnet **or** whose request arrives on the server's WireGuard interface.

{{< callout context="note" title="Important" icon="info-circle" >}}
The `/cloud-init/wg-init`, `/cloud-init/admin/*`, and `/cloud-init/phone-home/{id}` endpoints are **never** restricted by the WireGuard middleware, even when `WIREGUARD_ONLY=true`. This allows nodes to establish their WireGuard tunnel before fetching cloud-init data.
{{< /callout >}}

### Network Setup

The cloud-init container needs access to both the internal cluster network and an external network for WireGuard traffic. Configure this using Podman quadlet overrides.

{{< details "Example quadlet override (10-override.conf)" >}}

```ini
# /etc/containers/systemd/cloud-init-server.container.d/10-override.conf
[Container]
Image=ghcr.io/openchami/cloud-init:v1.4.2
Environment=WIREGUARD_SERVER=172.16.1.1/24
Environment=WIREGUARD_ONLY=true
Environment=DEBUG=true
AddCapability=NET_ADMIN
AddDevice=/dev/net/tun
PublishPort=58036:58036/udp
Network=openchami-internal.network:alias=cloud-init-int
Network=openchami-external.network:alias=cloud-init-wg
```

{{< /details >}}

### HAProxy Configuration

If using HAProxy in front of the cloud-init server, ensure the backend routes traffic to the internal network alias:

```haproxy
backend cloud-init
  server cloud-init-server cloud-init-int:27777
  http-request set-path %[path,regsub(^/cloud-init/,/)]
```

## Client-Side Configuration

Compute nodes require two pieces of setup to use WireGuard for cloud-init:

1. A **systemd override** that runs a pre-exec script before cloud-init starts.
2. A **shell script** that configures the WireGuard tunnel and requests a VPN IP from the server.

### Systemd Override

```ini
# /etc/systemd/system/cloud-init.service.d/override.conf
[Service]
Environment=ochami_wg_ip=172.16.0.254
ExecStartPre=/usr/local/bin/ochami-ci-setup.sh
ExecStopPost=/bin/bash -c "ip link delete wg0"
```

The `ochami_wg_ip` variable should point to the cloud-init server's external IP address (the one accessible from the compute node before the tunnel is established).

### WireGuard Setup Script

The pre-exec script performs the following steps:

1. Generate a WireGuard key pair on the compute node.
2. Request a VPN IP from the cloud-init server via the `/cloud-init/wg-init` endpoint.
3. Create and configure the `wg0` interface with the assigned IP and server peer.
4. Add a route to the WireGuard server IP over the tunnel.

{{< details "Example ochami-ci-setup.sh" >}}

```bash
#!/bin/sh
set -e -o pipefail

if [ -z "${ochami_wg_ip}" ]; then
    echo "ERROR: Failed to find the 'ochami_wg_ip' environment variable."
    if [ -f "/etc/cloud/cloud.cfg.d/ochami.cfg" ]; then
        echo "Removing ochami-specific cloud-config; cloud-init will use other defaults"
        rm /etc/cloud/cloud.cfg.d/ochami.cfg
    else
        echo "Not writing ochami-specific cloud-config; cloud-init will use other defaults"
    fi
    exit 0
fi

echo "Loading WireGuard kernel module"
modprobe wireguard

echo "Generating WireGuard keys"
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

echo "Requesting WireGuard tunnel configuration"
PUBLIC_KEY=$(cat /etc/wireguard/public.key)
PAYLOAD="{ \"public_key\": \"${PUBLIC_KEY}\" }"
WG_PAYLOAD=$(curl -s -X POST -d "${PAYLOAD}" http://${ochami_wg_ip}:8081/cloud-init/wg-init)

CLIENT_IP=$(echo $WG_PAYLOAD | jq -r '."client-vpn-ip"')
SERVER_IP=$(echo $WG_PAYLOAD | jq -r '."server-ip"' | awk -F'/' '{print $1}')
SERVER_PORT=$(echo $WG_PAYLOAD | jq -r '."server-port"')
SERVER_KEY=$(echo $WG_PAYLOAD | jq -r '."server-public-key"')

echo "Setting up WireGuard interface"
ip link add dev wg0 type wireguard
ip address add dev wg0 ${CLIENT_IP}/32
wg set wg0 private-key /etc/wireguard/private.key
ip link set wg0 up
wg set wg0 peer ${SERVER_KEY} allowed-ips ${SERVER_IP}/32 endpoint ${ochami_wg_ip}:${SERVER_PORT}

echo "Adding route to WireGuard server"
ip route replace "${SERVER_IP}/32" dev wg0

rm /etc/wireguard/private.key
rm /etc/wireguard/public.key
```

{{< /details >}}

### Image Building

Inject these files into the compute node image using the OpenCHAMI image builder. Add them under `copyfiles` in the image build configuration:

```yaml
copyfiles:
  - src: '/opt/workdir/images/files/cloud-init-override.conf'
    dest: '/etc/systemd/system/cloud-init.service.d/override.conf'
  - src: '/opt/workdir/images/files/ochami-ci-setup.sh'
    dest: '/usr/local/bin/ochami-ci-setup.sh'
```

The image must also include the `wireguard-tools` package:

```yaml
packages:
  - wireguard-tools
```

### Boot Parameters

Configure the node's boot parameters in BSS to point to the cloud-init server using the WireGuard subnet address:

```yaml
params: 'nomodeset ro root=live:http://172.16.0.254:7070/boot-images/... ip=dhcp ... cloud-init=enabled ds=nocloud-net;s=http://172.16.1.1:27777/cloud-init'
```

The `ds=nocloud-net` URL should use the WireGuard server IP (e.g. `172.16.1.1:27777`), which is the address the compute node will reach once the tunnel is established.

## How the Middleware Works

The WireGuard middleware enforces access policy based on two criteria:

- **Client IP in WireGuard subnet** — If the connecting client's IP falls within the configured WireGuard CIDR (e.g. `100.97.0.0/16`), the request is allowed.
- **Request arrived on WireGuard interface** — If the connection was received on the server's `wg0` interface, the request is allowed regardless of client IP.

Before the fix in PR [#113](https://github.com/OpenCHAMI/cloud-init/pull/113), the WireGuard middleware was applied globally to **all** routes when `WIREGUARD_ONLY=true`. This created a chicken-and-egg problem: compute nodes needed to call `/cloud-init/wg-init` to establish their WireGuard tunnel, but that endpoint was blocked by the middleware.

The fix scoped the middleware to only the data-bearing routes (`/meta-data`, `/user-data`, `/vendor-data`, `/{group}.yaml`), leaving the tunnel setup endpoint (`/wg-init`) and phone-home endpoint (`/phone-home/{id}`) accessible without restriction.

## Verification

To verify the WireGuard tunnel is functioning correctly from a compute node:

```bash
# Check the WireGuard interface
wg show

# Verify the tunnel is resolving the cloud-init server
ping 100.97.0.1
```

On the cloud-init server, check that the WireGuard interface is active:

```bash
# List WireGuard peers
wg show wg0

# Check debug logs for connection metadata
journalctl -u cloud-init-server
```

If `WIREGUARD_ONLY=true` is set and a non-WireGuard client tries to access a protected endpoint, they will receive:

```text
Access denied: IP 10.89.2.63 not in WireGuard subnet or interface
```
