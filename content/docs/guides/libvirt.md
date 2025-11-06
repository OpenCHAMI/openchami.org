---
title: "Deployment Using Libvirt Virtual Machines"
slug: "libvirt"
description: "Use OpenCHAMI to boot Libvirt VMs"
summary: "Deployment Using Libvirt Virtual Machines"
date: 2025-09-15T19:26:29+00:00
lastmod: 2025-09-15T19:26:29+00:00
draft: false
weight: 300
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

# 0 Overview

This guide walks through setting up a virtual OpenCHAMI cluster using [Libvirt](https://libvirt.org/) virtual machines. Everything will be virtualized so that the only requirement to run this guide is a working Libvirt installation. The only other requirement is to run a webserver to serve boot config for the head node, and this guide assumes Docker is present to use.

As shown in the diagram below, a single head node VM will be set up that will run the OpenCHAMI services, as well as adjacent services such as S3 and a container registry for storing images and image layers as well as the OpenCHAMI image-build tool. The head node is accessible from the host, but the compute nodes are isolated from the host and only accessible through the head node (except for `virsh`, of course).

{{< inline-svg src="svgs/diagrams/openchami-vm-net.svg" class="svg-inline-custom" >}}

This guide largely follows the same setup procedure as the tutorial in thie Wiki with minor variations.

## 0.1 Prerequisites

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
This guide assumes Libvirt + KVM, but the concepts should also be applicable to other hypervisors.
{{< /callout >}}

- Running on a host that supports Libvirt with enough resources to run multiple VMs; recommended is:
  - At least 4 CPU cores
  - At least 8 GB of RAM
  - At least 20GB of free disk space
- Sudo access on the host
- A working Libvirt installation
  - `virsh`
  - `virt-install`
  - `qemu-img`
  - KVM
- Python 3 (for running a quick webserver)

## 0.2 Contents

- [0 Overview](#0-overview)
  - [0.1 Prerequisites](#01-prerequisites)
  - [0.2 Contents](#02-contents)
- [1 Setup](#1-setup)
  - [1.1 Creating Libvirt Networks and Head Node VM](#11-creating-libvirt-networks-and-head-node-vm)
    - [1.1.1 Set Up Kickstart Server](#111-set-up-kickstart-server)
    - [1.1.2 Set Up Libvirt Networks](#112-set-up-libvirt-networks)
    - [1.1.3 Set Up Virtual Head Node VM](#113-set-up-virtual-head-node-vm)
  - [1.2 Configuring the Head Node VM](#12-configuring-the-head-node-vm)
    - [1.2.1 Install Dependencies](#121-install-dependencies)
    - [1.2.3 Storage Directories](#123-storage-directories)
    - [1.2.4 Networking](#124-networking)
    - [1.2.5 Start and Enable S3](#125-start-and-enable-s3)
    - [1.2.6 Start and Enable OCI Container Registry](#126-start-and-enable-oci-container-registry)
    - [1.2.7 Reload Systemd and Start Services](#127-reload-systemd-and-start-services)
- [2 Configuring OpenCHAMI Services](#2-configuring-openchami-services)
  - [2.1 Installing OpenCHAMI Services](#21-installing-openchami-services)
  - [2.2 Starting OpenCHAMI Services](#22-starting-openchami-services)
  - [2.3 Installing `ochami` Client CLI and Testing Access](#23-installing-ochami-client-cli-and-testing-access)
    - [2.3.1 Install `ochami`](#231-install-ochami)
    - [2.3.2 Configure `ochami`](#232-configure-ochami)
    - [2.3.3 Check Access to Services](#233-check-access-to-services)
    - [2.3.4 Generate Access Token](#234-generate-access-token)
- [3 Populating OpenCHAMI Services](#3-populating-openchami-services)
  - [3.1 Set Node Data](#31-set-node-data)
  - [3.2 Build Compute Node Images](#32-build-compute-node-images)
    - [3.2.1 Install and Configure Registry Client](#321-install-and-configure-registry-client)
    - [3.2.2 Install And Configure S3 Client](#322-install-and-configure-s3-client)
    - [3.2.3 Configure the Base Image](#323-configure-the-base-image)
    - [3.2.4 Build the Base Image](#324-build-the-base-image)
    - [3.2.5 Configure the Base Compute Image](#325-configure-the-base-compute-image)
    - [3.2.6 Build the Base Compute Image](#326-build-the-base-compute-image)
    - [3.2.7 Configure the Compute Debug Image](#327-configure-the-compute-debug-image)
    - [3.2.8 Build the Debug Image](#328-build-the-debug-image)
    - [3.2.9 Verify Boot Artifacts](#329-verify-boot-artifacts)
    - [3.2.10 Simplify Image Build Command](#3210-simplify-image-build-command)
  - [3.3 Set Boot Parameters](#33-set-boot-parameters)
    - [3.3.1 Configure the BSS Payload](#331-configure-the-bss-payload)
    - [3.3.2 Send the BSS Payload](#332-send-the-bss-payload)
  - [3.4 Configure Cloud-Init](#34-configure-cloud-init)
    - [3.4.1 Configure Cluster Defaults](#341-configure-cluster-defaults)
    - [3.4.2 Configure Groups](#342-configure-groups)
    - [3.4.3 (_OPTIONAL_) Set Hostname for Specific Node](#343-optional-set-hostname-for-specific-node)
    - [Check Cloud-Init Metadata](#check-cloud-init-metadata)
- [4 Booting a Compute Node](#4-booting-a-compute-node)
  - [4.1 Booting](#41-booting)
  - [4.2 Access](#42-access)
  - [4.3 Next Steps](#43-next-steps)
- [5 Teardown](#5-teardown)
  - [Libvirt](#libvirt)
  - [Kickstart Server](#kickstart-server)

# 1 Setup

It is recommended to create a working directory on your host to store the artifacts created in this guide.

```
mkdir openchami-vm-workdir
cd openchami-vm-workdir
```

Steps in this section occur **on the host running Libvirt**.

## 1.1 Creating Libvirt Networks and Head Node VM

Our head node VM will be running Rocky Linux 9. In order to set it up quickly and automatically, we will be setting up a quick Kickstart server by running a webserver within a container.

Next, we'll create two virtual networks:

- an internal network for our virtual compute nodes and virtual head node to communicate on (**openchami-net-internal**)
- an external network that only our head node is on to allow SSH login to the head node and forwarded traffic from the compute nodes (**openchami-net-external**)

### 1.1.1 Set Up Kickstart Server

We'll create a directory **serve/** that will contain the webroot for our web server:

```
mkdir serve
```

Then, we will create the Kickstart file for our head node and place it there:

```
cat <<'EOF' > serve/kickstart.conf
#version=RHEL9
# Use text install
text

url --url='https://download.rockylinux.org/stg/rocky/9/BaseOS/$basearch/os/'

%packages
@^minimal-environment
bash-completion
kexec-tools
man-pages
tar
tmux

%end

# Keyboard layouts
keyboard --xlayouts='us'
# System language
lang en_US.UTF-8

# Network information
network  --bootproto=static --device=enp1s0 --bootproto=dhcp --ipv6=auto --activate
network  --bootproto=static --device=enp2s0 --ip=172.16.0.254 --netmask=255.255.255.0 --ipv6=auto --activate
network  --hostname=head

# Run the Setup Agent on first boot
firstboot --enable
# Do not configure the X Window System
skipx

ignoredisk --only-use=vda
# Partition clearing information
clearpart --all --drives=vda

## Disk partitioning information
##
## Automatically create partitions, including
## /boot/efi
## /boot
## /
## /home
autopart

# System timezone
#timezone America/Denver --utc

# Use known user and password
rootpw --lock
user --groups=wheel --name=rocky --password=rocky

# Disable SELinux.
selinux --disabled

# Disable firewalld.
firewall --disabled

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%post --log=/root/ks-post.log
# Kernel command line arguments to add.
grubby --update-kernel=ALL --args='console=tty0,115200n8 console=ttyS0,115200n8 systemd.unified_cgroup_hierarchy=1'
grub2-mkconfig -o /etc/grub2.cfg
# Enable mounting /tmp as tmpfs
systemctl enable tmp.mount
dnf install -y vim
%end

reboot
EOF
```

Finally, we'll run the webserver as a daemon to serve our the kickstart file:

```
python3 -m http.server -d ./serve 8000 &
```

### 1.1.2 Set Up Libvirt Networks

First, we will create the external network. This is a NAT network that creates a bridge interface (**br-ochami-ext**) on the host and gives it the IP **192.168.122.1**. DHCP is configured for this network, which will give **192.168.122.2** to our virtual head node (MAC address **52:54:00:c0:fe:01**), and this is the IP that will be used to SSH into it.

Create and start the external network:

```bash
cat <<EOF > openchami-net-external.xml
<network>
  <name>openchami-net-external</name>
  <bridge name="br-ochami-ext"/>
  <forward mode="nat"/>
  <ip address="192.168.122.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.122.2" end="192.168.122.2"/>
      <host mac="52:54:00:c0:fe:01" ip="192.168.122.2"/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-define openchami-net-external.xml
sudo virsh net-start openchami-net-external
```

Next, we will create the internal network. This is an isolated network with no forwarding mode enabled to allow connection to the host so that virtual compute nodes remain behind the virtual head node.

Create and start the internal network:

```bash
cat <<EOF > openchami-net-internal.xml
<network>
  <name>openchami-net-internal</name>
  <bridge name="br-ochami-int"/>
</network>
EOF

sudo virsh net-define openchami-net-internal.xml
sudo virsh net-start openchami-net-internal
```

### 1.1.3 Set Up Virtual Head Node VM

Ensure the `edk2-ovmf` package is installed on the host. This will provide the VM firmware and EFI variable files for our VMs. Using OVMF (Open Virtual Machine Firmware) instead of the default will allow us to see the console output for the PXE boot process so we can troubleshoot any issues that arise. For example, on Red Hat systems:

```
sudo dnf install -y edk2-ovmf
```

Create a virtual disk for the head node VM:

```
qemu-img create -f qcow2 head.img 20G
```

Create the Rocky Linux 9 head node VM using the Kickstart server:

```
sudo virt-install \
  --name head \
  --memory 4096 \
  --vcpus 1 \
  --disk path="$PWD/head.img" \
  --os-variant rocky9 \
  --network network=openchami-net-external,model=virtio,mac=52:54:00:c0:fe:01 \
  --network network=openchami-net-internal,model=virtio,mac=52:54:00:be:ef:ff \
  --graphics none \
  --location 'https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/kickstart/' \
  --console pty,target_type=serial \
  --boot hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm \
  --extra-args 'inst.ks=http://192.168.122.1:8000/kickstart.conf ip=dhcp ip=dhcp console=ttyS0,115200n8'
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If you get this:

```
ERROR    Failed to open file '/usr/share/OVMF/OVMF_VARS.fd': No such file or directory
```

Check the path under **/usr/share/OVMF**. Some distros store the files under a variant name under a variant directory (e.g. on Arch Linux, this file is at **/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd** for x86\_64 hosts).
{{< /callout >}}

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
When running the `virt-install` command above, if the following errors occur (assuming `openchami-vm-workdir` is in `/home/user`):
```
WARNING  /home/user/openchami-vm-workdir/head.img may not be accessible by the hypervisor. You will need to grant the 'qemu' user search permissions for the following directories: ['/home/user']
...
ERROR    Cannot access storage file '/home/user/openchami-vm-workdir/head.img' (as uid:107, gid:107): Permission denied
```
Allow the `qemu` user to search the problematic directory:
```
setfacl -m u:qemu:x /home/user
```
and try again.
{{< /callout >}}

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
When running the `virt-install` command above, if the following errors occur (assuming `openchami-vm-workdir` is in `/home/user`):
```
WARNING  /home/user/openchami-vm-workdir/head.img may not be accessible by the hypervisor. You will need to grant the 'qemu' user search permissions for the following directories: ['/home/user']
...
ERROR    Cannot access storage file '/home/user/openchami-vm-workdir/head.img' (as uid:107, gid:107): Permission denied
```
Allow the `qemu` user to search the problematic directory:
```
setfacl -m u:qemu:x /home/user
```
and try again.
{{< /callout >}}

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the VM installation fails for any reason, it can be destroyed and undefined so that the install command can be run again.

1. Shut down ("destroy") the VM:
   ```
   sudo virsh destroy head
   ```
2. Undefine the VM:
   ```
   sudo virsh undefine --nvram head
   ```
3. Re-run the `virt-install` command above.
{{< /callout >}}

We will see:

1. The kernel/initramfs for Rocky Linux download
2. The kernel boot and image download
3. The kickstart process (a tmux session) perform the installation
4. The node reboot into the installation that is now on `head.img`

After this, we should see the login prompt:

```
head login:
```

Exit the console with `Ctrl`+`]`. If you ever need to access the console again (e.g. to troubleshoot by logging in), use:

```
sudo virsh console head
```

We can now stop the Kickstart server. If we run:

```
jobs
```

we should see our python server running:

```
[1]  + running    python3 -m http.server -d ./serve 8000
```

We can stop it with:

```
kill %1
```

and we should see:

```
[1]  + terminated  python3 -m http.server -d ./serve 8000
```

Login to the head node via SSH:

```
ssh rocky@192.168.122.2
```

The next section will be all within the head node. Feel free to add any SSH key you like.

## 1.2 Configuring the Head Node VM

For this section, remain SSHed into the head node VM.

### 1.2.1 Install Dependencies

```
sudo dnf install -y epel-release podman buildah
```

### 1.2.3 Storage Directories

Container images:

```
sudo mkdir -p /data/oci
sudo chown -R rocky: /data/oci
```

S3 storage:

```
sudo mkdir -p /data/s3
sudo chown -R rocky: /data/s3
```

### 1.2.4 Networking

Enable packet forwarding so our virtual compute nodes can reach out to the Internet:

```
sudo sysctl -w net.ipv4.ip_forward=1
```

Add our cluster's domain to **/etc/hosts** so that domain resolution will work:

```
echo "172.16.0.254 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
```

### 1.2.5 Start and Enable S3

We will create a Podman quadlet to run our S3 service, [Minio](https://min.io), which is where our boot artifacts will be stored.

**Edit as root: `/etc/containers/systemd/minio.container`**

```ini
[Unit]
Description=Minio S3
After=local-fs.target network-online.target
Wants=local-fs.target network-online.target

[Container]
ContainerName=minio-server
Image=docker.io/minio/minio:latest
# Volumes
Volume=/data/s3:/data:Z

# Ports
PublishPort=9000:9000
PublishPort=9001:9001

# Environemnt Variables
Environment=MINIO_ROOT_USER=admin
Environment=MINIO_ROOT_PASSWORD=admin123

# Command to run in container
Exec=server /data --console-address :9001

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

### 1.2.6 Start and Enable OCI Container Registry

Next, we will create another Podman quadlet to run an OCI registry to store image layers to be re-used with the image building tool, which will be done later on.

**Edit as root: `/etc/containers/systemd/registry.container`**

```ini
[Unit]
Description=Image OCI Registry
After=network-online.target
Requires=network-online.target

[Container]
ContainerName=registry
HostName=registry
Image=docker.io/library/registry:latest
Volume=/data/oci:/var/lib/registry:Z
PublishPort=5000:5000

[Service]
TimeoutStartSec=0
Restart=always

[Install]
WantedBy=multi-user.target
```

### 1.2.7 Reload Systemd and Start Services

Reload systemd so that the systemd services get generated from the quadlet files, then start each service:

```
sudo systemctl daemon-reload
sudo systemctl start minio.service
sudo systemctl start registry.service
```

We can quickly make sure these services are running with:

```bash
for s in minio registry; do echo -n "$s: "; systemctl is-failed $s; done
```

We should see:

```
minio: active
registry: active
```

Each individual service can also be checked:

```
systemctl status minio
systemctl status registry
```

# 2 Configuring OpenCHAMI Services

For this section, we will remain SSHed into **the head node VM**.

## 2.1 Installing OpenCHAMI Services

Install the release RPM:

```bash
# Set repository details
OWNER="openchami"
REPO="release"

# Identify the latest release RPM
API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/latest"
release_json=$(curl -s "$API_URL")
rpm_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .browser_download_url' | head -n 1)
rpm_name=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .name' | head -n 1)

# Download the RPM
curl -L -o "$rpm_name" "$rpm_url"

# Install the RPM
sudo rpm -Uvh "$rpm_name"
```

Update the CoreDHCP config. To avoid potential spacing issues with YAML, we'll replace the entire contents of the config file with the below.

```
cat <<EOF | sudo tee /etc/openchami/configs/coredhcp.yaml
server4:
  # You can configure the specific interfaces that you want OpenCHAMI to listen on by
  # uncommenting the lines below and setting the interface
  listen:
    - "%enp2s0"
  plugins:
    # You are able to set the IP address of the system in server_id as the place to look for a DHCP server
    # DNS is able to be set to whatever you want but it is much easier if you keep it set to the server IP
    # Router is also able to be set to whatever you network router address is
    - server_id: 172.16.0.254
    - dns: 172.16.0.254
    - router: 172.16.0.254
    - netmask: 255.255.255.0
    # The lines below define where the system should assign ip addresses for systems that do not have
    # mac addresses stored in SMD
    - coresmd: https://demo.openchami.cluster:8443 http://172.16.0.254:8081 /root_ca/root_ca.crt 30s 1h false
    - bootloop: /tmp/coredhcp.db default 5m 172.16.0.200 172.16.0.250
EOF
```

Update the CoreDNS config as well:

```
cat <<EOF | sudo tee /etc/openchami/configs/Corefile
.:53 {
    # Enable readiness endpoint.
    ready

    # Bind Prometheus metrics endpoint.
    prometheus 0.0.0.0:9153

    # Bind to specific IP address.
    bind 172.16.0.254

    # Specify DNS forwarders.
    #forward . 8.8.8.8

    # Generate DNS records based on BMC and node data in SMD.
    coresmd {
        # Base URI of OpenCHAMI cluster. The SMD base endpoint is appended to this
        # when requesting node and BMC data from SMD.
        smd_url https://demo.openchami.cluster:8443

        # Path to CA certificate bundle to use when verifying TLS for smd_url.
        ca_cert /root_ca/root_ca.crt

        # Frequency to update the SMD data cache.
        cache_duration 30s

        # DNS zone configurations based on records generated from SMD data.
        zone openchami.cluster {
            # Besides generating DNS records for nodes based on xname, a custom
            # record format can be specified based on the node ID. For instance:
            #
            # nodes de{03d}
            #
            # will produce:
            #
            # de001.openchami.cluster
            #
            # for node ID 1 and domain openchami.cluster.
            nodes de{02d}
        }
    }
}
EOF
```

Configure cluster certificates to have the FQDN that we will set for our cluster (needs to match the one in **/etc/hosts**):

```
sudo openchami-certificate-update update demo.openchami.cluster
```

You should see:

```
Changed FQDN to demo.openchami.cluster
Either restart all of the OpenCHAMI services:

  sudo systemctl restart openchami.target

or run the following to just regenerate/redeploy the certificates:

  sudo systemctl restart acme-deploy

```

See what changed:

```
grep -RnE 'demo|openchami\.cluster' /etc/openchami/configs/openchami.env /etc/containers/systemd/
```

## 2.2 Starting OpenCHAMI Services

Start all of the services by starting the `openchami.target` systemd target:

```
sudo systemctl start openchami.target
```

Check the status of all OpenCHAMI services with:

```
systemctl list-dependencies openchami.target
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
It might be useful to continuously monitor this output to see when things fail. We can use the `watch` command for that:

```
watch systemctl list-dependencies openchami.target
```
{{< /callout >}}

If the services started correctly, we should see:

```
openchami.target
● ├─acme-deploy.service
● ├─acme-register.service
● ├─bss-init.service
● ├─bss.service
● ├─cloud-init-server.service
● ├─coresmd-coredhcp.service
● ├─coresmd-coredns.service
● ├─haproxy.service
● ├─hydra-gen-jwks.service
● ├─hydra-migrate.service
● ├─hydra.service
● ├─opaal-idp.service
● ├─opaal.service
● ├─openchami-cert-trust.service
● ├─postgres.service
● ├─smd-init.service
● ├─smd.service
● └─step-ca.service
```

If not, examine the logs for any problematic services with:

```
journalctl -eu <service>
```

where `<service>` is the name of the OpenCHAMI service in the `list-dependencies` output above.

## 2.3 Installing `ochami` Client CLI and Testing Access

The `ochami` CLI tool will be used for interacting with the OpenCHAMI service APIs.

### 2.3.1 Install `ochami`

```
latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
curl -L "${latest_release_url}" -o ochami.rpm
sudo dnf install -y ./ochami.rpm
```

As a sanity check, check the version to make sure it installed properly:

```
ochami version
```

We should get output like:

```
Version:    0.5.4
Tag:        v0.5.4
Branch:     HEAD
Commit:     1219bee4704bf00e3115b06ca2d9089db4342417
Git State:  clean
Date:       2025-09-19T22:46:05Z
Go:         go1.25.1
Compiler:   gc
Build Host: runnervmf4ws1
Build User: runner
```

### 2.3.2 Configure `ochami`

Add a cluster while creating the system-wide config:

```
sudo ochami config cluster set --system --default demo cluster.uri https://demo.openchami.cluster:8443
```

Look at the config to verify:

```
ochami config show
```

We should see:

```yaml
clusters:
    - cluster:
        enable-auth: true
        uri: https://demo.openchami.cluster:8443
      name: demo
default-cluster: demo
log:
    format: rfc3339
    level: warning
```

### 2.3.3 Check Access to Services

```
ochami bss service status
```

### 2.3.4 Generate Access Token

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
Access tokens only last for an hour by default. Thus, you should keep this incantation handy to run again, should your token expire.
{{< /callout >}}

```
export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

# 3 Populating OpenCHAMI Services

For this section, we will remain SSHed into **the head node VM**.

Let's create a directory for our payload files that we will use to populate OpenCHAMI with data.

```
sudo mkdir /etc/openchami/data
```

## 3.1 Set Node Data

We need to inform SMD about our nodes. We'll create a file for this and use `ochami` to send it to SMD.

**Edit as root: `/etc/openchami/data/nodes.yaml`**

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
When writing YAML, it's important to be consistent with spacing. **It is recommended to use spaces for all indentation instead of tabs.**

When pasting, you may have to configure your editor to not apply indentation rules (`:set paste` in Vim, `:set nopaste` to switch back).
{{< /callout >}}

```yaml
nodes:
- name: compute1
  nid: 1
  xname: x1000c0s0b0n0
  bmc_mac: de:ca:fc:0f:fe:e1
  bmc_ip: 172.16.0.101
  groups:
  - compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:01
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.1
- name: compute2
  nid: 2
  xname: x1000c0s0b1n0
  bmc_mac: de:ca:fc:0f:fe:e2
  bmc_ip: 172.16.0.102
  groups:
  - compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:02
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.2
- name: compute3
  nid: 3
  xname: x1000c0s0b2n0
  bmc_mac: de:ca:fc:0f:fe:e3
  bmc_ip: 172.16.0.103
  groups:
  - compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:03
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.3
- name: compute4
  nid: 4
  xname: x1000c0s0b3n0
  bmc_mac: de:ca:fc:0f:fe:e4
  bmc_ip: 172.16.0.104
  groups:
  - compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:04
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.4
- name: compute5
  nid: 5
  xname: x1000c0s0b4n0
  bmc_mac: de:ca:fc:0f:fe:e5
  bmc_ip: 172.16.0.105
  groups:
  - compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:05
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.5
```

Send to SMD:

```
ochami discover static -f yaml -d @/etc/openchami/data/nodes.yaml
```

Check that the population occurred with:

```
ochami smd component get | jq '.Components[] | select(.Type == "Node")'
```

The output should be:

```json
{
  "Enabled": true,
  "ID": "x1000c0s0b0n0",
  "NID": 1,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b1n0",
  "NID": 2,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b2n0",
  "NID": 3,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b3n0",
  "NID": 4,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b4n0",
  "NID": 5,
  "Role": "Compute",
  "Type": "Node"
}
```

## 3.2 Build Compute Node Images

Now, we will build images for our virtual compute nodes using the OpenCHAMI [image-builder](https://github.com/OpenCHAMI/image-builder).

First, create a directory to house image configs:

```
sudo mkdir /etc/openchami/data/images
```

### 3.2.1 Install and Configure Registry Client

We will use [`regctl`](https://github.com/regclient/regclient) in order to query the OCI registry about images that are present in it.

Install `regctl`:

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
Make sure you run the below **as your normal user** since this will create a config file in your home directory.
{{< /callout >}}

```
curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 > regctl && sudo mv regctl /usr/local/bin/regctl && sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled demo.openchami.cluster:5000
```

Make sure config got set:

```
cat ~/.regctl/config.json
```

Output should be:

```json
{
  "hosts": {
    "demo.openchami.cluster:5000": {
      "tls": "disabled",
      "hostname": "demo.openchami.cluster:5000",
      "reqConcurrent": 3
    }
  }
}
```

### 3.2.2 Install And Configure S3 Client

We will use [`s3cmd`](https://github.com/regclient/regclient) to communicate with our S3 service.

Install it:

```
sudo dnf install -y s3cmd
```

**Edit as normal user: `~/.s3cfg`**

```ini
# Setup endpoint
host_base = demo.openchami.cluster:9000
host_bucket = demo.openchami.cluster:9000
bucket_location = us-east-1
use_https = False

# Setup access keys
access_key = admin
secret_key = admin123

# Enable S3 v4 signature APIs
signature_v2 = False
```

Create and configure S3 buckets for our boot artifacts:

```
s3cmd mb s3://efi
s3cmd setacl s3://efi --acl-public
s3cmd mb s3://boot-images
s3cmd setacl s3://boot-images --acl-public
```

Set the retrieval policies of our boot ertifact S3 buckets:

**Edit as normal user: `~/s3-public-read-boot.json`**

```json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":"*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::boot-images/*"]
    }
  ]
}
```

**Edit as normal user: `~/s3-public-read-efi.json`**

```json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":"*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::efi/*"]
    }
  ]
}
```

```
s3cmd setpolicy ~/s3-public-read-boot.json s3://boot-images \
    --host=172.16.0.254:9000 \
    --host-bucket=172.16.0.254:9000

s3cmd setpolicy ~/s3-public-read-efi.json s3://efi \
    --host=172.16.0.254:9000 \
    --host-bucket=172.16.0.254:9000
```

We should see the following output:

```
s3://boot-images/: Policy updated
s3://efi/: Policy updated
```

Now, when we run:

```
s3cmd ls
```

we should see:

```
<date> <time>  s3://boot-images
<date> <time>  s3://efi
```

### 3.2.3 Configure the Base Image

First, we will create a "base image" that will essentially be a stock Rocky Linux 9 root filesystem.

**Edit as root: `/etc/openchami/data/images/rocky-base-9.yaml`**

```yaml
options:
  layer_type: 'base'
  name: 'rocky-base'
  publish_tags: '9'
  pkg_manager: 'dnf'
  parent: 'scratch'
  publish_registry: 'demo.openchami.cluster:5000/demo'
  registry_opts_push:
    - '--tls-verify=false'

repos:
  - alias: 'Rocky_9_BaseOS'
    url: 'https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/'
    gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'
  - alias: 'Rocky_9_AppStream'
    url: 'https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/'
    gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'

package_groups:
  - 'Minimal Install'
  - 'Development Tools'

packages:
  - chrony
  - cloud-init
  - dracut-live
  - kernel
  - rsyslog
  - sudo
  - wget

cmds:
  - cmd: 'dracut --add "dmsquash-live livenet network-manager" --kver $(basename /lib/modules/*) -N -f --logfile /tmp/dracut.log 2>/dev/null'
  - cmd: 'echo DRACUT LOG:; cat /tmp/dracut.log'
```

### 3.2.4 Build the Base Image

Now, let's build it:

```
podman run \
  --rm \
  --device /dev/fuse \
  --network host \
  -v /etc/openchami/data//images/rocky-base-9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build --config config.yaml --log-level DEBUG
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Messages prefixed with `ERROR` mean that these messages are being emitted at the "error" log level and aren't _necessarily_ errors.
{{< /callout >}}

This will take a good chunk of time (~10 minutes or so) since we are building an entire Linux filesystem from scratch. At the end, we should see:

```
-------------------BUILD LAYER--------------------
pushing layer rocky-base to demo.openchami.cluster:5000/demo/rocky-base:9
```

Check that our base image got pushed to the registry:

```
regctl repo ls demo.openchami.cluster:5000
```

Output should be:

```
demo/rocky-base
```

We can see the tag with:

```
regctl tag ls demo.openchami.cluster:5000/demo/rocky-base
```

It should match the tag we set in the image config:

```
9
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
This image is a standard OCI container image. This means we can pull it, run it, and poke around. Try it out:

```
podman run --tls-verify=false --rm -it demo.openchami.cluster:5000/demo/rocky-base:9 bash
```

This will run `bash` within the container, which means we can verify certain files exist, contain the right content, etc. Afterward, run `exit` to return to the host shell.
{{< /callout >}}

### 3.2.5 Configure the Base Compute Image

**Edit as root: `/etc/openchami/data/images/compute-base-rocky9.yaml`**

```yaml
options:
  layer_type: 'base'
  name: 'compute-base'
  publish_tags:
    - 'rocky9'
  pkg_manager: 'dnf'
  parent: 'demo.openchami.cluster:5000/demo/rocky-base:9'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish SquashFS image to local S3
  publish_s3: 'http://demo.openchami.cluster:9000'
  s3_prefix: 'compute/base/'
  s3_bucket: 'boot-images'

  # Publish OCI image to container registry
  #
  # This is the only way to be able to re-use this image as
  # a parent for another image layer.
  publish_registry: 'demo.openchami.cluster:5000/demo'
  registry_opts_push:
    - '--tls-verify=false'

repos:
  - alias: 'Epel9'
    url: 'https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/'
    gpg: 'https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9'

packages:
  - boxes
  - cowsay
  - figlet
  - fortune-mod
  - git
  - nfs-utils
  - tcpdump
  - traceroute
  - vim
```

Notice that this time, we push both to the OCI registry _and_ S3. We will be using this image _both_ as a parent layer to subsequent images _and_ to boot nodes directly.

### 3.2.6 Build the Base Compute Image

```
podman run \
  --rm \
  --device /dev/fuse \
  --network host \
  -e S3_ACCESS=admin \
  -e S3_SECRET=admin123 \
  -v /etc/openchami/data/images/compute-base-rocky9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build --config config.yaml --log-level DEBUG
```

This won't take as long as the base image since we are only installing packages on top of the already-built filesystem. This time, since we are pushing to S3 (and we passed `--log-level DEBUG`) we will see _a lot_ of S3 output. We should see in the output:

```
Pushing /var/tmp/tmpda2ddyh0/rootfs as compute/base/rocky9.6-compute-base-rocky9 to boot-images
pushing layer compute-base to demo.openchami.cluster:5000/demo/compute-base:rocky9
```

Check that this image got added to the registry in addition to the base image:

```
regctl repo ls demo.openchami.cluster:5000
```

The output should be:

```
demo/compute-base
demo/rocky-base
```

Verify the tag:

```
regctl tag ls demo.openchami.cluster:5000/demo/compute-base
```

which should be:

```
rocky9
```

Check that this image got added to S3 as well:

```
s3cmd ls -Hr s3://boot-images | grep compute/base
```

This should be similar to:

```
<date> <time>  1436M  s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
<date> <time>    82M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.28.1.el9_6.x86_64.img
<date> <time>    14M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.28.1.el9_6.x86_64
```

Your kernel/initramfs versions may vary.

### 3.2.7 Configure the Compute Debug Image

**Edit as root: `/etc/openchami/data/images/compute-debug-rocky9.yaml`**

```yaml
options:
  layer_type: base
  name: compute-debug
  publish_tags:
    - 'rocky9'
  pkg_manager: dnf
  parent: '172.16.0.254:5000/demo/compute-base:rocky9'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish to local S3
  publish_s3: 'http://172.16.0.254:9000'
  s3_prefix: 'compute/debug/'
  s3_bucket: 'boot-images'

packages:
  - shadow-utils

cmds:
  - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
```

See the image-builder reference for more detailed information on writing an image config. Let's take a moment to draw attention to what our debug image config does:

- Use the base compute image as the parent, pull it from the registry without TLS, and call the new image "compute-debug":

  ```yaml
  name: 'compute-debug'
  parent: '172.16.0.254:5000/demo/compute-base:rocky9'
  registry_opts_pull:
    - '--tls-verify=false'
  ```

- Push the image to `http://172.16.0.254:9000/boot-images/compute/debug/` in S3:

  ```yaml
  publish_s3: 'http://172.16.0.254:9000'
  s3_prefix: 'compute/debug/'
  s3_bucket: 'boot-images'
  ```

- Create a `testuser` user (password is `testuser`):

  ```yaml
  packages:
    - shadow-utils

  cmds:
    - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
  ```

  This will be the user we will login to the console as.

### 3.2.8 Build the Debug Image

This should be familiar by now:

```
podman run \
  --rm \
  --device /dev/fuse \
  -e S3_ACCESS=admin \
  -e S3_SECRET=admin123 \
  -v /etc/openchami/data/images/compute-debug-rocky9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build --config config.yaml --log-level DEBUG
```

### 3.2.9 Verify Boot Artifacts

```
s3cmd ls -Hr s3://boot-images/
```

We should see (again, kernel/initramfs versions may vary):

```
<date> <time>  1436M  s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
<date> <time>  1437M  s3://boot-images/compute/debug/rocky9.6-compute-debug-rocky9
<date> <time>    82M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.28.1.el9_6.x86_64.img
<date> <time>    14M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.28.1.el9_6.x86_64
<date> <time>    82M  s3://boot-images/efi-images/compute/debug/initramfs-5.14.0-570.28.1.el9_6.x86_64.img
<date> <time>    14M  s3://boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.28.1.el9_6.x86_64
```

We need to get the URIs for the compute debug image for the assignment of boot parameters in the next step:

```
s3cmd ls -Hr s3://boot-images | grep compute/debug | awk '{print $4}' | sed 's-^s3://--'
```

This will give us the paths that we'll need:

```
boot-images/compute/debug/rocky9.6-compute-debug-rocky9
boot-images/efi-images/compute/debug/initramfs-5.14.0-570.28.1.el9_6.x86_64.img
boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.28.1.el9_6.x86_64
```

In this case:

- Kernel path: `boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.28.1.el9_6.x86_64`
- Initramfs path: `boot-images/efi-images/compute/debug/initramfs-5.14.0-570.28.1.el9\_6.x86\_64.img`
- SquashFS image path: `boot-images/compute/debug/rocky9.6-compute-debug-rocky9`

**Copy these _for your kernel version_**. Do not copy from here as the versions may be different.

### 3.2.10 Simplify Image Build Command

We can create a function for the image-building command so we don't have to type out that long Podman command each time.

**Edit as root:** **`/etc/profile.d/build-image.sh`**

```bash
build-image-rh9()
{
    if [ -z "$1" ]; then
        echo 'Path to image config file required.' 1>&2;
        return 1;
    fi;
    if [ ! -f "$1" ]; then
        echo "$1 does not exist." 1>&2;
        return 1;
    fi;
    podman run \
            --rm \
            --device /dev/fuse \
            -e S3_ACCESS=admin \
            -e S3_SECRET=admin123 \
            -v "$(realpath $1)":/home/builder/config.yaml:Z \
            ${EXTRA_PODMAN_ARGS} \
            ghcr.io/openchami/image-build-el9:v0.1.2 \
            image-build \
                --config config.yaml \
                --log-level DEBUG
}

build-image-rh8()
{
    if [ -z "$1" ]; then
        echo 'Path to image config file required.' 1>&2;
        return 1;
    fi;
    if [ ! -f "$1" ]; then
        echo "$1 does not exist." 1>&2;
        return 1;
    fi;
    podman run \
           --rm \
           --device /dev/fuse \
           -e S3_ACCESS=admin \
           -e S3_SECRET=admin123 \
           -v "$(realpath $1)":/home/builder/config.yaml:Z \
           ${EXTRA_PODMAN_ARGS} \
           ghcr.io/openchami/image-build:v0.1.2 \
           image-build \
                --config config.yaml \
                --log-level DEBUG
}
alias build-image=build-image-rh9
```

This will be applied on every login, so source it to apply the current session:

```bash
source /etc/profile.d/build-image.sh
```

Now, we can build images with:

```
build-image /path/to/image/config.yaml
```

We can ensure that our alias is getting used:

```
$ which build-image
alias build-image='build-image-rh9'
        build-image-rh9 ()
        {
            if [ -z "$1" ]; then
                echo 'Path to image config file required.' 1>&2;
                return 1;
            fi;
            if [ ! -f "$1" ]; then
                echo "$1 does not exist." 1>&2;
                return 1;
            fi;
            podman run --rm --device /dev/fuse -e S3_ACCESS=admin -e S3_SECRET=admin123 -v "$(realpath $1)":/home/builder/config.yaml:Z ${EXTRA_PODMAN_ARGS} ghcr.io/openchami/image-build-el9:v0.1.2 image-build --config config.yaml --log-level DEBUG
        }
```

## 3.3 Set Boot Parameters

Now that we have boot artifacts present, we need to inform BSS that our compute nodes need to boot them. In this section, we'll tell our nodes to boot the debug image that we created.

Create a directory for our BSS payloads:

```
sudo mkdir -p /etc/openchami/data/boot
```

### 3.3.1 Configure the BSS Payload

The format of the payload will be:

```yaml
kernel: 'http://172.16.0.254:9000/<KERNEL_PATH>'
initrd: 'http://172.16.0.254:9000/<INITRAMFS_PATH>'
params: 'nomodeset ro root=live:http://172.16.0.254:9000/<IMAGE_PATH> ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```

Where:

- `<KERNEL_PATH>` is the kernel path we copied above
- `<INITRAMFS_PATH>` is the initramfs path we copied above
- `<IMAGE_PATH>` is the SquashFS image path we copied above

For example:

```yaml
kernel: 'http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64'
initrd: 'http://172.16.0.254:9000/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```

Create the payload for BSS, **/etc/openchami/data/boot/boot-compute-debug.yaml**, that contains the URIs for the boot artifacts:

```
URIS=$(s3cmd ls -Hr s3://boot-images | grep compute/debug | awk '{print $4}' | sed 's-s3://-http://172.16.0.254:9000/-' | xargs)
URI_IMG=$(echo "$URIS" | cut -d' ' -f1)
URI_INITRAMFS=$(echo "$URIS" | cut -d' ' -f2)
URI_KERNEL=$(echo "$URIS" | cut -d' ' -f3)
cat <<EOF | sudo tee /etc/openchami/data/boot/boot-compute-debug.yaml
---
kernel: '${URI_KERNEL}'
initrd: '${URI_INITRAMFS}'
params: 'nomodeset ro root=live:${URI_IMG} ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
EOF
```

Examine the `tee` output to make sure the format matches the example above.

### 3.3.2 Send the BSS Payload

Once configured, the payload can be sent to BSS:

```
ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/boot-compute-debug.yaml
```

Verify that the parameters got set:

```
ochami bss boot params get -F yaml
```

We should see tha they match from the payload set above:

```yaml
- cloud-init:
    meta-data: null
    phone-home:
        fqdn: ""
        hostname: ""
        instance_id: ""
        pub_key_dsa: ""
        pub_key_ecdsa: ""
        pub_key_rsa: ""
    user-data: null
  initrd: http://172.16.0.254:9000/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.28.1.el9_6.x86_64.img
  kernel: http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.28.1.el9_6.x86_64
  macs:
    - 52:54:00:be:ef:01
    - 52:54:00:be:ef:02
    - 52:54:00:be:ef:03
    - 52:54:00:be:ef:04
    - 52:54:00:be:ef:05
  params: nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
```

## 3.4 Configure Cloud-Init

Create a directory for cloud-init configs:

```
sudo mkdir /etc/openchami/data/cloud-init
```

### 3.4.1 Configure Cluster Defaults

Create SSH keypair for compute nodes:

```
ssh-keygen -t ed25519
```

Create a payload to send to cloud-init to set the cluster-wide defaults (notice that we add our SSH public key to the `public-keys` list):

```
cat <<EOF | sudo tee /etc/openchami/data/cloud-init/ci-defaults.yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 2
public-keys:
  - '$(cat ~/.ssh/id_ed25519.pub)'
short-name: "de"
EOF
```

If we print the file, we should see our SSH key, for example:

```
cat /etc/openchami/data/cloud-init/ci-defaults.yaml
```

```yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 2
public-keys:
  - 'ssh-ed25519 AAAA... rocky@head'
short-name: "de"
```

Send this to cloud-init:

```
ochami cloud-init defaults set -f yaml -d @/etc/openchami/data/cloud-init/ci-defaults.yaml
```

Verify that the configs were set:

```
ochami cloud-init defaults get -F json-pretty
```

We should see:

```json
{
  "base-url": "http://172.16.0.254:8081/cloud-init",
  "cluster-name": "demo",
  "nid-length": 2,
  "public-keys": [
    "ssh-ed25519 AAAA... rocky@head"
  ],
  "short-name": "de"
}
```

### 3.4.2 Configure Groups

When we populated SMD with our node information, we told it to add the nodes to a new group called `compute`. Now, we will tell cloud-init to provide a cloud-config for this group so that all nodes in that group will get that configuration.

This basic cloud-config will put our SSH public key in the `authorized_keys` file of the root user. The config allows Jinja2 templating so that we can use the `public-keys` variable from the cluster defaults.

**Edit as root: `/etc/openchami/data/cloud-init/ci-group-compute.yaml`**

```yaml
- name: compute
  description: "compute config"
  file:
    encoding: plain
    content: |
      ## template: jinja
      #cloud-config
      merge_how:
      - name: list
        settings: [append]
      - name: dict
        settings: [no_replace, recurse_list]
      users:
        - name: root
          ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
      disable_root: false
```

Send this to cloud-init:

```
ochami cloud-init group set -f yaml -d @/etc/openchami/data/cloud-init/ci-group-compute.yaml
```

Check config template by rendering it for a node:

```
ochami cloud-init group render compute x1000c0s0b0n0
```

We should see:

```yaml
## template: jinja
#cloud-config
merge_how:
- name: list
  settings: [append]
- name: dict
  settings: [no_replace, recurse_list]
users:
  - name: root
    ssh_authorized_keys: ['ssh-ed25519 AAAA... rocky@head']
disable_root: false
```

### 3.4.3 (_OPTIONAL_) Set Hostname for Specific Node

Cloud-Init supports setting the `local-hostname` per-node:

```
ochami cloud-init node set -d '[{"id":"x1000c0s0b0n0","local-hostname":"compute1"}]'
```

This will make our first compute node's hostname `compute1`.

This step isn't necessary. It is only here to demonstrate per-node configuration in cloud-init if that is desired.

### Check Cloud-Init Metadata

```
ochami cloud-init node get meta-data x1000c0s0b0n0 -F yaml
```

We should see something like:

```yaml
- cluster-name: demo
  hostname: de01
  instance-id: i-36c124e2
  instance_data:
    v1:
        instance_id: i-36c124e2
        local_ipv4: 172.16.0.1
        public_keys:
            - ssh-ed25519 AAAA... rocky@head
        vendor_data:
            cloud_init_base_url: http://172.16.0.254:8081/cloud-init
            cluster_name: demo
            groups:
                compute:
                    Description: compute config
            version: "1.0"
  local-hostname: de01
```

We can see which SMD groups a node will be merging:

```
ochami cloud-init node get vendor-data x1000c0s0b0n0
```

We only have one (`compute`), so we see:

```
#include
http://172.16.0.254:8081/cloud-init/compute.yaml
```

# 4 Booting a Compute Node

For this section, we will remain SSHed into **the head node VM**, since access to the compute node VMs can only happen through the head node VM.

## 4.1 Booting

At this point, we have what we need to boot a compute node. Exit the SSH session from the head node VM and start a virtual compute node VM:

```
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant rocky9 \
  --network network=openchami-net-internal,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If you need to destroy and restart the VM, first exit the console with `Ctrl`+`]`. Then:

1. Shut down ("destroy") the VM:
   ```
   sudo virsh destroy compute1
   ```
2. Undefine the VM:
   ```
   sudo virsh undefine --nvram compute1
   ```
3. Re-run the `virt-install` command above.
{{< /callout >}}

We should see the node:

1. Get its IP address (172.16.0.1)
2. Download the iPXE bootloader binary from CoreSMD
3. Download the `config.ipxe` script that chainloads the iPXE script from BSS (http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01)
4. Download the kernel and initramfs in S3
5. Boot into the image, running cloud-init

Watch it boot. First, it should PXE:

```
>>Start PXE over IPv4.
  Station IP address is 172.16.0.1

  Server IP address is 172.16.0.254
  NBP filename is ipxe-x86_64.efi
  NBP filesize is 1079296 Bytes
 Downloading NBP file...

  NBP file downloaded successfully.
BdsDxe: loading Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
BdsDxe: starting Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
iPXE initialising devices...
autoexec.ipxe... Not found (https://ipxe.org/2d12618e)



iPXE 1.21.1+ (ge9a2) -- Open Source Network Boot Firmware -- https://ipxe.org
Features: DNS HTTP HTTPS iSCSI TFTP VLAN SRP AoE EFI Menu
```

Then, we should see it get it's boot script from TFTP, then BSS (the `/boot/v1` URL), then download it's kernel/initramfs and boot into Linux.

```
Configuring (net0 52:54:00:be:ef:01)...... ok
tftp://172.16.0.254:69/config.ipxe... ok
Booting from http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.0.254:8081/boot/v1/bootscript... ok
http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64... ok
http://172.16.0.254:9000/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img... ok
```

During Linux boot, we should see the SquashFS image get downloaded and loaded.

```
[    2.169210] dracut-initqueue[545]:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
[    2.170532] dracut-initqueue[545]:                                  Dload  Upload   Total   Spent    Left  Speed
100 1356M  100 1356M    0     0  1037M      0  0:00:01  0:00:01 --:--:-- 1038M
[    3.627908] squashfs: version 4.0 (2009/01/31) Phillip Lougher
```

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
If the logs includes this, we've got trouble `8:37PM DBG IP address 10.89.2.1 not found for an xname in nodes`

It means that our iptables has mangled the packet and we're not receiving correctly through the bridge.
{{< /callout >}}

## 4.2 Access

Access is done **on the head node**. SSH there first when going through this section.

Since cloud-init regenerates SSH host keys on every boot, we can provide a configuration to ignore them for compute nodes.

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Cloud-Init is able to provide consistent keys, but we skip this for simplicity.
{{< /callout >}}

**Edit as root: `/etc/ssh/ssh_config.d/ignore.conf`**

```
Match host=nid???,de???,x????c?s?b?n?,172.16.0.*
        UserKnownHostsFile=/dev/null
        StrictHostKeyChecking=no
```

Now, we can SSH as root into the compute node:

```
ssh root@172.16.0.1
```

## 4.3 Next Steps

- Boot the rest of the compute nodes
- Perform system administration tasks

# 5 Teardown

## Libvirt

This section should be run **from the host**.

In order to destroy this VM setup, both the VMs and the networks should be brought down.

To bring down the VMs:

```
sudo virsh destroy compute1  # Do this for all computes
sudo virsh destroy head
```

To bring down the networks:

```
sudo virsh net-destroy openchami-net-external
sudo virsh net-destroy openchami-net-internal
```

The above will shutdown the VMs and networks, but will not delete them.

To delete the VMs:

```
sudo virsh undefine --nvram compute1  # Do this for all computes
sudo virsh undefine --nvram head
```

To delete the networks:

```
sudo virsh net-undefine openchami-net-internal
sudo virsh net-undefine openchami-net-external
```

Delete the head node's boot disk:

```
rm head.img
```

## Kickstart Server

Check if the Kickstart server is still running with:

```
jobs
```

If we see:

```
[1]  + running    python3 -m http.server -d ./serve 8000
```

when we can kill it with:

```
kill %1
```

and we should see:

```
[1]  + terminated  python3 -m http.server -d ./serve 8000
```
