---
title: "Chapter 1. Installation"
description: "How to install and deploy OpenCHAMI."
slug: "installation"
date: 2025-09-11T19:26:29+00:00
lastmod: 2025-09-11T19:26:29+00:00
draft: false
weight: 200
toc: true
pinned: false
homepage: false
---
<!-- vi: set tw=80 sw=2 sts=2: -->

Since OpenCHAMI is composable and adaptable, it can be installed and deployed in
a variety of ways: bare-metal, via Docker/Docker Compose, via [Podman
Quadlets](https://www.redhat.com/en/blog/quadlet-podman), and even Kubernetes.
This page provides an index to some of them.

## 1.1. Deployment Recipes

The OpenCHAMI organization maintains a Git repository containing [deployment
recipes](https://github.com/OpenCHAMI/deployment-recipes) used by various sites.
It is ever-evolving, but currently it has recipes for Docker Compose, Podman
Quadlets, and Helm for Kubernetes.

## 1.2. Release RPM

There is also an official [release](https://github.com/OpenCHAMI/release) Git
repository that houses an RPM package that installs OpenCHAMI services as Podman
Quadlets and installs configuration files in standard filesystem locations. It
is meant to be a "quickstart for quadlets" on Red Hat systems since, by
installing the package and running an additional command, it configures and
starts a base OpenCHAMI installation that is ready to boot nodes.

Currently, only RPM is supported and there is only one package that contains all
of the necessary services. This is obviously not very composable, so future work
entails supporting more packaging options. Contributions are welcome!

To fill any gaps, the deployment recipes repository mentioned above is a good
starting point.

## 1.3. Deployment Guide Index

Here is an index of common OpenCHAMI deployment strategies with links to
guides/resources:

- **Docker Compose (Quickstart)** -- Use Docker Compose to quickly get started
  with OpenCHAMI by setting up base services.
  - [**Guide/Repo**](https://github.com/OpenCHAMI/deployment-recipes/tree/main/quickstart)
- **Podman Quadlets (Release RPM)** -- Use the OpenCHAMI release RPM to run
  OpenCHAMI services using Podman Quadlets.
  - [**Guide**](/docs/handbook/installation/quadlets-rpm)
  - [**Repo**](https://github.com/OpenCHAMI/release)
- **Libvirt Virtual Machines** -- Boot Libvirt VMs using OpenCHAMI and Podman
  Quadlets.
  - [**Guide**](/docs/guides/libvirt)
