---
title: "OpenCHAMI in ten minutes or less"
description: "Guides lead a user through a specific task they want to accomplish, often with a sequence of steps."
summary: "Deploying an OpenCHAMI cluster in 20 minutes or less!"
date: 2023-09-07T16:04:48+02:00
lastmod: 2023-09-07T16:04:48+02:00
draft: false
menu:
  docs:
    parent: ""
    identifier: "example-6a1a6be4373e933280d78ea53de6158e"
weight: 810
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

OpenCHAMI has everything you need to go from bare hardware to a running cluster in a matter of minutes.  In the guide below, we'll show you how to install and run the OpenCHAMI VM with all the containers you need to generate an inventory of your compute nodes and boot them.  We'll show you how to confirm everything is working by using SLURM to run a simple HPC application.

Happy HPC!

## Configuring the head node

In a simple HPC cluster, there is one head node, just for managing the cluster.  It is typically not as powerful as the rest of the nodes where HPC jobs will run.  All services for configuration and maintenance of the cluster run on the head node.  For OpenCHAMI, we have tested managing over a hundred compute nodes from a single raspberry pi.  The following instructions have been tested with Red Hat 8, but should work with minor changes with any modern rpm-based Linux operating system.  

### Running in a virtual machine

OpenCHAMI is maintained as a set of containers that can be deployed in multiple ways.  We recommend that beginners start with a dedicated (libvirt/kvm) virtual machine and docker-compose.

### Installing the external services

In production, OpenCHAMI relies on an external service for storing compute node images and managing the head node virtual machine.  For development purposes, we recommend installing compatible services on the head node itself.  These will persist beyond the lifetime of the OpenCHAMI vm which is convenient for development and testing as you familiarize yourself with the system.

```shell
dnf install \ 
    podman \
    libvirt \
    grub2-efi-x64 \
    shim-x64 \
    qemu-kvm
```

### Launching our containers with docker-compose

OpenCHAMI services are all built and delivered as containers.  We publish them automatically to ghcr.io and provide SLSA attestations and signatures for everything.  For more details on our secure supply chain, see our dedicated guide on verification.  While you're free to run each container independently, we provide a set of docker-compose files and supporting configuration files to make it easy.

```shell
# Download our latest release tarball
curl -sL "https://api.github.com/repos/OpenCHAMI/deployment-recipes/releases/latest" | grep "browser_download_url.*tar.gz" | cut -d : -f 2,3 | tr -d \" | xargs curl -LO
# Unpack the tarball
tar -zxvvf release*.tar.gz
# Move into the docker-compose directory
cd docker-compose
# Generate the secrets you'll need for passwords and other credentials
./generate-creds.sh
# Launch the docker-compose files
docker compose -f ochami-services.yml -f ochami-krakend-ce.yml -f hydra.yml up
```

