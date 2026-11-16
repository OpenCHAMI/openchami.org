+++
title = "Magellan Updates: Structured Logs and a REST Daemon"
description = "A look at recent Magellan improvements that make it easier to integrate, operate, and configure BMC discovery workflows."
summary = "Magellan now offers configurable log output, a long-running REST service, and a CLI for reading and changing BMC settings."
date = 2026-11-05
lastmod = 2026-11-05
draft = true
weight = 10
categories = ["HPC", "Operations"]
tags = ["OpenCHAMI", "Magellan", "Redfish", "BMC", "Observability"]
+++

Magellan began as a command-line tool for discovering Baseboard Management Controllers (BMCs), collecting their Redfish inventory, and sending that inventory to OpenCHAMI's SMD service. Recent work makes it more comfortable to use in different environments: operators can choose how CLI logs are rendered, run Magellan as a long-lived REST service, and inspect or change BMC settings directly. All of the new features are available in version `v0.9.0` of the release.

Let's go over some of the recent changes made right before Supercomputing 2026. For installation and the full command reference, see the [README in the repository](https://github.com/OpenCHAMI/magellan/blob/main/README.md).

## Introducing Log Formatting and Colors

Magellan's `--log-format` option separates operational log messages from the data produced by commands such as `collect`. It defaults to the `json` option to maintain compatibility with older releases of Magellan.

- **`json`** emits structured JSON events, useful for log processors and scripts.
- **`rfc3339`** emits readable console messages with timestamps.
- **`basic`** emits compact level-prefixed messages without timestamps.

For example, keep JSON output for a collector or log pipeline:

```bash
magellan --log-format json --log-level info collect --secrets-file secrets.json
```

Or use compact output during an interactive session:

```bash
magellan --log-format basic --log-color auto scan --subnet 172.16.0.0/24
```

Color is controlled separately with `--log-color auto|on|off`. The `auto` option colors console output when stderr is connected to a terminal, whereas `on` and `off` allow setting the color explicitly. Keep in mind, however, that the standard `NO_COLOR` environment variable disables colors even if `--log-color on` is set. These options only affect log messages on standard error and not command data formats. If `--log-file` is enabled, the file records JSON events regardless of the format displayed in the terminal.

```bash
# The same options can be set for repeated use through environment variables.
LOG_FORMAT=rfc3339 LOG_COLOR=auto magellan scan --subnet 172.16.0.0/24
```

The log-format and color options were added in [PR #195](https://github.com/OpenCHAMI/magellan/pull/195). Alongside the existing log-level and log-file controls, they let operators keep terminal output human-friendly without losing structured records for automation.

## Run Magellan as a REST service

The `magellan serve` command runs a long-lived HTTP service backed by the same BMC functionality as the CLI. This gives another service or automation client an API for inventory collection and power operations, rather than requiring each caller to implement Redfish access itself. The daemon addition was developed in [PR #133](https://github.com/OpenCHAMI/magellan/pull/133).

For example, start the service with TLS and bearer-token authentication enabled:

```bash
export MAGELLAN_API_TOKEN="replace-with-a-long-random-token"

magellan serve \
  --host 127.0.0.1 \
  --port 8500 \
  --tls-cert ./server.crt \
  --tls-key ./server.key \
  --auth-token "$MAGELLAN_API_TOKEN" \
  --secrets-file ./secrets.json
```

The server exposes health checks and versioned API routes. For example, query a BMC's power state:

```bash
curl --cacert ./ca.crt \
  -H "Authorization: Bearer $MAGELLAN_API_TOKEN" \
  --get https://127.0.0.1:8500/v1/power \
  --data-urlencode 'bmc=https://172.16.0.10' \
  --data-urlencode 'system=Node0'
```

The power endpoint requires `bmc` and `system` query parameters to be set and the `--data-urlencode` flag handles encoding them. The inventory endpoint accepts one or more BMC URLs and returns JSON in the same format as `magellan collect`, which can be piped to other Magellan commands.

```bash
export ACCESS_TOKEN=$JWT_TOKEN
curl --cacert ./ca.crt \
  -H "Authorization: Bearer $MAGELLAN_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"bmcs":["https://172.16.0.10","https://172.16.0.11"]}' \
  https://127.0.0.1:8500/v1/inventory | magellan send https://demo.openchami.cluster:8443/hsm/v2 -f json --cacert openchami.pem
```

The service can be configured with command-line flags, environment variables, or Magellan's configuration file. It shuts down gracefully on `SIGINT` or `SIGTERM`, allowing in-flight requests to finish.

{{< callout context="warning" title="Protect the service" icon="alert-triangle" >}}
The daemon binds to all interfaces by default, and API authentication is disabled if no token is configured. Do not expose it on a network without deliberate access controls. Use TLS and authentication, or bind it to loopback and place it behind a trusted gateway. Keep BMC credentials in the secrets store or a protected file; do not put them in source control.
{{< /callout >}}

## Configure BMC settings from the CLI

The `magellan settings` command provides a focused way to read and write BMC settings exposed by Redfish. You can explore what a device supports, inspect a nested property, update a value, or request a reset using this interface.

Here are a couple of simple examples:

```bash
# Explore available settings and read a specific value.
magellan settings list 172.16.0.10 NetworkProtocol
magellan settings get 172.16.0.10 ComputerSystem default Boot BootOrder

# Update a setting exposed by this BMC.
magellan settings set 172.16.0.10 NetworkProtocol SSH '{"ProtocolEnabled":true,"Port":22}'
```

This is useful when preparing or troubleshooting nodes without switching tools. Redfish schemas and supported actions vary between vendors and firmware versions, so inspect the BMC's available settings and verify the effect of a change before applying it broadly. See the [Magellan settings documentation](https://github.com/OpenCHAMI/magellan#configuring-bmc-settings) for additional commands and options.

## What's next?

The OpenCHAMI team is hard at work to improve handling BMC credentials by providing a `SecretStore` backend with OpenBao integration. The initial work started with [draft PR #197](https://github.com/OpenCHAMI/magellan/pull/197) by adding an OpenBao `SecretStore` implementation and continues in [draft PR #200](https://github.com/OpenCHAMI/magellan/pull/200) by adding credential rotation. Feedback is welcome!

## A more adaptable Magellan

These additions address different parts of the operator workflow: configurable logs fit Magellan into terminals and log pipelines, the REST daemon makes its BMC operations available to other software, and the settings commands provide a direct way to work with Redfish configuration. They build on Magellan's discovery and inventory role without requiring every deployment to use the same interface or logging style.

Explore the [Magellan source and documentation](https://github.com/OpenCHAMI/magellan), or join the [OpenCHAMI community](https://github.com/OpenCHAMI/community) to discuss what you are building!
