---
title: "Introducing Manta: A Cutting-Edge CLI for HPC Infrastructure Management"
date: 2023-10-05T00:00:00Z
draft: false
weight: 12
description: "Discover Manta, a CLI for CSM and OpenCHAMI based HPC systems."
tags: ["Manta", "Introduction", "Productivity"]
categories: ["Development"]
contributors: ["Manuel Sopena Ballesteros", "Miguel Gila", "Matteo Chesi"]
---

# Introducing Manta: A Cutting-Edge CLI for HPC Infrastructure Management

Managing High-Performance Computing (HPC) infrastructure efficiently requires a tool that is both flexible and powerful. **Manta** is a next-generation Command Line Interface (CLI) designed to streamline HPC management for external developers by integrating multiple backend technologies and simplifying complex workflows. Whether you're managing thousands of compute nodes or configuring a single system, Manta provides a seamless and intuitive experience.

## Why Choose Manta?

HPC infrastructures often involve a mix of backend technologies, requiring smooth interactions between components like system management, authentication, configuration, and monitoring. Manta acts as the bridge between these complexities, offering a unified, developer-friendly interface to manage HPC resources effortlessly across diverse environments.

## Key Features of Manta

Manta is designed with flexibility and scalability in mind, featuring an extensive set of capabilities to make HPC management more efficient and accessible.

### **1. Polyglot Architecture for Seamless Backend Interaction**

Manta is built on a **polyglot architecture**, enabling interaction with multiple backend technologies. Currently, it supports:

- **CSM (Cray System Management)**
- **OpenCHAMI (OCHAMI)**

Each backend is encapsulated within an independent library, and the CLI intelligently directs user operations to the appropriate backend, ensuring a smooth and efficient experience.

### **2. Multi-Backend Support for Distributed Environments**

Manta allows users to configure and manage multiple backend instances within a single configuration file. Each backend:

- Can be powered by **CSM or OpenCHAMI**
- Manages different compute nodes or servers
- Operates independently, even if geographically distributed
- Enables seamless switching between backends as needed

This feature makes Manta ideal for organizations with multiple data centers and heterogeneous computing environments.

### **3. Deep Integration with Key HPC Components**

Manta enhances infrastructure management by integrating with critical HPC services:

#### Get cluster or nodes summary

The command below will show most common information (groups, nid, power status, CFS configuration used to build boot/rootfs image, boot/rootfs image id, runtime CFS configuration, etc) related to a list of xnames

```
manta get nodes x1001c1s0b0n0,x1001c1s0b0n1
+---------------+-----------+------------+--------------+-------------------------------------------+----------------------+---------+-------------+---------------------+--------------------------------------+
| XNAME         | NID       | HSM        | Power Status | Runtime Configuration                     | Configuration Status | Enabled | Error Count | Image Configuration | Image ID                             |
+===============================================================================================================================================================================================================+
| x1001c1s0b0n1 | nid001289 | alps,      | READY        | fora-mc-compute-config-cscs-24.8.0.r0-0.2 | configured           | true    | 0           | Not found           | d39fedce-82e3-48d5-bd83-534f37c74c0c |
|               |           | fora,      |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_cn,   |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_nc,   |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_test2 |              |                                           |                      |         |             |                     |                                      |
|---------------+-----------+------------+--------------+-------------------------------------------+----------------------+---------+-------------+---------------------+--------------------------------------|
| x1001c1s0b0n0 | nid001288 | alps,      | READY        | fora-mc-compute-config-cscs-24.8.0.r0-0.2 | configured           | true    | 0           | Not found           | d39fedce-82e3-48d5-bd83-534f37c74c0c |
|               |           | fora,      |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_ns,   |              |                                           |                      |         |             |                     |                                      |
|               |           | fora_uan   |              |                                           |                      |         |             |                     |                                      |
+---------------+-----------+------------+--------------+-------------------------------------------+----------------------+---------+-------------+---------------------+--------------------------------------+
```

Note: If CFS session is deleted, then manta won't be able to find the CFS configuration used to build the image.

#### **Boot Configuration Management**

