+++
title = 'Magellan: Alternative Redfish Discovery for OpenCHAMI/CSM'
date = 2023-10-28T09:27:54-04:00
draft = false
categories = ['Development', 'LANL', 'SC23']
summary = "As part of LANL's exploration of the CSM codebase, they found it necessary to augment the built-in discovery features of CSM with a new standalone command based on gofish and bmclib."
include_toc = true
contributors = ["David J. Allen (LANL)"]
description = "Magellan is a bmclib/gofish-based Redfish discovery tool for CSM/OpenCHAMI that scans, collects, and uploads inventory to SMD."
slug = "ochami-magellan"
lastmod = 2025-11-06T00:00:00+00:00
canonical = "/blog/ochami-magellan/"
tags = ["Magellan", "Redfish", "Discovery", "OpenCHAMI"]
+++


# Magellan: A "bmclib"-based Discovery Tool

As part of our exploration of the [CSM codebase](https://github.com/Cray-HPE), we found it necessary to augment the built-in Redfish discovery mechanism with one that was easier for us to maintain and troubleshoot.  Our tool, which we called `magellan` after the pioneering explorer, is based on [`bmclib`](https://github.com/bmc-toolbox/bmclib) and [`gofish`](https://github.com/stmcginnis/gofish).  It scans subnets for BMCs and collects inventory information to generate the compute node inventory in CSM.  Read on for the full story including the tradeoffs we made along the way.

## What is CSM and how does Magellan fit in?

Cray System Management is the software we use to manage several of the HPC systems at LANL.  It was supplied by HPE as part of their exascale systems and they have subsequently open sourced much of it.  We want to work independently with that codebase and explore other ways of using it at our site.

CSM includes a whole cornucopia of services for managing systems with features like multi-tenancy, network and log management, and even a built in policy engine for security enforement.  We decided that our first project would be to start from the ground up, focusing solely on booting a diskless operating system on a small set of non-HPE nodes.  We sought the smallest useful set of CSM services to meet a narrow goal.

Like many other system managers, CSM is built around an inventory system that provides timely informaiton about the state of the thousands of compute nodes in the system.  HPC Application developers need to target their jobs based on characteristics like Linux kernel versions, GPU firmware versions, access to various high speed networks and other inventory related information.  In CSM, the inventory is discovered rather than declared.  It expects each node to have a BMC that can be queried to describe the hardware and firmware it contains.  This means that the inventory system starts with finding all the BMCs and asking each one to describe itself using redfish.

CSM's discovery system works well in the controlled environment of a Cray EX system.  For our purposes, however, we found it a challenge to troubleshoot.  We couldn't easily tell if discovery failures were related to programming errors on our part, poor support for our hardware, or even failures in our hardware.  In addition, the continuous discovery process in CSM runs as a separate thread on the inventory database manager.  It was hard for us to be sure our changes weren't causing other problems in other parts of the service.  After a few false starts, we decided to explore alternatives that were easier for us to manage.

## Introducing Magellan

Magellan is a board management controller (BMC), command-line interface, discovery tool used to retrieve information about BMC nodes via the Redfish protocol. It is written in the Go programming language and is uses [`bmclib`](https://github.com/bmc-toolbox/bmclib) and [`gofish`](https://github.com/stmcginnis/gofish) libraries under the hood.

Magellan is designed to work alongside Cray's State Management Database's (SMD) discovery processes.  It acts as a client of SMD, populating the inventory system.  The built-in discovery service can continue to run using initial discovery information from Magellan or, with the addition of a custom commandline flag, internal discovery can be disabled and Magellan can be re-run as needed.

## How does Magellan work?

Magellan has two modes, scanning and collecting.  Both have separate corresponding CLI commands. Each leverages capabilities from existing libraries to do the heavy lifting.  In scanning mode, it is exploring a CIDR for any BMCs that advertise Redfish endpoints.  In collection mode, it queries those endpoints for all inventory information.  There is a third magellan command that isn't necesarily part of the inventory process.  We discovered during development that some versions of the BMC firmware returned redfish information that made no sense.  With a few lines of code, we added the ability to update BMC firmware directly from magellan as well.

### Scanning for Redfish Services

The scanning process occurs by sending out raw TCP packets to all IP addresses on a subnet with either a CIDR or subnet mask and port. If no CIDR or subnet mask is set, then Magellan will use a default mask of `255.255.255.0` and the default SSL port `443`. If a service is found, then Magellan will temporarily store the host IP address and port in memory. At this point in the scanning process, Magellan does not make a distinction between any services that may response. Therefore, to reduce the number of overall requests made during the collection process, Magellan makes another HTTP request to the root Redfish endpoint to verify it is a Redfish service and discards any host and IP address that does not return a valid response. If the service returns a `200` HTTP response status code, then the host IP address and port are stored in a local SQLite database to be used for querying the nodes. The default storage destination is `/tmp/magellan/magellan/db`, but can be set using the `--db.path` flag. Additional subnets, hosts, and ports can be added with their respective flags `--subnet`, `--host`, and `--port`.

```bash
magellan scan --subnet 127.0.0.0/24 --host 172.16.0.100 --port 443 --db.path storage/data.db
```

This command will scan IP addresses 127.0.0.1 - 127.0.0.255 and 172.16.0.100 over port 443. If the `--threads` arguments is not passed, it will try to use one goroutine per host. If no `--timeout` flag is provided, it will wait up to 30 seconds for a response before the scan fails for that host/port. The output will be stored at the relative path location "storage/data.db" containing each successful host and port that was found.

### Collecting Information from Nodes

After performing a scan, the `collect` command is called which fetches the output data from the SQLite database from the `scan` command output. The data is used to make a requests via `bmclib` and `gofish` gathering information about each node's chassis, systems, and ethernet interfaces.

### Updating Firmware

Magellan is capable of updating firmware on a node through Redfish. Currently, it only support updating using a HTTP server and not locally (unless the HTTP server is hosted locally). Updates can be ran by using the following commands:

```bash
magellan update --host 172.16.0.102 --port 443 --user username --pass password --firmware-url http://172.16.0.254:8005/126105/fw/rom.ima_enc --component BMC
magellan update --host 172.16.0.102 --port 443 --user username --pass password --firmware-url http://172.16.0.254:8005/bios/RBU/image.RBU --component BIOS
```

The first command with update's a BMC node's firmware by setting the `--host` and `--port` flags to tell Magellan where to find the BMC on the network. Then, the `--user` and `--pass` flags must be set to login to the node. Finally, the `--firmware-url` flag must be set to tell Magellan where to find the firmware binaries and what component is being update via the `--component` flag.

The status of the update can be checked using the following:

```bash
magellan update --status --host 172.16.0.102 --user username --pass password | jq "."
watch -n 1 "./magellan update --status --host 172.16.0.102 --user admin --pass password | jq '.'"
```

Both of the update function calls make a HTTP request to the hosted firmware server and Redfish server to make the update.

## How does Magellan work with Cray's Hardware State Manager (SMD)?

After collecting information about each BMC node, Magellan makes an HTTP request to send the data to an SMD instance in a JSON format. It uses the `/hsm/v2/Inventory/RedfishEndpoint` endpoint that would normally add a new `RedfishEndpoint` objects and trigger the internal discovery process. SMD was modified to make the internal discovery process optional by adding a `--disable-discovery` flag so that SMD could only use the data sent from Magellan and not probe from hardware components even when the `RediscoverOnUpdate` parameter is set to true in the HTTP request body. Using `curl`, the command to send inventory data to SMD would look something like the following:

```bash
curl -k -d "@magellan.json" -X POST -H "Content-Type: application/json" http://localhost:27779/hsm/v2/Inventory/RedfishEndpoints
```

And the Magellan output HTTP request body from a single node would look something like the following below:

```json5
{
    "FQDN": "172.17.0.1",
    "ID": "x1000c1s7b0",
    "MACRequired": true,
    "Name": null,
    "Password": "root_password",
    "RediscoverOnUpdate": false,
    "Type": "",
    "User": "root"
    "Chassis": [ ... ],
    "Systems": [
        {
            "Data": { ... },
            "EthernetInterfaces": [ ... ]
        }
    ]
}
```

This output has been trimmed down for brevity. Notice that there is an additional "Chassis" and "Systems" field here. These fields are added by Magellan and are optional to be parsed by a slightly modified version of SMD. Once the data is parsed, it then used to populate the underlining database with `Components` and `ComponentEndpoints` structures that are queried by the boot script service (BSS) to manage and boot nodes.

### Possible Areas of Improvement

There are some immediate areas where Magellan could be improved. Currently, Magellan is designed to send requests for services using TCP, but can also be changed to do so with SSDP as well to support UPnP and using UDP port 1900. UPnP discovery is commonly used for the discovery of printer, scanners, and other devices on a local network.

Additionally, the collect command could be split into two separate commands: collect and upload. The new "collect" command would complete without submitting the inventory payload to SMD, instead saving the discovered information solely locally. The "upload" command would then make HTTP call to SMD based on the local files. Having these as two separate commands gives the user more control over which parts of the discovery process are run at which times.

While splitting commands allows for more flexibility, it breaks the continuously workflow of being able to scan for services, collect information, and immediately send it to it's target service. One possible solution to this problem, is to format the output of one command to pipe into another command as input:

```bash
# Run all Magellan commands in sequence
magellan scan --subnet 127.0.0.1 |
    magellan collect --user user --pass password |
    magellan upload --host http://my-host --port 27779
```

This solution offers more flexibility:

```bash
# Save and modify output of scan for input to collect
magellan scan --subnet 172.16.0.0/24 > input.txt
cat "172.16.0.111" >> input.txt
cat input.txt | magellan collect
```

Finally, Magellan can always be adapted send more or less information about BMC nodes as needed in the future. SMD would have to also be updated to parse more of this information of course, but the pipeline for doing so is already established. Additionally, updating this mechanism would have little to no impact on how SMD works today.

## Conclusion

Magellan is a `bmclib`-based BMC discovery tool that reimagines how discovery can work with existing SMD instances and beyond. The tool provides a gateway to explore different ways to approach discovery with a broad range of hardware that would not be possible with the current CSM discovery process. At LANL, we have learned a lot about how the redfish standard can be used for discovery and how the team at HPE has implemented the CSM inventory system.  We have already contributed this code back to the community and plan to expand the discovery capabilities of Magellan in the future.

{{< blog-cta >}}