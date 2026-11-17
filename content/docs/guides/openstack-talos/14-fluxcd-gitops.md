---
title: "§14 — GitOps with FluxCD"
description: "Hand the cluster's software over to Git. FluxCD applies whatever you commit to one repository, infrastructure before apps."
slug: "14-fluxcd-gitops"
date: 2026-10-21
lastmod: 2026-10-21
weight: 140
toc: true
draft: false
---
> ⏱ **About 25 minutes** · on the head node · creates a Git repository, installs Flux into the cluster and lays out the repository
>
> - **What this chapter is for.** You hand the cluster's software over to Git. You finish with Flux applying whatever you commit to one repository, with infrastructure always applied before apps.
>
> - **What you will learn.** Why a Git repository is a better record of an experiment than a shell history, how Flux authenticates to GitHub, and how `dependsOn` orders what gets applied.
>
> - **Don't skip it.** §§15–17 install everything through this repository. Without Flux, you would type each of those installs by hand, and again after every rebuild.

---

## Introduction

### A commit is the record of what ran

On an experiment rig, the question that matters afterwards is "what was deployed when we took that measurement?" A rig like this is for plugging, playing and tweaking. You try an inference engine, swap a scheduler, add an accelerator, measure and repeat. If you do that with `kubectl apply`, nothing records what was running at the time.

GitOps fixes that. A controller in the cluster keeps comparing the cluster with a Git repository, and makes the cluster match. So:

- **The repository is the record of what ran**, with history and authors.

- **A change is a commit**, so undoing an experiment is `git revert`.

- **Rebuilding the cluster from scratch restores the whole software stack** with one bootstrap command. §12.7 makes rebuilding cheap.

- **Moving to real hardware is pointing Flux at the same repository** from the new cluster.

The last point matters most: §§15–17 could all be done with manual `helm install` commands, but then you would have to remember every install and repeat it by hand on real hardware. With Flux, those installs live as declarative files in Git.

### Flux, rather than Argo CD

Either would work. We use Flux because it is driven from the command line, like the rest of this tutorial. It also has no web interface to expose and secure on an isolated network. Argo CD is the better choice if a team wants a dashboard.

### Flux starts where Kubernetes starts

Flux manages only what lives inside Kubernetes. The OpenStack resources, the OpenCHAMI control plane and the Talos nodes are all *below* Kubernetes, so Flux can't manage them. That is a job for tools such as OpenTofu and Ansible. Flux owns everything from §13 upward, and the boundary is exactly the Kubernetes API.

### What you will do

- **Make a repository, and choose how Flux logs in to it** (Step 14.1). Then check the nodes can reach your Git host.

- **Install the `flux` command-line tool, pinned to one version** (Step 14.2), and check the cluster is ready for it.

- **Bootstrap Flux** (Step 14.3). It installs its controllers and commits their manifests to your repository.

- **Lay out the repository** (Step 14.4), with two Kustomizations that apply infrastructure before apps.

- **Check all three Kustomizations reconcile the same commit** (the checkpoint).

📌 The Flux documentation goes into more detail:

