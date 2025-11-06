---
title: "Add Nodes"
description: ""
summary: "Add Nodes"
date: 2024-04-07T16:04:48+02:00
lastmod: 2024-04-07T16:04:48+02:00
draft: false
weight: 300
toc: true
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

Adding nodes to an OpenCHAMI system can happen through either discovery with [Magellan](/docs/software/magellan) or through manually creating the nodes using the API.  In this tutorial, we'll show you how to manually interact with the API to add one or more nodes to the system.

Regardless of the tool you choose, you'll need access to an OpenCHAMI deployment, a valid token, and the certificate so that your client can verify the connection.

{{< details "Your token and certificate" >}}
The quickstart repository has a set of bash functions for obtaining the certificate and token needed for these examples:
```bash
source bash_functions.sh
get_ca_cert > cacert.pem
ACCESS_TOKEN=$(gen_access_token)
echo $ACCESS_TOKEN
```
{{< /details >}}


## Using curl to read the list of nodes

Curl is a useful tool for interacting with HTTP APIs.  It provides plenty of feedback through flags and allows for extensive customization.  Assiming the system name you've chosen for your cluster is `foobar` and you've updated your `/etc/hosts` file to resolve the url below correctly, you can use curl as described below to verify that your certificates and token are working properly.

```bash
curl --cacert cacert.pem -H "Authorization: Bearer $ACCESS_TOKEN" https://foobar.openchami.cluster/hsm/v2/State/Components
```

### Common errors

1. `curl: (6) Could not resolve host: foobar.openchami.cluster`
    This indicates that your local system cannot match the domain name to the ip address of your installation.  Check your /etc/hosts file and update it if necessary.

1. `token is unauthorized`
   This indicates that something isn't working with the access token in your Authorization header.  First confirm that the header is being specified correctly.  It's imporant that the header matches precisely. `"Authorization: Bearer <token>"` where the token is a very long string.




## Adding nodes with ochami-cmdline

Coming soon!
