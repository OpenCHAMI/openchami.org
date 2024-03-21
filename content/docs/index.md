---
title: "Docs"
description: ""
summary: ""
date: 2023-09-07T16:12:03+02:00
lastmod: 2023-09-07T16:12:03+02:00
draft: false
menu:
  docs:
    parent: ""
    identifier: "docs-9602b15bad02600f3883f55e2ade6b81"
weight: 999
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

HPC System Administration Guides are famously verbose.  OpenCHAMI documentation seeks to be comprehensive while also remaining approachable.

## Guides

For those interested in building a cluster with OpenCHAMI as quickly as possible, we recommend the [Getting Started Guide](/docs/guides/get-started/).  It is the first in our collection of [Administration Guides](/docs/guides/).

## References

Administrators looking for a quick reference on how to use OpenCHAMI software to accomplish a task can browse our [reference documentation](/docs/reference/) which is organized around common HPC use cases.

## Software

For those looking for a deeper understanding of our microservices, we recommend the software references:

* [Magellan](/docs/software/magellan/) - Our Redfish-based discovery system for generating hardware inventory snapshots
* [OPAAL](/docs/software/opaal/) - Our OIDC helper application to support social logins and token creations for use with OpenCHAMI APIs
* [BSS](/docs/software/bss/) - Our microservice for generating customized bootscripts for network-based boot of compute nodes
* [SMD](/docs/software/smd/) - Our inventory microservice that makes state information accessible via HTTP API