- [The Flux documentation](https://fluxcd.io/flux/), for bootstrap, Kustomizations and `dependsOn`.

- [Flux releases on GitHub](https://github.com/fluxcd/flux2/releases), where Step 14.2 downloads from.

---

## Step 14.1 — A repository

Flux needs a Git repository it can read *and* write, because it commits its own manifests during bootstrap. Create an empty `ochami-lab-flux` on GitHub or GitLab.

⚠ **Treat this repository as public, even if it is private.** Nothing secret goes in it. Step 14.4 covers how to handle secrets instead.

Set up Git on the head node, which has never used it. A missing identity fails late, after you have done real work:

```
head$ git config --global user.name  "Your Name"
head$ git config --global user.email "you@example.com"
```

🛑 **Without these, Step 14.4's `git commit` fails** with `Please tell me who you are`. That happens *after* you have written four files. Nothing is lost, but it interrupts the step where a mangled paste is most likely.

### Choosing how Flux authenticates

Flux needs a credential to clone and push. There are three ways to authenticate—check your organisation's policy before starting so you don't hit a restriction halfway through bootstrap:

| Method | Flux command | What it needs |
|---|---|---|
| **SSH deploy key** | `flux bootstrap git` | A key added to the repo with write access. Never calls the provider's API |
| **Fine-grained PAT** | `flux bootstrap github` | Contents *and* Administration read/write; the org may need to approve it |
| **Classic PAT** | `flux bootstrap github` | `repo` scope |

A PAT is a personal access token.

🛑 **Check your organisation's policy first.** Organisations often close off both easy routes. A GitHub organisation can refuse classic PATs that live longer than 7 days, and can turn off deploy keys altogether. GitHub Apps are what it usually recommends instead. Both limits are invisible until you hit them. The first looks like this, with your organisation's name in place of `<your-org>`:

```
✗ failed to get Git repository: provider error: 403 The '<your-org>' organization
  forbids access via a personal access tokens (classic) if the token's lifetime is
  greater than 7 days.
```

The second shows on the repository's **Settings → Deploy keys** page as `Disabled by <your-org>`.

This tutorial uses a deploy key, on a repository owned by a person rather than the organisation. It is the fastest route that doesn't need a new credential every week. Nothing secret lives in the repository, so the cost is in governance, not security. ⚠ **Treat that as a proof-of-concept choice with an expiry date.** For anything longer-lived, use a repository the organisation owns, behind a GitHub App.

📌 Pointing Flux at a different repository later takes one `--url`. The layout in Step 14.4 is built for several clusters in one repository. So moving later is a fresh bootstrap, not a redesign.

#### Method A — SSH deploy key *(what we used)*

```
head$ ssh-keygen -t ed25519 -f ~/.ssh/flux_ochami-lab -N "" -C "flux@och-head"
head$ cat ~/.ssh/flux_ochami-lab.pub
```

Add that public key at **the repository → Settings → Deploy keys → Add deploy key**, and **tick "Allow write access"**.

🛑 **A read-only key fails halfway through.** Bootstrap clones, writes manifests and installs the controllers into the cluster. *Then* it fails on the push. Flux is left running with nothing in Git describing it, which is exactly the split GitOps exists to prevent.

A deploy key works for **one repository** only. Nobody can use it against anything else you can reach, and it doesn't expire. The cost is that the private key sits unencrypted on the head node. Whoever controls that host can push to this repository.

#### Method B — a token

```
head$ read -rs GITHUB_TOKEN && export GITHUB_TOKEN
```

Paste the token and press Enter. Nothing echoes.

⚠ **Use `read -rs`, not `export GITHUB_TOKEN=ghp_…`.** The second form puts the token on screen and in your shell history, and a token that has been seen should be revoked.

For a fine-grained token, set:

- **The resource owner** to the **organisation**.

- **Repository access** to this one repository only.

- **Permissions** to **Contents: read/write** *and* **Administration: read/write**. The second one isn't obvious. It lets bootstrap create the deploy key that Flux uses afterwards.

📌 Even with a token, the cluster ends up using a deploy key. `flux bootstrap github` uses the token on the head node to talk to GitHub's API. It then creates a key, so that `source-controller` can clone. So when the token expires, your pushes and any new bootstrap break, but reconciliation carries on. The exception is `--token-auth`. That stores the token in the cluster, and ties reconciliation to the token's lifetime.

### Can the cluster reach your Git host?

`source-controller` runs on a worker node, not the head node, and it clones over SSH port 22. The nodes reach the internet only through the head node's NAT (network address translation). §§9–12 only ever proved that HTTPS on port 443 works. So test port 22 before bootstrapping:

```
head$ kubectl run sshtest --rm -it --restart=Never --image=alpine -- \
        sh -c 'apk add -q openssh-client; ssh -o StrictHostKeyChecking=no -T git@github.com; echo rc=$?'
Warning: Permanently added 'github.com' (ED25519) to the list of known hosts.
git@github.com: Permission denied (publickey).
rc=255
```

⚠ **That output is a pass.** `Permission denied (publickey)` is an answer from GitHub itself. The connection succeeded, and the key exchange completed, which is why the host key was recorded. GitHub then refused to log in, because the pod offered no key. Blocked traffic gives a **timeout**, never a refusal. Telling those two apart is the whole point of the test.

The PodSecurity warning it prints is only advice (`warn: restricted` against `enforce: baseline`). It blocks nothing.

---

## Step 14.2 — Install the CLI and check the cluster

📌 Why the head node, not the devbox? §13.5 gave the devbox a working `kubectl`, so either would work. But Flux needs three things at once: the Kubernetes API, outbound HTTPS to GitHub and a Git working copy. The head node has all three directly. On the devbox, the Kubernetes API comes through an SSH tunnel that can drop halfway. Bootstrap is the one operation you least want interrupted. It commits to your repository *and* installs controllers, so a failure halfway leaves the two out of step.

🛑 **Pin the Flux version.** Just as §13.4 pinned Helm so the tool installing your charts doesn't silently cross a major version, pin the Flux CLI before it applies §§15–17. Pick a version, record it, and use the same version on real hardware.

Find the current release, then choose on purpose:

```
head$ curl -fsSL https://api.github.com/repos/fluxcd/flux2/releases/latest | grep -m1 '"tag_name"'
head$ FLUX_VERSION=2.9.4          # ← what you chose, without the leading v
```

The first command prints one line, naming the current release tag.

📌 This build used Flux 2.9.4 against Kubernetes v1.36.0. Record both versions together, since they are tested as a pair.

Download, verify and install, the same way as §13.4's Helm:

```
head$ ARCH=$(uname -m); [ "$ARCH" = x86_64 ] && ARCH=amd64 || ARCH=arm64
head$ curl -fsSLO https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${ARCH}.tar.gz
head$ curl -fsSLO https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_checksums.txt
head$ sha256sum --check --ignore-missing flux_${FLUX_VERSION}_checksums.txt
flux_${FLUX_VERSION}_linux_amd64.tar.gz: OK
head$ tar -xzf flux_${FLUX_VERSION}_linux_${ARCH}.tar.gz flux
head$ sudo install -m 0755 flux /usr/local/bin/flux
head$ rm -f flux flux_${FLUX_VERSION}_*
head$ flux --version
flux version 2.9.4
```

`--ignore-missing` is needed because the checksums file covers every platform, and you downloaded one. Without it, `sha256sum` reports every other line as missing and exits with an error. That looks like a failed check, but it isn't.

If you would rather use one line, upstream's installer honours the same pin. It is still pinned, but it runs a script from the internet as root:

```
head$ curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION=${FLUX_VERSION} bash
```

Then check the cluster before changing anything:

```
head$ flux check --pre
```

`flux check --pre` checks the Kubernetes version and your permissions, without touching the cluster. The line to read is the version comparison. It also appears in `flux check` after bootstrap:

```
► checking prerequisites
✔ Kubernetes 1.36.0 >=1.33.0-0
```

⚠ **A Kubernetes version complaint here is about the `flux` tool, not the cluster.** Talos ships a very recent Kubernetes. Flux states a supported *minimum*, which is `>=1.33.0-0` for 2.9.4. If `--pre` objects, the fix is a newer `flux`, not an older cluster. That is why the pair is worth writing down.

---

## Step 14.3 — Bootstrap

**With a deploy key**, use the form that works with any Git host. `flux bootstrap git` never calls GitHub's API, so no token policy applies:

```
head$ flux bootstrap git \
    --url=ssh://git@github.com/<owner>/ochami-lab-flux.git \
    --branch=main \
    --path=clusters/ochami-lab \
    --private-key-file=$HOME/.ssh/flux_ochami-lab \
    --components-extra=image-reflector-controller,image-automation-controller
```

**With a token**, if your organisation allows one:

```
head$ flux bootstrap github \
    --owner=<your-org-or-user> \
    --repository=ochami-lab-flux \
    --branch=main \
    --path=clusters/ochami-lab \
    --components-extra=image-reflector-controller,image-automation-controller
```

⚠ **Use `--personal` only for repositories a user owns.** Against an organisation, it sends Flux looking in the wrong place. It then fails with a `404` that reads as if the repository doesn't exist.

A successful run, abridged:

```
► cloning branch "main" from Git repository "ssh://git@github.com/…/ochami-lab-flux.git"
✔ cloned repository
✔ committed component manifests to "main" ("b7416236…")
► installing components in "flux-system" namespace
✔ installed components
► generating source secret
✔ public key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA…
Please give the key access to your repository: y
✔ committed sync manifests to "main" ("bbc0dbcc…")
✔ GitRepository reconciled successfully
✔ Kustomization reconciled successfully
► confirming components are healthy
✔ helm-controller: deployment ready
✔ image-automation-controller: deployment ready
✔ image-reflector-controller: deployment ready
✔ kustomize-controller: deployment ready
✔ notification-controller: deployment ready
✔ source-controller: deployment ready
✔ all components are healthy
```

📌 `Please give the key access to your repository:` is a confirmation, not a new task. With `--private-key-file`, that public key is the deploy key you already added. Flux is asking you to confirm it has access before going on, so answer `y`. Without `--private-key-file`, Flux makes a new key pair, and then you really do have to add it.

`flux bootstrap` installs the Flux controllers into `flux-system`, commits their manifests to `clusters/ochami-lab/flux-system/` in your repository, and configures Flux to reconcile that path. From now on, **anything committed under that path is applied to the cluster within a minute**.

- **`--path` names this cluster.** The same repository can later hold another cluster's directory next to it, sharing the `infrastructure/` and `apps/` definitions while differing only where necessary. That is how you move to real hardware later.

- **`--components-extra` adds the image automation controllers.** They can update a container tag automatically when a new one is published. That is useful for fast-moving inference images, and harmless if unused.

- **`flux bootstrap gitlab` exists too.** `git` is the one that works anywhere.

✅ **Checkpoint**

```
head$ flux check
► checking prerequisites
✔ Kubernetes 1.36.0 >=1.33.0-0
► checking version in cluster
✔ distribution: flux-v2.9.4
✔ bootstrapped: true
► checking controllers
✔ helm-controller: deployment ready
…
► checking crds
…
✔ all checks passed

head$ kubectl -n flux-system get pods
NAME                                          READY   STATUS    RESTARTS   AGE
helm-controller-66b87ccf5b-r6jts              1/1     Running   0          63m
image-automation-controller-6df84bd69-mxgsn   1/1     Running   0          63m
image-reflector-controller-678fc4d54c-txjdl   1/1     Running   0          63m
kustomize-controller-6d959d5f65-t92gf         1/1     Running   0          63m
notification-controller-5c895fb568-zpk78      1/1     Running   0          63m
source-controller-645ff9f8b9-25pnb            1/1     Running   0          63m

head$ flux get kustomizations
NAME          REVISION             SUSPENDED   READY   MESSAGE
flux-system   main@sha1:add5c7be   False       True    Applied revision: main@sha1:add5c7be
```

The `flux check` output is abridged where it shows `…`. Under `checking controllers` you should see all six controllers, each with the image tag it runs. Under `checking crds` you should see the fourteen Flux CRDs (custom resource definitions).

📌 `bootstrapped: true` confirms that `flux bootstrap` installed this Flux instance, so it owns a path in Git and reconciles itself (unlike a manually applied install).

📌 `flux check` prints the image tag of each controller. Those are the versions that matter when you read upstream issues. They differ from `flux --version`, because the tool and the controllers are released together but numbered separately. So `flux-v2.9.4` ships `kustomize-controller:v1.9.4` and `helm-controller:v1.6.3`.

⚠ **`✔ all components are healthy` describes the *controllers*, not your cluster's desired state.** It means six deployments are running. Whether they are applying anything is what `flux get kustomizations` tells you. That is why the checkpoint asks for both.

---

## Step 14.4 — The repository layout

Clone the repository, and lay out the structure that §§15–17 will fill:

```
head$ GIT_SSH_COMMAND="ssh -i $HOME/.ssh/flux_ochami-lab -o IdentitiesOnly=yes" \
        git clone ssh://git@github.com/<owner>/ochami-lab-flux.git ~/ochami-lab-flux
head$ git -C ~/ochami-lab-flux config core.sshCommand "ssh -i $HOME/.ssh/flux_ochami-lab -o IdentitiesOnly=yes"
head$ cd ~/ochami-lab-flux
head$ mkdir -p clusters/ochami-lab infrastructure/{controllers,configs} apps/inference
```

⚠ **A plain `git clone` fails here with `Permission denied (publickey)`, even though bootstrap just worked.** Bootstrap was told which key to use, and `git` wasn't. SSH only offers keys with **default names**, such as `id_ed25519` and `id_rsa`. `flux_ochami-lab` isn't one. So SSH offers whatever else it finds, which on this head node is the OpenStack key. GitHub refuses it, and the error reads like a missing repository.

The second line writes the setting into `~/ochami-lab-flux/.git/config`. So every later `push` uses the deploy key, with no environment variable to remember. `IdentitiesOnly=yes` stops SSH trying every key it can find first, which uses up attempts against GitHub's limit.

📌 Per repository, rather than in `~/.ssh/config`. A `Host github.com` block would also work. But it would silently change how every other repository on this host logs in. Keep the setting to the one thing that needs it.

🛑 **Paste the `cat > … << 'EOF'` blocks below one at a time, and verify each file before committing.** Some terminals truncate long multi-line pastes over SSH (or garble the terminal redraw, such as `EOF         kserveGateway: kserve/kserve-ingress-gatewayources, no Knative.`, which `Ctrl-L` clears):

```
EOF         kserveGateway: kserve/kserve-ingress-gatewayources, no Knative.
```

A truncated paste can still leave valid YAML—for example, a `Kustomization` missing its `dependsOn` block—that Flux will happily reconcile and fail on much later. Verify what arrived on disk rather than relying on what scrolled past:

```
head$ git status --short && git diff --stat
head$ tail -3 clusters/ochami-lab/infrastructure.yaml     # ends where you expect?
```

```
head$ wc -l <file>                       # the length you expect?
head$ tail -1 <file>                     # ends on the line you expect?
head$ kubectl apply --dry-run=client -f <file>
```

The repository layout:

![The Git repository Flux watches, ochami-lab-flux, has three top-level directories. clusters/ochami-lab holds what this cluster runs: flux-system, which bootstrap creates and which is not edited by hand, and two Kustomizations — infrastructure.yaml, pointing at ../../infrastructure, and apps.yaml, pointing at ../../apps and depending on the infrastructure one. infrastructure holds controllers, the things that add CRDs such as KServe and KubeRay (sections 15 and 17), and configs, the things that use those CRDs such as Gateways and ServingRuntimes. apps holds inference, the models actually being served (section 16). There are two Kustomizations rather than one because an InferenceService cannot be applied before KServe's CRDs exist, so apps waits on infrastructure.](diagrams/14-flux-repo-layout.svg)

<details>
<summary>ASCII version</summary>

```
ochami-lab-flux/
├── clusters/
│   └── ochami-lab/          ← what THIS cluster runs
│       ├── flux-system/        ← created by bootstrap; don't hand-edit
│       ├── infrastructure.yaml ← Kustomization → ../../infrastructure
│       └── apps.yaml           ← Kustomization → ../../apps  (depends on infra)
├── infrastructure/
│   ├── controllers/            ← KServe, KubeRay: things that add CRDs (§15, §17)
│   └── configs/                ← Gateways, ServingRuntimes: things that USE those CRDs
└── apps/
    └── inference/              ← the actual models being served (§16)
```

</details>

There are two Kustomizations rather than one, because order matters. An `InferenceService` can't be applied before KServe's CRDs exist. Flux expresses that with `dependsOn`:

```
head$ cat > clusters/ochami-lab/infrastructure.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true          # block until everything here is Ready…
  timeout: 10m
EOF

head$ cat > clusters/ochami-lab/apps.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure   # …so that CRDs exist before apps use them
EOF

head$ cat > infrastructure/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - controllers
  - configs
EOF
head$ printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources: []\n' \
        | tee infrastructure/controllers/kustomization.yaml \
              infrastructure/configs/kustomization.yaml \
              apps/kustomization.yaml > /dev/null

head$ wc -l clusters/ochami-lab/*.yaml infrastructure/kustomization.yaml
 14 clusters/ochami-lab/apps.yaml
 14 clusters/ochami-lab/infrastructure.yaml
  5 infrastructure/kustomization.yaml
head$ git add -A && git diff --cached --stat       # look before you commit
head$ git commit -m "Scaffold infrastructure and apps kustomizations" && git push
head$ flux reconcile kustomization flux-system --with-source
head$ flux get kustomizations
```

📌 `git diff` shows nothing for new files, so stage them first. `git diff` reports changes to *tracked* files, and these are untracked. `git status --short` lists them as `??`, and `git diff --stat` prints nothing at all. That looks as if the files are empty. `git add -A` then `git diff --cached --stat` is the check that works. The `wc -l` above is the blunter version, and catches a cut-short file just as well.

With `prune: true`, deleting a file from Git makes Flux delete the corresponding resource in the cluster, preventing old experiments from piling up.

📌 **Handling secrets in GitOps:** Nothing in §§15–17 requires a secret, because §16 uses an ungated model. If you later need a Hugging Face token or private registry credentials, **do not** commit them in plaintext:

- **SOPS (Secrets OPerationS) with age.** The secret is encrypted in Git, and Flux's kustomize-controller decrypts it with a key held in the cluster. This is the GitOps answer, and the one to use on real hardware.

- **Create the Secret separately**, with `kubectl create secret`, and refer to it by name from the committed manifests. It is less tidy, but fine for a proof of concept. It also keeps the "nothing secret in Git" rule absolute.

---

## ✅ Checkpoint

```
head$ flux get kustomizations
NAME            REVISION             SUSPENDED  READY  MESSAGE
apps                                 False      False  dependency 'flux-system/infrastructure' is not ready
flux-system     main@sha1:add5c7be   False      True   Applied revision: main@sha1:add5c7be
infrastructure  main@sha1:add5c7be   False      True   Applied revision: main@sha1:add5c7be

head$ flux get kustomizations
NAME            REVISION             SUSPENDED  READY  MESSAGE
apps            main@sha1:add5c7be   False      True   Applied revision: main@sha1:add5c7be
flux-system     main@sha1:add5c7be   False      True   Applied revision: main@sha1:add5c7be
infrastructure  main@sha1:add5c7be   False      True   Applied revision: main@sha1:add5c7be
```

📌 Both runs are shown on purpose, and the first one isn't a failure. `dependency 'flux-system/infrastructure' is not ready` is `dependsOn` doing its job. `apps` won't apply until `infrastructure` reports healthy. With `wait: true`, that means everything under `./infrastructure` is Ready. That is an empty set for now, so it clears in seconds. Run the command twice and watch it clear. In §15 the same message stays for minutes while KServe's CRDs settle, and it means the same thing.

⚠ **All three sharing one revision is the real check.** `main@sha1:add5c7be` on every row means all three Kustomizations are reconciling the same commit. A different revision would mean one is stuck on an older commit, and `READY True` alone wouldn't tell you.

You now have three reconciling Kustomizations, with the dependency order in place. From here on, **the way to change the cluster is a commit**. If you find yourself reaching for `kubectl apply` in §§15–17, put the file in Git instead.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `flux bootstrap` fails on authentication | `GITHUB_TOKEN` lacks repo scope, or `--personal` is wrong for a repository an organisation owns |
| `403 … organization forbids access via a personal access tokens (classic) if the token's lifetime is greater than 7 days` | Organisation policy. Shorten the token's life, use a fine-grained one, or switch to `flux bootstrap git` with a deploy key (Step 14.1) |
| The Deploy keys page says `Disabled by <org>` | Organisation policy again. A GitHub App is the approved route, and a personal repository is the proof-of-concept shortcut |
| `git clone` gives `Permission denied (publickey)` after bootstrap worked | `git` was never told which key to use. Set `GIT_SSH_COMMAND`, then `core.sshCommand` (Step 14.4) |
| Bootstrap installed the controllers but failed to push | The deploy key is read-only. Tick **Allow write access** and run it again |
| `apps` shows `dependency … is not ready` | Not a failure. `dependsOn` is waiting, so run the command again |
| `flux check --pre` complains about the Kubernetes version | Your `flux` is older than this Talos. Install a newer one, and don't downgrade the cluster |
| Kustomization `Ready=False`, `kustomization path not found` | The `path:` doesn't exist in the repository, or you didn't push |
| `apps` never becomes Ready | `dependsOn` is working. Fix `infrastructure` first, and `apps` follows |
| Flux applies nothing after a push | Run `flux reconcile kustomization flux-system --with-source` to force it. The default interval is 10 minutes |
| Resources you deleted from Git are still in the cluster | That Kustomization is missing `prune: true` |
| `git commit` gives `Please tell me who you are` | The head node has no Git identity (Step 14.1) |
| `git push` asks for a username, or says `Authentication failed` | The clone URL carries no token. `GITHUB_TOKEN` is only used by `flux bootstrap` (Step 14.1) |
| `sha256sum --check` reports dozens of missing files | Expected, because the checksums file covers every platform. Add `--ignore-missing` |
| `error converting YAML to JSON`, `yaml: line 13: found unexpected end of stream`, or a manifest that ends mid-line | A paste was cut short. Paste that block again on its own, then `git diff` before committing |
| A Kustomization is Ready, but the order is wrong in §15 | A cut-short paste lost `dependsOn`. The file still parsed, so nothing complained |

Next: [§15 — KServe](15-kserve.md)
