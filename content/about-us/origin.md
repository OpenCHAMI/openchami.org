---
title: "Origin of OpenCHAMI"
linktitle: "Origin"
slug: "origin"
description: ""
summary: ""
date: 2024-03-07T16:12:03+02:00
lastmod: 2024-03-07T16:12:03+02:00
draft: false
toc: false
---
<!-- vi: set tw=80 sw=2 sts=2: -->

In 2023, a group of some of the largest HPC sites came together to invest in an
open source future system manager that could bridge the worlds of cloud and
HPC.  They formed a consortium and established governance to guide the
development of that system manager. At early board meetings, the team decided
on core concepts and used them to establish the name of the project.

* **Open** - The community is more important than any included software and all
  parts of the solution should be freely available for anyone to build an HPC
  system or customize to meet the needs of their system or site.
* **Composable** - Rather than a fully integrated system, the goal of OpenCHAMI
  is to be modular.  Not all sites or systems will need the same set of
  software, and it should be possible to replace software components as needed.
* **Heterogeneous** - Sites with multiple kinds of hardware, should be able to
  manage them all with the same resilient and scalable infrastructure.
  OpenCHAMI makes no design assumptions that force a single system image, single
  architecture, or even a single High Speed Interconnect that must be shared
  across all nodes.
* **Adaptable** - The community values constant evolution of system management
  software.  This is true at the individual system scale where adaptability
  means resiliency and stability.  It is also true as the industry evolves to
  embrace new technologies and the solution itself needs to adapt.
* **Management Infrastructure** - Describing the solution in this way narrows
  the scope of OpenCHAMI to activities in the management plane of HPC systems.
  Sysadmins need a stable base upon which they can choose the best Operating
  Systems and user interaction methods for their users.

## First steps

A core team at Los Alamos National Laboratory took the lead on software
development.  Their first goal was to strip back much of CSM to the bare
minimum needed to boot ten nodes. Within a few months, they had established the
core repositories and were able to share their progress at SC23 in Denver.  The
lightweight solution involved just a few microservices and support services and
was able discover and boot ten nodes. [Learn more
here...](https://github.com/OpenCHAMI/lanl-demo-sc23)

Following the initial demonstration, additional teams have been adding
resoruces to the effort with their own goals.  Work continues on using
OpenCHAMI to manage clusters at the US National Laboratories.  At the same
time, sites are working to manage HPC systems from the public cloud with
OpenCHAMI on GKE.  Other sites are collaborating on managing multiple HPC
clusters with the same OpenCHAMI installation.

In May of 2024, the team will showcase progress at the International
Supercomputing Conference in Germany.  Installation times, boot times, and
overall scale have improved considerably in the last six months.

Join us as we plan the next steps in our journey!
