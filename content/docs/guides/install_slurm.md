---
title: "Install Slurm"
description: ""
summary: "Install SLURM and run a simple job"
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

# 0 Overview

This guide walks through setting up Slurm on a OpenCHAMI cluster. This guide will assume you have already setup an OpenCHAMI cluster per Sections 1-2.6 in the [OpenCHAMI Tutorial](https://openchami.org/docs/tutorial/). The only other requirement is to run a webserver to serve a Slurm repo for the image builder to use, and this guide assumes Podman is present to use. This guide will only walk through Slurm setup for a cluster with one head node and one compute node, but is easily expanded to multiple compute nodes by updating the node list with ochami.

## 0.1 Prerequisites

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
This guide assumes you have setup an OpenCHAMI cluster per Sections 1-2.6 in the OpenCHAMI tutorial.
{{< /callout >}}

## 0.2 Contents

- [0 Overview](#0-overview)
  - [0.1 Prerequisites](#01-prerequisites)
  - [0.2 Contents](#02-contents)
- [1 Setup and Configure Slurm](#1-setup-and-configure-slurm)
  - [1.1 Setup Slurm Build/Installation as a Local Repository](#11-setup-slurm-build/installation-as-a-local-repository)
  - [1.2 Configure Slurm and Slurm Services](#12-configure-slurm-and-slurm-services)
  - [1.3 Install Slurm and Setup Configuration Files](#13-install-slurm-and-setup-configuration-files)
  - [1.4 Make a Local Slurm Repository and Serve it with Nginx](#14-make-a-local-slurm-repository-and-serve-it-with-nginx)
  - [1.5 Configure the Boot Script Service and Cloud-Init](#15-configure-the-boot-script-service-and-cloud-init)
  - [1.6 Boot the Compute Node with the Slurm Compute Image](#16-boot-the-compute-node-with-the-slurm-compute-image)
  - [1.7 Configure and Start Slurm in the Compute Node](#17-configure-and-start-slurm-in-the-compute-node)
  - [1.8 Test Munge and Slurm](#18-test-munge-and-slurm)

 
# 1 Setup and Configure Slurm

Steps in this section occur on the head node created in the OpenCHAMI tutorial (or otherwise).

## 1.1 Setup Slurm Build/Installation as a Local Repository

Download Slurm pre-requisite sources compatible with Rocky 9 OS:

```bash
sudo dnf -y update && \
sudo dnf clean all && \
sudo dnf -y install epel-release && \
sudo dnf -y install dnf-plugins-core && \
sudo dnf config-manager --set-enabled devel && \
sudo dnf config-manager --set-enabled crb && \
sudo dnf groupinstall -y 'Development Tools' && \
sudo dnf install -y createrepo freeipmi freeipmi-devel dbus-devel gtk2-devel hdf5 hdf5-devel http-parser-devel \
               hwloc hwloc-devel jq json-c-devel libaec libconfuse libcurl-devel libevent-devel \
               libyaml libyaml-devel lua-devel lua-filesystem lua-json lua-lpeg lua-posix lua-term mariadb mariadb-devel \
               munge munge-devel munge-libs ncurses-devel numactl numactl-devel oniguruma openssl-devel pam-devel \
               perl-DBI perl-ExtUtils-MakeMaker perl-Switch pigz python3 python3-devel readline-devel \
               lsb_release rrdtool rrdtool-devel tcl tcl-devel ucx ucx-cma ucx-devel ucx-ib wget \
               lz4-devel s2n-tls-devel libjwt-devel librdkafka-devel && \
sudo dnf clean all
```

Create build script to install Slurm 24.05.5 and PMIX 4.2.9-1:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
This guide installs Slurm 24.05.5 and PMIX 4.2.9-1 to ensure compatibility. Other versions can be installed instead, but make sure to check version compatibility first. 
{{< /callout >}}

**Create file as rocky user: 'home/rocky/build.sh'**
```bash {title="home/rocky/build.sh"}
SLURMVERSION=${1:-24.05.5}
PMIXVERSION=${2:-4.2.9-1}
ELRELEASE=${3:-el9} #Rocky 9

subversions=( ${PMIXVERSION//-/ } )
pmixmajor=${subversions[0]}
export LC_ALL="C"
OSVERSION=$(lsb_release -r | gawk '{print $2}')
CDIR=$(pwd)
SDIR="slurm/$OSVERSION/$SLURMVERSION"
mkdir -p ${SDIR}
if [[ -e ${SDIR}/pmix-${PMIXVERSION}.${ELRELEASE}.x86_64.rpm ]]; then
        echo "The RPM of PMIX version ${PMIXVERSION} is already available."
else
        cd slurm
        wget https://github.com/openpmix/openpmix/releases/download/v${pmixmajor}/pmix-${PMIXVERSION}.src.rpm || {
                echo "$? pmix-${PMIXVERSION}.src.rpm not downloaded"
                exit
        }
        rpmbuild --rebuild ./pmix-${PMIXVERSION}.src.rpm &> rpmbuild-pmix-${PMIXVERSION}.log || {
                echo "$? pmix-${PMIXVERSION}.src.rpm not builded, review rpmbuild-pmix-${PMIXVERSION}.log"
                exit
        }
        cd ${CDIR}
        mv /root/rpmbuild/RPMS/x86_64/pmix-${PMIXVERSION}.${ELRELEASE}.x86_64.rpm ${SDIR}
        dnf -y install ${SDIR}/pmix-${PMIXVERSION}.${ELRELEASE}.x86_64.rpm        
fi
if [[ -e ${SDIR}/slurm-${SLURMVERSION}-*.rpm ]]; then
        echo "The RPMs of slurm ${SLURMVERSION} are already available."
else
        cd slurm
        wget https://download.schedmd.com/slurm/slurm-${SLURMVERSION}.tar.bz2 || wget http://www.schedmd.com/download/archive/slurm-${SLURMVERSION}.tar.bz2 || {
                echo "$? slurm-${SLURMVERSION}.tar.bz2 not downloaded"
                exit
        }
        rpmbuild -ta --with pmix --with lua --with pam --with mysql --with ucx --with slurmrestd slurm-${SLURMVERSION}.tar.bz2 &> rpmbuild-slurm-${SLURMVERSION}.log || {
                echo "$? slurm-${SLURMVERSION}.tar.bz2 not builded, review rpmbuild-slurm-${SLURMVERSION}.log"
                exit
        }
        grep 'configure: WARNING:' rpmbuild-slurm-${SLURMVERSION}.log 
        cd ${CDIR}
        mv /root/rpmbuild/RPMS/x86_64/slurm*-${SLURMVERSION}-*.rpm ${SDIR}
fi
```

Adjust permissions for build script so that it is executable, and execute it with **root** privileges:

```bash
chmod 755 /home/rocky/build.sh
sudo ./build.sh
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
The following warnings are normal:
```bash
configure: WARNING: unable to locate libnvidia-ml.so and/or nvml.h
configure: WARNING: unable to locate librocm_smi64.so and/or rocm_smi.h
configure: WARNING: unable to locate libze_loader.so and/or ze_api.h
configure: WARNING: HPE Slingshot: unable to locate libcxi/libcxi.h
configure: WARNING: unable to build man page html files without man2html
```
{{< /callout >}}

Copy the Slurm packages to the desired location to create the local repository:

```bash
sudo mkdir -p /install/osupdates/rocky9/x86_64/
sudo cp -r slurm/9.7/24.05.5 /install/osupdates/rocky9/x86_64/slurm-24.05.5
```

Create the local repository (this will be used for installation and images later):

```bash
sudo createrepo /install/osupdates/rocky9/x86_64/slurm-24.05.5
```

The output should be:

```
Directory walk started
Directory walk done - 15 packages
Temporary output repo path: /install/osupdates/rocky9/x86_64/slurm-24.05.5/.repodata/
Preparing sqlite DBs
Pool started (with 5 workers)
Pool finished
```

## 1.2 Configure Slurm and Slurm Services

Create user and group ‘slurm’ with specified UID/GID:

```bash
SLURMID=666
sudo groupadd -g $SLURMID slurm
sudo useradd -m -c "Slurm workload manager" -d /var/lib/slurm -u $SLURMID -g slurm -s /sbin/nologin slurm
```

Update the UID and GID of ‘munge’ user and group to 616, update directory ownership, create munge key and restart the munge service:

```bash
# Update UID and GID
sudo usermod -u 616 munge
sudo groupmod -g 616 munge

# Fix user and group ownership
sudo chown munge:munge /var/log/munge/
sudo chown munge:munge /var/lib/munge/
sudo chown munge:munge /etc/munge/

# Create munge key
sudo create-munge-key

# Start munge again
sudo systemctl enable --now munge
```

Install mariaDB:

```bash
sudo dnf -y install mariadb-server
```

Tune mariaDB with the Slurm recommended options for the compute node where mariaDB will be running:

```bash
cat <<EOF | sudo tee /etc/my.cnf.d/innodb.cnf
[mysqld]
innodb_buffer_pool_size=5120M
innodb_log_file_size=512M
innodb_lock_wait_timeout=900
max_allowed_packet=16M
EOF
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
We are assigning 5GB to the `innodb_buffer_pool_size`. The pool size should be 5-50% of the available memory of the head node and at least 4GB.
{{< /callout >}}

Enable and start the mariaDB service as this is a single node cluster (so we aren't enabling High Availability):

```bash
sudo systemctl enable --now mariadb
```

Secure the mariaDB installation with a strong root password. Use `pwgen` to generate a password and store this password securely. You will use the `pwgen` password to setup and configure MariaDB, as well as to create a database for Slurm to access the head node:

```bash
sudo dnf -y install pwgen
pwgen 20 1 # generates 1 password of length 20 characters

sudo mysql_secure_installation
```

**MariaDB setup/settings should be done as follows:**
```
Enter current password for root (enter for none): # enter rocky password: 'rocky'

Switch to unix_socket authentication [Y/n] Y

Change the root password? [Y/n] Y
New password: # use the password from pwgen
Re-enter new password: # use the password from pwgen

Remove anonymous users? [Y/n] n

Disallow root login remotely? [Y/n] Y

Remove test database and access to it? [Y/n] n

Reload privilege tables now? [Y/n] Y
```

Create the database and grant access to localhost and the head node. You will need the password you generated with `pwgen` in the above step. Make sure you edit the bash code provided below to replace `<pwgen password>` with the actual password: 

```bash
mysql -u root -p # when prompted, enter the password from pwgen

create database slurm_acct_db;
grant all on slurm_acct_db.* to slurm@'localhost' identified by '<pwgen password>';
grant all on slurm_acct_db.* to slurm@'demo.openchami.cluster' identified by '<pwgen password>';
grant all on slurm_acct_db.* to slurm@'head' identified by '<pwgen password>';
exit
```

Install a few more dependencies that are required:

```bash
sudo dnf -y install jq libconfuse numactl parallel perl-DBI perl-Switch
```

Setup directory structure for the Slurm database and controller daemon services:

```bash
sudo mkdir -p /var/spool/slurmctld /var/log/slurm /run/slurm
sudo chown -R slurm. /var/spool/slurmctld /var/log/slurm /run/slurm
echo "d /run/slurm 0755 slurm slurm -" | sudo tee /usr/lib/tmpfiles.d/slurm.conf
```

## 1.3 Install Slurm and Setup Configuration Files

Add the Slurm repo created earlier to install from it (will ensure we get the correct package versions):

```bash
# Create local repo file
SLURMVERSION=24.05.5
RELEASE=rocky9

echo "[slurm-local]
name=Slurm ${SLURMVERSION} - Local
baseurl=file:///install/osupdates/${RELEASE}/x86_64/slurm-${SLURMVERSION}
gpgcheck=0
enabled=1
countme=1" | sudo tee /etc/yum.repos.d/slurm-local.repo

# Install from local repo file
sudo dnf -y install slurm slurm-contribs slurm-example-configs slurm-libpmi slurm-pam_slurm slurm-perlapi slurm-slurmctld slurm-slurmdbd pmix
```

Create configuration files by copying the example files, and then modify the directory and file ownership:

```bash
# Copy configuration files
sudo cp -p /etc/slurm/slurmdbd.conf.example /etc/slurm/slurmdbd.conf
sudo cp -p /etc/slurm/cgroup.conf.example /etc/slurm/cgroup.conf

# Set directory and file ownership to slurm
sudo chown -R slurm. /etc/slurm/
```

Modify the SlurmDB config. You will need the `pwgen` generated password generated earlier when setting up MariaDB for this section:

```bash
DBHOST=head
DBPASSWORD=<pwgen password>   # EDIT TO THE PASSWORD SET IN THE MARIADB CONFIGURATION SECTION
SLURMDBHOST1=head

sudo sed -i "s|DbdAddr.*|DbdAddr=${SLURMDBHOST1}|g" /etc/slurm/slurmdbd.conf
sudo sed -i "s|DbdHost.*|DbdHost=${SLURMDBHOST1}|g" /etc/slurm/slurmdbd.conf
sudo sed -i "s|PidFile.*|PidFile=/var/run/slurm/slurmdbd.pid|g" /etc/slurm/slurmdbd.conf

sudo sed -i "s|#StorageHost.*|StorageHost=${DBHOST}|g" /etc/slurm/slurmdbd.conf
sudo sed -i "s|#StoragePort.*|StoragePort=3306|g" /etc/slurm/slurmdbd.conf
sudo sed -i "s|StoragePass.*|StoragePass=${DBPASSWORD}|g" /etc/slurm/slurmdbd.conf
sudo sed -i "s|SlurmUser.*|SlurmUser=slurm|g" /etc/slurm/slurmdbd.conf
sudo sed -i "s|PidFile.*|PidFile=/var/run/slurm/slurmdbd.pid|g" /etc/slurm/slurmdbd.conf

sudo sed -i "s|#StorageLoc.*|StorageLoc=slurm_acct_db|g" /etc/slurm/slurmdbd.conf
```

Create the Slurm config file, which will be used by SlurmCTL. Note that you may need to update the `NodeName` info depending on the configuration of your compute node.

**Edit the Slurm config file as root: `/etc/slurm/slurm.conf`**
```bash {title="/etc/slurm/slurm.conf"}
#
ClusterName=demo
SlurmctldHost=demo.openchami.cluster
#
#DisableRootJobs=NO
EnforcePartLimits=ALL
#Epilog=
#EpilogSlurmctld=
#FirstJobId=1
#MaxJobId=67043328
#GresTypes=
#GroupUpdateForce=0
#GroupUpdateTime=600
#JobFileAppend=0
JobRequeue=0
#JobSubmitPlugins=lua
KillOnBadExit=1
#LaunchType=launch/slurm
#Licenses=foo*4,bar
#MailProg=/bin/mail
#MaxJobCount=10000
#MaxStepCount=40000
#MaxTasksPerNode=512
MpiDefault=pmix
#MpiParams=ports=#-#
#PluginDir=
#PlugStackConfig=
PrivateData=accounts,jobs,reservations,usage,users
ProctrackType=proctrack/linuxproc
#Prolog=
PrologFlags=Contain
#PrologSlurmctld=
#PropagatePrioProcess=0
PropagateResourceLimits=NONE
#PropagateResourceLimitsExcept=
#RebootProgram=
ReturnToService=2
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmctldPort=6817
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmUser=slurm
SlurmdUser=root
#SrunEpilog=
#SrunProlog=
StateSaveLocation=/var/spool/slurmctld
SwitchType=switch/none
#TaskEpilog=
TaskPlugin=task/none
#TaskProlog=
#TopologyPlugin=topology/tree
#TmpFS=/tmp
#TrackWCKey=no
#TreeWidth=
#UnkillableStepProgram=
#UsePAM=0
#
#
# TIMERS
#BatchStartTimeout=10
CompleteWait=32
#EpilogMsgTime=2000
#GetEnvTimeout=2
#HealthCheckInterval=0
#HealthCheckProgram=
InactiveLimit=300
KillWait=30
MessageTimeout=30
#ResvOverRun=0
MinJobAge=300
#OverTimeLimit=0
SlurmctldTimeout=120
SlurmdTimeout=300
#UnkillableStepTimeout=60
#VSizeFactor=0
Waittime=0
#
#
# SCHEDULING
DefMemPerCPU=2048
#MaxMemPerCPU=0
#SchedulerTimeSlice=30
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
SchedulerParameters=defer,bf_continue,bf_interval=60,bf_resolution=300,bf_window=1440,bf_busy_nodes,default_queue_depth=1000,bf_max_job_start=200,bf_max_job_test=500,max_switch_wait=1800
DependencyParameters=kill_invalid_depend
#
#
# JOB PRIORITY
#PriorityFlags=
#PriorityType=priority/multifactor
#PriorityDecayHalfLife=
#PriorityCalcPeriod=
#PriorityFavorSmall=
#PriorityMaxAge=
#PriorityUsageResetPeriod=
#PriorityWeightAge=
#PriorityWeightFairshare=
#PriorityWeightJobSize=
#PriorityWeightPartition=
#PriorityWeightQOS=
#
#
# LOGGING AND ACCOUNTING
AccountingStorageEnforce=safe,associations,limits,qos
#AccountingStorageHost=
#AccountingStoragePass=
#AccountingStoragePort=
AccountingStorageType=accounting_storage/slurmdbd
#AccountingStorageUser=
#AccountingStoreFlags=
#JobCompHost=
#JobCompLoc=
#JobCompPass=
#JobCompPort=
JobCompType=jobcomp/none
#JobCompUser=
JobContainerType=job_container/tmpfs
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/cgroup
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log
#SlurmSchedLogFile=
#SlurmSchedLogLevel=
#DebugFlags=
#
#
# POWER SAVE SUPPORT FOR IDLE NODES (optional)
#SuspendProgram=
#ResumeProgram=
#SuspendTimeout=
#ResumeTimeout=
#ResumeRate=
#SuspendExcNodes=
#SuspendExcParts=
#SuspendRate=
#SuspendTime=
#
#
# CUSTOM CONFIGS
LaunchParameters=use_interactive_step
#SlurmctldParameters=enable_configless
#
#
# COMPUTE NODES     ## GET CONF WITH `slurmd -C`
NodeName=de01 CPUs=1 Boards=1 SocketsPerBoard=1 CoresPerSocket=1 ThreadsPerCore=1 RealMemory=3892

PartitionName=main Nodes=de01 Default=YES State=UP OverSubscribe=NO PreemptMode=OFF
```

Add job container config file to Slurm config directory:

```bash
SLURMTMPDIR=/lscratch

echo "# Job /tmp on a local volume mounted on ${SLURMTMPDIR}
# /dev/shm has special handling, and instead of a bind mount is always a fresh tmpfs filesystem.
BasePath=${SLURMTMPDIR}
AutoBasePath=true
Shared=true" | sudo tee /etc/slurm/job_container.conf
```

Configure the hosts file with addresses for both the head node and the compute node:

```bash
cat <<EOF | sudo tee -a /etc/hosts
172.16.0.254   demo.openchami.cluster head
172.16.0.1     de01.openchami.cluster de01
EOF
```

## 1.4 Make a Local Slurm Repository and Serve it with Nginx

Use Podman to run Nginx in a container that has the local Slurm repository mounted into it:

```bash
podman run --name serve-slurm \
    --mount type=bind,source=/install/osupdates/rocky9/x86_64/slurm-24.05.5,target=/usr/share/nginx/html/slurm-24.05.5,readonly \
    -p 8080:80 -d nginx
```

Access the container:

```bash
podman exec -it serve-slurm /bin/bash
```

Install vim into the container so you can edit the Nginx config file:

```bash
apt-get update && apt-get install -y vim
```

Get location of Nginx configuration file (nginx.conf) - it should be in /etc/nginx/ but this is to make sure:

```bash
nginx -V 2>&1 | awk -F: '/configure arguments/ {print $2}' | xargs -n1 | grep conf-path
```

**Edit the Nginx config file as root: `/etc/nginx/nginx.conf`**
```bash {title="/etc/nginx/nginx.conf"}
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    include /etc/nginx/conf.d/*.conf;

    server {
        # configuration of HTTP virtual server 
        location /slurm-24.05.5 {
            # configuration for processing URIs for local Slurm repo
            # serve static files from this path 
            # such that a request for /slurm-24.05.5/repodata/repomd.xml will be served /usr/share/nginx/html/slurm-24.05.5/repodata/repomd.xml
            root /usr/share/nginx/html
        }
    }
}
```

Detach from the container with: `ctrl-P, then ctrl-Q`.

Check everything is working by grabbing the repodata file from inside the head node:

```bash
curl http://localhost:8080/slurm-24.05.5/repodata/repomd.xml
```

The output should be:

```
<?xml version="1.0" encoding="UTF-8"?>
<repomd xmlns="http://linux.duke.edu/metadata/repo" xmlns:rpm="http://linux.duke.edu/metadata/rpm">
  <revision>1770960915</revision>
  <data type="primary">
    <checksum type="sha256">4670c00aed4cc64e542e8b76f4f59ec4dd333a2e02258ddab5b7604874915dff</checksum>
    <open-checksum type="sha256">04f66940b8479413f57cf15aa66d56624aede301f064356ee667ccf4594470ef</open-checksum>
    <location href="repodata/4670c00aed4cc64e542e8b76f4f59ec4dd333a2e02258ddab5b7604874915dff-primary.xml.gz"/>
    <timestamp>1770960914</timestamp>
    <size>5336</size>
    <open-size>33064</open-size>
  </data>
  <data type="filelists">
    <checksum type="sha256">11b43e8e70d418dbe78a8c064ca42e18d63397729ba0710323034597f681d0a4</checksum>
    <open-checksum type="sha256">1f2b8e754a2db5c26557ad2a7b9c8b6a210115a4263fb153bc0445dc8210b59c</open-checksum>
    <location href="repodata/11b43e8e70d418dbe78a8c064ca42e18d63397729ba0710323034597f681d0a4-filelists.xml.gz"/>
    <timestamp>1770960914</timestamp>
    <size>11154</size>
    <open-size>68224</open-size>
  </data>
  <data type="other">
    <checksum type="sha256">a7f25375920bf5d30d9de42a6f4aeaa8105b1150bc9bef1440e700369bcdcf53</checksum>
    <open-checksum type="sha256">da1da29e2d02a626986c3647032c175e0cb768d4d643c9020e2ccc343ced93e4</open-checksum>
    <location href="repodata/a7f25375920bf5d30d9de42a6f4aeaa8105b1150bc9bef1440e700369bcdcf53-other.xml.gz"/>
    <timestamp>1770960914</timestamp>
    <size>1229</size>
    <open-size>3354</open-size>
  </data>
  <data type="primary_db">
    <checksum type="sha256">34f7acb86f91ab845250ed939181b88acb0be454e9c42eb99cb871e3241f75e4</checksum>
    <open-checksum type="sha256">038901ed7c43b991becd931370b539c29ad5c7abffefc1ce6fc20cb8e1c1b7c7</open-checksum>
    <location href="repodata/34f7acb86f91ab845250ed939181b88acb0be454e9c42eb99cb871e3241f75e4-primary.sqlite.bz2"/>
    <timestamp>1770960915</timestamp>
    <size>12132</size>
    <open-size>131072</open-size>
    <database_version>10</database_version>
  </data>
  <data type="filelists_db">
    <checksum type="sha256">1912b17f136f28e892c9591e34abc1c8ef5b466df8eed7d6d1c5adadb200c6ad</checksum>
    <open-checksum type="sha256">9eb023458e4570a8c3d9407e24ee52a94befc93785e71b1f72a5d90f314762e2</open-checksum>
    <location href="repodata/1912b17f136f28e892c9591e34abc1c8ef5b466df8eed7d6d1c5adadb200c6ad-filelists.sqlite.bz2"/>
    <timestamp>1770960915</timestamp>
    <size>15917</size>
    <open-size>73728</open-size>
    <database_version>10</database_version>
  </data>
  <data type="other_db">
    <checksum type="sha256">2872ebc347c2e5fe166907ba8341dc10ef9d0419261fac253cb6bab0d1eb046f</checksum>
    <open-checksum type="sha256">5db7c12e76bde1a6b5739ad5c52481633d1dd87599e86ce4d84bae8fe4504db1</open-checksum>
    <location href="repodata/2872ebc347c2e5fe166907ba8341dc10ef9d0419261fac253cb6bab0d1eb046f-other.sqlite.bz2"/>
    <timestamp>1770960915</timestamp>
    <size>1940</size>
    <open-size>24576</open-size>
    <database_version>10</database_version>
  </data>
</repomd>
```

Create the compute Slurm image config file (uses the base image created in the tutorial as the parent layer):

{{< callout context="caution" title="Warning" icon="outline/alert-triangle" >}}
When writing YAML, it's important to be consistent with spacing. **It is
recommended to use spaces for all indentation instead of tabs.**

When pasting, you may have to configure your editor to not apply indentation
rules (`:set paste` in Vim, `:set nopaste` to switch back).
{{< /callout >}}

**Edit as root: `/etc/openchami/data/images/compute-slurm-rocky9.yaml`**
```yaml {title="/etc/openchami/data/images/compute-slurm-rocky9.yaml"}
options:
  layer_type: base
  name: compute-slurm
  publish_tags:
    - 'rocky9'
  pkg_manager: dnf
  gpgcheck: False
  parent: 'demo.openchami.cluster:5000/demo/rocky-base:9'
  registry_opts_pull:
    - '--tls-verify=false'

  publish_s3: 'http://demo.openchami.cluster:7070'
  s3_prefix: 'compute/slurm/'
  s3_bucket: 'boot-images'

repos:
  - alias: 'Epel9'
    url: 'https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/'
    gpg: 'https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9'
  - alias: 'Slurm'
    url: 'http://localhost:8080/slurm-24.05.5'
            
packages:
  - boxes
  - figlet
  - git
  - nfs-utils
  - tcpdump
  - traceroute
  - vim
  - shadow-utils
  - pwgen
  - jq
  - libconfuse
  - numactl
  - parallel
  - perl-DBI
  - slurm-24.05.5
  - pmix-4.2.9
  - slurm-contribs-24.05.5
  - slurm-devel-24.05.5
  - slurm-example-configs-24.05.5
  - slurm-libpmi-24.05.5
  - slurm-pam_slurm-24.05.5
  - slurm-perlapi-24.05.5
  - slurm-sackd-24.05.5
  - slurm-slurmctld-24.05.5
  - slurm-slurmd-24.05.5
  - slurm-slurmdbd-24.05.5
  - slurm-slurmrestd-24.05.5
  - slurm-torque-24.05.5
```

Run podman container to run image build command. The S3_ACCESS and S3_SECRET tokens are set in the tutorial [here](https://openchami.org/docs/tutorial/#233-install-and-configure-s3-clients).

```bash
podman run \
  --rm \
  --device /dev/fuse \
  --network host \
  -e S3_ACCESS=${ROOT_ACCESS_KEY} \
  -e S3_SECRET=${ROOT_SECRET_KEY} \
  -v /etc/openchami/data/images/compute-slurm-rocky9.yaml:/home/builder/config.yaml \
  ghcr.io/openchami/image-build-el9:v0.1.2 \
  image-build \
    --config config.yaml \
    --log-level DEBUG
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If you have already aliased the image build command per the [tutorial](https://openchami.org/docs/tutorial/#233-install-and-configure-s3-clients), you can instead run:

`build-image /etc/openchami/data/images/compute-slurm-rocky9.yaml`
{{< /callout >}}


Check that the images built.

```bash
s3cmd ls -Hr s3://boot-images/ | cut -d' ' -f 4-
```

The output should be:

```
1615M  s3://boot-images/compute/slurm/rocky9.7-compute-slurm-rocky9
  84M  s3://boot-images/efi-images/compute/slurm/initramfs-5.14.0-611.20.1.el9_7.x86_64.img
  14M  s3://boot-images/efi-images/compute/slurm/vmlinuz-5.14.0-611.20.1.el9_7.x86_64
```

## 1.5 Configure the Boot Script Service and Cloud-Init.

Get a fresh access token for ochami:

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

Create payload for boot script service with URIs for slurm compute boot artefacts:

```bash
sudo mkdir /etc/openchami/data/boot/

URIS=$(s3cmd ls -Hr s3://boot-images | grep compute/slurm | awk '{print $4}' | sed 's-s3://-http://172.16.0.254:7070/-' | xargs)
URI_IMG=$(echo "$URIS" | cut -d' ' -f1)
URI_INITRAMFS=$(echo "$URIS" | cut -d' ' -f2)
URI_KERNEL=$(echo "$URIS" | cut -d' ' -f3)
cat <<EOF | sudo tee /etc/openchami/data/boot/boot-compute-slurm-rocky9.yaml
---
kernel: '${URI_KERNEL}'
initrd: '${URI_INITRAMFS}'
params: 'nomodeset ro root=live:${URI_IMG} ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
EOF
```

Set BSS parameters:

```bash
ochami bss boot params set -f yaml -d @/etc/openchami/data/boot/boot-compute-slurm-rocky9.yaml
```

Check the BSS boot parameters were added:

```bash
ochami bss boot params get -F yaml
```

The output should be:

```
- cloud-init:
    meta-data: null
    phone-home:
        fqdn: ""
        hostname: ""
        instance_id: ""
        pub_key_dsa: ""
        pub_key_ecdsa: ""
        pub_key_rsa: ""
    user-data: null
  initrd: http://172.16.0.254:9000/boot-images/efi-images/compute/slurm/initramfs-5.14.0-611.20.1.el9_7.x86_64.img
  kernel: http://172.16.0.254:9000/boot-images/efi-images/compute/slurm/vmlinuz-5.14.0-611.20.1.el9_7.x86_64
  macs:
    - 52:54:00:be:ef:01
  params: nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/slurm/rocky9.7-compute-slurm-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
```

Create new directory for setting up cloud-init configuration:

```bash
sudo mkdir -p /etc/openchami/data/cloud-init
cd /etc/openchami/data/cloud-init
```

Create new ssh key on the head node and press **Enter** for all of the prompts:

```bash
ssh-keygen -t ed25519
```

The new key that was generated can be found in `~/.ssh/id_ed25519.pub`. This key will need to be used in the cloud-init meta-data configured below.

Setup the cloud-init configuration by creating `ci-defaults.yaml`:

```bash
cat <<EOF | sudo tee /etc/openchami/data/cloud-init/ci-defaults.yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 2
public-keys:
  - "$(cat ~/.ssh/id_ed25519.pub)"
short-name: "de"
EOF
```

Then, set the cloud-init defaults using the `ochami` CLI:

```bash
ochami cloud-init defaults set -f yaml -d @/etc/openchami/data/cloud-init/ci-defaults.yaml
```

Verify that these values were set with:

```bash
ochami cloud-init defaults get -F json-pretty
```

The output should be:

```json
{
  "base-url": "http://172.16.0.254:8081/cloud-init",
  "cluster-name": "demo",
  "nid-length": 2,
  "public-keys": [
    "<YOUR SSH KEY>"
  ],
  "short-name": "nid"
}
```

Configure cloud-init for compute group:

**Edit as root: `/etc/openchami/data/cloud-init/ci-group-compute.yaml`**

```yaml {title="/etc/openchami/data/cloud-init/ci-group-compute.yaml"}
- name: compute
  description: "compute config"
  file:
    encoding: plain
    content: |
      ## template: jinja
      #cloud-config
      merge_how:
      - name: list
        settings: [append]
      - name: dict
        settings: [no_replace, recurse_list]
      users:
        - name: root
          ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
      disable_root: false      
```

Now, set this configuration for the compute group:

```bash
ochami cloud-init group set -f yaml -d @/etc/openchami/data/cloud-init/ci-group-compute.yaml
```

Check that it got added with:

```bash
ochami cloud-init group get config compute
```

The cloud-config file created within the YAML above should get print out:

```yaml
## template: jinja
#cloud-config
merge_how:
- name: list
  settings: [append]
- name: dict
  settings: [no_replace, recurse_list]
users:
  - name: root
    ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
disable_root: false
```

`ochami` has basic per-group template rendering available that can be used to
check that the Jinja2 is rendering properly for a node. Check if for the first
compute node (x1000c0s0b0n0):

```bash
ochami cloud-init group render compute x1000c0s0b0n0
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
This feature requires that impersonation is enabled with cloud-init. Check and
make sure that the `IMPERSONATION` environment variable is set in
`/etc/openchami/configs/openchami.env`.
{{< /callout >}}

The SSH key that was created above should appear in the config:

```yaml
#cloud-config
merge_how:
- name: list
  settings: [append]
- name: dict
  settings: [no_replace, recurse_list]
users:
  - name: root
    ssh_authorized_keys: ['<SSH_KEY>']
```


## 1.6 Boot the Compute Node with the Slurm Compute Image

Boot the compute1 compute node VM from the compute Slurm image:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If the head node is in a VM (see [**Head Node: Using Virtual
Machine**](https://openchami.org/docs/tutorial/#05-head-node-using-virtual-machine)), make sure to run the
`virt-install` command on the host!
{{< /callout >}}

{{< tabs "install-compute-vm" >}}
{{< tab "Bare Metal Head" >}}

```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant rocky9 \
  --network network=openchami-net,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```
{{< /tab >}}
{{< tab "Cloud Instance Head" >}}
```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant rocky9 \
  --network network=openchami-net,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```
{{< /tab >}}
{{< tab "VM Head" >}}
```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant rocky9 \
  --network network=openchami-net-internal,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```
{{< /tab >}}
{{< /tabs >}}

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If you recieve following error:

`ERROR    Failed to open file '/usr/share/OVMF/OVMF_VARS.fd': No such file or directory`

Repeat the command, but replace `OVMF_VARS.fd` with `OVMF_VARS_4M.fd` and replace `OVMF_CODE.secboot.fd` with `OVMF_CODE_4M.secboot.fd`.

If this still fails, check the path under **/usr/share/OVMF** to check the name of the files there, as some distros store them under varient names.
{{< /callout >}}


Watch it boot. First, it should PXE:

```
>>Start PXE over IPv4.
  Station IP address is 172.16.0.1

  Server IP address is 172.16.0.254
  NBP filename is ipxe-x86_64.efi
  NBP filesize is 1079296 Bytes
 Downloading NBP file...

  NBP file downloaded successfully.
BdsDxe: loading Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
BdsDxe: starting Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
iPXE initialising devices...
autoexec.ipxe... Not found (https://ipxe.org/2d12618e)



iPXE 1.21.1+ (ge9a2) -- Open Source Network Boot Firmware -- https://ipxe.org
Features: DNS HTTP HTTPS iSCSI TFTP VLAN SRP AoE EFI Menu
```

Then, we should see it get it's boot script from TFTP, then BSS (the `/boot/v1` URL), then download it's kernel/initramfs and boot into Linux.

```
Configuring (net0 52:54:00:be:ef:01)...... ok
tftp://172.16.0.254:69/config.ipxe... ok
Booting from http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.0.254:8081/boot/v1/bootscript... ok
http://172.16.0.254:7070/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-611.24.1.el9_7.x86_64... ok
http://172.16.0.254:7070/boot-images/efi-images/compute/debug/initramfs-5.14.0-611.24.1.el9_7.x86_64.img... ok
```

During Linux boot, output should indicate that the SquashFS image gets downloaded and loaded.

```
[    2.169210] dracut-initqueue[545]:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
[    2.170532] dracut-initqueue[545]:                                  Dload  Upload   Total   Spent    Left  Speed
100 1356M  100 1356M    0     0  1037M      0  0:00:01  0:00:01 --:--:-- 1038M
[    3.627908] squashfs: version 4.0 (2009/01/31) Phillip Lougher
```

Once PXE boot process is done, detach from the VM with `ctrl+]`. Log back into the virsh console if desired with `virsh console compute1`.

{{< callout context="tip" title="Tip" icon="outline/bulb" >}}
If the VM installation fails for any reason, it can be destroyed and undefined so that the install command can be run again.

1. Shut down ("destroy") the VM:
   ```bash
   sudo virsh destroy compute1
   ```
1. Undefine the VM:
   ```bash
   sudo virsh undefine --nvram compute1
   ```
1. Rerun the `virt-install` command above.


**Alternatively**, if you want to reboot the compute node VM with an updated image, do the following:

```bash
sudo virsh destroy compute1
sudo virsh start --console compute1
```
{{< /callout >}}


## 1.7 Configure and Start Slurm in the Compute Node

Login as root to the compute node, ignoring its host key:

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If using a VM head node, login from there. Else, login from host.
{{< /callout >}}

```bash
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@172.16.0.1 
```

Check all of the required packages were installed and from the correct sources (e.g. slurm packages should be installed from `@slurm-local` repo):

```bash
dnf list installed 
```

Create slurm config file that is identical to that of the head node. Note that you may need to update the `NodeName` info depending on the configuration of your compute node:

**Edit the Slurm config file as root: `/etc/slurm/slurm.conf`**
```bash {title="/etc/slurm/slurm.conf"}
#
ClusterName=demo
SlurmctldHost=demo.openchami.cluster
#
#DisableRootJobs=NO
EnforcePartLimits=ALL
#Epilog=
#EpilogSlurmctld=
#FirstJobId=1
#MaxJobId=67043328
#GresTypes=
#GroupUpdateForce=0
#GroupUpdateTime=600
#JobFileAppend=0
JobRequeue=0
#JobSubmitPlugins=lua
KillOnBadExit=1
#LaunchType=launch/slurm
#Licenses=foo*4,bar
#MailProg=/bin/mail
#MaxJobCount=10000
#MaxStepCount=40000
#MaxTasksPerNode=512
MpiDefault=pmix
#MpiParams=ports=#-#
#PluginDir=
#PlugStackConfig=
PrivateData=accounts,jobs,reservations,usage,users
ProctrackType=proctrack/linuxproc
#Prolog=
PrologFlags=Contain
#PrologSlurmctld=
#PropagatePrioProcess=0
PropagateResourceLimits=NONE
#PropagateResourceLimitsExcept=
#RebootProgram=
ReturnToService=2
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmctldPort=6817
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmUser=slurm
SlurmdUser=root
#SrunEpilog=
#SrunProlog=
StateSaveLocation=/var/spool/slurmctld
SwitchType=switch/none
#TaskEpilog=
TaskPlugin=task/none
#TaskProlog=
#TopologyPlugin=topology/tree
#TmpFS=/tmp
#TrackWCKey=no
#TreeWidth=
#UnkillableStepProgram=
#UsePAM=0
#
#
# TIMERS
#BatchStartTimeout=10
CompleteWait=32
#EpilogMsgTime=2000
#GetEnvTimeout=2
#HealthCheckInterval=0
#HealthCheckProgram=
InactiveLimit=300
KillWait=30
MessageTimeout=30
#ResvOverRun=0
MinJobAge=300
#OverTimeLimit=0
SlurmctldTimeout=120
SlurmdTimeout=300
#UnkillableStepTimeout=60
#VSizeFactor=0
Waittime=0
#
#
# SCHEDULING
DefMemPerCPU=2048
#MaxMemPerCPU=0
#SchedulerTimeSlice=30
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
SchedulerParameters=defer,bf_continue,bf_interval=60,bf_resolution=300,bf_window=1440,bf_busy_nodes,default_queue_depth=1000,bf_max_job_start=200,bf_max_job_test=500,max_switch_wait=1800
DependencyParameters=kill_invalid_depend
#
#
# JOB PRIORITY
#PriorityFlags=
#PriorityType=priority/multifactor
#PriorityDecayHalfLife=
#PriorityCalcPeriod=
#PriorityFavorSmall=
#PriorityMaxAge=
#PriorityUsageResetPeriod=
#PriorityWeightAge=
#PriorityWeightFairshare=
#PriorityWeightJobSize=
#PriorityWeightPartition=
#PriorityWeightQOS=
#
#
# LOGGING AND ACCOUNTING
AccountingStorageEnforce=safe,associations,limits,qos
#AccountingStorageHost=
#AccountingStoragePass=
#AccountingStoragePort=
AccountingStorageType=accounting_storage/slurmdbd
#AccountingStorageUser=
#AccountingStoreFlags=
#JobCompHost=
#JobCompLoc=
#JobCompPass=
#JobCompPort=
JobCompType=jobcomp/none
#JobCompUser=
JobContainerType=job_container/tmpfs
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/cgroup
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log
#SlurmSchedLogFile=
#SlurmSchedLogLevel=
#DebugFlags=
#
#
# POWER SAVE SUPPORT FOR IDLE NODES (optional)
#SuspendProgram=
#ResumeProgram=
#SuspendTimeout=
#ResumeTimeout=
#ResumeRate=
#SuspendExcNodes=
#SuspendExcParts=
#SuspendRate=
#SuspendTime=
#
#
# CUSTOM CONFIGS
LaunchParameters=use_interactive_step
#SlurmctldParameters=enable_configless
#
#
# COMPUTE NODES     ## GET CONF WITH `slurmd -C`
NodeName=de01 CPUs=1 Boards=1 SocketsPerBoard=1 CoresPerSocket=1 ThreadsPerCore=1 RealMemory=3892

PartitionName=main Nodes=de01 Default=YES State=UP OverSubscribe=NO PreemptMode=OFF
```

Configure the hosts file with addresses for both the head node and the compute node:

```bash
cat <<EOF | tee -a /etc/hosts
172.16.0.254   demo.openchami.cluster head
172.16.0.1     de01.openchami.cluster de01
EOF
```

Create the Slurm user on the compute node:

```bash
SLURMID=666
groupadd -g $SLURMID slurm
useradd -m -c "Slurm workload manager" -d /var/lib/slurm -u $SLURMID -g slurm -s /sbin/nologin slurm
```

Update Slurm file and directory ownership:

```bash
chown -R slurm:slurm /etc/slurm/
chown -R slurm:slurm /var/lib/slurm
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Use `find / -name "slurm"` to make sure everything that needs to be changed is identified. Note that not all results need ownership modified though, such as directories under `/run/`, `/usr/` or `/var/`!
{{< /callout >}}

Create the directory /var/log/slurm as it doesn't exist yet, and set ownership to Slurm:

```bash
mkdir /var/log/slurm
chown slurm:slurm /var/log/slurm
```

Creating job_container.conf file that matches the one in the head node:

```bash
cat <<EOF | tee /etc/slurm/job_container.conf
# Job /tmp on a local volume mounted on /lscratch
# /dev/shm has special handling, and instead of a bind mount is always a fresh tmpfs filesystem.
BasePath=/lscratch
AutoBasePath=true
Shared=true
EOF
```

Update ownership of the job container config file:

```bash
chown slurm:slurm /etc/slurm/job_container.conf
```

Munge UID is 991 and GID is 990, so change them both to 616 (to match head node UID/GID):

```bash
usermod -u 616 munge
groupmod -g 616 munge
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
If you get the following error:
`usermod: user munge is currently used by process <PID>`

Kill the process and repeat above two commands:
`kill -15 <PID>`
{{< /callout >}}

Update munge file/directory ownership:

```bash
chown -R munge:munge /var/log/munge/
chown -R munge:munge /var/lib/munge/
chown -R munge:munge /etc/munge/
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
Find all directories owned by old munge UID/GID with the following command:

`find / -uid 991 -type d`
{{< /callout >}}

Copy the munge key from the head node to the compute node.

**Inside the head node:**

```bash
cd ~
sudo cp /etc/munge/munge.key ./
sudo chown rocky:rocky munge.key
scp ./munge.key root@172.16.0.1:~/
```

**Inside the compute node:**

```bash
mv munge.key /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
In the case of an error about "Offending ECDSA key in /home/rocky/.ssh/known_hosts:3", wipe the contents of the known hosts file and try the 'scp' command again:

`> /home/rocky/.ssh/known_hosts`
{{< /callout >}}

Continuing **inside the compute node**, setup and start the services for Slurm.

Enable and start munge service:

```bash
systemctl enable munge.service
systemctl start munge.service
systemctl status munge.service
```

The output should be:

```
● munge.service - MUNGE authentication service
     Loaded: loaded (/usr/lib/systemd/system/munge.service; enabled; preset: disabled)
     Active: active (running) since Wed 2026-02-04 00:55:55 UTC; 1 week 2 days ago
       Docs: man:munged(8)
   Main PID: 1451 (munged)
      Tasks: 4 (limit: 24335)
     Memory: 2.2M (peak: 2.5M)
        CPU: 4.710s
     CGroup: /system.slice/munge.service
             └─1451 /usr/sbin/munged

Feb 04 00:55:55 de01 systemd[1]: Started MUNGE authentication service.
```

Enable and start slurmd:

```bash
systemctl enable slurmd
systemctl start slurmd
systemctl status slurmd
```

The output should be:

```
● slurmd.service - Slurm node daemon
     Loaded: loaded (/usr/lib/systemd/system/slurmd.service; enabled; preset: disabled)
     Active: active (running) since Fri 2026-02-13 05:59:32 UTC; 4s ago
   Main PID: 30727 (slurmd)
      Tasks: 1
     Memory: 1.3M (peak: 1.5M)
        CPU: 16ms
     CGroup: /system.slice/slurmd.service
             └─30727 /usr/sbin/slurmd --systemd

Feb 13 05:59:32 de01.openchami.cluster systemd[1]: Stopped Slurm node daemon.
Feb 13 05:59:32 de01.openchami.cluster systemd[1]: slurmd.service: Consumed 3.533s CPU time, 3.0M memory peak.
Feb 13 05:59:32 de01.openchami.cluster systemd[1]: Starting Slurm node daemon...
Feb 13 05:59:32 de01.openchami.cluster slurmd[30727]: slurmd: _read_slurm_cgroup_conf: No cgroup.conf file (/etc/slurm/cgroup.conf), using defaults
Feb 13 05:59:32 de01.openchami.cluster slurmd[30727]: _read_slurm_cgroup_conf: No cgroup.conf file (/etc/slurm/cgroup.conf), using defaults
Feb 13 05:59:32 de01.openchami.cluster slurmd[30727]: slurmd: CPU frequency setting not configured for this node
Feb 13 05:59:32 de01.openchami.cluster slurmd[30727]: slurmd: slurmd version 24.05.5 started
Feb 13 05:59:32 de01.openchami.cluster slurmd[30727]: slurmd: slurmd started on Fri, 13 Feb 2026 05:59:32 +0000
Feb 13 05:59:32 de01.openchami.cluster systemd[1]: Started Slurm node daemon.
Feb 13 05:59:32 de01.openchami.cluster slurmd[30727]: slurmd: CPUs=1 Boards=1 Sockets=1 Cores=1 Threads=1 Memory=3892 TmpDisk=778 Uptime=796812 CPUSpecList=(null) FeaturesAvail=(null) FeaturesActive=(null) 
```

Disable the firewall and reset the nft ruleset in the compute node:

```bash
systemctl stop firewalld
systemctl disable firewalld

nft flush ruleset
nft list ruleset
```

Restart Slurm service daemons to ensure changes are applied:

**Inside the head node:**

```bash
sudo systemctl restart slurmctld
sudo systemctl restart slurmdbd
```

**Inside the compute node:**

```bash
systemctl restart slurmd
```

## 1.8 Test Munge and Slurm

Test munge on the **head node**:

```bash
# Try to munge and unmunge to access the compute node
munge -n | ssh root@172.16.0.1 unmunge
```

The output should be:

```
STATUS:           Success (0)
ENCODE_HOST:      ??? (192.168.200.2)
ENCODE_TIME:      2026-02-13 05:33:34 +0000 (1770960814)
DECODE_TIME:      2026-02-13 05:33:34 +0000 (1770960814)
TTL:              300
CIPHER:           aes128 (4)
MAC:              sha256 (5)
ZIP:              none (0)
UID:              ??? (1000)
GID:              ??? (1000)
LENGTH:           0
```

{{< callout context="note" title="Note" icon="outline/info-circle" >}}
In the case of an error about "Offending ECDSA key in /home/rocky/.ssh/known_hosts:3", wipe the contents of the known hosts file and try the 'munge' command again:

`> /home/rocky/.ssh/known_hosts`
{{< /callout >}}

Test that you can submit a job from the **head node**.

Check that the node is present and idle:

```bash
sinfo
```

The output should be:

```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
main*        up   infinite      1   idle de01
```

Create user with a Slurm account:

```bash
sudo useradd -m -s /bin/bash testuser
sudo usermod -aG wheel testuser
sudo sacctmgr create user testuser defaultaccount=root
sudo su - testuser
```

Run a test job as the user 'testuser':

```bash
srun hostname
```

The output should be:

```
de01
```

If something goes wrong and your compute node goes down, restart it with this command:

```bash
sudo scontrol update NodeName=de01 State=RESUME
```


