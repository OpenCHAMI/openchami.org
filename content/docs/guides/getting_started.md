---
title: "Get Started"
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

## A tour of our containers

In our default configuration, we recommend using a minimum of seven modular lightweight containers.  As you get more advanced in your OpenCHAMI journey, you may decide to add or remove from this list.

### Postgres

Our only container that persists data is our Postgres container.  All other containers use it for storing runtime information.  It is possible to replace the internal postgres with an external or hosted version of the database by customizing the appropriate environment variables.  Please note that this is the only container that defines a docker volume that will persist even after you shut down the docker-compose environment.

### SMD

The OpenCHAMI inventory database is a customized version of the State Management Database (SMD) from the Cray System Manager.  It manages inventory information about the compute nodes and makes it accessible through an HTTP API that other microservices reference in the course of their work.  While it generally serves data from memory, it uses Postgres for persistent storage.

### BSS

Our Boot Script Service (BSS) is a customized version of the same service from the Cray System Manager.  It reads inventory information from SMD and generates appropriate boot scripts for each compute node.

### Cloud-Init

Cloud-Init is a defacto standard in the cloud world.  When you launch a virtual machine through the cloud providers, you may specify simple identity information as well as scripts that will be executed as part of the initialization of the instance.  In many cases, this is the only post-boot configuration required.  We use it for the same reason in OpenCHAMI.  Our cloud-init server provides identity and configuration information based on the contents of SMD and suitable for the cloud-init client which is included with most Linux distributions. 

### Krakend-CE

Krakend-CE is an open-source API gateway.  It sits between any external networks and our internal microservices to secure and manage access to the microservices themselves.  It also allows us to check for valid tokens and appropriate certificates before a microservice is asked to fulfil a request.

### Step-CA

Secure communication on the web requires cryptographically strong public key encryption and signatures.  All of the certificates and signatures need a root of trust known as a Certificate Authority (CA).  OpenCHAMI uses Step-CA to manage that CA.  Acts as an ACME server as well.  Without going deep in how ACME improves security on the web, we chose it so that services don't have to renew their certificates.  ACME maintains security and autmatically handles renewals and rotations.  Less for a busy admin to worry about! 

### OPAAL

Authentication and Authorization on the web has gradually converged on bearer tokens and OpenID Connect.  OPAAL is our own microservice for managing these two things.  It is remarkably small because it relies on Ory's Hydra server for all the hard work.

### Hydra

Hydra is an open-source OIDC provider that can generate secure tokens for us.  Through OPAAL, it can set up a connection with an external identity provider like Github.  OPAAL and Hydra together give OpenCHAMI the ability to leverage Gitlab or GitHub (or any other public Identity Provider like Auth0 or Google) for authentication.


## Further reading

- Read [about how-to guides](https://diataxis.fr/how-to-guides/) in the Diátaxis framework
