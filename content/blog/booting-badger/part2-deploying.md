Deploying OpenCHAMI

OpenCHAMI is a very adaptable set of containerized software.  Adaptability is one of our core principles.  Different sites must be able to put the containers together in whatever way works best for them.  We recommend that most folks start with our quickstart which utilizes docker-compose to bring up the software and associated infrastructure.  However, it's not the only way to deploy OpenCHAMI.  For Badger, we chose [Podman Quadlets](https://docs.podman.io/en/stable/markdown/podman-systemd.unit.5.html) instead.  For those unfamiliar with quadlets, it is helpful to understand them as systemd unit files for containers.  Since they work with the rest of systemd, they also get some of the benefits of docker-compose.  Through the syntax in the unit files, admins can specify shared resources like files, volumes, and networks.  An additional benefit for our sysadmin team was the Ansible [module](https://docs.ansible.com/ansible/latest/collections/containers/podman/podman_container_module.html) which allowed quadlets to fit seamlessly in to our existing deployment and security pipelines.


In the following unit file, we describe the postgres container which runs the core of data persistence for OpenCHAMI.  In it, we can see that our data will be stored in a named volume and that we've got some initialization information in a second volume.  We've also got several environment variables and secrets that customize the behavior of the container.  Two networks are attached to the container. (Networking works a little differently with quadlets.  See Below.)
```bash
[Unit]
Description=The postgres container

[Container]
ContainerName=postgres
HostName=postgres
Image=postgres:11.5-alpine

# Volumes
Volume=postgres-data.volume:/var/lib/postgresql/data
Volume=/etc/ochami/pg-init:/docker-entrypoint-initdb.d

# Environemnt Variables
Environment=POSTGRES_USER=ochami

# Secrets
Secret=postgres_password,type=env,target=POSTGRES_PASSWORD
Secret=bss_postgres_password,type=env,target=BSS_POSTGRES_PASSWORD
Secret=smd_postgres_password,type=env,target=SMD_POSTGRES_PASSWORD
Secret=hydra_postgres_password,type=env,target=HYDRA_POSTGRES_PASSWORD
Secret=postgres_multiple_databases,type=env,target=POSTGRES_MULTIPLE_DATABASES

# Networks for the Container to use
Network=ochami-internal.network
Network=ochami-jwt-internal.network

[Service]
Restart=always
```

Quadlet support for secrets, volumes, and environment variables all work similarly to docker-compose.  Once you understand the mappings, you can easily translate an existing docker-compose file to a set of quadlet files.  Where things get a bit complicated is networks.  By default quadlets don't support multiple segregated networks the way docker-compose does.

## Networks
The default CNI podman network didn't work for us with OpenCHAMI because we require multiple networks to be connected to each container. In order to work around the defaults, we needed to change the network backend to `netavark`.

```bash 
# /etc/containers/containers.conf
[network]
network_backend="netavark"
```
Based on our investigation during development, we believe netavark will soon be the default for quadlets.  Until then, it is a simple change.

On badger, we ended up with a pair of unit files that define the networks

```bash
[Unit]
Description=ochami-internal Network

[Network]
NetworkName=ochami-internal
Internal=True
```

## Deployment with Ansible

At LANL, we leverage Ansible for a lot of our sysadmin tasks.  In order for our sysadmins to deploy OpenCHAMI without developer support, we needed to meet them where they are, not force them to learn a new technology like Kubernetes or even docker-compose.  We built on our work with quadlets and created a set of ansible roles that set up each of the microservices in the right order using a simple ansible command to create and start the unit files.

> [Our Ansible Repository](https://github.com/OpenCHAMI/deployment-recipes/tree/trcotton/podman-quadlets/lanl/podman-quadlets)

Once created and started, the Units behave like any others on the system.  Our admins can troubleshoot them with tools they understand and even trace dependencies as they would any other system in the datacenter.

For our previous tests of OpenCHAMI, we deployed a Virtual Machine using libvirt on our dedicated head node for each cluster.  The speed of iteration on these development systems was more important than anything else.  With Badger, we wanted to reduce the troubleshooting burden.  While VMs are fast for iteration, they add complexity to the network stack, especially when we're dealing with protocols like DHCP.  We decided instead to install our systemd unit files directly on the head node for badger.

Read on for Part 3 in which we interact with a running OpenCHAMI system to boot Badger.

