---
title: "Service Tour"
description: "Tour of the containters/services that are used in the quickstart"
summary: ""
date: 2024-03-07T16:04:48+02:00
lastmod: 2024-03-07T16:04:48+02:00
draft: false
weight: 810
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

# A tour of our quick start containers

In our default configuration, we recommend using a minimum of seven modular lightweight containers.  As you get more advanced in your OpenCHAMI journey, you may decide to add or remove from this list.

## Postgres

Our only container that persists data is our Postgres container.  All other containers use it for storing runtime information.  It is possible to replace the internal postgres with an external or hosted version of the database by customizing the appropriate environment variables.  Please note that this is the only container that defines a docker volume that will persist even after you shut down the docker-compose environment.

## SMD

The OpenCHAMI inventory database is a customized version of the State Management Database (SMD) from the Cray System Manager.  It manages inventory information about the compute nodes and makes it accessible through an HTTP API that other microservices reference in the course of their work.  While it generally serves data from memory, it uses Postgres for persistent storage.

## BSS

Our Boot Script Service (BSS) is a customized version of the same service from the Cray System Manager.  It reads inventory information from SMD and generates appropriate boot scripts for each compute node.

## Cloud-Init

Cloud-Init is a defacto standard in the cloud world.  When you launch a virtual machine through the cloud providers, you may specify simple identity information as well as scripts that will be executed as part of the initialization of the instance.  In many cases, this is the only post-boot configuration required.  We use it for the same reason in OpenCHAMI.  Our cloud-init server provides identity and configuration information based on the contents of SMD and suitable for the cloud-init client which is included with most Linux distributions. 

## Krakend-CE

Krakend-CE is an open-source API gateway.  It sits between any external networks and our internal microservices to secure and manage access to the microservices themselves.  It also allows us to check for valid tokens and appropriate certificates before a microservice is asked to fulfil a request.

## Step-CA

Secure communication on the web requires cryptographically strong public key encryption and signatures.  All of the certificates and signatures need a root of trust known as a Certificate Authority (CA).  OpenCHAMI uses Step-CA to manage that CA.  Acts as an ACME server as well.  Without going deep in how ACME improves security on the web, we chose it so that services don't have to renew their certificates.  ACME maintains security and autmatically handles renewals and rotations.  Less for a busy admin to worry about! 

## OPAAL

Authentication and Authorization on the web has gradually converged on bearer tokens and OpenID Connect.  OPAAL is our own microservice for managing these two things.  It is remarkably small because it relies on Ory's Hydra server for all the hard work.

## Hydra

Hydra is an open-source OIDC provider that can generate secure tokens for us.  Through OPAAL, it can set up a connection with an external identity provider like Github.  OPAAL and Hydra together give OpenCHAMI the ability to leverage Gitlab or GitHub (or any other public Identity Provider like Auth0 or Google) for authentication.
