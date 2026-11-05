---
title: "§13 — Kubernetes Cluster Foundations"
description: "You add the parts a fresh Talos cluster leaves out, which §§15–17 depend on."
slug: "13-cluster-foundations"
date: 2026-10-21
lastmod: 2026-10-21
weight: 130
toc: true
draft: false
---
> ⏱ **About 20 minutes** · on the head node, then the devbox for Step 13.5 · installs storage, metrics, Gateway API and cert-manager, and a tunnel from the devbox
>
> - **What this chapter is for.** You add the parts a fresh Talos cluster leaves out, which §§15–17 depend on. You finish with a default storage class, working `kubectl top`, an accepted `GatewayClass`, and `kubectl` on the devbox through an SSH tunnel.
>
> - **What you will learn.** What Talos ships and what it doesn't, two Talos traps with storage and certificates, how Gateway API splits a controller from a class from a gateway, and how to reach a cluster on a network with no route in.
>
> - **Don't skip it.** KServe in §15 won't install without Gateway API and cert-manager, and its model cache needs the storage class.

---

## Introduction

### From here on, this is Kubernetes

OpenCHAMI's job is done once the nodes have booted. This chapter and the next four are about the Kubernetes cluster running on them. §18 comes back to the hardware.

### A Talos cluster arrives with the basics only

Talos gives you a working cluster, but nothing to store data, measure it or route traffic into it. It includes a CNI (Container Network Interface) plugin, flannel by default. It also includes CoreDNS, `kube-proxy` and the control-plane components.

It does **not** include a storage class, metrics, ingress or any extra CRDs (custom resource definitions). §§15–17 need three of those four, so you install them here.

### Each choice here has a real-hardware answer

These are the components most likely to differ between a cloud POC (proof of concept) and real hardware. So each step says what changes on real hardware, and why we chose what works on both where we could.

### What you will do

- **Check what you already have** (Step 13.1). Your variables, the nodes, and the empty storage list.

- **Add local storage** (Step 13.2). local-path-provisioner, with two Talos-specific patches, proved with a real pod.

- **Install metrics-server** (Step 13.3), and get past the kubelet certificate problem.

- **Install Gateway API, cert-manager and Envoy Gateway** (Step 13.4), then declare a `GatewayClass`.

- **Reach the cluster from your devbox** (Step 13.5), through an SSH tunnel to the head node.

- **Check all of it** (the checkpoint), with assertions that test effects rather than objects.

📌 The project documentation goes into more detail:

