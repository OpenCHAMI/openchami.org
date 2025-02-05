---
title: "BSS: The Boot Script Service"
description: ""
summary: ""
date: 2024-03-21T00:00:00+00:00
lastmod: 2025-02-03T00:00:00+00:00
draft: false
weight: 800
url: "/docs/software/bss/"
toc: true

---

# Customized Boot Parameters for each Compute Node

Managing the distribution and configuration of operating systems in a heterogenous HPC environment requires matching specific system image(s) and boot configurations with the compute nodes that need them.  BSS leverages OpenCHAMI's detailed inventory system to ensure each node recieves the kernel, initrd, and flags necessary to efficiently bring up the whole system.  Changes in the inventory are reflected in real time through the boot service.