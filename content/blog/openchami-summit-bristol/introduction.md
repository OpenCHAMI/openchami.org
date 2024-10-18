---
title: "Re-Introducing OpenCHAMI"
date: 2024-10-01
draft: false
contributors: ["Alex Lovell-Troy"]
---

The first presentation of the summit was Alex Lovell-Troy's review of what OpenCHAMI is and how it came to be.

{{<youtube ROZA9l5JC2A>}}

## What is OpenCHAMI?

OpenCHAMI is an independent partnership formed by large-scale HPC operators and vendors worldwide. It started about a year ago, with our official announcement coming in November after lengthy preparation. One of our goals was to ensure this partnership was international and not tied to any single country, institution, or site.

At the heart of OpenCHAMI’s origins are over 344 repositories of Cray-HPE’s microservices and APIs, open-sourced under the MIT license. However, rather than adopt all these components wholesale, we’re selectively integrating only what we need to keep things lean. Currently, only two to three of these repositories are in active use.

Our mission emphasizes operator-driven development. We want those who run HPC systems to shape how they’re managed, rather than developers who haven’t directly experienced HPC challenges.

### Community and Governance

OpenCHAMI is governed openly, inspired by standards used by many open-source projects, such as the Linux Foundation. We’ve documented our governance model, and you can find it on our GitHub. Although we haven’t had many situations that require governance intervention, it’s set up to ensure equitable management.

Our board, formed at Supercomputing ‘23, consists of representatives from each of the founding partners. We also established a Technical Steering Committee (TSC), responsible for the project’s direction. While much of the work has been driven by our team at Los Alamos, we’re actively seeking broader community input to shape OpenCHAMI’s future.

## OpenCHAMI’s Mission

Our mission focuses on building software guided by the needs of system operators. It’s essential that those who use the tools are the ones guiding their creation. Additionally, we aim to foster a community that is more valuable than the software itself. This means our goal isn’t just to develop software but to build a network of like-minded individuals interested in running HPC systems effectively.

### Key Principles of OpenCHAMI

	1.	Composable: Sites have different requirements, so OpenCHAMI is built to be composed of various tools that can be adapted based on need. There’s no “one right way” to deploy it. We support Docker Compose, Podman, Kubernetes Helm charts, and more, allowing flexibility for different environments.
	2.	Heterogeneous: We want to manage diverse systems, whether that’s a mix of ARM and x86 nodes or varying combinations of accelerators. Future systems will be a mix of different hardware, and we aim to handle them all seamlessly.
	3.	Adaptable: OpenCHAMI is built to scale, whether managing a small cluster or thousands of nodes. We’ve successfully deployed it on both compact switches and larger node clusters, showcasing its flexibility.
	4.	Management Interface: One of our main goals is to present a cohesive management interface to sysadmins. From understanding what nodes are present to verifying configurations, we aim to create a consistent and reliable user experience.
	5.	Cryptographic Certainty: Secure and tamper-proof systems are a core focus. We prioritize cryptographic verification to ensure supply chain integrity and trustworthiness in HPC environments.

## Current State of OpenCHAMI

Today, OpenCHAMI consists of several core services:

	1.	SMD (State Management Database): Our inventory system tracks components down to each field-replaceable unit, though currently, we’re only focusing on nodes.
	2.	BSS (Boot Script Service): Provides customized boot parameters for each node, enabling flexible booting processes based on the inventory database.
	3.	Cloud-Init Server: We extracted this from BSS to have more control over node-specific configuration. This allows us to provide metadata to nodes for post-boot actions, reducing the need for more complex tooling like Ansible.

Our stack includes several off-the-shelf components like Smallstep CA for certificate management and DNSMasq for DNS and DHCP services. However, we’re planning improvements, including finding alternatives for DNSMasq to enhance performance.

## Where Are We Going?

In our year-long journey, we’ve progressed from initial conception to a working model deployed at various scales, including a 640-node cluster at Los Alamos. Moving forward, we’re exploring how to:

	•	Adapt OpenCHAMI for diverse environments, potentially moving some services to the cloud.
	•	Introduce more nuanced network and power management capabilities.
	•	Further integrate security measures such as cryptographic certainty for supply chain integrity.

## Get Involved

Our GitHub repositories are open for exploration. You can check out our roadmap, contribute to discussions, and even try out our Quick Start, which provides a running system in under 90 seconds. We’re eager to receive feedback, hear about your experiences, and understand how OpenCHAMI can serve your HPC needs.

## Next Steps

This overview provides a glimpse into what OpenCHAMI is and where we’re headed. In upcoming posts and discussions, we’ll delve deeper into various aspects like cloud integration, hardware management boundaries, and security considerations.

Feel free to explore our resources and join the conversation as we shape the future of open-source HPC management together.