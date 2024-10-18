---
title: "Booting 640 HPC Nodes in 5 Minutes: Part 2 - Deploying OpenCHAMI "
date: 2024-10-17
draft: false
categories: ["HPC", "OpenCHAMI", "Booting"]
contributors: ["Alex Lovell-Troy"]
---

## Deploying OpenCHAMI: Flexibility and Adaptability in Cluster Management

One of the key strengths of OpenCHAMI is its flexibility. The software is fully containerized and can be deployed using a variety of methods. Our goal was to ensure sysadmins have the freedom to deploy it in a way that best fits their infrastructure, whether that’s through Docker, Podman, or another container management system.

### Docker Compose Quickstart

For those looking to get started quickly, we recommend using our [quickstart](https://openchami.org/guides/getting_started/) which leverages `docker-compose` to spin up the services and infrastructure needed for OpenCHAMI.  The

### Podman Quadlets for Badger

On the Badger cluster, however, we took a different approach. Our sysadmins already have a set of procedures for installing and managing systems with Ansible and systemd services.  Rather than asking them to learn our development technology, we approached deployment of the microservices by integrating with what they were already used to. We used [Podman Quadlets](https://docs.podman.io/en/stable/markdown/podman-systemd.unit.5.html), which integrate with systemd. Quadlets allow you to manage containers as systemd unit files, providing an easy way to orchestrate services while keeping system-level control.

The following unit file describes the postgres container that holds all the state for OpenCHAMI.  Many of the directives should be familiar from the corresponding docker-compose file in the quickstart.

```ini
[Unit]
Description=The postgres container

[Container]
ContainerName=postgres
HostName=postgres
Image=postgres:11.5-alpine

# Volumes
Volume=postgres-data.volume:/var/lib/postgresql/data
Volume=/etc/ochami/pg-init:/docker-entrypoint-initdb.d

# Environemnt Variables
Environment=POSTGRES_USER=ochami

# Secrets
Secret=postgres_password,type=env,target=POSTGRES_PASSWORD
Secret=bss_postgres_password,type=env,target=BSS_POSTGRES_PASSWORD
Secret=smd_postgres_password,type=env,target=SMD_POSTGRES_PASSWORD
Secret=hydra_postgres_password,type=env,target=HYDRA_POSTGRES_PASSWORD
Secret=postgres_multiple_databases,type=env,target=POSTGRES_MULTIPLE_DATABASES

# Networks for the Container to use
Network=ochami-internal.network
Network=ochami-jwt-internal.network

[Service]
Restart=always
```

This approach allowed us to take advantage of systemd's service management while still using containers. Sysadmins can control and monitor the containers as they would any other systemd service, simplifying operations and improving reliability.

## Quadlets with Ansible

At LANL, we leverage Ansible for a lot of our sysadmin tasks.  In order for our sysadmins to deploy OpenCHAMI without developer support, we needed to meet them where they were, not force them to learn a new technology.  We built on our work with quadlets and created a set of ansible roles using the [podman container module](https://docs.ansible.com/ansible/latest/collections/containers/podman/podman_container_module.html)that set up each of the microservices in the right order using a simple ansible command to create and start the unit files.

> [Our Ansible Repository](https://github.com/OpenCHAMI/deployment-recipes/tree/trcotton/podman-quadlets/lanl/podman-quadlets)

Once created and started, the Units behave like any others on the system.  Our admins could troubleshoot them with tools they understand and even trace dependencies as they would any other system in the datacenter.

In the next post, we’ll explore how to interact with OpenCHAMI via the CLI and API to manage large clusters efficiently.
