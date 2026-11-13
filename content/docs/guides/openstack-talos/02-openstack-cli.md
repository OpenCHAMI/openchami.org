---
title: "§2 — The OpenStack CLI"
description: "Install the openstack command-line interface (CLI), connect it to your project, and sign in with an application credential."
slug: "02-openstack-cli"
date: 2026-10-21
lastmod: 2026-10-21
weight: 20
toc: true
draft: false
---
> ⏱ **About 25 minutes** · on the devbox · creates nothing in the cloud except one application credential
>
> - **What this chapter is for.** Every later chapter drives OpenStack through the `openstack` command-line interface (CLI). This chapter installs the CLI, connects it to your project, and signs it in with a credential scoped solely to this tutorial.
>
> - **What you will learn.** How the CLI authenticates, the two ways to point it at your cloud, how to issue and use a token directly, and how to verify that your cloud's services are reachable.
>
> - **Skip it if** `~/.config/openstack/clouds.yaml` already has an `ochami-lab` entry holding an application credential for your project. Go straight to the [checkpoint](#-checkpoint). If your CLI works but you sign in with a password, complete Steps 2.5 and 2.6.

The *devbox* is whatever machine you run the CLI from: your laptop, a jump host, or a disposable VM.

---

## Introduction

In this chapter, you will install the OpenStack CLI and configure it using the files from Horizon (OpenStack's web dashboard). You will then use the CLI to issue a token from **Keystone**, test the API, and create a project-scoped application credential for the rest of the tutorial.

📌 The OpenStack documentation covers each of these topics in more depth. If a step here doesn't match what your cloud shows you, check there first:

- [OpenStackClient](https://docs.openstack.org/python-openstackclient/latest/): installing and using the `openstack` command.

- [OpenStackClient authentication](https://docs.openstack.org/python-openstackclient/latest/cli/authentication.html): how the CLI authenticates, and the `OS_*` variables.

- [Configuring OpenStack SDK applications](https://docs.openstack.org/openstacksdk/latest/user/config/configuration.html): the `clouds.yaml` format and where the CLI looks for it.

- [Keystone architecture](https://docs.openstack.org/keystone/latest/getting-started/architecture.html): users, projects, roles, tokens and the service catalog.

- [Application credentials](https://docs.openstack.org/keystone/latest/user/application_credentials.html): creating, restricting and revoking them.

- [OpenStack Dashboard user documentation](https://docs.openstack.org/horizon/latest/user/index.html): using Horizon.

---

## Step 2.1 — Install the CLI

The CLI is distributed as the `python-openstackclient` Python package. Install it inside a virtual environment so it stays isolated from your system Python:

```
devbox$ python3 -m venv --upgrade-deps --prompt openstack ~/os-venv
devbox$ ~/os-venv/bin/pip install python-openstackclient
devbox$ source ~/os-venv/bin/activate
devbox$ openstack --version
```

The last command prints the client version — note it down in case you need help later.

Sourcing the `activate` script adds `openstack` to your `PATH` and prefixes your shell prompt with `(openstack)`. You will need to run that `source` command in each new terminal session. Note that the `(openstack)` prefix only tells you the virtual environment is active, not whether you are authenticated.

📌 On Debian and Ubuntu, `python3 -m venv` will fail until you install the `python3-venv` package.

---

## Step 2.2 — Point the CLI at your cloud

Your cloud's Horizon dashboard offers two configuration downloads under **Project → API Access**. Either option works for Steps 2.3 and 2.4, and Step 2.6 will move you onto `clouds.yaml` for the rest of the tutorial.

🛑 **Use one method or the other in a shell, never both.** Rather than picking one, the CLI merges `OS_*` environment variables on top of `clouds.yaml`, which produces confusing authentication errors (see Common failures).

### Option A — the RC file

Choose **Download OpenStack RC File**, then source it:

```
devbox$ source ~/openrc.sh
Please enter your OpenStack Password for project ochami-lab as user alice:
```

The script exports your Keystone URL, username and project as `OS_*` environment variables, then prompts for your password and stores it in `OS_PASSWORD`. (Horizon names the file after your project; we call it `~/openrc.sh` here.) Every `openstack` command in that shell now uses those settings. If you open a new terminal, you will need to source the file again.

Avoid adding `openrc.sh` to `~/.bashrc`: every new shell would pause at the password prompt, which breaks non-interactive tools like `scp`, `ansible` and `tofu`.

### Option B — `clouds.yaml`

Choose **Download clouds.yaml**. This file holds named connection profiles (called *clouds*), and Horizon's download provides one containing your Keystone URL, username and project, without your password. The profile name is just a local nickname on your machine — not your project name or username. Move the file to where the CLI expects it and restrict its permissions:

```
devbox$ mkdir -p ~/.config/openstack
devbox$ mv ~/Downloads/clouds.yaml ~/.config/openstack/clouds.yaml
devbox$ chmod 600 ~/.config/openstack/clouds.yaml
```

⚠ **Horizon names the entry `openstack`.** Keep that name for now, as Step 2.6 will replace this file. Horizon sometimes omits `interface: public`; add it if it is missing.

Then pass the profile name on each command:

```
devbox$ openstack --os-cloud openstack token issue
```

Because there is no password in the file, the CLI prompts for it on every command.

### No Horizon?

If your cloud doesn't use Horizon, ask your cloud administrator for these three values:

| Value | Where to get it | Example |
|---|---|---|
| `auth_url` | Horizon → **Project → API Access**, the **Identity** row, with `/v3` appended (or `OS_AUTH_URL` in the RC file) | `https://keystone.cloud.example.org:5000/v3` |
| `region_name` | `OS_REGION_NAME` in the RC file, or `openstack region list` once you can authenticate | `RegionOne` |
| Project ID | The project selector in Horizon's header, or `openstack token issue` below | `3f2a9c1e5b7d4a8e9f0c1b2d3e4f5a6b` |

---

## Step 2.3 — Get a token

Every `openstack` command exchanges your credentials for a short-lived token behind the scenes. Running `openstack token issue` performs that exchange explicitly and shows you the result:

```
devbox$ openstack token issue
```

It prints four fields:

| Field | What it is |
|---|---|
| `id` | The token string itself. Anyone holding it can act as you until it expires, so treat it like a password |
| `expires` | When the token stops working |
| `project_id` | The project the token is scoped to, which determines where your commands take effect |
| `user_id` | Your user ID |

Even if your account belongs to several projects (`openstack project list`), any single token is only ever scoped to one project.

Once you have a token, the other OpenStack services need nothing else. Store one in a variable so you can test the API directly in Step 2.4:

```
devbox$ TOKEN=$(openstack token issue -c id -f value)
```

When you are finished with it, you can invalidate it early with `openstack token revoke "$TOKEN"`.

---

## Step 2.4 — Check the cloud answers

First, ask Keystone for the service catalog. This confirms that authentication works and lists the endpoint URLs for every service in your cloud:

```
devbox$ openstack catalog list
```

Each service lists URLs for each region and network interface; `region_name` and `interface: public` in your config tell the CLI which URL to pick. You should see a table with rows for `keystone`, `nova`, `neutron`, `glance` and other services.

Next, query Keystone directly with `curl` to see the underlying HTTP API in action. Set `KEYSTONE` to your `auth_url` without the trailing `/v3`:

```
devbox$ KEYSTONE=https://keystone.cloud.example.org:5000
devbox$ curl -s "$KEYSTONE/v3"
devbox$ curl -s -H "X-Auth-Token: $TOKEN" "$KEYSTONE/v3/auth/projects"
```

The first call requires no token and returns a short JSON description of the v3 API, confirming that your machine can reach Keystone and trusts its TLS certificate. The second call passes your token in the `X-Auth-Token` header — the exact header the CLI sends on every request — and lists the projects you can access.

Finally, run one read-only command against Nova, Neutron and Glance to confirm that their endpoints are reachable from your machine too:

```
devbox$ openstack server list
devbox$ openstack network list
devbox$ openstack image list
```

An empty table means the service answered cleanly. If a call fails, the error message will name the service that couldn't be reached.

---

## Step 2.5 — Create an application credential

An application credential is an ID and secret pair that lets tools authenticate as you without using your password. It is locked to a single project and can be revoked at any time. Check your active project ID first, since the new credential will inherit it:

```
devbox$ openstack token issue -c project_id -f value        # must be our project
devbox$ openstack application credential create \
    --description "OpenCHAMI lab, expires 2026-12-31" \
    --expiration 2026-12-31T00:00:00 \
    och-ochami-proto
```

Copy the `id` and `secret` immediately. **The secret is displayed only once** and cannot be retrieved later — if you lose it, delete the credential and create a new one.

You can also create one in Horizon under **Identity → Application Credentials → Create Application Credential**, which offers a ready-made **Download clouds.yaml** button on the confirmation screen.

Three properties make an application credential ideal for the rest of this tutorial:

| Property | What it means |
|---|---|
| **It acts with your permissions** | It can do what your account can do inside this project, and nothing outside it |
| **It is bound to one project** | It is locked to the project you were scoped to when you created it, and cannot be pointed at another project |
| **It cannot create further credentials** | `unrestricted` is `false` by default, so a leaked secret cannot be used to mint additional credentials |

Passing `--expiration` ensures that a forgotten credential eventually expires on its own.

---

## Step 2.6 — The final `clouds.yaml`, and changing scope

Your final configuration is a single `ochami-lab` entry in `~/.config/openstack/clouds.yaml` holding your application credential. Everything in the rest of the tutorial runs through this profile:

```yaml
clouds:
  ochami-lab:                                    # ← §§4-21, and ALL automation
    auth_type: v3applicationcredential
    auth:
      auth_url: https://keystone.cloud.example.org:5000
      application_credential_id: <ID_FROM_§2.5>
      application_credential_secret: <SECRET_FROM_§2.5>
    region_name: "RegionOne"
    interface: "public"
    identity_api_version: 3
```

Replace `<ID_FROM_§2.5>` and `<SECRET_FROM_§2.5>` with the `id` and `secret` from Step 2.5. A ready-to-edit copy lives in [`templates/clouds.yaml.example`](templates/clouds.yaml.example). (If you downloaded `clouds.yaml` in Option B, grab your `auth_url` from it before overwriting it.)

```
devbox$ mkdir -p ~/.config/openstack
devbox$ cp clouds.yaml.example ~/.config/openstack/clouds.yaml
devbox$ chmod 600 ~/.config/openstack/clouds.yaml
devbox$ echo 'export OS_CLOUD=ochami-lab' >> ~/.bashrc && export OS_CLOUD=ochami-lab
```

Keep the profile name `ochami-lab`, because `templates/och-vars-env.sh` expects that name.

⚠ **Don't leave any `<…>` placeholders in the file.** If you don't know your cloud's region name yet, delete the `region_name` line — on a single-region cloud, the CLI will pick the only region automatically, whereas a literal `<REGION>` will cause every command to fail.

**Changing scope.** Both tokens and application credentials are always scoped to a single project. If you need to work in another project, add another profile to `clouds.yaml` and select it per command:

```
devbox$ openstack --os-cloud <OTHER_ENTRY> server list
```

Passing `--os-cloud` on a single command is safer than exporting a new `OS_CLOUD`, since there is nothing to remember to switch back. Because an application credential cannot be re-scoped, create one per project if you work across multiple projects.

You can verify what settings the CLI is using with:

```
devbox$ openstack configuration show | grep -vi 'secret\|password'      # before pasting
```

🛑 **Always filter `configuration show` before sharing its output.** While it masks `auth.password`, it prints `auth.application_credential_secret` in plain text. If you paste that secret anywhere, revoke the credential immediately and create a new one.

---

## ✅ Checkpoint

Open a fresh shell so no `OS_*` variables from `openrc.sh` remain in your environment, then run:

```
devbox$ env | grep '^OS_'          # must print exactly one line: OS_CLOUD=ochami-lab
devbox$ openstack token issue -c project_id -c expires -f value
```

The project ID printed must be **yours**:

```
3f2a9c1e5b7d4a8e9f0c1b2d3e4f5a6b
2026-07-26T14:32:11+0000
```

If you see any other project ID, stop here — your credential is scoped to the wrong project, and you should recreate it before running any commands in later chapters.

---

## Common failures

| Symptom | Cause / fix |
|---|---|
| `python3: No module named venv`, or `ensurepip is not available` | Debian or Ubuntu without the `python3-venv` package. Install it and rerun Step 2.1 |
| `openstack: command not found` | The virtualenv isn't active in this shell. Run `source ~/os-venv/bin/activate` |
| `Cloud ochami-lab was not found` | `OS_CLOUD` names an entry that isn't in any `clouds.yaml` the CLI can find. Remember that the cloud name is a local nickname in `clouds.yaml`, not your project name. List existing profiles with `python3 -c 'import openstack.config as c; print("\n".join(sorted(c.OpenStackConfig().get_cloud_names())))'`, then make `OS_CLOUD` and the file match (Horizon's default profile name is `openstack`) |
| The same error from every command, including ones with obvious typos | Expected when `OS_CLOUD` is invalid — the CLI looks up the cloud profile before parsing the rest of the command. Fix `OS_CLOUD` and the real error will appear |
| `Region RegionOne is not a valid region name for cloud ochami-lab. Valid choices are <REGION>` | `clouds.yaml` still contains the literal `<REGION>` placeholder. Set `region_name: RegionOne`, or delete the line |
| `Application credentials cannot request a scope. (HTTP 401)` | Your `clouds.yaml` entry or shell environment also specifies a project. Because an application credential carries its own scope, remove `username`, `project_id`, `project_name`, `user_domain_name`, `project_domain_name` and `password` from its entry, and check `env \| grep '^OS_'` |
| Auth errors mentioning a username, password or project you didn't put in `clouds.yaml` | An RC file was sourced in the same shell. Open a fresh shell, or clear the variables with `for v in $(env \| sed -n 's/^\(OS_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done` followed by `export OS_CLOUD=ochami-lab` |
| `The request you have made requires authentication` | `OS_CLOUD` is unset, `clouds.yaml` is not at `~/.config/openstack/clouds.yaml`, or a password was mistyped. From `curl`, this means your token is missing or expired — issue a fresh one |
| `Could not find requested endpoint` / connection timeout | Your machine cannot reach the Keystone URL. If your cloud sits behind a VPN, make sure it is connected |
| `catalog list` works, but one service in Step 2.4 times out | Keystone is reachable, but that service's endpoint URL isn't. Check the URL in `openstack catalog list` and ask your cloud administrator whether it requires a VPN or specific network route |
| `You are not authorized to perform the requested action` | Your account lacks permission for that command (flavor creation in §3 is the most common example). Ask your administrator to run it or grant the permission |
| `openstack token issue` shows a different project | The application credential was created while your shell was scoped to another project. Delete it and repeat Step 2.5 from the right project |

Next: [§3 — OpenStack project configuration](03-openstack-project.md)
