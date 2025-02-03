---
title: "Design Philosophy"
date: 2024-04-07T16:12:03+02:00
lastmod: 2024-04-07T16:12:03+02:00
draft: false
weight: 40
toc: true
pinned: false
homepage: false
---
{{< callout context="note" title="Service Philosophy" icon="file-certificate" >}}
## OpenCHAMI services tend to:

* be HTTPS Microservices
* run as containers 
* be configured at runtime through flags and environment variables
* be based on go 1.21 and the wolfi base containers from chainguard
* leverage bearer tokens for decentralized authentication and authorization
* use go-chi with its robust middleware support
{{< /callout >}}

The OpenCHAMI archtectural concepts share a lot with the original UNIX concepts.  Tools should do one thing well and provide useful inputs and outputs to interoperate with other tools.

## Cloud Design Patterns

The UNIX philosophy remains core to most sofware development and is as relevant today to containerized microservices as it was for `sed` and `awk` in their early incarnations.  The technologies and design patterns available today are different and so the expressions are different of those concepts are different.

### The single container pattern

Like the first principle of UNIX philosophy, a program should do one thing and do it well.  In microservice development, each container should do one thing and do it well.  That means separating the long-running services, like web servers, from the scripts that are used to support those long running services.  This shifts the focus away from trying to containerize all aspects of an operation in one container and instead focuses on externalizing communication and configuration of services.

## Container inputs and outputs

If the first principle is to do one thing well which can be implemented with a single container or runtime, we need to follow up with a second design pattern to address the useful inputs and outputs.  In the UNIX world, pipes and text files are ubiquitous, but those both have some drawbacks in distributed systems that may evolve at different rates over time.  Modern containerized development extends the philosophy with practical tools to improve the speed and reliablity of development in an inherently distributed system.

Use structured data where possible.  Text processing is expensive and brittle.  Updates to the way one tool produces text need to be mirrored in any tools that consume text.  Structured data is much more forgiving.  When a program produces `yaml` or `json` data instead of plain text, other tools that interact with it can target the  data rather than the program itself.  This "loose coupling" between the program that produces the data and the program that reads it allows both programs to evolve at different speeds while remaining interoperable.

### The Sidecar Pattern

In containerized development, a sidecar is a container that operates in support of another container.  For example, if a program needs to re-read a configuration file as it changes, it is common to have a sidecar responsible for the update of that configuration file.  In this example, it is also common for the sidecar to signal the main container/process when a reload is necessary.  Keep in mind that many programs designed to operate in containers tend to avoid configuration files alltogether.

To use a concrete

### Runtime Configuration


* REST
* TLS
* JWT
* json/yaml
