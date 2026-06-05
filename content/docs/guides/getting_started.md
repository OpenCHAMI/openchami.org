---
title: "OpenCHAMI Quickstart Guide"
description: ""
summary: "Deploying an OpenCHAMI cluster in 20 minutes or less!"
date: 2023-09-07T16:04:48+02:00
lastmod: 2023-09-07T16:04:48+02:00
draft: false
weight: 300
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

  For the most up-to-date instructions on deploying OpenCHAMI, follow the **[OpenCHAMI Tutorial](/docs/tutorial/)**. It provides step-by-step guidance for setting up OpenCHAMI in a controlled environment using Podman Quadlets.

Happy HPC!




## Start OpenCHAMI Services

The **[OpenCHAMI Tutorial](/docs/tutorial/)** provides the most current and detailed instructions for deploying OpenCHAMI. Follow the tutorial to set up your environment and start the services using Podman Quadlets and the [Release RPM](https://github.com/OpenCHAMI/release).

{{< callout context="note" title="Legacy Docker Compose" icon="rocket" >}}
For legacy Docker Compose deployments, see the [deployment-recipes repository](https://github.com/OpenCHAMI/deployment-recipes/tree/main/quickstart). Note that these recipes are deprecated and not recommended for new users.
{{< /callout >}}

### Dependencies and Assumptions

The **[OpenCHAMI Tutorial](/docs/tutorial/)** uses Podman Quadlets for container management and is tested on Rocky Linux 9 with x86 processors.

For Docker Compose deployments (legacy), the OpenCHAMI services are containerized and tested running under `docker compose`. See the [deployment-recipes repository](https://github.com/OpenCHAMI/deployment-recipes/tree/main/quickstart) for details (not recommended for new users).

#### Assumptions

See the **[OpenCHAMI Tutorial](/docs/tutorial/)** for current system requirements and assumptions.

#### Dependencies

See the **[OpenCHAMI Tutorial](/docs/tutorial/)** for current dependencies and installation instructions.



## What's next

Now that you know where to find the current OpenCHAMI deployment instructions, explore the tutorial and related guides.

{{< card-grid >}}
{{< link-card
  title="OpenCHAMI Tutorial"
  description="Step-by-step guide for deploying OpenCHAMI"
  href="/docs/tutorial/"
>}}
{{< link-card
  title="Run a job"
  description="Deploy slurm and run a simple job"
  href="/guides/install_slurm/"
  target="_blank"
>}}
{{< link-card
  title="Deploy an OS"
  description="Deploy Alma Linux with OpenHPC"
  href="/guides/deploy_openhpc/"
  target="_blank"
>}}
{{< /card-grid >}}


## Helpful references

For Docker Compose deployments (legacy), this quickstart uses `docker compose` to start up services and define dependencies. If you have a basic understanding of Docker, you should be able to work with the included services. Some handy items to remember for when you are exploring the deployment are below.


* `docker volume list` This lists all the volumes.  If they exist, the project will try to reuse them.  That might not be what you want.
* `docker network list` ditto for networks.
* `docker ps -a` the -a shows you containers that aren't running.  We have several containers that are designed to do their thing and then exit.
* `docker logs <container-id>` allows you to check the logs of containers even after they have exited
* `docker compose ... down --volumes` will not only bring down all the services, but also delete the volumes
* `docker compose -f <file.yml> -f <file.yml> restart <service-name>` will restart one of the services in the specified compose file(s) without restarting everything.  This is particularly useful when changing configuration files.