- **Integration with BSS (Boot Script Service)** to define and configure node boot settings efficiently.
- **Sanitization and management of kernel parameters** to ensure a consistent and secure runtime environment across nodes.
- **Support for modifying kernel parameters dynamically** to adapt to specific workload requirements or security policies.

##### Example Usage:

Assume we want to change the kernel parameters for two nodes: `nid001288` and `nid001289`.

```
manta get kernel-parameters -n 'nid00128[8-9]'
```

This command lists and groups nodes based on shared kernel parameters, making it easier to manage configurations across multiple  nodes.

```
+---------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| XNAME         | Kernel Params                                                                                                                                                                                          |
+========================================================================================================================================================================================================================+
| x1001c1s0b0n0 | console=ttyS0,115200                                                                                                                                                                                   |
| x1001c1s0b0n1 | nmd_data=url=s3://boot-images/d39fedce-82e3-48d5-bd83-534f37c74c0c/rootfs,etag=89a5bd99d9c940ffa992308dc68c53a3-646 quiet                                                                              |
|               | root=craycps-s3:s3://boot-images/d39fedce-82e3-48d5-bd83-534f37c74c0c/rootfs:89a5bd99d9c940ffa992308dc68c53a3-646:dvs:api-gw-service-nmn.local:300:nmn0,hsn0:true spire_join_token=${SPIRE_JOIN_TOKEN} |
+---------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
```

Now, we want to add two new kernel parameters: `test=test` and `quiet`.

```
manta add kernel-parameters -n 'nid001288,  nid001289' 'test=test test=test2 quiet'
Add kernel params:
"test=test test=test2 quiet"
For nodes:
"x1001c1s0b0n0, x1001c1s0b0n1"
✔ This operation will add the kernel parameters for the nodes below. Please confirm to proceed · yes
? "x1001c1s0b0n0, x1001c1s0b0n1"
✔ "x1001c1s0b0n0, x1001c1s0b0n1"
The nodes above will restart. Please confirm to proceed? · no
Cancelled by user. Aborting.
```

Manta detects that the kernel parameters have changed and prompts the user for confirmation before applying updates, ensuring controlled modifications.

Also, kernel parameter test is specified twice but manta only stores it once.

To filter specific kernel parameters when inspecting configurations:

```
manta get kernel-parameters -n 'nid00128[8-9]' -f quiet,test
+---------------+---------------+
| XNAME         | Kernel Params |
+===============================+
| x1001c1s0b0n0 | quiet         |
| x1001c1s0b0n1 | test=test2    |
+---------------+---------------+
```

If a kernel parameter already exists, Manta prevents duplication, ensuring sanitized and clean configurations.

