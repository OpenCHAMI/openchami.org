---
title: "SMD: The State Management Daemon"
description: ""
summary: ""
date: 2024-03-21T00:00:00+00:00
lastmod: 2025-02-03T00:00:00+00:00
contributors: ["Alex Lovell-Troy"]
draft: false
weight: 500
toc: true
---

# State Management Daemon

The OpenCHAMI inventory database is a customized version of the State Management Database (SMD) from the Cray System Manager. It manages inventory information about the compute nodes and makes it accessible through an HTTP API that other microservices reference in the course of their work. While it generally serves data from memory, it uses Postgres for persistent storage.
