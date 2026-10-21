---
title: "§15 — KServe"
description: "Install the platform that serves models: the KServe controller without Knative, and a Gateway the head node can reach."
slug: "15-kserve"
date: 2026-10-21
lastmod: 2026-10-21
weight: 150
toc: true
draft: false
---
> ⏱ **About 20 minutes** · on the head node, committing to the Flux repository from §14 · installs KServe and its ingress Gateway
>
> - **What this chapter is for.** You install the platform that serves models. You finish with the KServe controller running without Knative, and a Gateway with an address the head node can reach.
>
> - **What you will learn.** What KServe adds over a plain Deployment, why we run it without Knative, and how a Gateway gets an address on a cluster with no load balancer.
>
> - **Don't skip it.** §16's `InferenceService` is a KServe object. Without this chapter, nothing reads it, and there is nowhere to send requests.

---

## Introduction

### KServe turns "serve this model" into one object

You can serve a model with a plain `Deployment` and a `Service`. What you *can't* do that way is scale on request load, or roll out a new version safely. You also can't offer the same inference API across different engines, or describe "serve this model" as one object. KServe adds a control plane for exactly that:

| KServe object | What it is |
|---|---|
| **`ServingRuntime`** / `ClusterServingRuntime` | A reusable description of *an engine*: the container image, its arguments, which model formats it accepts. Install once, use many times |
| **`InferenceService`** | "Serve *this model* using a matching runtime", plus scaling and routing. The object users actually write |
| **`LLMInferenceService`** | A newer, LLM-specific CRD built on the llm-d architecture: prefill/decode disaggregation, KV-cache-aware routing, multi-node serving. **Ships in separate charts and is not installed here** — see the checkpoint |

An LLM is a large language model, and a CRD (custom resource definition) adds a new object type to Kubernetes.

The value is in the separation. An `InferenceService` names a model and a format, and the platform picks the engine. When §18 adds GPU nodes, the *runtime* changes and the `InferenceService` barely does.

### Deployment mode — and why we avoid Knative

KServe can run in two modes, and this is the most important choice in the chapter.

- **Standard mode**, once called RawDeployment, builds on a plain `Deployment`, `Service` and HPA (HorizontalPodAutoscaler). It needs nothing extra beyond a Gateway, and pods stay up, so there is no cold start.

- **Serverless mode** builds on Knative Serving and its networking layer. It can scale to zero, so the first request after a quiet spell waits for a pod to start.

We use Standard, for three reasons. It removes a whole distributed system from the stack, which matters when the point is to understand the layers. Scaling to zero hurts LLM serving, because a cold start means loading gigabytes of weights again. And on real hardware, the nodes are there for inference, so there is nothing to give the capacity back to.

🔀 **Deviation: Standard mode.** Most KServe tutorials install the Knative-based serverless mode by default. If you follow upstream documentation and things look different, check which mode it assumes.

### The prerequisites, already done

