+++
title = 'Turnkey OpenCHAMI for the Supercomputer Institute'
date = 2024-01-24T10:24:44-05:00
draft = false
contributors = ["Alex Lovell-Troy"]
+++

## OpenCHAMI for the Supercomputer Institute
At Los Alamos National Laboratory, we're on the brink of launching a turnkey version of OpenCHAMI, specifically tailored for summer intern teams at the Supercomputer Institute. This initiative underscores our commitment to fostering the collaborative development of HPC (High-Performance Computing) systems with cloud-like management capabilities. This post will explore our motivations for this project, detail the features we've chosen to include (and exclude), and discuss the impact of these decisions on OpenCHAMI's evolution.

## The Supercomputer Institute at Los Alamos
We are proud to offer an 11-week paid internship at Los Alamos National Laboratory, aimed at introducing students from diverse backgrounds to HPC techniques and practices. Beginning in May 2024, the program includes a two-week boot camp designed to equip students with the skills necessary to construct and manage HPC clusters, regardless of their previous experience or academic background.

Learn more at [Los Alamos National Laboratory's website](https://www.lanl.gov/projects/national-security-education-center/information-science-technology/summer-schools/cscnsi/index.php).

## Boot Camp Overview
The boot camp, led by experienced sysadmins from our HPC group, covers everything from managing HPC hardware to assembling functional clusters capable of running HPC jobs with Slurm. With a curriculum that evolves yearly, we emphasize hands-on manual operations before progressing to automation, ensuring students gain a solid understanding of HPC system components.

## OpenCHAMI: The SI Tool of Choice
At the [Supercomputing Conference in 2023](https://github.com/OpenCHAMI/lanl-demo-sc23), we showcased how OpenCHAMI could manage a small HPC cluster, using hardware identical to what's found in the Supercomputer Institute (SI). This demonstration not only highlighted OpenCHAMI's potential as a teaching tool but also confirmed our belief in the educational value of exposing students to core system management protocols and modern computing concepts.

Despite the success of our demonstration, we recognize the need for further simplification to make OpenCHAMI more accessible and user-friendly for intern teams. Our aim is to enhance ease of use, speed, and safety in the coming months.

## Prioritizing Our Users: Documentation and Extensibility
Feedback from our demonstration highlighted a need for better documentation. Teams eager to replicate our setup encountered challenges with customization due to limited access to microservice settings and complex system interfaces. This feedback has been invaluable, prompting us to focus on enhancing documentation and system extensibility to support the SI's educational goals.

The SI's blend of novice users and expert mentors will create an environment where "all bugs are shallow," facilitating rapid learning and system improvement.

## The Road to SI
Our development team is diligently updating our [GitHub Roadmap](https://github.com/orgs/OpenCHAMI/projects/1), focusing on simplifying OpenCHAMI deployment for the SI, enhancing the instruction manual, and improving microservices usability.

## OpenCHAMI Deployment Recipe for SI
As we prepare each student to manage their own cluster — complete with a dedicated head node and several compute nodes, all isolated within the network — we are focusing on a deployment strategy that simplifies the process while maintaining robust functionality. Based on our experiences and the feedback received, we aim to consolidate services using docker-compose for ease of management and scalability. Here are some example core components that may be part of the OpenCHAMI deployment recipe:

* *[SMD (State Management Database)](https://github.com/OpenCHAMI/smd)*: Our cornerstone for inventory management, crucial for maintaining an updated view of system states.
* *[BSS (Bootscript Service)](https://github.com/OpenCHAMI/bss)*: A customizable bootscript generator, enabling precise control over the booting process of nodes.
* *[Cloud-Init](https://github.com/OpenCHAMI/cloud-init)*: Our implementation enhances node initialization with custom configurations, working seamlessly with SMD and BSS.
* *[KrakenD-CE](https://github.com/krakend/krakend-ce)*: An open-source API Gateway that facilitates request/response manipulation and integrates JWT protections, ensuring secure and flexible API management.
* *[Hydra](https://github.com/ory/hydra)*: A reliable OIDC provider for issuing JWTs, enhancing the security and scalability of authentication processes.
* *[coredhcp](https://github.com/coredhcp/coredhcp)*: A plugin-based DHCP server that dynamically responds to network configuration requests, guided by the system's source of truth.
* *nfs4 server*: An as yet undecided NFSv4 Server that can be managed through our virsh or docker-compose environments.

*NB* Ochami is designed to be moduar and each service listed provides some level of functionality.  If we can achieve the same goal with a different component, we'll swtich it up.  Based on discussion in our [issues](https://github.com/OpenCHAMI/deployment-recipes/issues/3), we may be switching to dnsmasq for dhcp services in SI while preserving the option for coredhcp or other solutions in the future.  You can follow our discussion about what to include and what to exclude in our [roadmap issue](https://github.com/OpenCHAMI/roadmap/issues/21). 

By incorporating these components into our docker-compose files, we ensure that each cluster is equipped with the necessary services to operate efficiently and securely. This approach not only streamlines the deployment process but also provides a modular and flexible framework for managing HPC clusters.

## Conclusion
The Turnkey OpenCHAMI project for the Supercomputer Institute marks a significant advance in HPC education and collaborative development. By addressing essential feedback and focusing on user-centric improvements, we're not only enhancing OpenCHAMI but also enriching the educational journey for future HPC professionals. As we progress, we look forward to the innovative contributions this initiative will spark, furthering our mission to democratize high-performance computing.

## Join Us!
Engage with us on [GitHub](https://www.github.com/openchami), [Slack](https://openchami.slack.com), or through our [Contact Page](/contact/) to be part of this exciting journey.