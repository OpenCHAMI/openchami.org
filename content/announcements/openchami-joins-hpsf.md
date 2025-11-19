+++
title = 'OpenCHAMI Joins the High Performance Software Foundation'
date = 2025-04-10
draft = false
categories = ['Announcement', 'Partnership']
contributors = ['Travis Cotton']
+++

We're pleased to announce that **OpenCHAMI has joined the High Performance Software Foundation (HPSF)**. The consortium that formed to steward OpenCHAMI believes in a broad coalition of developers and operators who support each other to improve the overall state of the HPC industry. By joining the HPSF, we activate an even larger community and are able to share tools and techniques with other open source projects in pursuit of our collaboration goals.

## About OpenCHAMI

OpenCHAMI is a cloud-like HPC provisioning and management toolkit for on-premise HPC systems. The core components of OpenCHAMI provide composable microservices that tailor provisioning and boot operations of each HPC node based on needs of the users, even when those needs are different across the same cluster. While it has been used on large, multi-row HPC systems, all the complexity is opt-in. Admins with only a few nodes can be up and running in less than five minutes with the same security levels and the exact same APIs available at full Supercomputer scale.

## Recent Highlights

The OpenCHAMI project is still young, having not yet achieved a 1.0 release. However, the team at Los Alamos National Laboratory (LANL) successfully integrated the first production OpenCHAMI cluster in February of 2025. This system, with hardware from Dell and NVIDIA, will be part of LANL's Institutional Commitment to AI and will rely on OpenCHAMI to perform with high availability and reliability.

OpenCHAMI is designed with flexibility in mind, allowing each deployment to be extensively customized without committing all users to the same feature set. As an example, one site focused on reducing boot times and simplifying management overhead. They focused on extensions to the OpenCHAMI cloud-init metadata server, which allowed them to remove Ansible plays from the boot process. Initial tests show an improvement from over eight minutes to boot a 650 node cluster to roughly 40 seconds, following the hardware Power On Self Test (POST).

## Get Involved

We need your help to use OpenCHAMI as it exists today and offer suggestions on how it should evolve over time.

- [Join us on Slack](https://join.slack.com/t/openchami/shared_invite/zt-2xn9wctqq-tptRqPUeFQtTsENRkrCkBg)
- Review our [open issues](https://github.com/search?q=org%3AOpenCHAMI++&type=issues&s=updated&o=desc&state=open) and [pull requests](https://github.com/search?q=org%3AOpenCHAMI++&type=pullrequests&s=updated&o=desc&state=open)
- Engage with our [RFDs](https://github.com/OpenCHAMI/roadmap/issues?q=is%3Aissue%20state%3Aopen%20label%3Arfd), which inform our overall architecture decisions

**Read the full announcement**: [OpenCHAMI Joins HPSF on the HPSF blog](https://hpsf.io/blog/2025/openchami-joins-hpsf-composable-software-to-securely-and-quickly-provision-hpc-ai-clusters/)

Read more about OpenCHAMI [here](/docs/introduction-to-openchami/) and try it yourself through the [install guide](/guides/getting_started/).