- [local-path-provisioner](https://github.com/rancher/local-path-provisioner), the storage driver in Step 13.2.

- [metrics-server](https://github.com/kubernetes-sigs/metrics-server), for Step 13.3.

- [Gateway API](https://gateway-api.sigs.k8s.io/), for the model behind Step 13.4.

- [cert-manager](https://cert-manager.io/docs/), [Envoy Gateway](https://gateway.envoyproxy.io/docs/) and [Helm](https://helm.sh/docs/), the other three things Step 13.4 installs.

---

## Step 13.1 — Check what you already have

`KUBECONFIG` and `TALOSCONFIG` should already be set, because `och-head-env.sh` sources §12.3's `~/och-head-talos-env.sh` in every shell. Check:

```
head$ echo "$TALOSCONFIG $KUBECONFIG" && kubectl get nodes
```

If they are empty, you skipped §12.3. Go back and write that file rather than exporting the variables by hand, because §§14–19 all assume it.

Then look at the cluster:

```
head$ kubectl get nodes -o wide
head$ kubectl get pods -A
head$ kubectl get storageclass
```

Expect the nodes `Ready`, `kube-system` healthy, and **no storage classes at all**:

```
head$ kubectl get storageclass
No resources found
```

No storage class isn't a fault. Talos ships no storage driver on purpose, because the right one depends on where it runs.

Look closely at `kubectl get nodes -o wide`, where the whole stack appears on one line: `Talos (v1.13.0)`, `6.18.24-talos (amd64)`, and `containerd://2.2.3`. `INTERNAL-IP` sits on the `172.16.0.x` provisioning network, and `EXTERNAL-IP` is `<none>`.

```
head$ kubectl cluster-info
head$ talosctl -n 172.16.0.1 get staticpods
```

---

## Step 13.2 — Storage

Nothing in §§15–17 strictly needs a PersistentVolume, but you will want one. vLLM can cache model weights in an `emptyDir`. Then every pod restart downloads several GB again, through the head node's NAT (network address translation). A local storage class fixes that.

We use local-path-provisioner. It turns each PVC (PersistentVolumeClaim) into a directory on a node. It needs no credentials, and it works the same way on real hardware, where nodes usually have large local NVMe disks. It doesn't replicate data, which is fine for a model cache.

📌 Why not the other two obvious choices. Cinder CSI (Container Storage Interface), OpenStack's own driver, needs OpenStack credentials *inside* the cluster, and doesn't exist on real hardware. A replicated store such as Longhorn is the right answer for data that must survive a node. It is more than this needs, and on Talos it needs system extensions, a §18 topic.

```
head$ kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

⚠ **Talos trap, part one: the default path is read-only.** local-path-provisioner defaults to `/opt/local-path-provisioner`. On Talos almost the entire filesystem is immutable, and only `/var` is writable.

🛑 **Talos trap, part two: pointing it at `/var` isn't enough on its own.** The provisioner doesn't create directories itself. It starts a short-lived *helper pod* on the target node, whose `data` volume is a `hostPath` with `type: DirectoryOrCreate`. The **kubelet** does that `mkdir`.

On Talos, the kubelet runs in its own mount namespace. Only a chosen set of paths from `/var` is bind-mounted into it, and it can't create a directory where it can't write. So first declare the directory as a kubelet mount, on every node that will hold a volume:

```
head$ cat > /tmp/lpp-mount.yaml << 'EOF'
machine:
  kubelet:
    extraMounts:
      - destination: /var/local-path-provisioner
        type: bind
        source: /var/local-path-provisioner
        options: [bind, rshared, rw]
EOF
head$ for n in 172.16.0.1 172.16.0.2 172.16.0.3; do talosctl -n $n patch machineconfig --patch-file /tmp/lpp-mount.yaml; done
patched MachineConfigs.config.talos.dev/v1alpha1 at the node 172.16.0.1
Applied configuration without a reboot
```

The same two lines repeat for each node.

`Applied configuration without a reboot` is what you want. Only the kubelet restarts. Talos creates the source directory for you, and `talosctl -n 172.16.0.2 ls /var | grep local-path` confirms it. Give the nodes a few seconds to return to `Ready`.

Only now point the provisioner at that path:

```
head$ kubectl -n local-path-storage patch configmap local-path-config --type merge -p '
{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/var/local-path-provisioner\"]}]}"}}'
head$ kubectl -n local-path-storage rollout restart deploy/local-path-provisioner
```

📌 Why `/var/local-path-provisioner` and not `/var/mnt/…`. `/var/mnt` looks like the obvious place for storage, and `talosctl` shows it as writable. But it is where Talos mounts *declared user volumes*, and it is read-only inside the kubelet's namespace. That fault reports nothing. The helper pod sits in `ContainerCreating`, is deleted 120 seconds later, and the PVC stays `Pending` for ever.

Make it the default, so later manifests don't have to name it:

```
head$ kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

📌 Two `PodSecurity` warnings are expected here, and they are only warnings. Applying the manifest and restarting the deployment both print `would violate PodSecurity "restricted:latest"`. They mention `allowPrivilegeEscalation`, capabilities, `runAsNonRoot` and `seccompProfile`. Nothing is blocked, and the deployment is created anyway. It is the cluster-wide *warn* level, reporting on a namespace with no enforcement label.

local-path-provisioner really does need to write to the host filesystem, because that is its purpose. On a cluster that enforces `restricted` by namespace, it needs an exemption.

✅ Prove it end to end. This needs a *consumer*, because a PVC on its own proves nothing:

```
head$ kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: smoke
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF
head$ kubectl get pvc smoke
NAME    STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
smoke   Pending                                      local-path     13s
```

🛑 **`Pending` here is permanent, and it is correct.** local-path's `volumeBindingMode` is `WaitForFirstConsumer`, so nothing is created until a pod mounts the claim. Waiting won't change it. So a `Pending` PVC proves **nothing at all** about whether the two patches worked. This step exists to catch exactly that, so give it something to consume:

```
head$ kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: smoke
spec:
  containers:
  - name: c
    image: busybox
    command: ["sh","-c","echo ok > /d/f; sleep 600"]
    volumeMounts:
    - {name: v, mountPath: /d}
  volumes:
  - name: v
    persistentVolumeClaim: {claimName: smoke}
EOF
head$ kubectl get pvc smoke
NAME    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
smoke   Bound    pvc-e372aa11-dc71-440c-bc7f-2470026b82dd   1Gi        RWO            local-path     83s
head$ kubectl exec smoke -- cat /d/f
ok
```

Seeing `Bound` and `ok` proves the storage class works end to end: the provisioner created a directory on a node, and a container wrote a file into it and read it back.

Confirm the third part on the node itself. `kubectl get pod smoke -o wide` names the node the pod landed on:

```
head$ talosctl -n 172.16.0.2 ls /var/local-path-provisioner
NODE         NAME
172.16.0.2   .
172.16.0.2   pvc-e372aa11-dc71-440c-bc7f-2470026b82dd_default_smoke
```

The other nodes show only `.`, which is correct. local-path is *local*, and the volume exists on exactly one node. Keep that in mind when a pod that mounts it is later moved to another node.

If either patch were missing, the pod would sit in `ContainerCreating` instead. A missing configmap patch gives a read-only filesystem error against `/opt`, in the provisioner log. A missing `extraMounts` gives `MountVolume.SetUp failed for volume "data" : mkdir …: read-only file system`. That one appears only in the helper pod's events, which are deleted before you are likely to read them.

```
head$ kubectl delete pod smoke && kubectl delete pvc smoke
```

Delete the pod first. A PVC with a live consumer won't delete, and hangs in `Terminating`.

---

## Step 13.3 — metrics-server

`kubectl top` needs metrics-server. So does any HorizontalPodAutoscaler, which KServe uses to scale an `InferenceService`:

```
head$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

⚠ **Talos trap: it sits at `0/1` until you fix the kubelet certificate check.** metrics-server reads each kubelet over TLS (Transport Layer Security), and verifies the certificate. Talos's kubelet signs its own certificate, with **no SANs (subject alternative names) at all**. So verification fails on every node:

```
head$ kubectl -n kube-system get deploy metrics-server
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   0/1     1            0           8m46s

head$ kubectl -n kube-system logs deploy/metrics-server --tail=20
E0813 18:34:34.728939  1 scraper.go:149] "Failed to scrape node" err="Get \"https://172.16.0.1:10250/metrics/resource\":
    tls: failed to verify certificate: x509: cannot validate certificate for 172.16.0.1
    because it doesn't contain any IP SANs" node="nid0001"
I0813 18:34:39.274720  1 server.go:192] "Failed probe" probe="metric-storage-ready" err="no metrics to serve"
```

It isn't crashing. `0/1` with the pod running means the readiness probe fails. With no successful reads, there are no metrics to serve.

There are two fixes. You can tell metrics-server not to verify the certificate, which is quick and fine for a POC. Or you can give the kubelet a properly signed certificate, which is what you want on real hardware.

For this POC, take the quick path:

```
head$ kubectl -n kube-system patch deploy metrics-server --type=json -p \
  '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
deployment.apps/metrics-server patched
head$ kubectl -n kube-system rollout status deploy/metrics-server
deployment "metrics-server" successfully rolled out
```

The connection stays encrypted. What stops is metrics-server checking *who* it is talking to. That is acceptable on a private network that only we use. **Write it down as debt**, because nothing will warn you about it later.

```
head$ kubectl top nodes
NAME      CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
nid0001   104m         2%       1536Mi          9%
nid0002   149m         1%       581Mi           0%
nid0003   61m          0%       555Mi           0%
```

⚠ **Allow 60 seconds.** `metrics not available` just after a successful rollout is normal. metrics-server needs a read cycle or two before it has anything to serve. `kubectl -n kube-system get deploy metrics-server` showing `1/1` is the real signal, because its readiness probe passes only once reads succeed.

📌 **On real hardware, issue signed kubelet serving certificates instead.** Patch the Talos machine config so each kubelet requests a cluster-signed serving certificate:

```
head$ cat > ~/talos/kubelet-certs-patch.yaml << 'EOF'
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: "true"
EOF
head$ talosctl patch machineconfig -n 172.16.0.1,172.16.0.2,172.16.0.3 \
        --patch-file ~/talos/kubelet-certs-patch.yaml
```

⚠ **Use `--patch-file`, not `--patch @~/...`.** The shell only expands `~` at the start of a word, so `@~/talos/…` passes the literal tilde to `talosctl` and fails with `no such file or directory`.

🛑 **Enabling rotation only creates the CSR (certificate signing request)—something still has to approve it.** Check the CSR state before assuming rotation is complete:

```
head$ kubectl get csr
```

| Output | Meaning |
|---|---|
| `No resources found` | Rotation is **off**, because the patch didn't apply. Check the tilde trap above |
| `Pending`, signer `kubernetes.io/kubelet-serving` | Rotation is on, and nothing is approving. **Still broken**, in a new way |
| `Approved,Issued` | Both halves are in place. Remove `--kubelet-insecure-tls` and test again |

Because Kubernetes does not auto-approve kubelet serving CSRs by default, production clusters pair `rotate-server-certificates` with [`kubelet-serving-cert-approver`](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/deploy-metrics-server).

---

## Step 13.4 — Gateway API and cert-manager

KServe (§15) needs both.

Gateway API replaces Ingress. It is a set of CRDs (`GatewayClass`, `Gateway`, `HTTPRoute`). They separate "who runs the load balancer" from "who routes traffic to my service". KServe uses it to expose model endpoints.

```
head$ kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

⚠ **Pin the version.** KServe documents Gateway API **v1.2.1**, and has kept that pin from 0.15 through 0.20. Newer Gateway API releases have moved fields between `v1beta1` and `v1`. Taking `latest` here reliably gives confusing webhook errors in §15.

cert-manager issues the webhook certificates that KServe's admission controllers need:

```
head$ kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
head$ kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=5m
```

KServe needs cert-manager 1.15.0 or later, and any later 1.x is fine.

Then a Gateway API implementation. The CRDs above are only definitions, and something has to run the proxy. We use **Envoy Gateway**: one controller, and one Envoy proxy per Gateway, which is ingress without a full service mesh.

📌 Istio is the fallback. It is the most-travelled path in KServe's own documentation and testing. If Envoy Gateway gives trouble in §15, switch to Istio before debugging Envoy Gateway. Use `istioctl install --set profile=minimal`, plus the Istio `GatewayClass`. Note in your run log which gateway you ended up with.

Envoy Gateway ships as a Helm chart, so install `helm` first. It isn't on the head node, and Rocky's repositories don't carry it.

🛑 **Pin the Helm version too.** Everything else in this chapter is pinned. An unpinned `latest` URL can cross a major version without telling you. This tutorial uses **Helm 4**. The one difference that shows is a flag: Helm 4 enforces field ownership, so the chart install below needs `--force-conflicts`.

Download the release tarball, check it against the published checksum, and install the single binary inside:

```
head$ HELM_VER=v4.2.3
head$ curl -fsSLO https://get.helm.sh/helm-${HELM_VER}-linux-amd64.tar.gz
head$ curl -fsSLO https://get.helm.sh/helm-${HELM_VER}-linux-amd64.tar.gz.sha256sum
head$ sha256sum -c helm-${HELM_VER}-linux-amd64.tar.gz.sha256sum
helm-${HELM_VER}-linux-amd64.tar.gz: OK
head$ tar -xzf helm-${HELM_VER}-linux-amd64.tar.gz
head$ sudo install -m 0755 linux-amd64/helm /usr/local/bin/helm
head$ rm -rf linux-amd64 helm-${HELM_VER}-linux-amd64.tar.gz*
head$ helm version --short
v4.2.3+g43e8b7f
```

⚠ **Check the major version matches.** Helm 3 and Helm 4 write to the cluster in different ways, and the next step behaves differently under each. If `helm version --short` disagrees with `HELM_VER`, these instructions are for a different tool.

🛑 **`sha256sum -c` must print `OK` before you continue.** It is the only step that proves the file you are about to run as root is the one upstream published. If it fails, stop. Don't download it again hoping for a different result.

📌 Why not Helm's one-line `curl … | bash` installer? It runs an unseen script and installs whatever is newest. That is a poor habit on a machine that holds cluster credentials.

⚠ **Check your architecture.** The URLs above say `amd64`. If `uname -m` reports `aarch64`, use `arm64` throughout. A mismatched binary fails with `cannot execute binary file`, which doesn't mention architecture.

Install Envoy Gateway with `--force-conflicts`:

```
head$ helm install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
        --version v1.2.4 -n envoy-gateway-system --create-namespace \
        --force-conflicts
head$ kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=5m
```

🛑 **Why `--force-conflicts` is needed.** The Envoy Gateway chart bundles its own copy of the Gateway API **v1.2.1** CRDs from the **experimental** channel rather than standard. Because Helm 4 uses server-side apply, Kubernetes refuses to let it overwrite fields that `kubectl apply` already owns unless you pass `--force-conflicts`. Without the flag, the install fails with `conflict occurred while applying object` on:

```
- .metadata.annotations.gateway.networking.k8s.io/channel
- .spec.versions
```

Passing `--force-conflicts` hands field ownership to Helm and installs the experimental v1.2.1 set—which includes all the standard CRDs plus `TCPRoute`, `TLSRoute`, `BackendTLSPolicy`, and `BackendLBPolicy`—while preserving the v1.2.1 version pin KServe requires.

Confirm both annotations directly:

```
head$ kubectl get crd gateways.gateway.networking.k8s.io \
        -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"  "}{.metadata.annotations.gateway\.networking\.k8s\.io/channel}'; echo
v1.2.1  experimental
```

⚠ **`bundle-version` is the assertion that matters.** `channel: experimental` is expected and harmless. A `bundle-version` other than `v1.2.1` means the pin KServe needs is gone. You would find out in §15, through webhook errors that point nowhere near here.

🛑 **Don't read the channel from `kubectl.kubernetes.io/last-applied-configuration`.** That annotation is a snapshot written by the original `kubectl apply`, and it still says `"channel":"standard"`. Nothing updates it now that Helm owns the object. The two annotations above are the live values.

List the Gateway API CRDs to see the experimental kinds alongside the five standard ones:

```
head$ kubectl get crd | grep gateway.networking
```

You should see the five standard kinds, plus `tcproutes`, `tlsroutes`, `backendtlspolicies` and `backendlbpolicies`.

Finally, declare a `GatewayClass`. The chart installs the *controller*, not a class. Until a class exists, the controller has nothing to act on:

```
head$ kubectl get gatewayclass
No resources found
```

A `GatewayClass` joins the two halves of Gateway API's model. It names a `controllerName`, and whichever controller watches for that exact string claims it. Read the name from the deployed config rather than copying it from here. If it doesn't match, the class is ignored:

```
head$ kubectl -n envoy-gateway-system get cm envoy-gateway-config -o yaml | grep -i controllername
    controllerName: gateway.envoyproxy.io/gatewayclass-controller
head$ echo '{"apiVersion":"gateway.networking.k8s.io/v1","kind":"GatewayClass","metadata":{"name":"eg"},"spec":{"controllerName":"gateway.envoyproxy.io/gatewayclass-controller"}}' | kubectl apply -f -
gatewayclass.gateway.networking.k8s.io/eg created
head$ kubectl get gatewayclass
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       11s
```

📌 The class is written as one line on purpose. A YAML heredoc is easier to read, but some terminals cut long multi-line pastes short. A cut-off heredoc fails with `yaml: line 13: found unexpected end of stream`. A mangled line of JSON fails to parse instead of applying half an object.

⚠ **`ACCEPTED True` is the assertion, not the object existing.** A `GatewayClass` whose `controllerName` matches nothing is created without complaint, and does nothing. There is no error and no event. §15 then fails, with KServe unable to create a Gateway, several steps away from the cause.

🛑 **A `GatewayClass` doesn't serve traffic on its own, so nothing is listening yet.** Gateway API splits routing across three layers:

| Layer | What it is | Who creates it |
|---|---|---|
| **Controller** | The Envoy Gateway deployment, watching for work | The Helm chart, Step 13.4 |
| **`GatewayClass`** | A named declaration: *"a controller answering to this name will handle Gateways of this class"* | You, just now |
| **`Gateway`** | A request for a real proxy on real ports. Creating one makes the controller start an Envoy pod and a Service | **Nobody yet.** KServe, in §15 |

After this step, the controller has nothing to do, and nothing refers to the class. `kubectl get gateway -A` is empty, there is no Envoy proxy pod, and nothing listens on port 80. All of that is correct. The first `Gateway` arrives in §15.

---

## Step 13.5 — Reaching the cluster from your laptop

One SSH tunnel lets the devbox drive both the cluster and OpenStack. So far you have run everything on the head node, because the provisioning network has no route in from outside. That means two sets of tools in two places. A tunnel gives the devbox `kubectl` against the cluster, and the OpenStack CLI stays where it already is.

The tunnel also forwards port `8080`. From §15 on, that is how a model endpoint becomes reachable from a browser. Set it up now, because it costs nothing until a `Gateway` exists.

This step needs two things that earlier chapters didn't.

⚠ **First, load your environment.** `OCH_HEAD_FIP` (the head node's floating IP address) lives in `~/och/och-vars-env.sh`, where §6.5 added it. A new shell doesn't have it until you source the file. Without it, every command below expands to `rocky@` and fails on a blank hostname:

```
devbox$ source ~/och/och-env.sh
OpenCHAMI lab env loaded (OS_CLOUD=ochami-lab). Run 'och_help'.
devbox$ echo $OCH_HEAD_FIP        # must not be empty
```

📌 Read the error before blaming the network. An unset variable gives `ssh: Could not resolve hostname : Name or service not known`. Note the empty name between `hostname` and `:`. It looks like a DNS problem, but it is a shell problem.

Second, install `kubectl` on the devbox. It has only ever run on the head node. Pin it to the cluster's version. `kubectl` supports one minor version of difference either way, and matching removes the question:

```
devbox$ ARCH=$(uname -m); [ "$ARCH" = x86_64 ] && ARCH=amd64 || ARCH=arm64; echo $ARCH
devbox$ curl -fsSLO https://dl.k8s.io/release/v1.36.0/bin/linux/${ARCH}/kubectl
devbox$ curl -fsSLO https://dl.k8s.io/release/v1.36.0/bin/linux/${ARCH}/kubectl.sha256
devbox$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: OK
devbox$ sudo install -m 0755 kubectl /usr/local/bin/kubectl
devbox$ rm -f kubectl kubectl.sha256
devbox$ kubectl version --client
Client Version: v1.36.0
Kustomize Version: v5.8.1
```

⚠ **Work out the architecture, don't assume it.** A devbox VM on an Apple Silicon Mac is `aarch64`, and on an Intel Mac it is `x86_64`. A wrong binary fails with `cannot execute binary file`, which never mentions architecture.

Now start the tunnel using the helper from §3's `och-helpers-env.sh`, which runs SSH in the background via a control socket so it doesn't tie up a terminal:

```
devbox$ och_tunnel_up
tunnel up:
  localhost:6443  -> 172.16.0.1:6443  Kubernetes API
  localhost:8080  -> 172.16.0.1:80    gateway (nothing listening until §15)
devbox$ och_tunnel_status
devbox$ och_tunnel_down            # when you are done
```

📌 `och_tunnel_down` closes only this control socket (unlike `pkill -f ssh`), and `och_tunnel_status` checks both whether the local port forward is open and whether the Kubernetes API answers through it.

If the helpers aren't loaded, or you want to see the underlying command, `och_tunnel_up` runs:

```
devbox$ ssh -i ~/.ssh/och_ed25519 -N \
    -L 6443:172.16.0.1:6443 \
    -L 8080:172.16.0.1:80 \
    rocky@${OCH_HEAD_FIP}
```

`-N` means "no command, just forward", so running the raw `ssh` command in the foreground **blocks and prints nothing** (pressing `Ctrl-C` kills the tunnel). To run it in the background without the helper, add `-f`:

```
devbox$ ssh -f -N -o ExitOnForwardFailure=yes -i ~/.ssh/och_ed25519 \
    -L 6443:172.16.0.1:6443 rocky@${OCH_HEAD_FIP}
devbox$ pgrep -af 'ssh.*6443'          # before
devbox$ kubectl get nodes
devbox$ pgrep -af 'ssh.*6443'          # after — gone means something really is killing it
```

🛑 **Nothing is listening on `172.16.0.1:80` until §15 creates a `Gateway`.** Until then, `curl localhost:8080` returns `Connection refused` and SSH logs `channel N: open failed: connect failed: Connection refused` whenever something connects to port 8080. That message only reflects port 8080—the port 6443 API forward is unaffected:

| Message | Who refused | Where to look |
|---|---|---|
| `connection to 127.0.0.1:6443 was refused` | Your own machine. **Nothing is bound to that port** | The tunnel isn't running. `ss -ltnp \| grep 6443` will be empty |
| `channel N: open failed: … Connection refused` | The far end of the forward | Whatever the forward points at isn't listening. Normal for 8080 here |
| A hang or timeout, not a refusal | Nobody. Packets are going nowhere | Your network path to the head node, the security group, or the head node itself |

Last, point `kubectl` at the tunnel. Copy the kubeconfig across, and change it to use the tunnel:

```
devbox$ mkdir -p ~/och
devbox$ scp -i ~/.ssh/och_ed25519 rocky@${OCH_HEAD_FIP}:~/talos/kubeconfig ~/och/kubeconfig
kubeconfig                        100% 2279    60.3KB/s   00:00
devbox$ sed -i 's|https://172.16.0.1:6443|https://127.0.0.1:6443|' ~/och/kubeconfig
devbox$ KUBECONFIG=~/och/kubeconfig kubectl get nodes
NAME      STATUS   ROLES           AGE     VERSION
nid0001   Ready    control-plane   6d12h   v1.36.0
nid0002   Ready    <none>          6d12h   v1.36.0
nid0003   Ready    <none>          6d12h   v1.36.0
```

📌 Run `mkdir -p ~/och` first. If the parent directory doesn't exist, `scp` writes a *file* called `och` instead of failing. The `sed` then edits something that isn't where you think.

🛑 **Re-running `scp` overwrites `~/och/kubeconfig` with `172.16.0.1:6443`, which makes `kubectl` hang on the devbox.** Whenever you copy the file again, re-run the `sed` command immediately afterwards. Check which server address your local kubeconfig points at:

```
devbox$ grep server: ~/och/kubeconfig
    server: https://127.0.0.1:6443       # correct — through the tunnel
    server: https://172.16.0.1:6443      # scp overwrote it — re-run the sed
```

Now that `~/och/kubeconfig` exists, sourcing `~/och/och-env.sh` exports `KUBECONFIG` automatically in your shell:

```
devbox$ source ~/och/och-env.sh
devbox$ kubectl get nodes
NAME      STATUS   ROLES           AGE     VERSION
nid0001   Ready    control-plane   6d13h   v1.36.0
nid0002   Ready    <none>          6d13h   v1.36.0
nid0003   Ready    <none>          6d12h   v1.36.0
```

📌 You can run the checkpoint below from the devbox as well—`kubectl top` and `kubectl get crd` exercise the tunnel end to end. The API server certificate matches because §10.6's `certSANs` patch included `172.16.0.1`.

🛑 **Keep the cluster behind this SSH tunnel.** Do not assign a floating IP to a compute node or open `och-sg-api` (§5.5) to a wider network.

---

## ✅ Checkpoint

```
head$ kubectl get storageclass
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  2d22h

head$ kubectl top nodes
NAME      CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
nid0001   97m          2%       1786Mi          11%
nid0002   58m          0%       649Mi           1%
nid0003   55m          0%       584Mi           0%

head$ kubectl get crd | grep -E 'gateway|cert-manager' | wc -l
24

head$ kubectl get gatewayclass
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       11s

head$ kubectl get pods -A | grep -v Running | grep -v Completed
NAMESPACE   NAME   READY   STATUS   RESTARTS   AGE
```

What each check proves:

| Assertion | Why it is the right check |
|---|---|
| `local-path (default)` | The `(default)` suffix is the annotation from Step 13.2. Without it, a PVC with no `storageClassName` stays `Pending` for ever, and §15 creates exactly those |
| `kubectl top nodes` returning **numbers** | metrics-server being `Running` proves nothing, because it runs perfectly while failing every read. Only real figures prove the TLS path works |
| `24` CRDs | A count rather than a list, because the exact number changes between versions. Zero means an install silently did nothing |
| Only the header line | Nothing in the cluster is unhealthy, including namespaces you didn't install into |

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| local-path pods `CrashLoopBackOff`, read-only filesystem errors | The `/opt` default path. Apply the configmap patch in Step 13.2 |
| PVC stuck `Pending` with `WaitForFirstConsumer` | Normal for local-path, and **permanent** until a pod mounts it. It isn't a fault, and it isn't proof the provisioner works either. Step 13.2's consumer pod is the real test |
| `local-path-provisioner` logs `read-only file system` | The `/opt` default path. Step 13.2's configmap patch didn't apply, or the deployment wasn't restarted after it |
| PVC `Pending` **with** a consumer pod; provisioner logs `create process timeout after 120 seconds` every 15 min | The kubelet can't create the directory. Step 13.2's `extraMounts` patch is missing, or the configmap points somewhere the kubelet can't write (`/var/mnt/…`) |
| Consumer pod `FailedScheduling`, `running PreBind plugin "VolumeBinding": binding volumes: context deadline exceeded` | The same fault, seen from the scheduler. A node was chosen, and the volume never appeared. Read the **provisioner** log, not the scheduler's |
| `would violate PodSecurity "restricted:latest"` on apply | A warning, not a rejection. Expected, and the deployment is created. See Step 13.2 |
| metrics-server `0/1` or `CrashLoopBackOff`, `x509` in the logs | The kubelet certificate check. See Step 13.3 |
| `talosctl patch`: `open ~/talos/…: no such file or directory`, for a file `cat` can read | The shell doesn't expand `~` inside `@~/…`. Use `--patch-file ~/…` |
| `helm: command not found` at Step 13.4 | Helm isn't on the head node or in Rocky's repositories. Install it first, as in Step 13.4 |
| `INSTALLATION FAILED: … conflicts with "kubectl-client-side-apply"` | Helm 4 enforces field ownership. Add `--force-conflicts` (Step 13.4) |
| `helm list -a` → `unknown shorthand flag: 'a'` | You are on Helm 4 and expected Helm 3. `-a` was Helm 3's short form of `--all` |
| `yaml: line 13: found unexpected end of stream` | The terminal cut a multi-line paste short. Use the one-line JSON form in Step 13.4 |
| `kubectl get gatewayclass` → `No resources found` after the chart installs | Expected. The chart ships the controller, not a class. Create one, as in Step 13.4 |
| `GatewayClass` exists but `ACCEPTED` isn't `True` | `controllerName` doesn't match what the controller watches for. Read it from `envoy-gateway-config` |
| `curl localhost:8080` → `Connection refused` through the Step 13.5 tunnel | Expected until §15. No `Gateway` exists, so there is no proxy and nothing on port 80 |
| `ssh: Could not resolve hostname : Name or service not known` | `OCH_HEAD_FIP` is unset. Note the empty name. Run `source ~/och/och-env.sh` |
| `kubectl: command not found` on the devbox | It has only been installed on the head node. Step 13.5 installs it |
| `kubectl` still not using the tunnel after `KUBECONFIG=~/och/kubeconfig` | That set a shell variable without exporting it. `export` it, or source the helpers again |
| `och_tunnel_up` → `Address already in use` | An earlier tunnel is running outside the helpers. Find it, stop it, and try again |
| `kubectl` worked, then `127.0.0.1:6443 was refused` | The tunnel died, usually from a `Ctrl-C` in its terminal. Nothing is bound locally, so your network path isn't involved |
| `channel N: open failed … Connection refused` while the tunnel runs | The 8080 forward reaching a port with no listener. Expected until §15 |
| `kubectl` **hangs** instead of refusing | Check two things, in this order. Was the kubeconfig copied again, so it points at `172.16.0.1`? (`grep server: ~/och/kubeconfig`) Or is the listener tied to a dead connection? (`och_tunnel_down && och_tunnel_up`) |
| The tunnel prints `channel N: read failed … Broken pipe` | The *local* end went away, because kubectl finished or was interrupted. Normal for each connection, not a fault |
| `cannot re-use a name that is still in use` when retrying a helm install | A failed release record survived. `helm uninstall` it first |
| A pasted command hangs with no output | You copied the `head$ ` prompt with it. `head` is a real program, and it is waiting for input. Press `Ctrl-C`, and paste from after the prompt |
| `kubectl top nodes` → `metrics not available` | Give metrics-server 60 seconds after it becomes Ready |
| Gateway API webhook errors, unknown fields | Version mismatch. You installed a Gateway API newer than v1.2.1 |
| `GatewayClass` never becomes `Accepted` | The implementation's controller isn't running. Check `kubectl -n envoy-gateway-system get pods` |
| Everything `Pending`, `Insufficient cpu/memory` | Your worker flavors are too small. Add a worker (§9.3) or use a bigger flavor |

Next: [§14 — GitOps with FluxCD](14-fluxcd-gitops.md)
