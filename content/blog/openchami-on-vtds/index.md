---
title: OpenCHAMI On vTDS
date: 2025-11-19T00:00:00+00:00
lastmod: 2025-11-19T00:00:00+00:00
draft: false
weight: 10
categories: ['Development', 'LANL', 'vTDS', 'virtualization', 'testing', 'CI/CD']
description: |
    Introducing OpenCHAMI on vTDS, a cloud based virtual cluster deployment
    framework able to fully deploy a virtual quadlet based OpenCHAMI cluster
    for testing and development use.
include_toc: true
contributors: ["Eric Lund"]
summary: |
    The vTDS framework defines a base library, a core configuration
    and a set of APIs within which plug-in layer implementations and
    layer specific configurations can be assembled to build a portable
    cloud-based virtual cluster to host a variety of applications for
    development or testing. Work to deploy OpenCHAMI on a vTDS cluster
    using a GCP cloud-provider layer and a custom OpenCHAMI
    application layer has been going on for several months. The first
    fruits of this effort are now publicly available for people to
    try. This post describes vTDS, and the implementation of OpenCHAMI
    on vTDS, provides the status of the on-going work and links readers
    to further documentation to let them get started using vTDS.
---
# OpenCHAMI On vTDS

## vTDS

The vTDS tool is an easy way to deploy a virtual Test and Development
System (vTDS) cluster on which application development and testing can
be done without the need for dedicated hardware resources. The vTDS
framework consists of a core that implements a simple set of commands,
a base library, a set of API definitions and a core configuration that
facilitates deploying vTDS clusters. The framework makes use of a
layered architecture and plug-in Layer Implementations that implement
the operations needed to take advantage of a specific resource
provider (the Provider Layer), customize a specific platform type on
that resource provider (the Platform Layer), construct a specific
cluster topology and set of nodes (the Cluster Layer) and deploy a
specific application onto that cluster (the Application Layer). All of
these elements are assembled using a core configuration that
selects the desired layer implementations and canned layer configurations
to use for a given cluster deployment, while also allowing for local
tweaks to customize the canned layer configurations for a particular
cluster deployment. By creating an OpenCHAMI Application Layer and a
set of canned vTDS configurations, we are able to deploy OpenCHAMI
as an application onto the Google Cloud Provider (GCP) using vTDS.

The commands provided by the vTDS core allow a user to deploy a cluster
(`vtds deploy`), release the resources associated with a cluster
(`vtds remove`), validate a final configuration (`vtds validate`),
review a final configuration (`vtds show_config`) and view the annotated
base default configuration of the selected layers
(`vtds base_config`). Using these a user can design and manage a cluster to
run an application like OpenCHAMI for development or testing purposes
on virtual resources, greatly reducing the need for dedicated
development hardware.

The key concepts within vTDS are, Virtual Blades, Blade Interconnects,
Virtual Nodes and Virtual Networks. In addition to these, vTDS
supports registration of secrets through the Provider Layer for the
sake of preserving and protecting secret data needed during and beyond
the deployment.  Virtual Blades, Blade Interconnects and Secrets are
created, accessed and managed through the Provider Layer. Virtual
Blades are customized for use by a specific cluster by the Platform
Layer. Virtual Nodes and Virtual Networks are created, accessed and
managed through the Cluster Layer, and, finally, the details of
application deployment are provided by the Application Layer.  Each
layer exports an API to the layers above it, allowing portable access
to the constructs and activities within that layer. For example, the
Provider Layer exports API objects that allow layers above it to
manipulate and inspect Virtual Blades, Network Interconnects and
Secrets. The other layers provide similar access. Since the
architecture is layered, only a given layer and the layers above it
can access a given layer API. For example, the Application layer can
access the Cluster layer but the Platform layer cannot.

## OpenCHAMI On vTDS

