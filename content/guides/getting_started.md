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

The OpenCHAMI stack is under active development and is constantly changing.  The intent of this guide is to stand up the OpenCHAMI services on a baremetal host or virtual machine for initial testing and exploration.  At the end of this guide, you will be able to generate an inventory of your compute nodes and boot them.


## Prerequisites

### Bare Metal

To run the OpenCHAMI components a bare metal system, you will need:

 - An x86_64 system.  Support for more architectures coming in the future!
 - A recent version of Docker with `docker compose` support.  See [Docker's install documentation](https://docs.docker.com/engine/install/) for more details.

### Virtual Machine

This guide uses Vagrant and VirtualBox to run the OpenCHAMI components on a virtual machine.  For that, you will need:

 - VirtualBox.  See the [VirtualBox download page](https://www.virtualbox.org/wiki/Downloads) for more details.
 - Vagrant.  See the [Vagrant install documentation](https://developer.hashicorp.com/vagrant/install) for more details.


## Step 1: Prepare Your System

### Bare Metal

If you have Docker installed, you're done!

### Virtual Machine

1. Create a new directory and download the development [Vagrantfile](https://gist.github.com/alexlovelltroy/1aa6d07119ef59fd966417c97baa2ff5) into it.
    ```
    mkdir vagrant-ochami-dev
    cd vagrant-ochami-dev
    curl -L -o Vagrantfile https://gist.githubusercontent.com/alexlovelltroy/1aa6d07119ef59fd966417c97baa2ff5/raw/c04db08e277b5d50206450b152a45ee0e2c5e7cb/Vagrantfile
    ```
2. Launch the Rocky 9 virtual machine.  Note that this will take a while, as the Vagrant provisioning script will do a full OS update and install Docker on first boot.
    ```
    vagrant up
    ```
3. Restart the virtual machine to ensure the newest kernel is running after the updates in the previous step.
    ```
    vagrant reload
    ```
4. Log in to the virtual machine.  The default `vagrant` user was added to the `docker` group when the virtual machine was provisioned, so it will be all set to run Docker commands.
    ```
    vagrant ssh
    ```


## Step 2: Start OpenCHAMI Services

The following instructions apply to both bare-metal and VM-based installs.

All the OpenCHAMI services come pre-configured to work together using docker-compose, making simple deployments easy.  Future documentation will cover other deployment methods for development or production systems.

1. Clone the deployment recipes repository.  This repository contains deployment recipes for various environments, but we will focus on the ones specific to this quickstart guide here.
    ```
    git clone https://github.com/OpenCHAMI/deployment-recipes.git
    cd deployment-recipes
    ```
2. (FIXME: this step shouldn't exist.  We need to merge the quickstart recipes in to the main branch.) Check out the quickstart branch.
    ```
    git checkout alovelltroy/quickstart-guide
    cd quickstart/
    ```
3. Generate environment-specific configs, including local secrets.  OpenCHAMI developers will never ask you for your secrets.
    ```
    ./generate-configs.sh
    ```
4. Start the services!  This will stand up a set of OpenCHAMI services, as well as a private network for them to communicate over
    ```
    docker compose -f base.yml \
        -f autocert.yml \
        -f postgres.yml \
        -f jwt-security.yml \
        -f api-gateway.yml \
        -f openchami-svcs.yml \
        up -d
    ```

The services created by these files are:

* autocert.yml - several 3rd party open source tools to automate creation and renewal of certificates including a per-installation certificate authority
* postgres.yml - a single instance of postgres that handles all the database needs of OpenCHAMI
* jwt-security.yml - our lightweight authentication infrastructure based on 3rd party open source tooling
* api-gateway.yml - KrakenD is our 3rd party open source API gateway of choice
* openchami-svcs.yml - OpenCHAMI microservices

Congratulations!  You now have the base set of OpenCHAMI services running.


## Step 3: What's next

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
