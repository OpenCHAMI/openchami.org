# Interacting with OpenCHAMI on Badger

OpenCHAMI is designed to operate more like a cloud api than a standard Linux application.  No command can succeed just based on POSIX user/group details.  The API server may be running on the same head node, but it also could be running on a different node, or even somewhere on the cloud.  Interacting with these APIs without adding significant management burden or dependencies has been a goal of OpenCHAMI from the beginning.  We've chosen JWTs as our standard for API authentication and authorization.  Once a JWT is issued, it can be reused until it expires with no need to contact any central authentication server.

Since most of our development effort in the past year has focused on the server side processing of the JWTs, we didn't have a ready-made client for making changes to a system in support of Badger.  Our testing involved a lot of pre-built curl commands as bash aliases.  That wouldn't work for Badger.  At the same time, we also didn't feel ready to build an actual CLI for the sysadmins without taking the time to really understand how it would be used.

Like many sysadmins before us, we decided to split the difference and create a stopgap solution in Python.  While we're very pleased with it for use with Badger, we'll also be fairly disappointed if we find it still in use a year from now.


## ochami-cli

Our stopgap python script is called [ochami-cli](https://github.com/OpenCHAMI/ochami-cmdline) which narrowly covers the things we need to run badger.  It makes plenty of assumptions about our environment, but we are learning a lot about sysadmin tooling as we work through the use cases.

The tool requires specific environment settings, which should be configured in `/etc/profile.d/ochami.sh`.

### Environment Variables
Set the following environment variables:
```bash
SMD_URL=https://badger.openchami.cluster:8443/hsm/v2
BSS_URL=https://badger.openchami.cluster:8443/boot/v1
CLOUD_INIT_URL=https://badger.openchami.cluster:8443/cloud-init
CLOUD_INIT_SECURE_URL=https://badger.openchami.cluster:8443/cloud-init-secure
```

Additionally, the profile script should create bash functions to obtain an access token and generate a CA certificate:
```bash
export ACCESS_TOKEN=$(gen_access_token)
get_ca_cert > /tmp/ochami.pem
export CACERT=/tmp/ochami.pem
```


## Populating our Inventory System

As noted in the description of Badger, we weren't working with state-of-the-art hardware.  It lacked modern BMCs with Redfish support so our normal discovery tooling was useless.  Instead, we had to rely on manually curated lists of nodes.  All 660 Nodes needed to be enumerated in a flat file with no mistakes in order to enroll everything in the OpenCHAMI system.  The format of our `nodes.yaml` file will be familiar to many HPC sysadmins.  Without discovery, this process of manual enrollment should be familiar to many.  It includes the three main IP addresses necessary for communicating with the nodes, BMC for power control, High Speed for managing jobs, and a management ip for ssh access to nodes.  It also includes a MAC address, hostname, xname (indicating location in the racks), and node id (nid).  The last field is `group` which is how our system determines what the purpose of the node is.  For our purposes, every node is a `compute` node which contributes directly to running jobs.  In other systems, we also have `io` nodes that provide access to data and `visualization` nodes that researchers can use to see their results.  The list can be extended for all of the many supporting node types that exist in an HPC cluster.


```yaml
nodes:
-   bmc_ipaddr: 192.168.8.1
    hsn_ipaddr: 10.16.24.1
    ipaddr: 192.168.4.1
    group: compute
    mac: AA:BB:CC:DD:EE:FF
    name: ba001
    nid: 1
    xname: x1000c0s0b0n0
```

Some of the data in our configuration file isn't directly used by OpenCHAMI for building the inventory.  Instead, it is stored with the inventory and passed through to our cloud-init server which provides individualized information to each node at boot time. Services on the node can then use that information to configure services or set up jobs.


### Populate the Inventory
```bash
# Populate the inventory service (SMD) with nodes
ochami-cli smd --fake-discovery --payload nodes.yaml
```

### Review the created resources
```bash
# Review created resources within SMD
ochami-cli smd --get-components
ochami-cli smd --get-interfaces
```

> __NB__ SMD doesn't store nodes as "nodes".  It stores components which represent nodes as well as other things and it stores Interfaces which are related to components.  The full data model of SMD is beyond the scope of this discussion.  For our purposes, it is sufficient to know that the only components we care about in Badger are nodes so the two terms can be used interchangably.

### Add Boot Parameters

In OpenCHAMI, a boot configuration is stored separately from the definition of a node.  This allows us to create a single boot configuration and link it to many nodes and ensure that they boot the same image and kernel.  Until we have a more advanced CLI that allows us to work with collections of nodes easily, we added some `bss` commands to `ochami-cli` that deal manually with the boot script service (bss).  Once again, we have a yaml file that must be managed manually and then uploaded to bss in order to ensure each node boots correctly.

```yaml
macs:
  - AA:BB:CC:DD:EE:FF
initrd: 'http://192.168.1.253:8080/alma/initramfs.img'
kernel: 'http://192.168.1.253:8080/alma/vmlinuz'
params: 'nomodeset ro ip=dhcp selinux=0 console=ttyS0,115200 ip6=off ochami_ci_url=http://10.1.0.3:8081/cloud-init/ ochami_ci_url_secure=http://10.1.0.3:8081/cloud-init-secure/ network-config=disabled rd.shell root=live:http://192.168.1.253:8080/alma/rootfs'
```

#### Kernel Commandline

In OpenCHAMI, our kernel commandline holds a lot of information about how the system supports the boot.

* __ochami_ci_url__ - The url for our cloud-init server which delivers a set of instance-specific information to each node
* __ochami_ci_url_secure__ - The secure endpoint for cloud-init which may transmit secrets
* __root__ - the root filesystem to boot.  This may be nfs:// or http:// or other exotic protocols as needed.  The `live` specification indicates that Linux will download the filesystem and make it an overlayfs layer for the newroot.

To populate BSS with `ochami-cli`:
```bash
ochami-cli bss --add-bootparams --payload bss.yaml
```
And to view the new data:
```bash
ochami-cli bss --get-bootparams
```

See more about the images we booted on Badger and how cloud-init helps us configure everything in Part 4