To remove the kernel parameter \`test=test2\`:

```
manta delete kernel-parameters -n nid001289 test
```

After executing this command, Manta confirms the operation and removes the specified parameter, maintaining a streamlined and consistent kernel configuration across nodes.

These capabilities allow administrators to maintain consistency across nodes while also offering flexibility for tuning kernel settings dynamically.

#### **Hardware and Inventory Management**

- **Integration with HSM (Hardware State Manager)** to organize compute groups, track hardware inventory, and manage Ethernet interfaces and Redfish endpoints.
- **Automatic translation of hardware definitions into node lists** to migrate compute nodes with identical hardware configurations across different management planes.

##### Example Usage:

Get hardware summary for all nodes in a HSM group called fora

```
manta get hardware cluster fora
+------------------------------------+----------+
| HW Component                       | Quantity |
+===============================================+
| Memory (GiB)                       | 3072     |
|------------------------------------+----------|
| SS11 200Gb 2P NIC Mezz REV02 (HSN) | 12       |
|------------------------------------+----------|
| AMD EPYC 7742 64-Core Processor    | 24       |
+------------------------------------+----------+
```

Get hardware summary in HSM group fora broken down by xname

```
manta get hardware cluster fora -o details
+---------------+-----------+---------------------------------+------------------------------------+
| Node          | 16384 MiB | AMD EPYC 7742 64-Core Processor | SS11 200Gb 2P NIC Mezz REV02 (HSN) |
+==================================================================================================+
| x1001c1s0b0n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s0b0n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s0b1n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s0b1n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b0n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b0n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b1n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s2b1n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b0n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b0n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b1n0 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
|---------------+-----------+---------------------------------+------------------------------------|
| x1001c1s4b1n1 |  ✅ (16)  |              ✅ (2)             |               ✅ (1)               |
+---------------+-----------+---------------------------------+------------------------------------+
```

#### Add nodes to a HSM group based on hardware description

If we want to add four AMD Epyc cpus into fora\_test HSM group:

```
manta add hardware -P 'epyc:4' -p fora -t fora_test
+---------------+--------+--------+
| Node          | epyc   | memory |
+=================================+
| x1001c1s0b0n0 | ✅ (2) |   ❌   |
|---------------+--------+--------|
| x1001c1s0b0n1 | ✅ (2) |   ❌   |
|---------------+--------+--------|
| x1001c1s2b0n0 | ✅ (2) |   ❌   |
+---------------+--------+--------+
✔ Please check and confirm new hw summary for cluster 'fora_test': {"epyc": 6, "memory": 48} · no
Cancelled by user. Aborting.
```

As a result of the previous command, manta will add two extra nodes x1001c1s0b0n0 and x1001c1s0b0n1 from group fora to fora\_test

#### **Authentication and Security**

- **Integration with Keycloak** for centralized user authentication.
- **Integration with HashiCorp Vault** to securely retrieve and manage secrets, improving security best practices.

#### **Kubernetes Integration for Enhanced Observability**

- Direct connectivity to **node consoles**.
- Seamless access to **CFS session logs** via Kubernetes, making debugging and monitoring easier.

##### Example Usage:

To get the logs of a CFS session:

```
manta log batcher-d241f65c-9114-4e38-ba3f-c62edd921fec
```

#### **Version Control and Configuration Management**

- **Integration with CFS (Configuration Framework Service)** to build boot images efficiently.
- **Gitea integration** to fetch configuration layer details such as commit metadata (committer, date, and time).
- **Expanded CFS configuration options** by introducing **git tags**, complementing the existing **git branch** and **git commit** functionalities.

#### Example Usage:

Get CFS configuration details

```
manta get configurations -n daint_xfer-generic-vcluster-1.0.14-x86-1.0.9`
+----------------------------------------------+---------------------+----------------------------------------------------+-------------------------------------------------------------+
| Configuration Name                           | Last updated        | Layers                                             | Derivatives                                                 |
+=======================================================================================================================================================================================+
| daint_xfer-generic-vcluster-1.0.14-x86-1.0.9 | 09/01/2025 11:39:19 | Name:     csm                                      | CFS sessions:                                               |
|                                              |                     | Branch:   cray/csm/1.16.33                         |                                                             |
|                                              |                     | Tag:                                               | BOS sessiontemplates:                                       |
|                                              |                     | Date:     2024-09-12T12:14:51Z                     |  - daint_xfer-generic-vcluster-1.0.14-x86-1.0.9-ramroot-nmn |
|                                              |                     | Author:   crayvcs - cf-gitea-import                |  - daint_xfer-generic-vcluster-1.0.14-x86-1.0.9-ramroot-hsn |
|                                              |                     | Commit:   2e92fb880d60e6d2f44e73ea122e03b602f7e7ab |  - daint_xfer-generic-vcluster-1.0.14-x86-1.0.9-nmn         |
|                                              |                     | Playbook: csm_packages.yml                         |  - daint_xfer-generic-vcluster-1.0.14-x86-1.0.9-hsn         |
|                                              |                     |                                                    |                                                             |
|                                              |                     | Name:     slingshot-host-software                  | IMS images:                                                 |
|                                              |                     | Branch:   cxi-p2p                                  |  - generic-vcluster-1.0.14-x86                              |
|                                              |                     | Tag:                                               |                                                             |
|                                              |                     | Date:     2024-10-14T18:57:57+02:00                |                                                             |
|                                              |                     | Author:   root                                     |                                                             |
|                                              |                     | Commit:   0020adb2c265fbac41c4a002cc1ce724bab28284 |                                                             |
|                                              |                     | Playbook: shs_cassini_install.yml                  |                                                             |
|                                              |                     |                                                    |                                                             |
|                                              |                     | Name:     uss                                      |                                                             |
|                                              |                     | Branch:                                            |                                                             |
|                                              |                     | Tag:                                               |                                                             |
|                                              |                     | Date:     2024-12-13T17:08:20+01:00                |                                                             |
|                                              |                     | Author:   Marco Induni                             |                                                             |
|                                              |                     | Commit:   067af80f395670201886098fa828252a1a10fdf9 |                                                             |
|                                              |                     | Playbook: cos-compute.yml                          |                                                             |
|                                              |                     |                                                    |                                                             |
|                                              |                     | Name:     csm-diags                                |                                                             |
|                                              |                     | Branch:   cray/csm-diags/1.5.46                    |                                                             |
|                                              |                     | Tag:                                               |                                                             |
|                                              |                     | Date:     2024-09-12T17:35:34Z                     |                                                             |
|                                              |                     | Author:   crayvcs - cf-gitea-import                |                                                             |
|                                              |                     | Commit:   8659bd5dfb2c0b34f5a2f2a08df50be4601e0571 |                                                             |
|                                              |                     | Playbook: csm-diags-compute.yml                    |                                                             |
|                                              |                     |                                                    |                                                             |
|                                              |                     | Name:     sma                                      |                                                             |
|                                              |                     | Branch:   cray/sma/1.9.18                          |                                                             |
|                                              |                     | Tag:                                               |                                                             |
|                                              |                     | Date:     2024-09-12T17:45:46Z                     |                                                             |
|                                              |                     | Author:   crayvcs - cf-gitea-import                |                                                             |
|                                              |                     | Commit:   a15f741958f850aa88ae7e9647bd8db477c6ea8b |                                                             |
|                                              |                     | Playbook: sma-ldms-compute.yml                     |                                                             |
|                                              |                     |                                                    |                                                             |
|                                              |                     | Name:     uss                                      |                                                             |
|                                              |                     | Branch:                                            |                                                             |
|                                              |                     | Tag:                                               |                                                             |
|                                              |                     | Date:     2024-12-13T17:08:20+01:00                |                                                             |
|                                              |                     | Author:   Marco Induni                             |                                                             |
|                                              |                     | Commit:   067af80f395670201886098fa828252a1a10fdf9 |                                                             |
|                                              |                     | Playbook: cos-compute-last.yml                     |                                                             |
|                                              |                     |                                                    |                                                             |
|                                              |                     | Name:     nomad-orchestrator                       |                                                             |
|                                              |                     | Branch:                                            |                                                             |
|                                              |                     | Tag:                                               |                                                             |
|                                              |                     | Date:     2025-01-08T12:09:49+01:00                |                                                             |
|                                              |                     | Author:   Alejandro Dabin                          |                                                             |
|                                              |                     | Commit:   dcbdf9439188b978e1791211f577129f2e305ab5 |                                                             |
|                                              |                     | Playbook: site-client.yml                          |                                                             |
+----------------------------------------------+---------------------+----------------------------------------------------+-------------------------------------------------------------+
```

