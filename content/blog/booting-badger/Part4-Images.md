+++
title = "Booting 640 HPC Nodes in 5 Minutes: Part 4 - Booting Nodes"
date = 2024-10-17
draft = false
categories = ["HPC", "OpenCHAMI", "Booting"]
contributors = ["Alex Lovell-Troy"]
+++

## Booting Nodes

In previous posts, we covered how we set up OpenCHAMI and interacted with it via the API and CLI. Now, let's dive into one of the most critical aspects of managing a large HPC cluster—booting nodes efficiently and reliably.

### Diskless Nodes and Remote Filesystems

Like many HPC systems, the nodes in the Badger cluster are diskless. Each boot relies on loading a remote filesystem image into memory. The image is built to include everything needed for the node to operate, while any filesystem changes during runtime are saved to an `overlayfs` layer, which also runs in memory.

OpenCHAMI itself doesn't include tooling to build, store, and serve system images.  In keeping with our core principle of modularity, each site has their own preferred OS and image build pipeline.  And, since OpenCHAMI doesn't have custom softare that must be installed in the system image, any Linux operating system should work.  OpenCHAMI references existing kernels, ramdisks, and system image through urls in boot parameters.

### Creating and sharing system images

At LANL, we use [Buildah](https://buildah.io/) and containers to create images and then share them with [Quay](https://www.redhat.com/en/technologies/cloud-computing/quay).  For automation, we use gitlab runners to trigger a new image build on new commits to our git repository.

1. Create a blank container
   ```bash
   CNAME=$(buildah from scratch)
   ```
2. Mount it
   ```bash
   MNAME=$(buildah mount $CNAME)
   ```
3. Install some base packages
   ```bash
   dnf groupinstall --installroot=$MNAME minimal-install
   dnf install --installroot=$MNAME some-other-list-of-packages
   ```
4. Install the kernel and some need dracut stuff:
   ```bash
   dnf install --installroot=$MNAME kernel dracut-live fuse-overlayfs
   ```
5. Rebuild the initrd so that during init it will download the image and mount the rootfs as an in memory overlay
   ```bash
   buildah run -tty $CNAME bash -c " \
       dracut \
       --add "dmsquash-live livenet network-manager" \
       --kver $(basename /lib/modules/*) \
       -N \
       -f \
       --logfile /tmp/dracut.log 2>/dev/null \
      "
   ```
6. Commit it
   ```bash
   buildah commit -t test-image:v1 $CNAME
   ```
7. Then you can push it to a remote registry if desired
   ```bash
   buildah push test-image:v1 registry.local/test-image:v1
   ```

### Create a boot configuration

Here’s how a node’s boot process is configured in OpenCHAMI using ochami-cli:

```yaml
# bss.yaml
macs:
  - AA:BB:CC:DD:EE:FF
initrd: 'http://192.168.1.253:8080/alma/initramfs.img'
kernel: 'http://192.168.1.253:8080/alma/vmlinuz'
params: 'nomodeset ro ip=dhcp selinux=0 console=ttyS0,115200 ip6=off ochami_ci_url=http://10.1.0.3:8081/cloud-init/ ochami_ci_url_secure=http://10.1.0.3:8081/cloud-init-secure/ network-config=disabled rd.shell root=live:http://192.168.1.253:8080/alma/rootfs'
```

Our kernel commandline has a few unique items:

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

## Summary

In this post, we explored how OpenCHAMI orchestrates the boot process for diskless HPC nodes, leveraging remote filesystem images and modular tools like Buildah for creating and managing system images. By maintaining flexibility in image creation and boot configurations, OpenCHAMI allows sites to use their preferred operating systems and infrastructure. With a focus on efficiency and scalability, the system simplifies booting large clusters by integrating seamlessly with existing tools and workflows. As we continue this series, we’ll dive deeper into deployment workflows and how OpenCHAMI can streamline HPC operations across a wide range of environments.

Stay tuned for the final part in our series!
