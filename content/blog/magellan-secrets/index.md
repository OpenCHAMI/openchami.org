---
title: "Storing BMC Credentails with Magellan"
description: "A new feature added to OpenCHAMI Magellan that makes BMC login easier, efficient, and secure."
date: 2025-03-24T00:00:00+00:00
lastmod: 2025-03-24T00:00:00+00:00
draft: false
weight: 10
categories: ["Security", "HPC", "Magellan"]
tags: ["Magellan", "BMC Discovery", "Inventory", "Secrets"]
contributors: ["David J. Allen"]
---

# Storing BMC Credentials with Magellan

As of the [v0.20](https://github.com/OpenCHAMI/magellan/releases/tag/v0.2.0) release, it's now possible to store BMC credentials in an encrypted local secret store using the new `secrets` command. This is incredibly useful when you're trying to access multiple BMC nodes that might have different usernames and passwords without having to specify each one every single time. Nothing is stored in plain-text other than the `secretID` key in a file, but retrieving secret values *always* require the exact same key used to store the secret. 

This post will provide a quick rundown about this new feature, how to use it, and some of the considerations taken into account with its implementation.

## How does it work?

The secret store is built from a `SecretStore` interface with two separate implementations: a `StaticStore` and a `LocalSecretStore`. 

The `StaticStore` maintains the original behavior of `magellan` prior to the new feature being added via the `--username/--password` flags. The `LocalSecretStore` encrypts the password using the `MASTER_KEY` and stores it to a file. Both are now being used implicitly whenever a `collect` or a `crawl` is executed.

Furthermore, the `SecretStore` interface allows us to create new (and possibly better) implementations in the future if needed.

### Typical Workflow using the Secret Store

The typical `magellan` workflow might look something like this:

1. Perform a `scan` to find BMC nodes on network

2. Run a `collect` or `crawl` to gather inventory information providing the login credentials for the BMC nodes

However, as stated above, the BMC nodes may have different login credentials. Therefore, the workflow with the secrets store would have a few extra steps:

1. Perform a `scan` to find BMC nodes on network
   
   ```bash
   magellan scan --subnet 172.16.0.0 --subnet-mask 255.255.255.0
   ```

2. Generate and set the `MASTER_KEY` environment variable using the new `secrets generatekey` command
   
   ```bash
   export MASTER_KEY=$(magellan secrets generatekey)
   ```

3. Inspect the BMC nodes found from the `scan` using the `list` command
   
   ```bash
   magellan list
   ```

4. Store secrets for the BMC nodes listed by the `list` command using `secrets store` command (host must be EXACT!)
   
   ```bash
   magellan secrets store https://172.16.0.101:443 $bmc_username:$bmc_password
   ```

5. Run a `collect` or `crawl` to gather inventory information providing the login credentials for the BMC nodes
   
   ```bash
   magellan crawl https://172.16.0.101:443 -i
   magellan collect \
     --username $default_bmc_username \
     --password $default_bmc_password \
     --host https://smd.openchami.cluster \
     --cacert ochami.pem
   ```

Some of the new `secrets` sub-commands are omitted here for brevity, but can be viewed with `magellan secrets --help`. Note that in step 5, both the `--username` and `--password` flags are still being used like before. If no credential is found for a specific BMC node in the local store, then the provided values for both flags above will be used as a fallback. This allows us to have to original behavior before if all of the BMC nodes have the same login credentials, while also being able to only specify the ones that are different.

## Are my secrets *actually* safe?

The implementation is simple and straight-forward, but it is sufficient for `magellan`. There were a couple of concerns that we wanted to address. 

We obviously did not want to store anything in plain-text, which is *super bad*. The consensus was that the secrets needed to be stored in a way that was undecipherable by anyone without the appropriate key. Right now, this is only done with `magellan secrets retrieve` for a single `secretID` provided.

We also wanted to make sure that we could not access the same store with a different `MASTER_KEY`. Trying to do so will return a cryptographic-related error message:

```bash
Error retrieving secret: cipher: message authentication failed
```

The file itself can always be protected using permissions and such so there wasn't anything to do there. And since there's no server/daemon running, there's no need to worry too much about extracting secrets remotely...*for now*.

## What's Next?

The current implementation of the secret store works and is needed for some other experimental features for another project (maybe another blog post soonish). In the future, however, we may want to investigate measures to prevent exfiltration of secrets if we decide to turn `magellan` into a micro-service.


