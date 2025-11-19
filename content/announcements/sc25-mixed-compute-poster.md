+++
title = 'SC25 Poster: Mixed Compute Environments with OpenCHAMI'
date = 2025-11-17
draft = false
categories = ['Announcement', 'Research', 'Conference']
contributors = ['Sean Gibson', 'Richard Kim', 'Samuel Quan', 'Travis Cotton', 'Thomas Mackell']
+++

OpenCHAMI is featured in a research poster at **SC25** in St. Louis, showcasing innovative work on managing mixed compute environments across HPC and Kubernetes workloads.

## Mixed Compute Environments with OpenCHAMI

**Authors**: Sean Gibson, Richard Kim, Samuel Quan, Travis Cotton, Thomas Mackell (Los Alamos National Laboratory)

**Supervisor**: Travis Cotton (Los Alamos National Laboratory)

### Abstract

There is a growing need for workloads that don't follow a traditional HPC workflow. Many of these workloads are developed with Kubernetes as the workload manager rather than an HPC-focused one such as Slurm. Mixing different workloads presents a challenge for a few reasons: The demand for either type of resource may fluctuate, so static assignments of Kubernetes or Slurm as the WLM may result in idle resources; the desire for one WLM or another may increase, so extra resources will need to be assigned and moved.

To address this demand, we utilized OpenCHAMI, an open-source system management platform for deploying, managing, and scaling HPC clusters. With OpenCHAMI, we created **"spread"**: a command line tool that configures nodes' workload environments across the cluster. We support fast node booting using kexec and a dynamic base of workload environments to swap between, including Slurm and Kubernetes.

### Resources

- **Full Poster**: [PDF](https://sc25.supercomputing.org/proceedings/posters/poster_files/post139s2-file2.pdf)
- **Poster Summary**: [PDF](https://sc25.supercomputing.org/proceedings/posters/poster_files/post139s2-file3.pdf)
- **SC25 Archive**: [Poster Page](https://sc25.supercomputing.org/proceedings/posters/poster_pages/post139.html)

Read more about OpenCHAMI [here](/docs/introduction-to-openchami/) and try it yourself through the [install guide](/guides/getting_started/).
