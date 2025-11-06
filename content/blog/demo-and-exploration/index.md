+++
title = 'Exploring CSM Microservices for OpenCHAMI'
date = 2023-10-28T09:27:54-04:00
draft = false
categories = ['Development', 'LANL', 'SC23']
description = "To help bootstrap the OpenCHAMI effort, the team at LANL ran several parallel experiments to discover and boot a small cluster using as few CSM services as productively possible."
summary = "At LANL, we used two microservices from HPE's CSM to do discovery and boot of a ten node cluster and we learned so much along the way about redfish, postgres, httpboot, aws, and of course, ourselves."
include_toc = true
contributors = ["Alex Lovell-Troy"]
+++




## Introduction
High-performance computing is a critical domain for AI/ML and traditional parallel codes.  Every nuance in efficiency translates to significant computational gains or losses.  The system manager is often overlooked because it doesn’t interact directly with the applications.  However, the system management software is the most important software for preventing system downtime.  Reducing the amount of downtime a system incurs for maintenance can lead to more job runs and longer jobs through the lifetime of an HPC machine.  When Cray/HPE approached modernizing HPC system management to meet the needs of exascale, they turned to management paradigms more popular in cloud computing than those in traditional HPC management and subsequently open sourced the results.  We delved into the expansive set of repositories released by HPE with a goal to discern the core elements for booting a ten-node HPC cluster.  Of the 311 repositories, we found that only two microservices were necessary.  Over several months, we ran a set of experiments to explore the codebase, dependencies and interactions and ultimately boot a small cluster.

## The Cornerstones: Deciphering Essential Microservices
HPE's original system manager was delivered to the HPC customers as an integrated installer with dozens of microservices, running on a Kubernetes cluster with accompanying services for persistent storage.  Many, but not all of the necessary building blocks were provided to the open source community.  As we began, we couldn't find an easy way of using the provided tooling to deploy a subset of CSM.  Instead, we started from the bottom up to find the smallest subset of CSM that would allow to run discovery and manage booting our nodes. Diving into HPE's open-source release was akin to navigating a labyrinth. Amidst the 311 repositories, our analysis spotlighted two microservices indispensable for booting an HPC cluster:

* **State Management Database (SMD)**: SMD expresses one of the core ideas of CSM.  If Redfish allows us to discover and catalog every piece of the system, the smallest logical representation of a system is the list of redfish endpoints to query.  It provides APIs so internal or external clients can manage the list of endpoints and build a higher level inventory of the nodes, networks, etc.. that make up an HPC system.  As discovery clients spring into action, they consult each endpoint and, using SMD's APIs, fashion the comprehensive operational blueprint of nodes and ethernet devices.

* **Boot Script Service (BSS)**: Acting as the bridge between system state and operability, BSS consumes data from SMD and crafts iPXE scripts needed for booting nodes. It can also provide nodes with bootstrap information through cloud-init as part of the boot process.

### A note on BSS persistence
On of the main stakeholders in our project at LANL is the systems management group.  These sysadmins have used CSM to manage our systems and gave us feedback about which parts of the code were contributing to unplanned maintenance or unplanned downtime.  One critical challenge they highlighted lay beneath BSS's operation. Originally reliant on etcd for its backend operations, BSS presented concerns regarding maintenance downtime. Our sysadmin team identified this as a significant source of toil. With a mission to mitigate these downtimes, we invested roughly two weeks to transition BSS from etcd to postgres. This strategic pivot not only simplified backend management but also contributed significantly to the overall system robustness, drastically minimizing potential downtimes.

## Reimagining Discovery: The Genesis of Magellan
The internal Redfish discovery mechanism within SMD, while adept for the HPE nodes it was built for, posed challenges when extrapolated to diverse hardware types. As we attempted to use it with unknown hardware, it proved challenging to differentially troubleshoot issues with the hardware itself and issues with the software attempting to map the hardware.  The quest for a more robust, universal discovery process led us to the bmclib project. Our endeavors crystallized into Magellan – a tool named in homage to the iconic explorer. With its foundation in the bmclib, Magellan rapidly matured into an autonomous SMD client, ushering in enhanced reliability and scalability. As we expanded its capabilities, integrating big data logging functionalities, Magellan solidified its position as a pivotal component in our HPC management toolset. Its independent architecture opened avenues for versatile deployments, as exemplified by our experiment with AWS-hosted SMD and locally-operated Magellan.

## Deployment Strategies: Beyond Conventional Paradigms
CSM's traditional deployment relied heavily on Helm charts within Kubernetes clusters, detailing the intricate microservice interplay. Our goal was to be as minimalist as possible with the codebase so we experimented with alternate deployment strategies.  All proved useful for different microservice deployment and management needs:

* **Docker Compose:** Suited for compact deployments or development settings, Docker Compose provides a streamlined method, emphasizing rapid deployment without sacrificing inter-service communication.

* **Native Binary Deployment:** For environments devoid of container orchestration, we engineered a model where microservices operate as native binaries. This approach trades off some automation for enhanced control and direct oversight.  As part of developing the native binaries, we discovered that environment variables and commandline flags were much easier to iterate with than configuration files.

* **Hybrid Deployment:** Venturing into the realm of cloud integration, we experimented with models that combined local operations with cloud scalability. Such deployments leverage the best of both worlds, optimizing resource allocation and ensuring resilience.

### CSM on AWS

As part of our exploration of deployment strategies, we invested two weeks in deploying microservices using AWS Elastic Container Service and Lambda.  Through some trial and error, we were able to deploya fully functional SMD and BSS on ECS while Magellan and the network services continued to run locally.  This strategy was beneficial for cycle time.  We could iterate at different speeds on different parts of the stack.  One person redeploying a microservice didn't necessarily impact someone else's work on a different one.  It got even more interesting as we integrated AWS Cognito for authentication/authorization and introduced lambda functions for managing access to S3 buckets and for registering clusters.  While two weeks wasn't enough time for us to build a repeatable end-to-end demo, it was enough time to show us what's possible with the cloud and get us thinking about what other options we might pursue in the future.

## Concluding Thoughts: The Imperative of Robust System Management
The HPC landscape is rife with challenges and opportunities. Our exploration, spanning the vast repositories of HPE's open-source release, to pioneering discovery with Magellan, and delving into versatile deployment strategies, has been illuminating. System management, often relegated to the background, stands out as a linchpin in HPC's pursuit of efficiency. Our endeavors underscore the necessity for adaptive, resilient system management paradigms, which can drastically augment the uptime and efficiency of HPC setups.
