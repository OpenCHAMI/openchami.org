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

Baseboard Management Controllers (BMCs) are essential for remote hardware management but managing their credentials can pose security risks if not done carefully. With the [v0.20](https://github.com/OpenCHAMI/magellan/releases/tag/v0.2.0) release of Magellan, administrators now have a straightforward and secure solution: the `secrets` command, designed to store encrypted BMC credentials locally, reducing complexity and enhancing safety. This post outlines this new capability, demonstrates typical workflows, and addresses some important implementation and security considerations.

As of the [v0.20](https://github.com/OpenCHAMI/magellan/releases/tag/v0.2.0) release, it's now possible to store BMC credentials in an encrypted local secret store using the new `secrets` command. This is incredibly useful when you're trying to access multiple BMC nodes that might have different usernames and passwords without having to specify each one every single time. 

This post will provide a quick rundown about this new feature, how to use it, and some of the security considerations taken into account with its implementation.

## How does it work?

The secret store is built from a `SecretStore` [interface](https://github.com/OpenCHAMI/magellan/blob/48a53f6d5d5cb6ac6988a17511052678985f8a07/pkg/secrets/main.go#L1-L7) with two separate implementations: a `StaticStore` and a `LocalSecretStore`.  Future implementations could leverage hashicorp vault or other more mature secret stores.

The `StaticStore` maintains the original behavior of `magellan` prior to the new feature being added via the `--username/--password` flags. The `LocalSecretStore` encrypts the password using the `MASTER_KEY` and stores it to a file. Both are now being used implicitly whenever a `collect` or a `crawl` is executed.

Furthermore, the `SecretStore` interface allows us to create new (and possibly better) implementations in the future if needed.

### Classic Workflow for Magellan

The typical `magellan` workflow might look something like this:

1. Perform a `scan` to find BMC nodes on network

2. Run `collect` or `crawl` using a common username/password to gather inventory information providing the login credentials for the BMC nodes


### Magellan Workflow with SecretStore

With SecretStore, the classic workflow is still possible.  The StaticStore implementation responds with the same username and password for all nodes.  It gets more interesting with the LocalStore which allows the admin to securely store a different username and password for each node and use them for the scan.

#### 1. Perform a `scan` to find BMC nodes on network
   
   ```bash
   magellan scan --subnet 172.16.0.0 --subnet-mask 255.255.255.0
   ```

#### 2. Generate and set the `MASTER_KEY` environment variable using the new `secrets generatekey` command
   
   ```bash
   # Using the same MASTER_KEY in the future is essential.  Keep this safe.
   export MASTER_KEY=$(magellan secrets generatekey)
   ```

#### 3. Inspect the BMC nodes found from the `scan` using the `list` command
   
   ```bash
   magellan list
   ```

#### 4. Store secrets for the BMC nodes listed by the `list` command using `secrets store` command (host must be EXACT!)
   
   ```bash
   magellan secrets store https://172.16.0.101:443 $bmc_username:$bmc_password
   ```

#### 5. Run a `collect` or `crawl` to gather inventory information providing the login credentials for the BMC nodes
   
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

The `LocalStore` implementation relies on AES-GCM encryption of each secret using a separate key.  Rather than manually manage a different key for each secret, the keys are generated dynamically and predictably using a procedure called [HKDF](https://en.wikipedia.org/wiki/HKDF) which leverages a 32-bit `MASTER_KEY`.  Without the id of the secret -and- the appropriate id of the secret, the storage file is useless.

The file itself can always be protected using permissions and such so there wasn't anything to do there. And since there's no server/daemon running, there's no need to worry too much about extracting secrets remotely...*for now*.


## What's Next?

With Magellan v0.20, securely managing BMC credentials has become easier and more streamlined. The introduction of the new `secrets` command provides a secure way to store and retrieve encrypted credentials locally, significantly enhancing both usability and security for diverse infrastructures.

Future enhancements may explore additional security layers and support integration with external secret management tools, especially if Magellan evolves into a micro-service architecture.

Your feedback is valuable! If you'd like to contribute ideas, report issues, or request new features, we invite you to [open an issue on GitHub](https://github.com/OpenCHAMI/magellan/issues) or directly submit a pull request.