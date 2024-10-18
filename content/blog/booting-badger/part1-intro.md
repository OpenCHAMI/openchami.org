---
title: "Booting 640 HPC Nodes in 5 Minutes: Part 1 - An Introduction to OpenCHAMI"
date: 2024-10-17
draft: false
categories: ["HPC", "OpenCHAMI", "Booting"]
contributors: ["Alex Lovell-Troy"]
---

Managing HPC systems often means dealing with rigid tools and repetitive tasks. But what if you could approach your HPC clusters with the flexibility of modern cloud workflows? OpenCHAMI is designed to do just that—introduce cloud-like tooling to on-premise clusters in a way that aligns with both traditional HPC workflows and DevOps principles for emerging AI needs.

### The Challenge: Finding the Right Environment

One of the greatest challenges when developing HPC tooling is the limited access to large-scale environments. Development nodes are often scarce and seldom match production-like conditions. Most dev environments provide only a handful of nodes, nowhere near the size or configuration of the clusters they support in real-world use.

At LANL, our OpenCHAMI development team is fortunate to be embedded within our sysadmin group.  Through their help, we discovered that a 660-node cluster was about to be decommissioned. Rather than let the hardware go offline , we jumped at the chance to put OpenCHAMI to the test. The result? We booted 640 nodes in under five minutes.

### The System: Badger

**Badger**, an older machine built by Penguin Computing circa 2016, comprises Relion OCP1930e nodes with three servers per shelf, each featuring a pair of Xeon processors in a 1U form factor. This dense configuration results in 96 nodes per rack, totaling just shy of seven racks for Badger's 660 nodes. To connect all these CPUs, Penguin included a 100G OmniPath High-Speed Network. When we originally opened Badger to science users, we described it as a 798 Teraflop machine. For nearly a decade, it was a workhorse for our scientists.

It's crucial to put this in context. Today's top HPC systems are being tested at over an Exaflop—thousands of Teraflops. The bottom system on the Top500 list from early 2024 exceeds twice the speed of Badger, and low-latency interconnects surpass eight times the speed of OmniPath. Moreover, improvements in chip design allow us to achieve the same computing power with dramatically lower energy consumption.

### How OpenCHAMI Works

OpenCHAMI is a set of containerized microservices that cooperate to manage the hardware of an HPC system.  The microservices don't exist in isolation.  They rely on external services for things like authentication and certificate management.  As an admin, you interact with all the microservices and dependencies as a single solution, commonly through a CLI that makes HTTP calls to the microservices.

In this series, we'll explore how we used the microservices and our cli to boot all 640 nodes quickly and securely. We'll cover the technical decisions we made, from deployment strategies to authentication methods, all designed to make OpenCHAMI a viable replacement for traditional HPC management systems like xCAT or CSM.

Stay tuned for Part 2, where we dive into the deployment process in detail and explain how we set everything up for maximum efficiency.
