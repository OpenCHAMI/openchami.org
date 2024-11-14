---
title: "OpenCHAMI Mini Bootcamp"
date: 2024-11-13
draft: false
categories: ["HPC", "OpenCHAMI", "LANL"]
contributors: ["Travis Cotton", "Alex Lovell-Troy"]
---


# Deploying OpenCHAMI: A Hands-On Guide to Setting Up and Running Your Cluster

This blog post is an abridged version of the training we give internal sysadmins at LANL.  It guides you through the whole process of building and deploying OpenCHAMI on a set of small teaching clusters that we maintain for that purpose.  For more details and example image configurations, visit our repo at [github.com/OpenCHAMI/mini-bootcamp](https://github.com/OpenCHAMI/mini-bootcamp)

---

### Pre-requisites

To get started, you'll need:
- **Linux OS** installed on your machine (we assume you’ve done this).
- **Basic Configuration Management** knowledge—while this guide covers essential configs, we won’t dive into full system deployment.
- **Cluster Images**—OpenCHAMI doesn’t come with image-build tools, so we’ll work through building images locally.

---


### 1. Initial Package Installations

Install necessary packages for OpenCHAMI deployment:

```bash
dnf install -y ansible git podman jq
```

---

### 2. Configure Cluster Hosts

Edit your `/etc/hosts` file to include entries for your cluster. For example:

```plaintext
172.16.0.254    stratus.openchami.cluster
172.16.0.1      st001
#...additional entries for each node
```

---

### 3. Setup Power Management

Install `powerman` and `conman` for node power and console management:

```bash
dnf install -y powerman conman jq
```

**Configure Powerman:** Add device and node info to `/etc/powerman/powerman.conf` using your shortnames.

```plaintext
device "ipmi0" "ipmipower" "/usr/sbin/ipmipower -D lanplus -u admin -p Password123! -h pst[001-009] -I 17 -W ipmiping |&"
node "st[001-009]" "ipmi0" "pst[001-009]"
```

**Start Powerman:**

```bash
systemctl start powerman
systemctl enable powerman
```

---

### 4. Building a Test Image

Use `buildah` to create a lightweight test image.

1. Install buildah:
   ```bash
   dnf install -y buildah
   ```
2. Build the base image:
   ```bash
   CNAME=$(buildah from scratch)
   MNAME=$(buildah mount $CNAME)
   dnf groupinstall -y --installroot=$MNAME --releasever=8 "Minimal Install"
   ```

3. Set up the kernel and dependencies:
   ```bash
   dnf install -y --installroot=$MNAME kernel dracut-live fuse-overlayfs cloud-init
   ```

4. Rebuild initrd:
   ```bash
   buildah run --tty $CNAME bash -c 'dracut --add "dmsquash-live livenet network-manager" --kver $(basename /lib/modules/*) -N -f --logfile /tmp/dracut.log 2>/dev/null'
   ```

5. Save the image:
   ```bash
   buildah commit $CNAME test-image:v1
   ```

---

### 5. Microservices Overview

OpenCHAMI relies on several key microservices:

- **SMD** (State Management Database): Stores system hardware data.
- **BSS** (BootScript Service): Provides iPXE scripts to nodes.
- **Cloud-init**: Customized for OpenCHAMI to configure nodes during boot.
- **TPM-manager**: Issues JWTs for secure configurations.

---

### 6. Setup OpenCHAMI with Ansible

1. Clone the deployment recipes repository:
   ```bash
   git clone https://github.com/OpenCHAMI/deployment-recipes.git
   ```

2. Go to the LANL podman-quadlets recipe:
   ```bash
   cd deployment-recipes/lanl/podman-quadlets
   ```

3. **Inventory Setup**: Edit the `inventory/01-ochami` file to specify your hostname.

4. **Cluster Configurations**: Update `inventory/group_vars/ochami/cluster.yaml` with your cluster name and shortname.

5. **SSH Key Pair**: Generate an SSH key, add it to `inventory/group_vars/ochami/cluster.yaml` under `cluster_boot_ssh_pub_key`.

6. **Run the Playbook**:
   ```bash
   ansible-playbook -l $HOSTNAME -c local -i inventory -t configs ochami_playbook.yaml
   ```

---

### 7. Testing OpenCHAMI Services

After rebooting, run the full playbook:

```bash
ansible-playbook -l $HOSTNAME -c local -i inventory ochami_playbook.yaml
```

Check that the expected containers are running:

```bash
# podman ps | awk '{print $NF}' | sort
```

---

### 8. Setting Up Cloud-init and BSS

1. **Verify Services**: Ensure SMD, BSS, and cloud-init are populated correctly.
   ```bash
   ochami-cli smd --get-components
   ochami-cli bss --get-bootparams
   ochami-cli cloud-init --get-ci-data --name compute
   ```

2. **Boot Nodes**: Start and monitor node boots using `pm` and `conman` commands.

3. **Logs for Debugging**: Open additional terminal windows to monitor logs for DHCP, BSS, and cloud-init.

---

### 9. Building and Using Images

For more complex deployments, use the image-builder tool to build layered images.

```bash
podman build -t image-builder:test -f dockerfiles/dnf/Dockerfile_interactive .
podman run --device /dev/fuse -it --name image-builder --rm -v $PWD:/data image-builder:test 'image-build --log-level INFO --config /data/image-configs/base.yaml'
```

---

### 10. Advanced Topics: Security and Automation

1. **Two-Step Cloud-init**: Set up secure configurations by adding a second layer of cloud-init for sensitive data.
2. **JWT for Secure Data**: Use `tpm-manager` to handle secure data distribution to nodes.

---

### Conclusion

By now, you should have a fully deployed OpenCHAMI environment, equipped with essential microservices and custom-built images, ready to scale. As a final step, consider adding further integrations like Slurm for job scheduling and network-mounted filesystems for additional storage solutions.
