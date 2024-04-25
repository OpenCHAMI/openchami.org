---
title: "Cloud-Init: Standard node personalization for the cloud"
description: ""
summary: ""
date: 2024-03-21T00:00:00+00:00
lastmod: 2024-03-21T00:00:00+00:00
draft: false
weight: 800
toc: true
---


Cloud-Init is a defacto standard in the cloud world. When you launch a virtual machine through the cloud providers, you may specify simple identity information as well as scripts that will be executed as part of the initialization of the instance. In many cases, this is the only post-boot configuration required. We use it for the same reason in OpenCHAMI. Our cloud-init server provides identity and configuration information based on the contents of SMD and suitable for the cloud-init client which is included with most Linux distributions.