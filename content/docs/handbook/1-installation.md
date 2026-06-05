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
a variety of ways. The best method for you depends on your environment and use
case.

We recommend starting with the **[OpenCHAMI Tutorial](/docs/tutorial/)**, which
provides a standardized way to learn OpenCHAMI using Podman Quadlets. Once you
are familiar with the basics, you can explore other deployment methods.

## 1.1. Recommended for New Users

- **Tutorial (Podman Quadlets)** -- The best way to learn OpenCHAMI. Uses the
  [Release RPM](https://github.com/OpenCHAMI/release) for a unified deployment.
  - [**Guide**](/docs/tutorial/)

## 1.2. Alternative Deployment Methods

- **Release RPM (Quadlet-Based)** -- Deploy OpenCHAMI as Podman Quadlets on Red
  Hat-based systems. Companion to the tutorial.
  - [**Repo**](https://github.com/OpenCHAMI/release)
- **Kubernetes (kube-deploy)** -- Deploy OpenCHAMI on Kubernetes using Helm
  charts.
  - [**Repo**](https://github.com/OpenCHAMI/kube-deploy)
- **Kubernetes Operator (openchami-operator)** -- Use the OpenCHAMI operator for
  advanced Kubernetes orchestration.
  - [**Repo**](https://github.com/OpenCHAMI/openchami-operator)
- **Integration Sandbox** -- Test OpenCHAMI in a sandbox environment.
  - [**Repo**](https://github.com/OpenCHAMI/integration-sandbox)
- **Libvirt Virtual Machines** -- Boot Libvirt VMs using OpenCHAMI and Podman
  Quadlets.
  - [**Guide**](/docs/guides/libvirt)

## 1.3. Organization-Specific Recipes

The OpenCHAMI organization maintains a Git repository containing
[deployment recipes](https://github.com/OpenCHAMI/deployment-recipes) with
organization-specific patterns (e.g., Dell, LBNL). These are **not officially
supported** for general use and may require customization. New users should
start with the tutorial instead.
