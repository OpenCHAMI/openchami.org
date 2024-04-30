---
title: "Early Design Decisions"
date: 2024-04-07T16:12:03+02:00
lastmod: 2024-04-07T16:12:03+02:00
draft: false
weight: 50
toc: true
pinned: false
homepage: false
---

In establishing the governance and charter of OpenCHAMI, the board and technical steering committee made a few foundational decisions.

1. All development must be publically available through the [OpenCHAMI Github Organization](https://github.com/OpenCHAMI) including meeting notes and design discussions.
1. The software development effort must start with MIT-licensed microservices from the Cray System Manager(CSM) which was developed for the first Exascale Class Supercomputers.
1. Initial development must be focused on containerized microservices with REST APIS and cloud-like authentication/authorization.
1. The system must operate well for traditional, highly parallel, shared memory workloads.
1. The system must support new types of workloads that are being developed to support Machine Learning, Model Training, and Inference.
1. The system must support the evoloving concept of HPC multitenancy.