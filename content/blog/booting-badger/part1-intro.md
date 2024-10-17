---
title: "Booting 640 HPC Nodes in 5 Minutes: An Introduction to OpenCHAMI"
date: 2024-10-17
tags: ["HPC", "OpenCHAMI", "Booting"]
---

Managing HPC systems can often feel rigid and cumbersome. For those curious about applying cloud-like tooling to on-premise clusters, OpenCHAMI presents a compelling alternative to traditional HPC management tools. 

Finding a development environment for HPC tooling can be a significant challenge. Every cycle used for development is a cycle lost to science users. When developers like the team at OpenCHAMI can find dedicated systems, they are usually only a few nodes and often not in production-like environments.

One of the benefits of embedding the OpenCHAMI development team in the day-to-day work of the sysadmins at LANL is the opportunity to work closely with those responsible for decommissioning hardware that has reached the end of its useful life. When we learned that a 660-node cluster was soon to be rolled off the floor, we jumped at the chance to test with it.

**Badger**, an older machine built by Penguin Computing circa 2016, comprises Relion OCP1930e nodes with three servers per shelf, each featuring a pair of Xeon processors in a 1U form factor. This dense configuration results in 96 nodes per rack, totaling just shy of seven racks for Badger's 660 nodes. To connect all these CPUs, Penguin included a 100G OmniPath High-Speed Network. When we originally opened Badger to science users, we described it as a 798 Teraflop machine. For nearly a decade, it was a workhorse for our scientists.

It's crucial to put this in context. Today's top HPC systems are being tested at over an Exaflop—thousands of Teraflops. The bottom system on the Top500 list from early 2024 exceeds twice the speed of Badger, and low-latency interconnects surpass eight times the speed of OmniPath. Moreover, improvements in chip design allow us to achieve the same computing power with dramatically lower energy consumption.

Dealing with dated hardware brought its own challenges to our development process. OpenCHAMI typically relies on probing the Baseboard Management Controllers (BMCs) of all nodes through Redfish. This data is used to build an inventory without accessing the running operating system of the node. However, the BMCs for Badger's nodes do not support Redfish, making this process impossible. OpenCHAMI also includes features for cryptographic assertion and verification of the node states before and after jobs, but without the required TPMs, this feature was not part of our testing.

To compensate for the missing Redfish inventory, we created a manual inventory of nodes, including all the MAC addresses of the interface cards. We opted not to attempt any cryptographic verification on Badger.

In the upcoming parts of this series, we'll delve deeper into how we deployed OpenCHAMI and successfully booted 640 nodes in just five minutes. Stay tuned for Part 2!
