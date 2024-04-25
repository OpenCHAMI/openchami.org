---
title: "Architecture"
date: 2024-03-07T16:12:03+02:00
lastmod: 2024-03-07T16:12:03+02:00
draft: false
weight: 50
toc: false
pinned: false
homepage: false
---


## Philosophy

The OpenCHAMI archtectural concepts share a lot with the original UNIX concepts.  Tools should do one thing well and provide useful inputs and outputs to interoperate with other tools.  With tools that interact on the same system, UNIX pipes and plain text remain core to interoperability.  For tools that interact across distributed systems and potentially across the internet, we add additional useful constratins.

* REST
* TLS
* JWT
* json/yaml

## Early design decisions

In establishing the governance and charter of OpenCHAMI, the board and technical steering committee made a few foundational decisions.

1. All development must be publically available through the [OpenCHAMI Github Organization](https://github.com/OpenCHAMI) including meeting notes and design discussions.
1. The software development effort must start with MIT-licensed microservices from the Cray System Manager(CSM) which was developed for the first Exascale Class Supercomputers.
1. Initial development must be focused on containerized microservices with REST APIS and cloud-like authentication/authorization.
1. The system must operate well for traditional, highly parallel, shared memory workloads.
1. The system must support new types of workloads that are being developed to support Machine Learning, Model Training, and Inference.
1. The system must support the evoloving concept of HPC multitenancy.

## Third Party Services

Most of the components found in a deployment of OpenCHAMI are not part of the OpenCHAMI project.  Common open source-software like `dnsmasq` and `haproxy` have much larger developer and user communities, and they fulfill HPC needs without customization.  There are also plenty of resources for teams that would prefer alternatives to each of the recommended third party applications. 

Where OpenCHAMI microservices do need to be specific, we favor, but do not require, a set of common technologies.

## OpenCHAMI services tend to:

* be HTTPS Microservices
* run as containers 
* be configured at runtime through flags and environment variables
* be based on go 1.21 and the wolfi base containers from chainguard
* leverage bearer tokens for decentralized authentication and authorization
* use go-chi with its robust middleware support