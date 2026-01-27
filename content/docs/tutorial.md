---
title: "OpenCHAMI Tutorial"
linktitle: "Tutorial"
description: "Learn about OpenCHAMI by setting it up in a controlled environment."
slug: "tutorial"
summary: ""
date: 2025-10-06T15:34:25-06:00
lastmod: 2025-12-15T10:09:00-06:00
contributors: ["Devon Bautista", "David Allen"]
draft: false
weight: 100
toc: true
---
<!-- vi: set tw=80 sw=2 sts=2: -->

## Part 0. Prerequisites

### 0.1. Overview

This tutorial focuses on setting up OpenCHAMI in a virtual environment such that
the reader may become familiar with the basics of using OpenCHAMI and apply
learned concepts to real deployments.

### 0.2. Setup

Readers will set up OpenCHAMI services via containers (this tutorial uses
[Podman quadlets](https://www.redhat.com/en/blog/quadlet-podman) for container
deployment), either on their host itself or in a virtual machine (see next
subsection). These services will then be configured to boot Libvirt virtual
machines that have no disk and run their OS in RAM.

### 0.3. Deployment Options for Head Node

Two different deployment methods for the "head node" (where the OpenCHAMI
services will run) are supported in this tutorial: **Cloud Instance/Bare Metal**
and **Virtual Machine**.

- **Cloud Instance/Bare Metal:** OpenCHAMI service containers run on a cloud
  instance (e.g. EC2) or on a bare metal host.
  - In this case, the networking to be set up is between the host and the VMs to
    be booted with OpenCHAMI.
- **Virtual Machine:** OpenCHAMI service containers run in their own virtual
  machine.
  - In this case, the networking to be set up is between the head node VM and
    the VMs to be booted with OpenCHAMI.

Either of the above options for a head node will work, and the reader should
choose one, follow the steps in the relevant deployment section below, then
move to [**Part 1. Installation**](#part-1-installation).

### 0.3. Head Node: Using Cloud Instance

#### 0.3.1. Instance Type

As for the instance type:

- **AWS:** [c5.metal](https://aws.amazon.com/ec2/instance-types/c5/) on AWS, at
  the time of writing, seems to be optimized for RAM and cost.
- **JetStream2:**
  [m3.medium](https://docs.jetstream-cloud.org/general/vmsizes/) (8GB RAM), at
  the time of writing, seems optimal for RAM and cost.

**x86_64** has the most support and is recommended.

If using a different cloud service, ensure the following specifications.

#### 0.3.2. Memory

If using a cloud instance, ensure at least **4GB of RAM** is available.

#### 0.3.3. Operating System

This tutorial assumes **Rocky Linux 9** is running on the instance.

#### 0.3.4. Storage

The tutorial has been historically run with a **60GB root disk** and the launch
template expands the filesystem to use the entire disk.

#### 0.3.5. Launch Template

The following launch templates, in the form of a cloud-init config, are recommended.

##### 0.3.5.a. AWS

```yaml
#cloud-config

packages:
  - libvirt
  - qemu-kvm
  - virt-install
  - virt-manager
  - dnsmasq
  - podman
  - buildah
  - git
  - vim
  - ansible-core
  - openssl
  - nfs-utils

# Post-package installation commands
runcmd:
  - dnf install -y epel-release
  - dnf install -y s3cmd awscli
  - systemctl enable --now libvirtd
  - newgrp libvirt
  - usermod -aG libvirt rocky
  - sudo growpart /dev/xvda 4
  - sudo pvresize /dev/xvda4
  - sudo lvextend -l +100%FREE /dev/rocky/lvroot
  - sudo xfs_growfs /
```

##### 0.3.5.b. JetStream2

In the **Advanced Options** section of the template or instance definition,
there is a text box marked **Boot Script**. Underneath the following header:

```
--=================exosphere-user-data====
Content-Transfer-Encoding: 7bit
Content-Type: text/cloud-config
Content-Disposition: attachment; filename="exosphere.yml"
```

Use the following cloud-config:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
The Rocky 9 Jetstream2 image does not allow containers to accept TCP
connections, which prevents connections to Quadlet services. As a mitigation,
the below cloud-config adds/enables/starts a Systemd service that marks the
`container_t` type as permissive.
{{< /callout >}}

```yaml
#cloud-config

packages:
  - ansible-core
  - buildah
  - dnsmasq
  - git
  - libvirt
  - nfs-utils
  - openssl
  - podman
  - qemu-kvm
  - vim
  - virt-install
  - virt-manager

write_files:
  - path: /etc/systemd/system/selinux-container-permissive.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Make container_t domain permissive
      After=network.target

      [Service]
      Type=oneshot
      ExecStart=/usr/sbin/semanage permissive -a container_t
      Restart=on-failure
      RestartSec=5
      StartLimitBurst=5

      [Install]
      WantedBy=multi-user.target

# Post-package installation commands
runcmd:
  - dnf install -y epel-release
  - dnf install -y s3cmd awscli
  - systemctl enable --now libvirtd
  - newgrp libvirt
  - usermod -aG libvirt rocky
  - sudo growpart /dev/xvda 4
  - sudo pvresize /dev/xvda4
  - sudo lvextend -l +100%FREE /dev/rocky/lvroot
  - sudo xfs_growfs /
  - systemctl daemon-reload
  - systemctl enable selinux-container-permissive
  - systemctl start selinux-container-permissive
```

### 0.4. Head Node: Using Bare Metal

Setup is similar to the cloud instance setups above. Ensure the following
packages are installed (Red Hat package names used):

- ansible-core
- awscli
- buildah
- dnsmasq
- git
- libvirt
- nfs-utils
- openssl
- podman
- qemu-kvm
- s3cmd
- vim
- virt-install
- virt-manager

Make sure that the Libvirt daemon is running:

```bash
sudo systemctl start libvirtd
```

### 0.5. Head Node: Using Virtual Machine

If using a virtual machine as a head node, this tutorial assumes the following
network layout:

{{< inline-svg src="svgs/diagrams/openchami-vm-net.svg" class="svg-inline-custom" >}}

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
This tutorial assumes Libvirt + KVM, but the concepts should also be applicable
to other hypervisors.
{{< /callout >}}

#### 0.5.1. Prerequisites

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

#### 0.5.2. Preparing Head Node VM

The head node VM will run Rocky Linux 9. In order to set it up quickly and
automatically, a
[Kickstart](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/automatically_installing_rhel/index)
server will be set up to serve a [Kickstart
file](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/automatically_installing_rhel/creating-kickstart-files_rhel-installer)
temporarily for the installation.

The VM will have two virtual networks:

- an internal network for our virtual compute nodes and virtual head node to
  communicate on (**openchami-net-internal**)
- an external network that only our head node is on to allow SSH login to the
  head node and forwarded traffic from the compute nodes
  (**openchami-net-external**)

First, create a directory on your host to store artifacts created in this
guide:

```bash
mkdir openchami-vm-workdir
cd openchami-vm-workdir
```

Steps in this section occur **on the host running Libvirt**.

##### 0.5.2.a. Create Kickstart Server

Within the working directory created above, create a serve directory:

```bash
mkdir serve/
```

Then, create `kickstart.conf` within that directory:

```yaml {title="openchami-vm-workdir/serve/kickstart.conf",linenos=true,linenostart=1}
#version=RHEL9
# Use text install
text

url --url='https://download.rockylinux.org/stg/rocky/9/BaseOS/$basearch/os/'

%packages
@^minimal-environment
bash-completion
buildah
epel-release
kexec-tools
man-pages
podman
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
grubby --update-kernel=ALL --args='console=ttyS0,115200n8 systemd.unified_cgroup_hierarchy=1'
grub2-mkconfig -o /etc/grub2.cfg
# Enable mounting /tmp as tmpfs
systemctl enable tmp.mount
dnf install -y vim s3cmd awscli
%end

reboot
```

Run a temporary webserver to serve the kickstart file created above:

```bash
python3 -m http.server -d ./serve 8000 &
```

##### 0.5.2.b. Create External VM Network

Create and start the external VM network:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
The **192.168.200.0/24** network is assumed to be nonexistent on the system. If
this is not the case, choose a different network when creating the networks and
VMs throughout this tutorial.
{{< /callout >}}

```bash
cat <<EOF > openchami-net-external.xml
<network>
  <name>openchami-net-external</name>
  <bridge name="br-ochami-ext"/>
  <forward mode="nat"/>
  <ip address="192.168.200.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.200.2" end="192.168.200.2"/>
      <host mac="52:54:00:c0:fe:01" ip="192.168.200.2"/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-define openchami-net-external.xml
sudo virsh net-start openchami-net-external
```

This is the network that the user will SSH into the VM through.

##### 0.5.2.c. Create Internal VM Network

Create and start the internal VM network:

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

This is the network that access to the compute nodes from the head node will be
through. This network is **isolated from the host** such that SSH access to the
compute nodes must be done through the head node VM.

##### 0.5.2.d. Kickstart the Head Node VM

Ensure the **edk2-ovmf** package is installed on the host, which will provide
the VM firmware and EFI variable files for the VMs. Using the Open Virtual
Machine Firmware (OVMF) instead of the default will allow one to see the
console output for the PXE boot process so errors can more easily be
troubleshot.

On Red Hat systems:

```bash
sudo dnf install -y edk2-ovmf
```

Next, create a virtual disk for the head node VM:

```bash
qemu-img create -f qcow2 head.img 20G
```

Then, the head node VM can finally be created:

```bash {title="Creating Head Node VM"}
sudo virt-install \
  --name head \
  --memory 4096 \
  --vcpus 1 \
  --disk path="$PWD/head.img" \
  --os-variant rocky9 \
  --network network=openchami-net-external,model=virtio,mac=52:54:00:c0:fe:01 \
  --network network=openchami-net-internal,model=virtio,mac=52:54:00:be:ef:ff \
  --graphics none \
  --location 'https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/kickstart' \
  --console pty,target_type=serial \
  --boot hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm \
  --extra-args 'inst.ks=http://192.168.200.1:8000/kickstart.conf ip=dhcp ip=dhcp console=ttyS0,115200n8'
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the following error occurs:

```
ERROR    Failed to open file '/usr/share/OVMF/OVMF_VARS.fd': No such file or directory
```

Check the path under **/usr/share/OVMF**. Some distros store the files under a
variant name under a variant directory (e.g. on Arch Linux, this file is at
**/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd** for x86\_64 hosts).
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
If the VM installation fails for any reason, it can be destroyed and undefined
so that the install command can be run again.

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

The following should be seen during the Kickstart process:

1. The kernel/initramfs for Rocky Linux download
2. The kernel boot and image download
3. The kickstart process (a tmux session) perform the installation
4. The node reboot into the installation that is now on `head.img`

After the steps above complete, a login prompt should appear:

```
head login:
```

Exit the console with `Ctrl`+`]`. If the console ever needs to be accessed
again (e.g. to troubleshoot by logging in), use:

```bash
sudo virsh console head
```

##### 0.5.2.e. Cleanup

The Kickstart server can now be torn down. Run:

```bash
jobs
```
The Python webserver should be seen:

```bash
[1]  + running    python3 -m http.server -d ./serve 8000
```

Stop it with:

```bash
kill %1
```

the output should be:

```bash
[1]  + terminated  python3 -m http.server -d ./serve 8000
```

##### 0.5.2.f. Accessing the Head Node VM

Login to the head node via SSH:

```bash
ssh rocky@192.168.200.2
```

## Part 1. Installation

In this part, the head node will be prepared to run OpenCHAMI and OpenCHAMI
will be installed to the head node.

**This part should be done on the head node**, whether that is on the host (for
cloud or bare-metal head node deployments) or in the VM (for VM head node
deployments).

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
**Try to avoid running everything in a root shell.** It's tempting to avoid
having to run `sudo` each time, but being root for every command invocation
will have some unintended side effects.
{{< /callout >}}

### 1.1 Set Up Storage Directories

Our tutorial uses a container registry to store system images (in OCI format)
for reuse in other image layers (we'll go over this later).

Create a local directory for storing the container images:

```bash
sudo mkdir -p /data/oci
sudo chown -R rocky: /data/oci
```

SELinux treats home directories specially. To avoid cgroups conflicting with SELinux enforcement, we set up a working directory outside our home directory:

```bash
sudo mkdir -p /opt/workdir
sudo chown -R rocky: /opt/workdir
cd /opt/workdir
```

### 1.2 Set Up Network and Hostnames

#### 1.2.1 Network Forwarding

For the purposes of the tutorial, the head node will need to be able to forward
network traffic. Configure this persistently:

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-forward.conf
sudo sysctl --system
```

#### 1.2.2 Update Hosts File

Add the cluster's service domain to `/etc/hosts` so that the certificates will work:

```bash
echo "172.16.0.254 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
```


#### 1.2.3 Create and Start Internal Network

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
**This step is only necessary if not using [a
VM](#05-head-node-using-virtual-machine) as the head node.** Only perform this
step if using a [bare metal](#04-head-node-using-bare-metal) or [cloud
instance](#03-head-node-using-cloud-instance) deployment for the head node.
{{< /callout >}}

Now, an internal Libvirt network needs to be created that will be used as the
network interface on the head node that the virtual compute nodes will be
attached to:

```bash
cat <<EOF > openchami-net.xml
<network>
  <name>openchami-net</name>
  <bridge name="virbr-openchami" />
  <forward mode='route'/>
  <dns enable='no'/>
  <ip address="172.16.0.254" netmask="255.255.255.0">
  </ip>
</network>
EOF

sudo virsh net-define openchami-net.xml
sudo virsh net-start openchami-net
sudo virsh net-autostart openchami-net
```

Check that the network got created:

```bash
sudo virsh net-list
```

The output should be:

```
 Name            State    Autostart   Persistent
--------------------------------------------------
 default         active   yes         yes
 openchami-net   active   yes         yes
```

### 1.3 Enable Non-OpenCHAMI Services

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Files in this section need to be edited as root!

If you accidentally edit a file as your normal user and need to save it as root
and you're using Vim, invoke (in Normal mode): `:w !sudo tee %`.
{{< /callout >}}

#### 1.3.1 S3

For the S3 gateway, this tutorial uses a pre-built RPM to install and configure
[versitygw](https://github.com/versity/versitygw) (Versity S3 Gateway) for
deployment as a quadlet.

```bash
# Download the latest release RPM
curl -LO $(curl -s https://api.github.com/repos/openchami/versitygw-quadlet/releases/latest | grep "browser_download_url.*\.rpm" | grep -v "\.src\.rpm" | cut -d '"' -f 4)

# Install the RPM
sudo dnf install ./versitygw-quadlet-*.noarch.rpm
```

#### 1.3.2 Container Registry

For the OCI container registry, the standard docker registry is used. Once
again, this is deployed as a quadlet.

**Edit as root: `/etc/containers/systemd/registry.container`**

```ini {title="/etc/containers/systemd/registry.container"}
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

#### 1.3.3 Reload Systemd

Reload Systemd to update it with the new changes and then start the services:

```bash
sudo systemctl daemon-reload
sudo systemctl start registry.service

# Enable and start secret generation for authentication with versity gateway(one-time)
sudo systemctl enable --now versitygw-gensecrets.service

# Start the versity gateway (generated from Quadlet - cannot be enabled directly)
sudo systemctl start versitygw.service

# Bootstrap users and buckets
sudo systemctl enable --now versitygw-bootstrap.service
```

#### 1.3.4 Checkpoint

Make sure the S3 (`versitygw`) and OCI (`registry`) services are up and running.

**Quickly:**

```bash
for s in versitygw registry; do echo -n "$s: "; systemctl is-failed $s; done
```

The output should be:

```
versitygw: active
registry: active
```

**More detail:**

```bash
systemctl status versitygw
systemctl status registry
```

### 1.4 Install OpenCHAMI

Now, the OpenCHAMI services need to be installed. Luckily, there is [a release
RPM](https://github.com/openchami/release) for this that provides signed RPMs.
The latest version ca be used.

**Run the commands below in the `/opt/workdir` directory!**

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

#### 1.4.1 Update CoreDHCP Configuration

The release RPM unpacks config files for many of the services including
`coredhcp`. The `/etc/openchami/configs/coredhcp.yaml` config file needs to be
edited for this setup:

{{< tabs "configure-coredhcp" >}}
{{< tab "Bare Metal Head" >}}
```bash
cat <<EOF | sudo tee /etc/openchami/configs/coredhcp.yaml
server4:
  # You can configure the specific interfaces that you want OpenCHAMI to listen on by
  # uncommenting the lines below and setting the interface
  listen:
    - "%virbr-openchami"
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
{{< /tab >}}
{{< tab "Cloud Instance Head" >}}
```bash
cat <<EOF | sudo tee /etc/openchami/configs/coredhcp.yaml
server4:
  # You can configure the specific interfaces that you want OpenCHAMI to listen on by
  # uncommenting the lines below and setting the interface
  listen:
    - "%virbr-openchami"
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
{{< /tab >}}
{{< tab "VM Head" >}}
```bash
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
{{< /tab >}}
{{< /tabs >}}

This will allow the compute node later in the tutorial to request its PXE script.

#### 1.4.2 Update CoreDNS Configuration

Update the CoreDNS config as well:

```bash
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

This will allow the resolution of node hostnames, e.g. `de01.openchami.cluster`.

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
Users should be aware of potential port conflicts if the installation target is
already running similar network services. Although, CoreDNS cannot bind to
in-use IP/port combinations, it may be configured to forward queries to the
existing DNS server instead. If you encounter a port conflict, CoreDNS is not a
required service dependency and can be safely disabled; however, doing so means
name resolution for nodes/BMCs will not function and you will need to manage
node hostnames manually. A lower-friction alternative that preserves DNS
functionality is to change the CoreDNS configuration to use an unused port like
`1053` and manually specify that port to any DNS dependent CLI tools.
{{< /callout >}}

### 1.5 Configure Cluster FQDN for Certificates

OpenCHAMI includes a minimal, open source certificate authority from
[Smallstep](https://smallstep.com/) that is run via the `step-ca` service. The
certificate generation and deployment happens as follows:

1. `step-ca.service` -- Generates the certificate authority certificate.
2. `openchami-cert-trust.service` -- Copies the generated CA certificate to the host system and adds it to the system trust bundle.
3. `acme-register.service` -- Issues a new certificate (derived from the CA certificate) for haproxy, the API gateway.
4. `acme-deploy.service` -- Deploys the issued certificate to haproxy. Restarting this service will restart 1-3 as well.

The `acme-*` services handle certificate rotation, and the
`openchami-cert-renewal` service and Systemd timer do exactly this.

When OpenCHAMI is installed, the FQDN used for the certificates and services is
set to the hostname of the system the package is installed on.  This needs to
be changed to `demo.openchami.cluster`, which is what the tutorial uses. The
OpenCHAMI package provides a script to do this:

```bash
sudo openchami-certificate-update update demo.openchami.cluster
```

The output should be:

```
Changed FQDN to demo.openchami.cluster
Either restart all of the OpenCHAMI services:

  sudo systemctl restart openchami.target

or run the following to just regenerate/redeploy the certificates:

  sudo systemctl restart acme-deploy

```

The script instructs to either restart all of the OpenCHAMI services
(`openchami.target`) or restart `acme-deploy` to regenerate the certificates.
Since OpenCHAMI is running for the first time, the former should be run, but
**not yet**.

To see what the script changed, run:

```bash
grep -RnE 'demo|openchami\.cluster' /etc/openchami/configs/openchami.env /etc/containers/systemd/
```

Whether this worked or not will be able to be verified shortly.

### 1.6 Start OpenCHAMI

OpenCHAMI runs as a collection of containers. Podman's integration with Systemd
allows the user to start, stop, and trace OpenCHAMI as a set of dependent
Systemd services through the `openchami.target` unit.

```bash
sudo systemctl start openchami.target
systemctl list-dependencies openchami.target
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
The `watch` command can be used to dynamically see the services starting:
```bash
watch systemctl list-dependencies openchami.target
```
{{< /callout >}}

If the services started correctly, the second command above should yield:

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

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the `haproxy` container fails with the following error, try restarting the
`opaal` and `haproxy` containers.
```bash
haproxy[363101]: [ALERT]    (3) : [/usr/local/etc/haproxy/haproxy.cfg:55] : 'server opaal/opaal' : could not resolve address 'opaal'.
haproxy[363101]: [ALERT]    (3) : [/usr/local/etc/haproxy/haproxy.cfg:58] : 'server opaal-idp/opaal-idp' : could not resolve address 'opaal-idp'.
```
{{< /callout >}}

Check the [**Troubleshooting**](#161-troubleshooting) subsection below if issues arise.

#### 1.6.1 Troubleshooting

If a service fails (if `×` appears next to a service in the `systemctl list-dependencies` command), try using `journalctl -eu <service_name>` to look at the logs

##### 1.6.1.a Dependency Issue

If a service fails because of another dependent service, use the following
dependency chart diagram to pinpoint the service causing the dependency
failure. Black arrows are hard dependencies (service will fail if dependent
service not started) and grey arrows are soft dependencies.

{{< inline-svg src="svgs/diagrams/openchami-svc-deps.svg" class="svg-inline-custom" width="100%" height="auto" >}}

##### 1.6.1.b Certificates

One common issue is with certificates. If TLS errors are occurring, **make sure
the domain in the `acme-register.container` and `acme-deploy.container` files
within `/etc/containers/systemd/` (argument to `-d` flag) match the cluster
domain set in `/etc/hosts`.**

Since the release RPM automatically sets the FQDN, it may be necessary to
update it to the correct value.

```bash
sudo openchami-certificate-update update demo.openchami.cluster
```

After ensuring the above or the error is of a different cause, regenerating the
OpenCHAMI certificates can usually solve such issues. This can be done with:

```bash
sudo systemctl restart acme-deploy
```

#### 1.6.1 Service Configuration

The OpenCHAMI release RPM is created with sensible default configurations for
this tutorial and all configuration files are included in the `/etc/openchami`
directory. To understand each one in detail, review the [**Service
Configuration**](service_configuration.md) instructions
<!-- TODO: Point link of above to Handbook -->

### 1.7 Install and Configure OpenCHAMI Client

The [`ochami` CLI](https://github.com/OpenCHAMI/ochami) provides an easy way to
interact with the OpenCHAMI services.

#### 1.7.1 Installation

The latest RPM can be installed with the following:

```bash
latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
curl -L "${latest_release_url}" -o ochami.rpm
sudo dnf install -y ./ochami.rpm
```

As a sanity check, check the version to make sure it is installed properly:

```bash
ochami version
```

The output should look something like:

```
Version:    0.6.0
Tag:        v0.6.0
Branch:     HEAD
Commit:     2243fa5a8b1b47667b0e2c662397fbc5c1761627
Git State:  clean
Date:       2025-11-25T16:13:22Z
Go:         go1.25.4
Compiler:   gc
Build Host: runnervmg1sw1
Build User: runner
```

#### 1.7.2 Configuration

To configure `ochami` to be able to communicate with our cluster, a config file
needs to be created. One can be created in one fell swoop with:

```bash
sudo ochami config cluster set --system --default demo cluster.uri https://demo.openchami.cluster:8443
```

This will create a system-wide config file at `/etc/ochami/config.yaml`. Check
that `ochami` is reading it properly with:

```bash
ochami config show
```

The output should be:

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

The cluster should now be able to be communicated with. Verify by checking the
status of one of the services:

```bash
ochami bss service status
```

The output should be:

```json
{"bss-status":"running"}
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If TLS errors occur, see the **Certificates** subsection within the
[**Troubleshooting**](#161-troubleshooting) section above.
{{< /callout >}}

Voilà!

#### 1.7.3 Documentation

`ochami` comes with several manual pages. Run:

```bash
apropos ochami
```

the output should be:

```
ochami (1)           - OpenCHAMI command line interface
ochami-bss (1)       - Communicate with the Boot Script Service (BSS)
ochami-cloud-init (1) - Communicate with the cloud-init server
ochami-config (1)    - Manage configuration for ochami CLI
ochami-config (5)    - ochami CLI configuration file
ochami-discover (1)  - Populate SMD using a file
ochami-pcs (1)       - Communicate with the Power Control Service (PCS)
ochami-smd (1)       - Communicate with the State Management Database (SMD)
```

### 1.8 Generating Authentication Token

In order to interact with protected endpoints, a JSON Web Token (JWT,
pronounced _jot_) needs to be generated. `ochami` reads an environment variable
named `<CLUSTER_NAME>_ACCESS_TOKEN` where `<CLUSTER_NAME>` is the configured
name of the cluster in all capitals, `DEMO` in our case.

Since the tutorial does not use an external identity provider, OpenCHAMI's
internal one will be used. The RPM that was installed comes with some shell
functions that allow one to do this.

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
**Keep this command handy! Tokens expire after an hour.**

If the following output is observed:
```
Environment variable DEMO_ACCESS_TOKEN unset for reading token for cluster "demo"
```
when running the `ochami` command later, it is time to rerun this command.
{{< /callout >}}

Note that `sudo` is needed because the containers are running as root and so if
`sudo` is omitted, the containers will not be found.

OpenCHAMI tokens last for an hour by default. Whenever one needs to be
regenerated, run the above command.


### 1.9 Checkpoint

1. ```bash
   systemctl list-dependencies openchami.target
   ```
   should yield:
   ```bash
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
1. ```
   ochami bss service status
   ```
   should yield:
   ```
   {"bss-status":"running"}
   ```
1. ```
   ochami smd service status
   ```
   should yield:
   ```
   {"code":0,"message":"HSM is healthy"}
   ```

## Part 2. Configuration

In this part, OpenCHAMI will be populated with node and boot information,
images will be built, and the virtual compute nodes will be booted.

### 2.1 Libvirt introduction

Libvirt is an open-source virtualization management toolkit that provides a
unified interface for managing various virtualization technologies, including
KVM/QEMU, Xen, VMware, LXC containers, and others. Through its standardized API
and set of management tools, libvirt simplifies the tasks of defining,
managing, and monitoring virtual machines and networks, regardless of the
underlying hypervisor or virtualization platform.

For this tutorial, we leverage a hypervisor which is built-in to the Linux
Kernel. The kernel portion is called Kernel-based Virtual Machine (KVM) and the
userspace component is included in QEMU.

### 2.2 Node Discovery for Inventory

In order for OpenCHAMI to be useful, the State Management Database (SMD) needs
to be populated with system information. This can be done one of two ways:
_static_ discovery via [the `ochami` CLI](https://github.com/OpenCHAMI/ochami)
or _dynamic_ discovery via [the `magellan`
CLI](https://github.com/OpenCHAMI/magellan).

Static discovery is predictable and easily reproduceable, so we will use it in
this tutorial.

#### 2.2.1 Dynamic Discovery Overview

Dynamic discovery happens via Redfish using `magellan`.

At a high level, `magellan` `scan`s a specified network for hosts running a
Redfish server (e.g. BMCs). Once it knows which IPs are using Redfish, the tool
can `crawl` each BMC's Redfish structure to get more detailed information about
it and `collect` it, then `send` this information to SMD.

When combined with DHCP dynamically handing out IPs, this process can be
non-deterministic.

#### 2.2.2 Static Discovery Overview

Static discovery happens via `ochami` by giving it a static discovery file.
"Discovery" is a bit of a misnomer as nothing is actually discovered. Instead,
predefined node data is given to SMD which creates the necessary internal
structures to boot nodes.

##### 2.2.2.a Anatomy of a Static Discovery File

`ochami` adds nodes to SMD through data or a file in YAML syntax (or JSON) that
lists node descriptions through a minimal set of node characteristics and a set
of interface definitions.

As of `ochami` v0.6.0, characteristics are split out into two arrays, `bmcs`
and `nodes`, which allows more flexibility in certain cases, such as when there
are multiple nodes per-BMC as is apparent in some HPE hardware.

- **nodes:** An array of node definitions, each of which describe a node's
  identification, group membership, network interfaces, and BMC device it is
  attached to.
- **bmcs:** An array of BMC definitions, each of which describe a management
  controller's identification and networking information.

For **bmcs:**

- **name:** An optional human-readable name to assign the BMC that can be used
  when mapping one or more nodes to it.
- **xname:** The unique BMC identifier which follows HPE's [xname
  format](https://cray-hpe.github.io/docs-csm/en-10/operations/component_names_xnames/)
  (see the "Node Controller or BMC" entry in the table) and is supposed to encode
  location data. The format is `x<cabinet>c<chassis>s<slot>b<bmc>` and must be
  unique per-BMC.
- **mac:** The BMC's MAC address.
- **ip:** The IP address to be assigned to the BMC.

For **nodes:**

- **name:** User-friendly name of the node stored in SMD.
- **nid:** *Node Identifier*. Unique number identifying node, used in the
  DHCP-given hostname. Mainly used as a default hostname that can be easily
  ranged over (e.g. `nid[001-004,006]`).
- **xname:** The unique node identifier which follows HPE's [xname
  format](https://cray-hpe.github.io/docs-csm/en-10/operations/component_names_xnames/)
  (see the "Node" entry in the table) and is supposed to encode location data.
  The format is `x<cabinet>c<chassis>s<slot>b<bmc>n<node>` and must be unique
  per-node.
- **bmc:** The BMC to assign this node to. It can either be the value of a
  BMC's **xname** field or its **name** field. If omitted, the BMC's xname is
  inferred from the value of the node's **xname** field.
- **groups:** An optional list of SMD groups to add this node to. cloud-init
  reads SMD groups when determining which meta-data and cloud-init config to
  give a node.
- **interfaces** is a list of network interfaces attached to the node. Each of
  these interfaces has the following keys:
  - **mac_addr:** Network interface's MAC address. Used by CoreDHCP/CoreSMD to
    give the proper IP address for interface listed in SMD.
  - **ip_addrs:** The list of IP addresses for the node.
    - **name:** A human-readable name for this IP address for this interface.
    - **ip_addr:** An IP address for this interface.

```yaml {title="Example static discovery file containing one node and BMC (DO NOT USE)"}
bmcs:
- xname: x1000c1s7b0
  mac: de:ca:fc:0f:ee:ee
  ip: 172.16.0.101

nodes:
- name: node01
  nid: 1
  xname: x1000c1s7b0n0
  bmc: x1000c1s7b0
  groups:
  - compute
  interfaces:
  - mac_addr: de:ad:be:ee:ee:f1
    ip_addrs:
    - name: internal
      ip_addr: 172.16.0.1
  - mac_addr: de:ad:be:ee:ee:f2
    ip_addrs:
    - name: external
      ip_addr: 10.15.3.100
  - mac_addr: 02:00:00:91:31:b3
    ip_addrs:
    - name: HSN
      ip_addr: 192.168.0.1
```

#### 2.2.3 "Discover" Nodes

We can make a directory at **/etc/openchami/data** to store the cluster configuration data:

```bash
sudo mkdir -p /etc/openchami/data
```

Then, create a static discovery file there.

**Edit as root: `/etc/openchami/data/nodes.yaml`**

```yaml {title="/etc/openchami/data/nodes.yaml"}
bmcs:
- xname: x1000c0s0b0
  mac: de:ca:fc:0f:fe:e1
  ip: 172.16.0.101
- xname: x1000c0s0b1
  mac: de:ca:fc:0f:fe:e2
  ip: 172.16.0.102
- xname: x1000c0s0b2
  mac: de:ca:fc:0f:fe:e3
  ip: 172.16.0.103
- xname: x1000c0s0b3
  mac: de:ca:fc:0f:fe:e4
  ip: 172.16.0.104
- xname: x1000c0s0b4
  mac: de:ca:fc:0f:fe:e5
  ip: 172.16.0.105

nodes:
- name: compute1
  nid: 1
  xname: x1000c0s0b0n0
  bmc: x1000c0s0b0
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
  bmc: x1000c0s0b1
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
  bmc: x1000c0s0b2
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
  bmc: x1000c0s0b3
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
  bmc: x1000c0s0b4
  groups:
  - compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:05
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.5
```

Now, run the following to populate SMD with the node information:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Make sure `DEMO_ACCESS_TOKEN` is set! Refer to [**Generating Authentication
Token**](#18-generating-authentication-token).
{{< /callout >}}

```bash
ochami discover static -f yaml -d @/etc/openchami/data/nodes.yaml
```

There should be no output for the above command.

#### 2.2.4 Checkpoint

Run the following to view the components tracked by SMD:

```bash
ochami smd component get | jq '.Components[] | select(.Type == "Node")'
```

The output should be:

```json
{
  "Enabled": true,
  "ID": "x1000c0s0b0n0",
  "NID": 1,
  "Role": "Compute",
  "State": "On",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b1n0",
  "NID": 2,
  "Role": "Compute",
  "State": "On",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b2n0",
  "NID": 3,
  "Role": "Compute",
  "State": "On",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b3n0",
  "NID": 4,
  "Role": "Compute",
  "State": "On",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b4n0",
  "NID": 5,
  "Role": "Compute",
  "State": "On",
  "Type": "Node"
}
```

### 2.3 Building and Organizing System Images

The virtual nodes in this tutorial operate the same way many HPC centers run
their physical nodes. Rather than managing installations on physical disks,
they boot directly from the network and run entirely in memory. And, through
clever use of overlays and kernel parameters, all nodes reference the same
remote system image (SquashFS), dramatically reducing the chances of
differences in the way they operate.

OpenCHAMI isn't opinionated about how these system images are created, managed,
or served. Sites can even run totally from disk if they choose.

For this tutorial, building boot images is done using a project from the
OpenCHAMI consortium that creates and manages system images called
[image-builder](https://github.com/OpenCHAMI/image-builder). It is an
Infrastructure-as-Code (IaC) tool that translates YAML configuration files
into:

- SquashFS images served through S3 (served to nodes)
- Container images served through OCI registries (used as parent layers for child image layers)

Create a directory for the cluster's image configs.

```bash
sudo mkdir -p /etc/openchami/data/images
cd /etc/openchami/data/images
```

#### 2.3.1 Preparing Tools

* [**image-builder**](https://github.com/OpenCHAMI/image-builder) -- a
  containerized version will be used to build images.
* [**regclient**](https://github.com/regclient/regclient/) -- will be used to
  interact with images organized in the OCI registry.
* [**s3cmd**](https://s3tools.org/s3cmd) -- will be used for general
  interactions with the Versity S3 Gateway for S3-compatible object storage.
* [**aws**](https://github.com/aws/aws-cli) -- will be used to configure S3
  bucket level ACLs within the Versity S3 Gateway instance.

#### 2.3.2 Install and Configure `regctl`

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
Make sure that the below commands are run as the `rocky` user and not using
`sudo` or a root shell. `regctl` configs are user-level _only_, meaning that
they live in the running user's home directory and are read _per-user_.
{{< /callout >}}

```bash
curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 | sudo tee /usr/local/bin/regctl >/dev/null && sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled demo.openchami.cluster:5000
```

Make sure the config got set:

```bash
cat ~/.regctl/config.json
```

The output should be:

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

#### 2.3.3 Install and Configure S3 Clients

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
Make sure that the below commands are run as the `rocky` user and not using
`sudo` or a root shell. `s3cmd` configs are user-level _only_, meaning that
they live in the running user's home directory and are read _per-user_.
{{< /callout >}}

`s3cmd` was installed during the AWS setup, but we need to create a user-level
config file to use it with our local S3 server. Since we'll need to specify
access credentials, let's pull in the server environment file and generate
`${HOME}/.s3cfg` with a heredoc:

```bash
# Add ROOT_ACCESS_KEY and ROOT_SECRET_KEY to the shell environment
# for later use
source <(sudo cat /etc/versitygw/secrets.env)

# Create the s3cmd config file
cat <<EOF | tee "${HOME}/.s3cfg"
# Setup endpoint
host_base = demo.openchami.cluster:7070
host_bucket = demo.openchami.cluster:7070
bucket_location = us-east-1
use_https = False

# Setup access keys
access_key = ${ROOT_ACCESS_KEY}
secret_key = ${ROOT_SECRET_KEY}

# Enable S3 v4 signature APIs
signature_v2 = False
EOF
```

We also will briefly need to use the `aws` CLI to ensure proper configuration
of ACLs for `versitygw` buckets as the XML schema used by `s3cmd` for this
operation is not compatible.

```bash
aws configure set aws_access_key_id "${ROOT_ACCESS_KEY}"
aws configure set aws_secret_access_key "${ROOT_SECRET_KEY}"
aws configure set region us-east-1
```

#### 2.3.4 Create and Configure S3 Buckets

Create a `boot-images` bucket to store the images that are built:

```bash
s3cmd mb s3://boot-images
s3cmd setownership s3://boot-images BucketOwnerPreferred
aws s3api put-bucket-acl --bucket boot-images --acl public-read --endpoint-url http://localhost:7070
```

The output should be:

```
Bucket 's3://boot-images/' created
s3://boot-images/: Bucket Object Ownership updated
```

Set the policy to allow public downloads from the `boot-images` bucket:

**Edit as normal user: `/opt/workdir/s3-public-read-boot.json`**

```json {title="/opt/workdir/s3-public-read-boot.json"}
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

Apply the policy in S3:

```bash
s3cmd setpolicy /opt/workdir/s3-public-read-boot.json s3://boot-images \
    --host=demo.openchami.cluster:7070 \
    --host-bucket=demo.openchami.cluster:7070
```

The output should be:

```
s3://boot-images/: Policy updated
```

List the S3 buckets (removing the timestamps):

```bash
s3cmd ls | cut -d' ' -f 4-
```

In addition to the default buckets created when we installed the RPM for
`versitygw`, the output should include:

```
s3://boot-images
```

You can obtain more information using `s3cmd info <bucket-name>`. For example,
with `s3cmd info s3://boot-images`:

```
s3://boot-images/ (bucket):
   Location:  us-east-1
   Payer:     none
   Ownership: BucketOwnerPreferred
   Versioning:none
   Expiration rule: none
   Block Public Access: none
   Policy:    {
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

   CORS:      none
   ACL:       1b835f0cce711c0ab5668c05afaff93d: FULL_CONTROL
   ACL:       all-users: READ
```

### 2.4 Building System Images

The image builder speeds iteration by encouraging the admin to compose bootable
images by layering one image on top of another. Below are three definitions for
images.

- `rocky-base-9.yaml` starts from an empty container and adds a minmal set of
  common packages including the kernel.

  This image is a stock Rocky Linux 9 filesystem. It is meant to be built on
  top of and not to boot, so it is only stored in the OCI registry.

- `compute-base-rocky9.yaml` re-uses the image built by `rocky-base-9.yaml` and
  adds on top of it.

  This means that it doesn't have to rebuild everything in the base container.
  Instead, it just references it and overlays it's own files on top to add more
  creature comforts necessary for HPC nodes.

  This image is meant to be the most basic image that is bootable, so it is
  stored both in the OCI registry (so it can be reused by other images) and in
  S3 (to be booted).

- `compute-debug-rocky9.yaml` re-uses the image built by
  `compute-base-rocky9.yaml` (and therefore also by `rocky-base-9.yaml`) and
  adds on top of it.

  This image adds a test user for debugging, which likely isn't desired in the
  base compute image, so it gets a separate layer. This image doesn't get used
  in additional layers but is bootable, so it only gets stored in S3.

Create a working directory for the image configs:

```bash
sudo mkdir -p /etc/openchami/data/images
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
The naming convention used in this tutorial for image config files is:

```
<name>-<tag>.yaml
```

Where `<name>` is the name of the image (which can include type information)
and `<tag>` is the container tag (or S3 suffix if only pushing there).

For example:

- `rocky-base-9.yaml`:
  - `rocky-base` is the name (`base` can be a "type", i.e. it's stock, as
    opposed to `rocky-test` for a testing image).
  - `9` is the tag (the version of Rocky).
- `compute-base-rocky9.yaml`:
  - `compute-base` is the name ("compute" can be the category and "base" the
    type).
  - `rocky9` is the tag, since it was built on top of a Rocky 9 base image.
- `compute-debug-rocky9.yaml`:
  - `compute-debug` is the name ("compute" the category and "debug" the type).
  - `rocky9` is the tag, since this is in the line of Rocky 9 images.

This is just a guide  to match the image metadata specified inside each file
(for easy identification) but is not meant to be a governing standard.
{{< /callout >}}

#### 2.4.1 Configure The Base Image

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
When writing YAML, it's important to be consistent with spacing. **It is
recommended to use spaces for all indentation instead of tabs.**

When pasting, you may have to configure your editor to not apply indentation
rules (`:set paste` in Vim, `:set nopaste` to switch back).
{{< /callout >}}

**Edit as root: `/etc/openchami/data/images/rocky-base-9.yaml`**

```yaml {{title="/etc/openchami/data/images/rocky-base-9.yaml"}
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

Notice that this image is pushed to the OCI registry, but not S3. This is
because this image will not be booted directly but will rather be used as a
parent layer for the base compute image, which will be built in the next
section.

#### 2.4.2 Build the Base Image

After creating the base image config above, build it:

```bash
podman run \
  --rm \
  --device /dev/fuse \
  --network host \
  -v /etc/openchami/data/images/rocky-base-9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build \
    --config config.yaml \
    --log-level DEBUG
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Messages prefixed with `ERROR` mean that these messages are being emitted at
the "error" log level and aren't _necessarily_ errors.
{{< /callout >}}

This will take a good chunk of time (~10 minutes or so) since an entire Linux
filesystem is being built from scratch. At the end, the following should
appear:

```
-------------------BUILD LAYER--------------------
pushing layer rocky-base to demo.openchami.cluster:5000/demo/rocky-base:9
```

After the build completes, verify that the image has been created and stored in
the registry:

```bash
regctl repo ls demo.openchami.cluster:5000
```

The output should be:

```
demo/rocky-base
```

The tags of this container can be queried to verify that the "9" tag got pushed:

```bash
regctl tag ls demo.openchami.cluster:5000/demo/rocky-base
```

The output should be:

```
9
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
Since this is an OCI image, it can be inspected like one. Try it out:

```bash
podman run --tls-verify=false --rm -it demo.openchami.cluster:5000/demo/rocky-base:9 bash
```

**NOTE:** Make sure to exit out of this shell before continuing.
{{< /callout >}}

#### 2.4.3 Configure the Base Compute Image

Now, create the base compute image that will use the base image that was just
built before as the parent layer. In this compute image layer, the stock Rocky
9 image is being pulled and packages are added on top of it that will be common
for all compute nodes.

**Edit as root: `/etc/openchami/data/images/compute-base-rocky9.yaml`**

```yaml {title="/etc/openchami/data/images/compute-base-rocky9.yaml"}
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
  publish_s3: 'http://demo.openchami.cluster:7070'
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

Notice that this time, the image is pushed both to the OCI registry _and_ S3.
This image will be used _both_ as a parent layer to subsequent images _and_ to
boot nodes directly.

#### 2.4.4 Build the Compute Image

Build the base compute image:

```bash
podman run \
  --rm \
  --device /dev/fuse \
  --network host \
  -e S3_ACCESS="${ROOT_ACCESS_KEY}" \
  -e S3_SECRET="${ROOT_SECRET_KEY}" \
  -v /etc/openchami/data/images/compute-base-rocky9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build \
    --config config.yaml \
    --log-level DEBUG
```

Note that this time, `S3_ACCESS` and `S3_SECRET` are set to authenticate to
Versity S3 Gateway. These are needed whenever pushing an image to S3.

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If you find yourself with the error "The AWS Access Key Id you provided does
not exist in our records.", determine whether values have been set for
environment variables `ROOT_ACCESS_KEY` and `ROOT_SECRET_KEY` by observing the
output of `env | grep KEY`. If no definitions exist for these variables, re-run
the following command to pull them back in:
```bash
source <(sudo cat /etc/versitygw/secrets.env)
```
{{< /callout >}}

This won't take as long as the base image since the only thing being done is
installing packages on top of the already-built filesystem. This time, since
the image is being pushed to S3 (and `--log-level DEBUG` was passed) _a lot_ of
S3 output will be seen. The following should appear:

```
Pushing /var/tmp/tmpda2ddyh0/rootfs as compute/base/rocky9.6-compute-base-rocky9 to boot-images
pushing layer compute-base to demo.openchami.cluster:5000/demo/compute-base:rocky9
```

Note that the format of the image name being pushed to S3 is:

```
<distro><version>-<name>-<tag>
```

In this case:

- `<distro>` is `rocky`
- `<version>` is `9.6`
- `<name>` is `compute-base` (from `name` field in image config file)
- `<tag>` is `rocky9.6` (from `publish_tags` in image config file, there can be multiple)

Verify that the image has been created and stored in the registry:

```bash
regctl repo ls demo.openchami.cluster:5000
```

Both of the images built so far should be seen:

```
demo/compute-base
demo/rocky-base
```

The tag of the new `demo/compute-base` image should now be seen:

```bash
regctl tag ls demo.openchami.cluster:5000/demo/compute-base
```

The output should be:

```
rocky9
```

The new image, kernel, and initramfs should all be now seen in S3:

```bash
s3cmd ls -Hr s3://boot-images | cut -d' ' -f 4- | grep compute/base
```

The output should be akin to:

```
1436M  s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
  82M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.26.1.el9_6.x86_64.img
  14M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.26.1.el9_6.x86_64
```

Note the following:

- SquashFS image: `s3://boot-images/compute/base/rocky9.6-compute-base-rocky9`
- Initramfs: `s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.26.1.el9_6.x86_64.img`
- Kernel: `s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.26.1.el9_6.x86_64`

#### 2.4.5 Configure the Debug Image

Before booting an image, it is prudent to build a debug image that is based off
of the base compute image. The images built so far don't contain users (these
can be created using post-boot configuration via cloud-init). This image will
contain a user with a known password which can be logged into via the serial
console. This will be useful later on when debugging potential post-boot
configuration issues (e.g. SSH keys weren't provisioned and so login is
impossible).

**Edit as root: `/etc/openchami/data/images/compute-debug-rocky9.yaml`**

```yaml {title="/etc/openchami/data/images/compute-debug-rocky9.yaml"}
options:
  layer_type: base
  name: compute-debug
  publish_tags:
    - 'rocky9'
  pkg_manager: dnf
  parent: 'demo.openchami.cluster:5000/demo/compute-base:rocky9'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish to local S3
  publish_s3: 'http://demo.openchami.cluster:7070'
  s3_prefix: 'compute/debug/'
  s3_bucket: 'boot-images'

packages:
  - shadow-utils

cmds:
  - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
```

The debug image uses a few different directives that are worth drawing attention to:

- Use the base compute image as the parent, pull it from the registry without TLS, and call the new image "compute-debug":

  ```yaml
  name: 'compute-debug'
  parent: 'demo.openchami.cluster:5000/demo/compute-base:rocky9'
  registry_opts_pull:
    - '--tls-verify=false'
  ```

- Push the image to `http://demo.openchami.cluster:7070/boot-images/compute/debug/` in S3:

  ```yaml
  publish_s3: 'http://demo.openchami.cluster:7070'
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

  This will be the user that will be used to login to the console.

#### 2.4.6 Build the Debug Image

Build this image:

```bash
podman run \
  --rm \
  --device /dev/fuse \
  -e S3_ACCESS="${ROOT_ACCESS_KEY}" \
  -e S3_SECRET="${ROOT_SECRET_KEY}" \
  -v /etc/openchami/data/images/compute-debug-rocky9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build \
    --config config.yaml \
    --log-level DEBUG
```

#### 2.4.7 Verify Boot Artifact Creation

Once finished, the debug image artifacts should now show up in S3:

```bash
s3cmd ls -Hr s3://boot-images/ | cut -d' ' -f 4-
```

The output should be akin to (note that the base image is not here because it
wasn't pushed to S3, only the registry):

```
1436M  s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
1437M  s3://boot-images/compute/debug/rocky9.6-compute-debug-rocky9
  82M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.26.1.el9_6.x86_64.img
  14M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.26.1.el9_6.x86_64
  82M  s3://boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img
  14M  s3://boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64
```

A kernel, initramfs, and SquashFS should be visible for each image that was built.

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Each time an image pushed to S3, three items are pushed:

 - The SquashFS image
 - The kernel
 - The initramfs

It is important to select the right one when setting boot parameters!
{{< /callout >}}

For the debug boot artifacts, the URLs (everthing after `s3://`) for the
`compute/debug` items will be used. The following one-liner can be used to
print the actual URLs:

```bash
s3cmd ls -Hr s3://boot-images | grep compute/debug | awk '{print $4}' | sed 's-s3://-http://demo.openchami.cluster:7070/-'
```

In a following section, these will be programmatically used to set boot
parameters.

#### 2.4.8 Simplify Image Build Command

Instead of typing that long Podman command each time an image needs to be
built, a bash function can help shorten the process.

**Edit as root:** **`/etc/profile.d/build-image.sh`**

```bash {title="/etc/profile.d/build-image.sh"}
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
    if [ -z "${ROOT_ACCESS_KEY:-}" ]; then
      echo "ROOT_ACCESS_KEY is not set" 1>&2;
      echo "S3 credentials not loaded. Run: source <path-to-credentials>" 1>&2;
      return 1;
    fi
    if [ -z "${ROOT_SECRET_KEY:-}" ]; then
      echo "ROOT_SECRET_KEY is not set" 1>&2;
      echo "S3 credentials not loaded. Run: source <path-to-credentials>" 1>&2;
      return 1;
    fi
    podman run \
            --rm \
            --device /dev/fuse \
            -e S3_ACCESS="${ROOT_ACCESS_KEY}" \
            -e S3_SECRET="${ROOT_SECRET_KEY}" \
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
    if [ -z "${ROOT_ACCESS_KEY:-}" ]; then
      echo "ROOT_ACCESS_KEY is not set" 1>&2;
      echo "S3 credentials not loaded. Run: source <path-to-credentials>" 1>&2;
      return 1;
    fi
    if [ -z "${ROOT_SECRET_KEY:-}" ]; then
      echo "ROOT_SECRET_KEY is not set" 1>&2;
      echo "S3 credentials not loaded. Run: source <path-to-credentials>" 1>&2;
      return 1;
    fi
    podman run \
           --rm \
           --device /dev/fuse \
           -e S3_ACCESS="${ROOT_ACCESS_KEY}" \
           -e S3_SECRET="${ROOT_SECRET_KEY}" \
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

Now, images can be built with:

```bash
build-image /path/to/image/config.yaml
```

Ensure that the alias is getting used:

```bash
which build-image
```

The output should be:

```
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
            if [ -z "${ROOT_ACCESS_KEY:-}" ]; then
              echo "ROOT_ACCESS_KEY is not set" 1>&2;
              echo "S3 credentials not loaded. Run: source <path-to-credentials>" 1>&2;
              return 1;
            fi
            if [ -z "${ROOT_SECRET_KEY:-}" ]; then
              echo "ROOT_SECRET_KEY is not set" 1>&2;
              echo "S3 credentials not loaded. Run: source <path-to-credentials>" 1>&2;
              return 1;
            fi
            podman run --rm --device /dev/fuse -e S3_ACCESS="${ROOT_ACCESS_KEY}" -e S3_SECRET="${ROOT_SECRET_KEY}" -v "$(realpath $1)":/home/builder/config.yaml:Z ${EXTRA_PODMAN_ARGS} ghcr.io/openchami/image-build-el9:v0.1.2 image-build --config config.yaml --log-level DEBUG
        }
```

### 2.5 Managing Boot Parameters

With the introduction of the new `boot-service` into OpenCHAMI, we now have two
services that handle distributing PXE boot scripts. therefore, we are going to
cover how to work with managing boot parameters with both BSS and `boot-service`.
Managing boot parameters with BSS uses the `ochami` tool whereas `boot-service`
has a client generated by [`fabrica`](https://github.com/OpenCHAMI/fabrica).
The `boot-service` code generation by `fabrica` is outside of the scope of this
tutorial, but for more information about `fabrica`, refer to [this](https://openchami.org/blog/2025/11/using-fabrica-to-generate-a-hardware-inventory-api/) blog post.

The `ochami` tool provides a convenient interface for changing boot parameters
through IaC (Infrastructure as Code). The desired configuration can be stored
in a file and be applied with a command. We'll use the `ochami` tool only with
BSS for now.

To set boot parameters using the BSS backend, it's necessary to pass:

1. The identity of the node that the boot parameters will be applied for (MAC
   address, name, or node ID number)
2. At least one of:
   1. URI to kernel file
   2. URI to initrd file
   3. Kernel command line arguments

   ***OR:***

   4. A file containing the boot parameter data (this method will be used here)

#### 2.5.1 Create the Boot Configuration

Create a directory for the boot configs:

```bash
sudo mkdir -p /etc/openchami/data/boot/bss
```

Then, create the payload for BSS,
**/etc/openchami/data/boot/bss/compute-debug-rocky9.yaml**, that contains the
URIs for the boot artifacts:

```bash
URIS=$(s3cmd ls -Hr s3://boot-images | grep compute/debug | awk '{print $4}' | sed 's-s3://-http://172.16.0.254:7070/-' | xargs)
URI_IMG=$(echo "$URIS" | cut -d' ' -f1)
URI_INITRAMFS=$(echo "$URIS" | cut -d' ' -f2)
URI_KERNEL=$(echo "$URIS" | cut -d' ' -f3)
cat <<EOF | sudo tee /etc/openchami/data/boot/bss/compute-debug-rocky9.yaml
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

Examine the `tee` output to make sure that the URIs got populated properly. For example:

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
The file will not look like the one below due to differences in kernel versions
over time. Be sure to update with the output of `s3cmd ls` as stated above!
{{< /callout >}}

```yaml
kernel: 'http://172.16.0.254:7070/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64'
initrd: 'http://172.16.0.254:7070/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:7070/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```

##### 2.5.2.a Set the Boot Configuration with BSS Backend

Apply the boot parameters created above with:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
`ochami` supports both `add` and `set`.  The difference is idempotency.  If
using the `add` command, `bss` will reject replacing an existing boot
configuration.
{{< /callout >}}

```bash
ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/bss/compute-debug-rocky9.yaml
```

Verify that the parameters were set correctly with:

```bash
ochami bss boot params get -F yaml
```

The output should be akin to:

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
  initrd: http://172.16.0.254:7070/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img
  kernel: http://172.16.0.254:7070/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64
  macs:
    - 52:54:00:be:ef:01
    - 52:54:00:be:ef:02
    - 52:54:00:be:ef:03
    - 52:54:00:be:ef:04
    - 52:54:00:be:ef:05
  params: nomodeset ro root=live:http://172.16.0.254:7070/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
```

The things to check are:

- `initrd` URL points to debug initrd (try `curl`ing it to make sure it works)
- `kernel` URL points to debug kernel (try `curl`ing it to make sure it works)
- `root=live:` URL points to debug image (try `curl`ing it to make sure it works)

##### 2.5.2.b Set the Boot Configuration with the `boot-service` Backend

Setting the boot configuration with the `boot-service` backend is a little
different than with the BSS backend. Instead of using the `ochami` client, we
will be using the client generated for `boot-service` with `fabrica`.
Unfortunately, the client command can only take a JSON value with the `--spec`
flag and cannot be set using a file. However, for the purpose of this tutorial,
we will create a file to make comparing this method to the `ochami` easier.

Edit the **/etc/openchami/data/boot/boot-service/compute-debug-rocky9.yaml** file.
Copy the contents below into the file. Notice that the values in this file should
be the same values from section 2.5.2.a but in JSON.

```json
{
  "macs": [
    "52:54:00:be:ef:01",
    "52:54:00:be:ef:02",
    "52:54:00:be:ef:03",
    "52:54:00:be:ef:04",
    "52:54:00:be:ef:05"
  ],
  "params": "nomodeset ro root=live:http://172.16.0.254:7070/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init",
  "kernel": "http://172.16.0.254:7070/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64",
  "initrd": "http://172.16.0.254:7070/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img",

}
```

Set the boot configuration with the client.

```bash
boot-service-client bootconfiguration create --spec $(cat /etc/openchami/data/boot/boot-service/compute-debug-rocky9.yaml) --server https://demo.openchami.cluster:8443
```

Verify that the boot configuration was set.

```bash
boot-service-client bootconfiguration list --server https://demo.openchami.cluster:8443
```

You should see output that is similar to the input JSON. At this point, you should
be ready to boot the compute node.

### 2.6 Boot the Compute Node with the Debug Image

Boot the first compute node into the debug image, following the console:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If the head node is in a VM (see [**Head Node: Using Virtual
Machine**](#05-head-node-using-virtual-machine)), make sure to run the
`virt-install` command on the host!
{{< /callout >}}

{{< tabs "install-compute-vm" >}}
{{< tab "Bare Metal Head" >}}

```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant rocky9 \
  --network network=openchami-net,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```
{{< /tab >}}
{{< tab "Cloud Instance Head" >}}
```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant rocky9 \
  --network network=openchami-net,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```
{{< /tab >}}
{{< tab "VM Head" >}}
```bash
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
{{< /tab >}}
{{< /tabs >}}

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the VM needs to be destroyed and restarted, first exit the console with
`Ctrl`+`]`. Then:

1. Shut down ("destroy") the VM:
   ```
   sudo virsh destroy compute1
   ```
1. Undefine the VM:
   ```
   sudo virsh undefine --nvram compute1
   ```
1. Rerun the `virt-install` command above.
{{< /callout >}}

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
http://172.16.0.254:7070/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.26.1.el9_6.x86_64... ok
http://172.16.0.254:7070/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.26.1.el9_6.x86_64.img... ok
```

During Linux boot, output should indicate that the SquashFS image gets downloaded and loaded.

```
[    2.169210] dracut-initqueue[545]:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
[    2.170532] dracut-initqueue[545]:                                  Dload  Upload   Total   Spent    Left  Speed
100 1356M  100 1356M    0     0  1037M      0  0:00:01  0:00:01 --:--:-- 1038M
[    3.627908] squashfs: version 4.0 (2009/01/31) Phillip Lougher
```

Cloud-Init (and maybe SSH) will fail (since we haven't set it up yet), but that's okay for now.

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the error below is seen when trying to boot the compute node, make sure that
the `/etc/openchami/configs/coredhcp.yaml` config file was edited in [**Update
CoreDHCP Configuration**](#141-update-coredhcp-configuration) and restart
CoreDHCP with `systemctl restart coresmd-coredhcp`.

```bash
>>Start PXE over IPv4.
 PXE-E18: Server response timeout.
BdsDxe: failed to load Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0): Not Found
```
{{< /callout >}}

#### 2.6.1 Log In to the Compute Node

Once the login prompt appears:

```
Rocky Linux 9.6 (Blue Onyx)
Kernel 5.14.0-570.21.1.el9_6.x86_64 on x86_64

nid0001 login:
```

Login with `testuser` for the username and password and check that the live image was booted:

```bash
[testuser@nid0001 ~]$ findmnt /
TARGET SOURCE        FSTYPE  OPTIONS
/      LiveOS_rootfs overlay rw,relatime,lowerdir=/run/rootfsbase,upperdir=/run/
```

It works! Play around a bit more and then logout. Use `Ctrl`+`]` to exit the Virsh console.


### 2.7 OpenCHAMI's Cloud-Init Metadata Server

[Cloud-Init](https://cloudinit.readthedocs.io/en/latest/index.html) is the way
that OpenCHAMI provides post-boot configuration. The idea is to keep the image
generic without any sensitive data like secrets and let cloud-init take care of
that data.

Cloud-Init works by having an API server that keeps track of the configuration
for all nodes, and nodes fetch their configuration from the server via a
cloud-init client installed in the node image. The node configuration is split
up into meta-data (variables) and a configuration specification that can
optionally be templated using the meta-data.

OpenCHAMI [has its own flavor](https://github.com/OpenCHAMI/cloud-init) of
Cloud-Init server that utilizes groups in SMD to provide the appropriate
configuration. (This is why we added our compute nodes to a "compute" group
during discovery.)

In a typical OpenCHAMI Cloud-Init setup, the configuration is set up in three phases:

1. Configure cluster-wide default meta-data
2. Configure group-level cloud-init configuration with optional group meta-data
3. (_OPTIONAL_) Configure node-specific cloud-init configuration and meta-data

This tutorial will use the OpenCHAMI Cloud-Init server for node post-boot configuration.

#### 2.7.1 Configure Cluster Meta-Data

Create a directory for storing Cloud-Init configuration:

```bash
sudo mkdir -p /etc/openchami/data/cloud-init
cd /etc/openchami/data/cloud-init
```

Now, create a new SSH key on the head node and press **Enter** for all of the prompts:

```bash
ssh-keygen -t ed25519
```

The new key that was generated can be found in `~/.ssh/id_ed25519.pub`. This
key will need to be used in the cloud-init meta-data configured below.

```bash
cat ~/.ssh/id_ed25519.pub
```

Create `ci-defaults.yaml`, setting the cluster-wide default values including
the SSH key created above:

```bash
cat <<EOF | sudo tee /etc/openchami/data/cloud-init/ci-defaults.yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 2
public-keys:
  - "$(cat ~/.ssh/id_ed25519.pub)"
short-name: "de"
EOF
```
The content should be, e.g:

```yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 2
public-keys:
- "ssh-ed25519 AAAA... rocky@head"
short-name: "de"
```

Then, set the cloud-init defaults using the `ochami` CLI:

```bash
ochami cloud-init defaults set -f yaml -d @/etc/openchami/data/cloud-init/ci-defaults.yaml
```

Verify that these values were set with:

```bash
ochami cloud-init defaults get -F json-pretty
```

The output should be:

```json
{
  "base-url": "http://172.16.0.254:8081/cloud-init",
  "cluster-name": "demo",
  "nid-length": 2,
  "public-keys": [
    "<YOUR SSH KEY>"
  ],
  "short-name": "nid"
}
```

#### 2.7.2 Configure Group-Level Cloud-Init

Now, the cloud-init configuration needs to be set for the `compute` group,
which is the SMD group that all of the virtual compute nodes are in. For now, a
simple config that only sets created SSH key for the root user can be created.

First, create a templated cloud-config file. Create `ci-group-compute.yaml`
with the following contents:

**Edit as root: `/etc/openchami/data/cloud-init/ci-group-compute.yaml`**

```yaml {title="/etc/openchami/data/cloud-init/ci-group-compute.yaml"}
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

Now, set this configuration for the compute group:

```bash
ochami cloud-init group set -f yaml -d @/etc/openchami/data/cloud-init/ci-group-compute.yaml
```

Check that it got added with:

```bash
ochami cloud-init group get config compute
```

The cloud-config file created within the YAML above should get print out:

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
    ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
disable_root: false
```

`ochami` has basic per-group template rendering available that can be used to
check that the Jinja2 is rendering properly for a node. Check if for the first
compute node (x1000c0s0b0n0):

```bash
ochami cloud-init group render compute x1000c0s0b0n0
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
This feature requires that impersonation is enabled with cloud-init. Check and
make sure that the `IMPERSONATION` environment variable is set in
`/etc/openchami/configs/openchami.env`.
{{< /callout >}}

The SSH key that was created above should appear in the config:

```yaml
#cloud-config
merge_how:
- name: list
  settings: [append]
- name: dict
  settings: [no_replace, recurse_list]
users:
  - name: root
    ssh_authorized_keys: ['<SSH_KEY>']
```

### 2.7.3 (_OPTIONAL_) Configure Node-Specific Meta-Data

If the host naming scheme is unsatisfactory, hostnames can be changed on a
per-node basis via cloud-init meta-data.

For instance, if the hostname of the first compute node needed to be changed
from `de01`, it could be changed to `compute1` with:

```bash
ochami cloud-init node set -d '[{"id":"x1000c0s0b0n0","local-hostname":"compute1"}]'
```

#### 2.7.4 Check the Cloud-Init Metadata

The merged cloud-init meta-data for a node can be examined with:

```bash
ochami cloud-init node get meta-data x1000c0s0b0n0 -F yaml
```

The output should be something like:

```yaml
- cluster-name: demo
  hostname: de01
  instance-id: i-3903b323
  instance_data:
    v1:
        instance_id: i-3903b323
        local_ipv4: 172.16.0.1
        public_keys:
            - <SSH_KEY>
        vendor_data:
            cloud_init_base_url: http://172.16.0.254:8081/cloud-init
            cluster_name: demo
            groups:
                compute:
                    Description: compute config
            version: "1.0"
  local-hostname: compute1
```

This merges the cluster default, group, and node-specific meta-data.

If the node is a member of multiple groups, the order of the merging of those
groups' configs can be seen by running:

```bash
ochami cloud-init node get vendor-data x1000c0s0b0n0
```

The result will be an `#include` directive followed by a list of URIs to each
group cloud-config endpoint for each group the node is a member of:

```
#include
http://172.16.0.254:8081/cloud-init/compute.yaml
```

So far, this compute node is only a member of the one group above.

### 2.8 Boot Using the Compute Image

#### 2.8.1 Switch from the Debug Image to the Compute Image

BSS still thinks that the nodes are booting the debug image, so it needs to be
told to boot the base compute image.

Just as was done for setting the boot parameters for the debug compute image,
the URIs for the boot artifacts for the base compute image needs to be gotten
to configure BSS with them.

```bash
s3cmd ls -Hr s3://boot-images/ | awk '{print $4}' | grep compute/base
```

The output should look something like (versions will likely be different):

```
s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
```

Create `boot-compute-rocky9.yaml` with these values, using the same method used
before to create the debug boot parameters.

```bash
URIS=$(s3cmd ls -Hr s3://boot-images | grep compute/base | awk '{print $4}' | sed 's-s3://-http://172.16.0.254:7070/-' | xargs)
URI_IMG=$(echo "$URIS" | cut -d' ' -f1)
URI_INITRAMFS=$(echo "$URIS" | cut -d' ' -f2)
URI_KERNEL=$(echo "$URIS" | cut -d' ' -f3)
cat <<EOF | sudo tee /etc/openchami/data/boot/bss/compute-base-rocky9.yaml
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

As before, it's a good idea to check that these URIs work before applying the
config.

Then, these new parameters can be set with:

```bash
ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/bss/compute-base-rocky9.yaml
```

Double-check that the params were updated:

```bash
ochami bss boot params get -F yaml
```

They should match the file above:

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
  initrd: http://172.16.0.254:7070/boot-images/efi-images/compute/base/initramfs-5.14.0-570.26.1.el9_6.x86_64.img
  kernel: http://172.16.0.254:7070/boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.26.1.el9_6.x86_64
  macs:
    - 52:54:00:be:ef:01
    - 52:54:00:be:ef:02
    - 52:54:00:be:ef:03
    - 52:54:00:be:ef:04
    - 52:54:00:be:ef:05
  params: nomodeset ro root=live:http://172.16.0.254:7070/boot-images/compute/base/rocky9.6-compute-base-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
```

#### 2.8.2 Booting the Compute Node

Now that the compute base image has been set up, BSS has been configured to
point to it, and Cloud-Init has been configured with the post-boot
configuration, a node can now be fully booted.

Check that the boot parameters point to the base image with:

```bash
ochami bss boot params get | jq
```

Then, power cycle `compute1` and attach to the console to watch it boot:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If the head node is in a VM (see [**Head Node: Using Virtual
Machine**](#05-head-node-using-virtual-machine)), make sure to run the
`virsh` commands below on the host!
{{< /callout >}}

```bash
sudo virsh destroy compute1
sudo virsh start --console compute1
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the following error occurs:

```
error: failed to get domain 'compute1'
```

it may be that the VM is already undefined. Run the [`virt-install`](#26-boot-the-compute-node-with-the-debug-image) command from
before to recreate it.
{{< /callout >}}

Just like with the debug image, the node should:

1. Get its IP address (172.16.0.1)
2. Download the iPXE bootloader binary from CoreSMD
3. Download the `config.ipxe` script that chainloads the iPXE script from BSS (http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01)
4. Download the kernel and initramfs in S3
5. Boot into the image, running cloud-init

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
Configuring (net0 52:54:00:be:ef:01)...... ok
tftp://172.16.0.254:69/config.ipxe... ok
Booting from http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.0.254:8081/boot/v1/bootscript... ok
http://172.16.0.254:7070/boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.26.1.el9_6.x86_64... ok
http://172.16.0.254:7070/boot-images/efi-images/compute/base/initramfs-5.14.0-570.26.1.el9_6.x86_64.img... ok
```

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
If the logs includes this, there is trouble:

```
DBG IP address 10.89.2.1 not found for an xname in nodes
```

It means that the iptables rules has mangled the packet and cloud-init is not
receiving correctly through the network bridge.
{{< /callout >}}

#### 2.8.3 Logging Into the Compute Node

Login as root to the compute node, ignoring its host key:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If using a VM head node, login from there. Else, login from host.
{{< /callout >}}

```bash
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@172.16.0.1
```

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
The SSH host key of the compute nodes is not stored because cloud-init
regenerates it on each reboot. To permanently ignore, create
`/etc/ssh/ssh_config.d/ignore.conf` **on the head node (not the virtual
compute)** with the following content:

```ssh {title="/etc/ssh/ssh_config.d/ignore.conf"}
Match host=172.16.0.*
        UserKnownHostsFile=/dev/null
        StrictHostKeyChecking=no
```

Then, the `-o` options can be omitted to `ssh`.
{{< /callout >}}

If Cloud-Init provided the SSH key, it should work:

```
Warning: Permanently added '172.16.0.1' (ED25519) to the list of known hosts.
Last login: Thu May 29 06:59:26 2025 from 172.16.0.254
[root@compute1 ~]#
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If the optional hostname change in [**2.7.3 (OPTIONAL) Configure Node-Specific
Meta-Data**](#273-_optional_-configure-node-specific-meta-data) was not done,
the hostname should be `de01` instead of `compute1`.
{{< /callout >}}

Congratulations, you've just used OpenCHAMI to boot and login to a compute
node! 🎉

## Part 3: Choose Your Own Adventure

At this point, what has been learned so far in the OpenCHAMI tutorial can be
used to customize the nodes in various ways such as changing how images are
served, deriving new images, and updating the cloud-init config. This sections
explores some of the use cases that may be of use to explore to utilize
OpenCHAMI to fit one's own needs.

### 3.1 Serve Images Using NFS Instead of HTTP

For this tutorial, images were served via HTTP using a local S3 bucket (Versity
S3 Gateway) and OCI registry. Instead, images could be mounted over NFS by
setting up and running a NFS server on the head node, including NFS tools in
the base image, and configuring the nodes to work with NFS.

### 3.2 Customize Boot Image and Operating System

Often, one may want to allocate nodes for different purposes using different
images. One can use the base image that was created before and create another
Kubernetes layer called `kubernetes-worker` based on the `base` image that was
created before. One would need to modify the boot script to use this new
Kubernetes image and update cloud-init set up the nodes.

### 3.3 Use `kexec` to Reboot Nodes without POSTing

### 3.4 Discovery Dynamically Using `magellan`

In this tutorial, static discovery was used to populate the inventory in SMD
instead of dynamically discovering nodes on the network. Static discovery is
good when the MAC address, IP address, xname, and NID of our nodes are known
beforehand and need to guarantee determistic behavior. However, if these
properties are not known beforehand or if one wants to update one's inventory
state, one can use `magellan` to scan, collect, and populate SMD with these
properties.

### 3.5 Run a Sample MPI Job Across Two VMs

After getting the nodes to boot using the compute images, one can try running a
test MPI job. Both SLURM and MPI need to be installed and configured to do so.
This can be done in at least two ways here:

- Create a new `compute-mpi` image similar to the `compute-debug` image using
  the `compute-base` image as a base. The parent images do not need to be
  rebuilt unless changes are made to them, but keep in mind that any derivative
  images will need to be rebuilt.

- Alternatively, the necessary SLURM and MPI packages can be installed via the
  cloud-init config.
