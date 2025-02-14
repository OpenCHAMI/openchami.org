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

  In the guide below, we'll show you how to install and run the OpenCHAMI services with all the containers you need to generate an inventory of your compute nodes and boot them.

  Things move quickly, so the official guide on github may have updated information. See the [quickstart README on Github](https://github.com/OpenCHAMI/deployment-recipes/tree/main/quickstart#readme) for the most current documentation.

Happy HPC!




## Start OpenCHAMI Services

All the OpenCHAMI services come pre-configured to work together using docker-compose.  Using the directions below, you can clone the repos and run the containers in about five minutes without any external dependencies.  See [What's Next](#whats-next) for customization options and running jobs.

{{< callout context="note" title="Quickstart" icon="rocket" >}}
The quickstart is meant to be used on a dedicated node or VM running an RPM-based Linux system with an x86 processor.

The minimum tested configuration is 4 vCPUs and 8 Gigabytes of memory

```bash {title="Download, Configure, and Run the Quickstart…"}
# Clone the repository
git clone https://github.com/OpenCHAMI/deployment-recipes.git
# Enter the quickstart directory
cd deployment-recipes/quickstart/
# Create the secrets in the .env file.  Do not share them with anyone. 
# This also sets the system name for your certificates.  The system will be called "foobar" and the full url will be https://foobar.openchami.cluster which can be set in /etc/hosts to make life easier for you later
./generate-configs.sh
# Start the services
docker compose -f base.yml -f postgres.yml -f jwt-security.yml -f haproxy-api-gateway.yml -f  openchami-svcs.yml -f autocert.yml up -d
# This shouldn't take too long.  A minute or two depending on how long pulling containers takes.
```

Once you get the prompt back, you can download the public certificate from your ca and generate your access token.
```bash {title="Obtain your rootca and tokens"}
# Assuming you're using bash as your shell, you can use the included functions to simplify interactions with your new OpenCHAMI system.
source bash_functions.sh
# Download the root ca so you can validate the ssl certificates included with your system
get_ca_cert > cacert.pem
# Create a jwt access token for use with the apis.
ACCESS_TOKEN=$(gen_access_token)
# If you're curious about that token, you can safely copy and paste it into https://jwt.io to learn more.
# Add an entry to /etc/hosts for the cluster
echo '127.0.0.1  foobar.openchami.cluster' | sudo tee -a /etc/hosts
# Use curl to confirm that everything is working
curl --cacert cacert.pem -H "Authorization: Bearer $ACCESS_TOKEN" https://foobar.openchami.cluster:8443/hsm/v2/State/Components
# This should respond with an empty set of Components: {"Components":[]}
```

Explore the environment on [Github](https://github.com/openchami/deployment-recipes/tree/main/quickstart/).

Also, take a look at the [`ochami` command line tool](https://github.com/OpenCHAMI/ochami) for interacting with OpenCHAMI beyond using cURL.
{{< /callout >}}

### Dependencies and Assumptions

The OpenCHAMI services themselves are all containerized and tested running under `docker compose`.  It should be possible to run OpenCHAMI services on any system with docker installed.

This quickstart makes a few assumptions about the target operating system and is only tested on Rocky Linux 9.3 running on x86 processors.  Feel free to file bugs about other configurations, but we will prioritize support for systems that we can directly test at LANL.

#### Assumptions

* Linux - The quickstart automation makes several assumptions about the behavior Unix tools and their operation under bash from Rocky Linux 9.3
* x86_64 - Some of the containers involved are built and tested for alternative operating systems and architectures, but the solution as a whole is only tested with x86 containers
* Dedicated System - The docker compose setup assumes that it can take control of several TCP ports and interact with the host network for DHCP and TFTP.  It is tested on a dedicated virtual machine
* Local Name Registration - The quickstart bootstraps a Certificate Authority and issues an SSL certificate with a predictable name.  For access, you will need to add that name/IP to /etc/hosts on all clients or make it resolvable through your site DNS

#### Dependencies

* Docker - This quickstart assumes that the target operating system is Rocky Linux 9.3, which by default does not come pre-installed with docker. Rocky also does not by default have access to docker's repositories, and will install an alternaitve that's incompatible with OpenCHAMI, Podman, when a user attempts to install `docker` from yum. We've provided steps from [Docker's installation guide](https://docs.docker.com/engine/install/rhel/) to make sure you can get your containers up and running with ease:

Install yum-utils and point your machine at Docker's repo:
```bash {title="Install yum-utils"}
sudo yum install -y yum-utils
```
```bash {title="Add Docker's repository to your machine"}
sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
```
Install Docker and start Docker's service:
```bash {title="Install Docker and related utilities"}
sudo yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
```bash {title="Start the Docker daemon"}
sudo systemctl start docker
```
Additional verification and troubleshooting steps available at the page linked above if needed.



## What's next

Now that you've got a set of containers up and running that provide OpenCHAMI services, it's time to use them.  We've got a set of administration guides and user guides for you to choose from.

{{< card-grid >}}
{{< link-card
  title="Docker Compose Tour"
  description="Learn just enough docker compose to explore our quickstart files"
  href="/guides/docker_tour/"
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


## Helpful docker compose cheatsheet

This quickstart uses `docker compose` to start up services and define dependencies.  If you have a basic understanding of docker, you should be able to work with the included services.  Some handy items to remember for when you are exploring the deployment are below.


* `docker volume list` This lists all the volumes.  If they exist, the project will try to reuse them.  That might not be what you want.
* `docker network list` ditto for networks
* `docker ps -a` the -a shows you containers that aren't running.  We have several containers that are designed to do their thing and then exit.
* `docker logs <container-id>` allows you to check the logs of containers even after they have exited
* `docker compose ... down --volumes` will not only bring down all the services, but also delete the volumes
* `docker compose -f <file.yml> -f <file.yml> restart <service-name>` will restart one of the services in the specified compose file(s) without restarting everything.  This is particularly useful when changing configuration files.
