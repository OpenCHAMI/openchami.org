---
title: "Docker Tour"
description: ""
date: 2024-04-07T16:04:48+02:00
lastmod: 2024-04-07T16:04:48+02:00
draft: false
weight: 300
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

The [quickstart](/guides/getting_started/) is designed to launch quickly so developers and sysadmins can get familiar with the system.  It makes many assumptions about a small system that may not be valid for your site.  The `docker compose` environment and all the concepts may not be familiar to you.  This tour is meant to provide devlopers with a starting point when trying to make changes.

## What is Docker Compose?

Docker compose is a part of the docker ecosystem.  It is documented based on the [compose file format](https://docs.docker.com/compose/compose-file/) which is partially supported by other tools.  It uses the underlying docker runtime to deploy containerized applications in a prescribed order and with various elements shared between containers.

### How does the quickstart Docker Compose?

The quickstart compose files define the service, volumes, and networks necessary for establishing a containerized system for managing an HPC cluster.  Services that need to communicate with each other share networks.  Containers that need to share files do so through volumes.  Containers define their own healthchecks and their own service dependencies to ensure one service doesn't start until another process is complete or a dependent service is running.  The whole process takes about a minute, even when downloading container images for the first time.

## Docker Volumes

Docker volumes are specified in a top-level construct `volumes` within the compose format, and used by individual services.  They must be defined before they can be used.  Volumes exist as containers for files on the host running the docker compose project.  From an HPC background, you can think of them as shared mounts.  In the following example, we define three volumes.  When docker compose reads this configuration, it creates an empty volume for each of these names and keeps track of which containers are allowed to either read or write to the volume.  They do not exist on disk in a way that is easily browsable by the sysadmin.  Instead, they are opaque references to temporary directories that are maintained by the docker daemon.  Sysadmins with control over the docker daemon may attatch and detatch these volumes with advanced docker commands.  Volumes follow their own lifecycles which are separate from the container lifecycles.  Once a volume is created, it exists until the sysadmin deletes it.  Volumes even survive restarts of the docker daemon as well as restarts of the server.  In our quickstart, we specifically delete them using the `--volumes` flag passed to `docker compose down`.  Without the `--volumes` flag, the databases and certificates of previous runs would persist from experiment to experiment.

In the following example, we are creating three volumes with the intention of using them to create files through one container and read them in a different container without having to create services to copy those files around.

* The first empty volume is called `step-root-ca` which is used in OpenCHAMI to hold the CA bundle needed to verify all locally signed certificates.  The certificate authority writes to it and all other containers can mount it with the `:ro` flag to read the certificate.
* The second empty volume is called `haproxy-certs`.  This volume holds the certificates that our API gateway (haproxy) needs for SSL termination.  Haproxy itself doesn't have the capacity to request certs.  We rely on a sidecar which interacts with the certificate authority to generate and renew the SSL certificates as needed.

```yaml
volumes:
  step-root-ca:
  haproxy-certs:
```

Containers specify which volumes they need access to in a `volumes:` section of their service definition.

## Docker Networks

Docker networks are specified in a top-level construct `networks:` within the compose format, and used by individual services.  They must be defined before they can be used.  Containers that share a network may communicate freely across any port, using just the name of the service as the hostname.  It is helpful to think of each docker network as a shared localhost network between containers.  These networks also provide a degree of isolation between services.  Without a specific directive to expose a port or service, it is inaccessible outside it's network(s).

In the following example excerpt, we show a chain of services.  `hydra` is our secure service for managing credentials.  We don't want other services calling it directly.  We built `opaal` specifically to implement only the very few client operations necessary for our system.  All access from outside docker compose to internal services must go through `haproxy` which has access to the outside world.  `haproxy` has access to both `internal` and `external` networks which allows it to act as a proxy for `opaal`.

```yaml
networks:
  external:
  internal:
  hydra-only:

services:
  hydra:
    networks:
      - hydra-only

  opaal:
    networks:
      - hydra-only
      - internal

  haproxy:
    networks:
      - internal
      - external

```