The current implementation of OpenCHAMI on vTDS consists of the
[vTDS core](https://github.com/Cray-HPE/vtds-core)
and
[base library](https://github.com/Cray-HPE/vtds-base)
configured to use the following Layer Implementations:

- [vtds-provider-gcp](https://github.com/Cray-HPE/vtds-provider-gcp):
  a Provider Layer implementation designed to obtain resources from the
  Google Cloud Platform (GCP) and make them available to a vTDS cluster.
- [vtds-platform-ubuntu](https://github.com/Cray-HPE/vtds-platform-ubuntu):
  a Platform Layer implementation designed to for Virtual Blades running
  the Ubuntu distribution of Linux.
- [vtds-cluster-kvm](https://github.com/Cray-HPE/vtds-cluster-kvm):
  a Cluster Layer implementation using KVM, libvirt and VxLAN facilities
  to deploy Virtual Nodes on Virtual Blades and Virtual Networks on
  Blade Interconnects.
- [vtds-application-openchami](https://github.com/Cray-HPE/vtds-application-openchami):
  an Application Layer with the ability to deploy OpenCHAMI using the
  Quadlet based deployment described in the
  [2025 OpenCHAMI Tutorial](https://github.com/OpenCHAMI/tutorial-2025)
  or to deploy a bare cluster ready for use in manually following the
  2025 OpenCHAMI Tutorial.

The default deployment of OpenCHAMI on vTDS is driven from a core
configuration built from a
[template](https://github.com/Cray-HPE/vtds-configs/blob/main/core-configs/vtds-openChami-gcp.yaml)
currently found in the
[vtds-configs repository](https://github.com/Cray-HPE/vtds-configs)
hosted within HPE's public GitHub organization. That template pulls in
canned configurations from a
[Provider Layer configuration](https://github.com/Cray-HPE/vtds-configs/blob/main/layers/provider/gcp/provider-gcp-openChami.yaml),
a
[Platform Layer configuration](https://github.com/Cray-HPE/vtds-configs/blob/main/layers/platform/ubuntu/platform-ubuntu-openChami.yaml),
a
[Cluster Layer configuration](https://github.com/Cray-HPE/vtds-configs/blob/main/layers/cluster/kvm/cluster-kvm-openChami.yaml)
and an
[Application Layer configuration](https://github.com/Cray-HPE/vtds-configs/blob/main/layers/application/ubuntu/application-ubuntu-openChami.yaml).
While these canned configurations are currently hosted by HPE's GitHub
organization, the plan is to move them and the OpenCHAMI Application layer
code under the OpenCHAMI organization soon.

This default deployment creates a GCP project containing a single instance
which acts as a Virtual Blade. This Virtual Blade runs Ubuntu Linux,
provides a RedFish server implemented using `Sushy-Tools` to access
managed nodes, and hosts one management Virtual Node and up to 4 managed
(compute) Virtual Nodes. OpenCHAMI itself runs on the management node,
and the managed nodes network boot from OpenCHAMI over a cluster Virtual
Network. The current implementation supports up to 16 managed nodes running
on up to 4 Virtual Blades without a significant configuration change. Changes
to this default deployment can be localized to a given user's cluster by
simply adding them to the core configuration, or shared by creating and
publishing configuration overlay files for the affected layers.

## Development Status

The code for OpenCHAMI on vTDS is still under development and is still a
bit fragile (early alpha stage), but it does work and is publicly available.
Work to remove the fragility by improving templating is underway and should
be finished soon. Meanwhile, anyone is welcome to take OpenCHAMI on vTDS for
a spin.

## Getting Started

Those interested in finding out more or trying OpenCHAMI on vTDS should start
with the
[OpenCHAMI on vTDS Getting Started Guide](https://github.com/Cray-HPE/vtds-application-openchami/blob/main/README.md#getting-started-with-openchami-on-vtds).
This contains the information needed to set up and run OpenCHAMI on vTDS
and perform some simple operations on the resulting cluster.