We install KServe v0.20.0, released 6 Aug 2026. Its [installation guide](https://kserve.github.io/website/docs/admin-guide/kubernetes-deployment) asks for exactly three things, and §13 left all three in place:

| KServe wants | We have | From |
|---|---|---|
| Kubernetes **1.32+** | `v1.36.0` | Talos v1.13.0, §12 |
| cert-manager **≥ 1.15.0** | `v1.16.2` | §13.4 |
| Gateway API **v1.2.1** | `v1.2.1`, experimental channel | §13.4 |

If you skipped §13.4, go back. KServe's webhooks won't start without cert-manager, and its routing won't work without a `GatewayClass`.

📌 Gateway API v1.2.1 is still the required version at 0.20, unchanged since 0.15. That is why §13.4 pins it rather than taking the latest. The pin has lasted through four KServe releases.

### The one thing §13 did not leave you

⚠ **This cluster has no `LoadBalancer` implementation.** There is no OpenStack cloud-controller-manager and no MetalLB. So a `Service` of type `LoadBalancer` gets an `EXTERNAL-IP` of `<pending>` for ever. Nothing has needed one until now.

Envoy Gateway creates a `LoadBalancer` Service [by default](https://github.com/envoyproxy/gateway/blob/v1.2.4/api/v1alpha1/shared_types.go#L271) for every `Gateway`. Left at that default on this cluster, it starts a healthy Envoy pod whose `Gateway` status never receives an address, leaving §16's `curl` with nothing to connect to. Step 15.3 configures Envoy Gateway to expose the proxy as a `NodePort` Service instead.

### What you will do

Everything in this chapter goes into Git, through the Flux repository. There is no `kubectl apply`.

- **Create the namespace and a Helm source** (Step 15.1). Flux needs to know where KServe's charts live.

- **Install KServe's CRDs, then its controller** (Step 15.2), in Standard mode.

- **Add the Gateway, with an address the head node can reach** (Step 15.3). This is also where the 10-minute request timeout goes.

- **Check the controller, the CRDs, the Gateway address and the deployment mode** (the checkpoint).

📌 The KServe and Envoy Gateway documentation goes into more detail:

- [KServe's installation guide](https://kserve.github.io/website/docs/admin-guide/kubernetes-deployment), for Standard mode and its prerequisites.

- [KServe on GitHub](https://github.com/kserve/kserve), for the charts and release notes.

- [Envoy Gateway's deployment modes](https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/), which explain where the proxy is created in Step 15.3.

---

## Step 15.1 — A namespace, and a Helm source for KServe

KServe publishes its Helm charts in OCI (Open Container Initiative) format, from a container registry. First create the namespace that everything else here lands in, then tell Flux where the charts are:

```
head$ cd ~/ochami-lab-flux
head$ cat > infrastructure/controllers/kserve-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: kserve
EOF
head$ cat > infrastructure/controllers/kserve-source.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: kserve
  namespace: flux-system
spec:
  type: oci
  url: oci://ghcr.io/kserve/charts
  interval: 1h
EOF
```

🛑 **The namespace manifest is not optional.** The `HelmRelease` objects in Step 15.2 and the `Gateway` in Step 15.3 all live in `metadata.namespace: kserve`, so Flux's `kustomize-controller` has to create the `kserve` namespace before those objects can be applied. Setting `install.createNamespace: true` on the `HelmRelease` only tells Helm to create the target namespace when it installs the chart—which is one step too late when the `HelmRelease` object itself resides in `kserve`.

📌 The order of files in the directory doesn't matter. kustomize-controller applies namespaces and CRDs before everything else. So one `Namespace` manifest anywhere in the Kustomization covers every object in it. That includes Step 15.3's `Gateway`, which is in a different subdirectory but the same Flux `Kustomization`.

---

## Step 15.2 — CRDs, then the controller

There are two charts, installed in order, because the controller's own manifests use its CRDs. `dependsOn` makes helm-controller wait for the first `HelmRelease` to report `Ready` before it starts the second:

```
head$ cat > infrastructure/controllers/kserve.yaml << 'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kserve-crd
  namespace: kserve
spec:
  interval: 1h
  targetNamespace: kserve
  install:
    createNamespace: true
  chart:
    spec:
      chart: kserve-crd
      version: "v0.20.0"
      sourceRef:
        kind: HelmRepository
        name: kserve
        namespace: flux-system
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kserve
  namespace: kserve
spec:
  interval: 1h
  targetNamespace: kserve
  dependsOn:
    - name: kserve-crd
  chart:
    spec:
      chart: kserve-resources
      version: "v0.20.0"
      sourceRef:
        kind: HelmRepository
        name: kserve
        namespace: flux-system
  values:
    kserve:
      storage:
        resources:
          limits:
            # KServe's default is 1Gi, against a model of about the same size.
            # The init container is OOM-killed mid-download — see below.
            memory: 4Gi
      controller:
        # THE important setting: standard Kubernetes resources, no Knative.
        deploymentMode: Standard
        gateway:
          ingressGateway:
            enableGatewayApi: true
            kserveGateway: kserve/kserve-ingress-gateway
EOF
```

List all three files in the Kustomization, and push:

```
head$ cat > infrastructure/controllers/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - kserve-namespace.yaml
  - kserve-source.yaml
  - kserve.yaml
EOF
head$ ls infrastructure/controllers/
kserve-namespace.yaml  kserve-source.yaml  kserve.yaml  kustomization.yaml
head$ git add -A && git commit -m "Install KServe 0.20 in Standard (no-Knative) mode" && git push
head$ flux reconcile kustomization infrastructure --with-source
```

⚠ **Confirm with `ls` that all three new files exist before committing.** If you forgot `cd ~/ochami-lab-flux` in Step 15.1, the heredoc fails with:

```
-bash: infrastructure/controllers/kserve-namespace.yaml: No such file or directory
```

When everything is in place, `git commit` prints three `create mode` lines:

```
 create mode 100644 infrastructure/controllers/kserve-namespace.yaml
 create mode 100644 infrastructure/controllers/kserve-source.yaml
 create mode 100644 infrastructure/controllers/kserve.yaml
```

If a file listed in `kustomization.yaml` is missing on disk, Kustomize refuses to build the directory, `flux reconcile` waits indefinitely, and `flux get kustomizations` reports `accumulateFile "kserve-namespace.yaml": no such file or directory`.

⚠ **Pin the chart version.** `v0.20.0` above goes with Gateway API v1.2.1 from §13.4. KServe is moving quickly towards the `LLMInferenceService` model. On `latest`, a chart upgrade can change the CRD schemas under your committed manifests. Upgrade on purpose, in a commit, so you can see what changed.

📌 Why 0.20, when it is so new? The documentation you will reach for is 0.20's, so an older pin would mean following instructions for a different release. `Standard` has been valid since 0.15. `RawDeployment` is the old name, which KServe now [rewrites internally](https://github.com/kserve/kserve/blob/v0.20.0/pkg/constants/constants.go#L559). If 0.20 misbehaves, `v0.19.0` (14 Jun 2026) is the fallback.

⚠ **`deploymentMode` in the chart defaults to `Knative`, in every version.** Leave it out and you get the serverless mode this chapter avoids. The failure then appears in §16, as an `InferenceService` that never produces a pod.

Watch it arrive:

```
head$ flux get helmreleases -A
head$ kubectl -n kserve get pods -w
```

🛑 **The `storage.resources` override is set here, a chapter before it matters.** KServe's storage-initializer downloads the model weights into the pod. Its default memory limit is **1 GiB**, and the model is about 1 GB, downloaded in parallel chunks. Leave the default and §16's pod loops on `Init:OOMKilled`, where OOM means out of memory. Nothing you can see in this chapter warns you.

📌 The obvious setting for that limit is the wrong one. The `inferenceservice-config` ConfigMap has a `storageInitializer.memoryLimit`, fixed at `1Gi` by the chart. That isn't the one that applies. KServe matches the start of the model's `storageUri` against a **`ClusterStorageContainer`** called `default`. That container accepts `hf://` URIs, and takes its resources from `kserve.storage.resources`. The ConfigMap value is only a fallback, for URIs that no storage container claims. Confirm which one you changed:

```
head$ kubectl get clusterstoragecontainer default \
        -o jsonpath='{.spec.container.resources.limits.memory}'; echo
```

📌 The CRD chart is very large, and Flux is the right way to apply it. `serving.kserve.io_inferenceservices.yaml` alone is **1.9 MB**. That is why KServe ships its CRDs as a separate chart. `kubectl apply -f` on it fails with `metadata.annotations: Too long: must have at most 262144 bytes`. Helm doesn't use that annotation, so through Flux it causes no trouble. Know this before anyone applies the CRDs by hand.

Upstream also publishes a `kserve-crd-minimal` chart, with the validation schemas removed. We use the full one. If a more limited cluster ever hits a size limit, the minimal chart is the way out. The cost is that the API server no longer checks your manifests.

---

## Step 15.3 — The Gateway, and how it gets an address

KServe sends model traffic through a `Gateway` that you provide. This is the first one in the cluster, in the layer that §13.4 left empty on purpose. You need two objects, because of the `LoadBalancer` problem in the Introduction, plus a timeout policy:

```
head$ cat > infrastructure/configs/kserve-gateway.yaml << 'EOF'
# Tell Envoy Gateway to expose this Gateway's proxy as a NodePort service
# rather than the default LoadBalancer, which nothing here can fulfil.
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: kserve-proxy-nodeport
  namespace: kserve
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kserve-ingress-gateway
  namespace: kserve
spec:
  # Must match the GatewayClass from your §13.4 implementation:
  #   Envoy Gateway → "eg"        Istio → "istio"
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: kserve-proxy-nodeport     # same namespace as this Gateway; no namespace field exists
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All        # model InferenceServices live in their own namespaces
---
# Envoy's default route timeout is 15 seconds. Generating tokens on a CPU is
# far slower than that, so without this every non-trivial request is cut off
# mid-generation and the client gets an Envoy error page instead of JSON.
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: kserve-inference-timeout
  namespace: kserve
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: kserve-ingress-gateway     # policy and target MUST share a namespace
  timeout:
    http:
      requestTimeout: 600s
EOF
head$ cat > infrastructure/configs/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - kserve-gateway.yaml
EOF
head$ wc -l infrastructure/configs/kserve-gateway.yaml infrastructure/configs/kustomization.yaml
 35 infrastructure/configs/kserve-gateway.yaml
  4 infrastructure/configs/kustomization.yaml
head$ git add -A && git commit -m "KServe ingress Gateway, exposed as NodePort" && git push
head$ flux reconcile kustomization infrastructure --with-source
```

🛑 **Make sure `wc -l` reports `4` lines for `infrastructure/configs/kustomization.yaml` (not `3`).** §14.4 created that file as a three-line placeholder (`resources: []`). If the second `cat >` above didn't run, Flux reconciles the empty Kustomization without complaint, applies nothing, and `kubectl` later reports:

```
Error from server (NotFound): gateways.gateway.networking.k8s.io "kserve-ingress-gateway" not found
```

Similarly, `git commit` should report **two** changed files (`1 file changed` means `kustomization.yaml` was not updated):

```
 2 files changed, 39 insertions(+), 1 deletion(-)
 create mode 100644 infrastructure/configs/kserve-gateway.yaml
```

⚠ **`gatewayClassName` must match what you installed.** It is `eg` for Envoy Gateway and `istio` for Istio. Check with `kubectl get gatewayclass`. A wrong value leaves the Gateway `Programmed=False` for ever, and model endpoints never get an address.

### Why the `EnvoyProxy`, and why attached here

An `EnvoyProxy` describes how Envoy Gateway deploys the proxy: its replicas, resources and the Service in front of it. It is Envoy Gateway's own CRD.

We attach it to the `Gateway`, through `spec.infrastructure.parametersRef`, so it applies to this Gateway only. It could go on the `GatewayClass` instead, for every Gateway of that class. But §13.4 created the `GatewayClass` by hand with `kubectl apply`, and it isn't in Git. Editing it from Flux would make Flux take over an object `kubectl` already owns. That is the field-ownership conflict from §13.4. Attaching to the `Gateway` keeps the change inside a file Flux already owns.

📌 Envoy Gateway fills in the `Gateway` address differently for each Service type, which is why `NodePort` works ([`status/gateway.go`](https://github.com/envoyproxy/gateway/blob/v1.2.4/internal/gatewayapi/status/gateway.go#L50-L76)):

- **`LoadBalancer`**, the default, gives the load balancer's IPs. Here that is **empty**, because nothing assigns one.

- **`ClusterIP`** gives the cluster IP. That works inside the cluster, but not from the head node.

- **`NodePort`** gives **the node IPs**, `172.16.0.x`, which the head node can reach directly.

`NodePort` is the only one that both gets an address and can be reached from where you type `curl`.

📌 `spec.infrastructure.parametersRef` is available in both Gateway API channels at v1.2.1 (many similar extension fields are experimental-only), so this works regardless of which channel §13.4 left in place.

⚠ **The address is a node IP, but the port isn't 80.** A NodePort listener lands somewhere in `30000–32767`. So §16's requests need the port as well as the address. Get both:

```
head$ kubectl -n kserve get gateway kserve-ingress-gateway \
        -o jsonpath='{.status.addresses[0].value}'; echo
head$ kubectl get svc -A -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway \
        -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}'; echo
```

🛑 **Keep the `-A` on the second command, and don't "correct" it to `-n kserve`.** The `Gateway` object lives in `kserve`. But the Envoy proxy it creates, with its Deployment, Service and pod, lives in **`envoy-gateway-system`**, the controller's own namespace. That is Envoy Gateway's default ["controller namespace" deployment mode](https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/), with every proxy in one place ([`infra.go`](https://github.com/envoyproxy/gateway/blob/v1.2.4/internal/infrastructure/kubernetes/infra.go#L63)). Searching `kserve` for the Service finds nothing, and looks as if the Gateway failed. `-A` with the owner label works in either deployment mode.

📌 Any node IP works, so the one you get isn't special. A NodePort opens on *every* node in the cluster. `status.addresses` may list several, and `kubectl get gateway` shows only the first. `-o jsonpath='{.status.addresses[*].value}'` gives you all of them. Know this before anyone writes one into a config. The port is the stable half, and the address is any node that is up.

🛑 **On real hardware, use MetalLB or the OpenStack cloud-controller-manager instead.** [§21](21-summary.md) gives the reasons. NodePort suits a proof of concept on an isolated network. It needs no extra component and no address pool, and the head node is already on the node network. It is wrong for anything with real clients. The port is arbitrary, it changes if the Service is recreated, and there is no stable virtual IP to put in DNS. Switching later is one `EnvoyProxy` field plus an address pool, and the `Gateway` itself doesn't change.

### The ten-minute request timeout

🛑 **Envoy times out a route after 15 seconds by default, and inference takes longer than that.** This is the most confusing failure in §16, because it is a *partial* success. Short requests work and longer ones don't, and the difference is a number you didn't set. On our run, a request for eight tokens came back in about a second, and one for eighty failed.

The symptom is `curl … | jq` reporting:

```
parse error: Invalid numeric literal at line 1, column 9
```

That says nothing about timeouts. It means the body wasn't JSON, because Envoy replaced vLLM's answer with an error page. ⚠ **Drop the `| jq` and add `-i` as soon as a response fails to parse.** You are looking at the wrong layer's output, and `jq` can't tell you that.

📌 `BackendTrafficPolicy` is Envoy Gateway's own CRD, not part of Gateway API. Gateway API can set a timeout per route, with `HTTPRoute.spec.rules[].timeouts.request`. But **KServe generates the `HTTPRoute`**, and puts it back if you edit it by hand. A policy attached to the *Gateway* leaves KServe's objects alone. It also covers every model that ever routes through it, including ones added later. Use the same approach for anything you want to change about a route you don't own.

⚠ **The policy must be in the same namespace as the object it targets**, which here is `kserve`. A policy in the wrong namespace is accepted, reports nothing useful and does nothing.

HTTP only, on purpose. TLS (Transport Layer Security) on the model endpoint would need certificates for a name that only exists on an isolated network. §13.5's SSH tunnel is the way in. On real hardware, put a real certificate here. cert-manager is already installed for exactly that.

---

## ✅ Checkpoint

Captured 15 Aug 2026 on `och-head`:

```
head$ flux get helmreleases -A
NAMESPACE  NAME        REVISION  SUSPENDED  READY  MESSAGE
kserve     kserve      v0.20.0   False      True   Helm install succeeded for release kserve/kserve-kserve.v1 with chart kserve-resources@v0.20.0
kserve     kserve-crd  v0.20.0   False      True   Helm install succeeded for release kserve/kserve-kserve-crd.v1 with chart kserve-crd@v0.20.0

head$ kubectl -n kserve get pods
NAME                                         READY   STATUS    RESTARTS   AGE
kserve-controller-manager-8547c64c57-j2xsq   2/2     Running   0          27m

head$ kubectl get crd | grep kserve
clusterservingruntimes.serving.kserve.io         2026-08-15T11:45:22Z
clusterstoragecontainers.serving.kserve.io       2026-08-15T11:45:22Z
inferencegraphs.serving.kserve.io                2026-08-15T11:45:22Z
inferenceservices.serving.kserve.io              2026-08-15T11:45:23Z
servingruntimes.serving.kserve.io                2026-08-15T11:45:22Z
trainedmodels.serving.kserve.io                  2026-08-15T11:45:22Z

head$ kubectl -n kserve get gateway kserve-ingress-gateway
NAME                     CLASS   ADDRESS      PROGRAMMED   AGE
kserve-ingress-gateway   eg      172.16.0.3   True         2m52s

head$ kubectl -n kserve get configmap inferenceservice-config \
        -o jsonpath='{.data.deploy}' ; echo
{
  "defaultDeploymentMode": "Standard"
}
```

There are six CRDs, and `llminferenceservices` isn't one of them. That is explained below. **`172.16.0.3` is `nid0003`**, a worker node, chosen only by ordering.

Two of those five checks matter most:

⚠ **A non-empty `ADDRESS` is the whole point of Step 15.3, and `PROGRAMMED True` doesn't imply it.** Envoy Gateway reports `Programmed` from the state of the proxy *deployment*. The address comes from the Service. With the `EnvoyProxy` wrong, a healthy but unreachable Gateway reports `True` with an empty address column. In §16 that shows up as an empty `${GW}`, and a `curl` to `http:///v1/…`. Read both columns.

⚠ **`defaultDeploymentMode` is the value to confirm before §16.** If it says `Knative`, or the old name `Serverless`, the Helm values didn't apply. Every `InferenceService` would then wait for Knative objects that don't exist. Nothing in that failure hints at a chart value you set two steps ago.

📌 `LLMInferenceService` is left out on purpose. At 0.20 it ships in its own pair of charts, `kserve-llmisvc-crd` and `kserve-llmisvc-resources`, so nothing installed here provides it. That is the right default for us. It brings the llm-d architecture, which splits prefill from decode and routes by cache. That needs hardware we don't have until §18. Adding it later means two more `HelmRelease` objects next to these, not a reinstall.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `Kustomization/infrastructure` fails with `namespaces "kserve" not found` | The namespace manifest from Step 15.1 is missing, misspelt, or not listed in `infrastructure/controllers/kustomization.yaml` |
| `flux reconcile` sits at `◎ waiting for Kustomization reconciliation` and never returns | Not a hang. It is waiting on a build that can't succeed. Press `Ctrl-C`, since nothing is mid-flight, then run `flux get kustomizations` for the real message |
| `accumulateFile "<name>.yaml": … no such file or directory` | `kustomization.yaml` lists a file that doesn't exist. Almost always a heredoc that ran before `cd ~/ochami-lab-flux`. Check with `ls infrastructure/controllers/` |
| Flux reports success, but the object is `NotFound` | The reverse: the file exists but **isn't listed** in `kustomization.yaml`, so Kustomize built nothing. Run `wc -l infrastructure/configs/kustomization.yaml`. `3` means it is still §14.4's empty placeholder |
| `HelmRelease kserve` stuck on `dependency 'kserve/kserve-crd' is not ready` | Usually brief, while the 1.9 MB CRD chart installs. If it lasts, read the CRD release in `flux logs -n flux-system --kind HelmRelease` |
| `metadata.annotations: Too long: must have at most 262144 bytes` | You applied the KServe CRDs with `kubectl apply -f`. Let Flux install the `kserve-crd` chart instead (Step 15.2) |
| `Gateway` shows `PROGRAMMED True`, but `ADDRESS` is empty | The `EnvoyProxy` isn't attached. Check `spec.infrastructure.parametersRef` on the Gateway, and that the `EnvoyProxy` is in the **same namespace**. The reference has no namespace field, so a copy in `envoy-gateway-system` is silently not found |
| `Gateway` shows `PROGRAMMED False`, and there is no Envoy pod | `gatewayClassName` doesn't match a `GatewayClass` with `ACCEPTED True`. Check with `kubectl get gatewayclass` |
| The Envoy Service is a `LoadBalancer`, with `EXTERNAL-IP <pending>` | The `EnvoyProxy` was applied after the Gateway, and the Service wasn't recreated. Run `kubectl delete svc -A -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway`, and let the controller rebuild it |
| `kubectl -n kserve get svc` shows no Envoy Service and no proxy pod | Not a failure. The proxy is created in **`envoy-gateway-system`**, not in the Gateway's namespace. Use `-A` with the `owning-gateway-name` label |
| `curl … \| jq` gives `parse error: Invalid numeric literal at line 1, column 9` (§16) | Envoy cut the request off at its 15-second default and returned an error page. Check the `BackendTrafficPolicy` in Step 15.3 is applied, in the `kserve` namespace |
| `defaultDeploymentMode` reads `Knative` | The `values:` block didn't apply. Check the indentation under `kserve.controller`, which is three levels deep and the easiest thing here to get wrong |
| Webhook errors that mention certificates | cert-manager isn't `Ready`, or was installed after KServe. Check `kubectl -n cert-manager get pods`, then run `flux reconcile helmrelease kserve -n kserve --force` |
| `flux reconcile` says the source is up to date, but your file isn't there | You committed but didn't push. Check with `git log origin/main..HEAD` |

Next: [§16 — Serving an LLM with vLLM](16-vllm-inference.md)