#### **Runtime Configuration**

- Enables **real-time node configuration**, providing agility in handling live infrastructure updates.

#### Example Usage:

```
manta apply boot nodes --runtime-configuration <cfs configuration name> <list of xnames>
```

#### SAT commands

- **Replicates SAT (System Admin Toolkit) operations**, ensuring continuity with familiar HPC administration tools.
- We guarantee compatibility with SAT schema [https://github.com/Cray-HPE/sat/blob/main/sat/data/schema/bootprep\_schema.yaml](https://github.com/Cray-HPE/sat/blob/main/sat/data/schema/bootprep_schema.yaml) and backward compatibility since CSM 1.3
- Manta process the SAT template file as a jinja template therefore making it more flexible and scalable than the original \`sat bootprep\` command

##### Example Usage:

```
manta sat-file --sat-template-file <sat template file> --values-file <sat values file>
```

With template file

```
cat sat-file/my_template_mc.yml
---
schema_version: 1.0.2
configurations:
- name: "img-{{vcluster.name}}-mc-{{vcluster.version}}"
  layers:
  - name: test_layer
    playbook: site.yml
    git:
      url: https://api-gw-service-nmn.local/vcs/cray/test_layer.git
      tag: {{test_layer.tag}}

- name: "runtime-{{vcluster.name}}-mc-{{vcluster.version}}"
  layers:
  - name: test_layer
    playbook: site.yml
    git:
      url: https://api-gw-service-nmn.local/vcs/cray/test_layer.git
      tag: {{test_layer.tag}}

images:
- name: "{{vcluster.name}}-mc-{{vcluster.version}}"
  ims:
    is_recipe: false
    id: "{{vcluster.base_image_id}}"
  configuration: "img-{{vcluster.name}}-mc-{{vcluster.version}}"
  configuration_group_names:
    {{ vcluster.image_group_list }}

session_templates:
- name: "my-template-{{ template_version }}"
  image:
    ims:
      name: "{{vcluster.name}}-mc-{{vcluster.version}}"
  configuration: "runtime-{{vcluster.name}}-mc-{{vcluster.version}}"
  bos_parameters:
    boot_sets:
      compute:
        arch: X86
        kernel_parameters: ip=dhcp quiet ksocklnd.skip_mr_route_setup=1 cxi_core.disable_default_svc=0 cxi_core.enable_fgfc=1 cxi_core.sct_pid_mask=0xf spire_join_token=${SPIRE_JOIN_TOKEN}
        node_groups:
          {{ vcluster.sessiontemplate_group_list }}
        rootfs_provider_passthrough: "dvs:api-gw-service-nmn.local:300:nmn0,hsn0:true"
```

And values file

```
---
template_version: 1.0
vcluster:
  name: fora-test
  version: __DATE__
  base_image_id: 016b42f4-d1fe-4505-914a-4e31841a9313
  cscs_git_branch: "cscs-24.8.0"
  image_group_list:
    - Compute
    - alps
    - fora_test
  sessiontemplate_group_list:
    - fora_test

default:
  network_type: "cassini"
  working_branch: "{{ vcluster.cscs_git_branch }}"

test_layer:
  tag: v0.1.2

uss:
  version: 1.1.0-135-csm-1.5
  working_branch: "{{ vcluster.cscs_git_branch }}"

cpe:
  version: 23.12.3
  working_branch: "{{ vcluster.cscs_git_branch }}"

csm:
  version: 1.5.2

csm_diags:
  version: 1.5.46

slingshot_host_software:
  version: 2.1.3-107-csm-1.5-x86-64
  working_branch: "{{ vcluster.cscs_git_branch }}"

sma:
  version: 1.9.18
```

Note: when processing a SAT template/values file `__DATE__` will get replaced with current timestamp

Note: for quick prototyping, manta allows overwrite values inline

```
manta apply sat-file -t sat-file/my_template_mc.yml -f sat-file/my_values.yml --values vcluster.version=1.0
```

## Why Manta Stands Out

Unlike traditional CLI tools, Manta is designed with **modern HPC workflows in mind**. Its ability to interact with multiple backend technologies, support distributed infrastructure, and provide deep integration with Kubernetes and security services makes it a **game-changer for HPC administrators and developers**.

## Get Started with Manta

Manta is built for **HPC administrators and developers** looking for a powerful yet intuitive CLI for infrastructure management. By abstracting backend complexities and offering a robust set of integrations, Manta **simplifies complex workflows, enhances security, and provides greater control over compute nodes and servers**.

Stay tuned for detailed guides, real-world use cases, and tutorials on how to make the most of Manta. If you're interested in testing or contributing to the project, reach out—we'd love to collaborate!

## Roadmap and GitHub Issues

Our development roadmap is transparent and community-driven. We actively manage and update our roadmap through GitHub issues, which include:

- Improve error messages:

https://github.com/eth-cscs/manta/issues/64

- Reuse functionality to build http API:

https://github.com/eth-cscs/manta/issues/82

- Review and Feedback on Current CLI Operations Implementation

https://github.com/eth-cscs/manta/issues/93

- Integrate CSM Functionalities into OCHAMI for HPC Cluster Management

https://github.com/eth-cscs/manta/issues/94
