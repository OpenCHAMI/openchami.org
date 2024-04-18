---
title: "OpenCHAMI Quickstart Guide"
description: ""
summary: "Deploying an OpenCHAMI cluster in 20 minutes or less!"
date: 2023-09-07T16:04:48+02:00
lastmod: 2023-09-07T16:04:48+02:00
draft: false
weight: 810
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

OpenCHAMI has everything you need to go from bare hardware to a running cluster in a matter of minutes.  In the guide below, we'll show you how to install and run the OpenCHAMI services in a VM with all the containers you need to generate an inventory of your compute nodes and boot them.  

Happy HPC!




## Start OpenCHAMI Services

All the OpenCHAMI services come pre-configured to work together using docker-compose.  Using the directions below, you can clone the repos and run the containers in about five minutes without any external dependencies.  Read on for customization options and deployment instructions that don't use docker compose. 

```bash
# Clone the repository
git clone https://github.com/OpenCHAMI/deployment-recipes.git
# Enter the quickstart directory
cd deployment-recipes
git checkout alovelltroy/quickstart-guide
cd quickstart/
# Create the secrets.  Do not share them with anyone
./generate-configs.sh
# Start the services
docker compose -f autocert.yml -f postgres.yml -f jwt-security.yml -f api-gateway.yml -f openchami-svcs.yml up -d
```

### OPTIONAL Run the OpenCHAMI Development Vagrantbox

Containers are great for deploying software without relying on shared libraries and other host-level dependencies.  However, if you aren't comfortable with docker compose, or you're not running an operating system that makes installation easy, it helps to test against a known-good system configuration.  OpenCHAMI developers rely on a consistent virtual machine for development and testing.  You can use the same [Vagrantfile](https://gist.github.com/alexlovelltroy/1aa6d07119ef59fd966417c97baa2ff5) we use by following these directions.

1. Install Vagrant by following the [instructions from Hashicorp](https://developer.hashicorp.com/vagrant/docs/installation)
2. Create a new directory with only the [Vagrantfile](https://gist.github.com/alexlovelltroy/1aa6d07119ef59fd966417c97baa2ff5) in it.
3. Run `vagrant up` to download and launch the virtual machine
4. Run `vagrant reload` restart the virtual machine and apply any kernel-related fixes.
5. Run `vagrant ssh` to connect to the virtual machine


That's it!  From there you should be able to move on to installing and running the OpenCHAMI services using the instructions above.

### Services tour

* autocert.yml - several 3rd party open source tools to automate creation and renewal of certificates including a per-installation certificate authority
* postgres.yml - a single instance of postgres that handles all the database needs of OpenCHAMI
* jwt-security.yml - our lightweight authentication infrastructure based on 3rd party open source tooling
* api-gateway.yml - KrakenD is our 3rd party open source API gateway of choice
* openchami-svcs.yml - OpenCHAMI microservices

## What's next

Now that you've got a set of containers up and running that provide OpenCHAMI services, it's time to use them.  We've got a set of administration guides and user guides for you to choose from.

* Using Magellan to discover your hardware
* Launching a compute image using OpenHPC
* Installing and using slurm to run a job

## Helpful docker compose cheatsheet

This quickstart uses `docker compose` to start up services and define dependencies.  If you have a basic understanding of docker, you should be able to work with the included services.  Some handy items to remember for when you are exploring the deployment are below.


* `docker volume list` This lists all the volumes.  If they exist, the project will try to reuse them.  That might not be what you want.
* `docker network list` ditto for networks
* `docker ps -a` the -a shows you containers that aren't running.  We have several containers that are designed to do their thing and then exit.
* `docker logs <container-id>` allows you to check the logs of containers even after they have exited
* `docker compose ... down --volumes` will not only bring down all the services, but also delete the volumes
* `docker compose -f <file.yml> -f <file.yml> restart <service-name>` will restart one of the services in the specified compose file(s) without restarting everything.  This is particularly useful when changing configuration files.
