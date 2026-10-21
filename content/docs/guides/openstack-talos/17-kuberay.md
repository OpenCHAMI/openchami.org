---
title: "§17 — Ray and KubeRay"
description: "You add Ray, the layer that matters most once a cluster has more than one kind of accelerator."
slug: "17-kuberay"
date: 2026-10-21
lastmod: 2026-10-21
weight: 170
toc: true
draft: false
---
> ⏱ **About 20 minutes** · on the head node, committing to Git · installs the KubeRay operator and a small CPU Ray cluster
>
> - **What this chapter is for.** You add Ray, the layer that matters most once a cluster has more than one kind of accelerator. You finish with a Ray cluster spread over two pods, and proof that it shares work between them.
>
> - **What you will learn.** What Ray and KubeRay are, when Ray Serve suits better than KServe, and how Ray places work on the right hardware.
>
> - **Skip it if** you only need the inference endpoint from §16. Nothing later depends on this chapter, apart from the Ray examples in §18.

---

## Introduction

### Ray is a distributed execution framework

You write Python, and Ray runs it across a cluster, moving objects between processes and machines for you. In inference workloads, it appears in three forms:

| Ray piece | What it does |
|---|---|
| **Ray Core** | Tasks and actors: the general-purpose distributed scheduler. This is the "heterogeneous workload scheduler" in the stack this tutorial builds |
| **Ray Serve** | A serving layer built on Core: compose multiple models and Python steps into one deployment graph, each part scaled independently |
| **Ray Data / Train** | Batch inference and training, on the same cluster |

### KubeRay runs Ray on Kubernetes

KubeRay is the Kubernetes operator for Ray. It adds three CRDs (custom resource definitions):

- **`RayCluster`**, a long-lived head pod plus worker pods, with autoscaling.

- **`RayJob`**, which runs a script on a cluster and then removes the cluster.

- **`RayService`**, a Ray Serve application, updated without downtime.

### Why bother, when §16 works?

There are three reasons, though only the third matters for this build:

1. **Serving pipelines, not single endpoints.** A real inference service is rarely a single model. It might combine retrieval, re-ranking, a guardrail model and a summariser, each with different hardware needs. KServe gives you one endpoint per model and `InferenceGraph` to chain them. Ray Serve lets you write the whole graph in Python and scale each step independently, which suits agent frameworks such as LangGraph and CrewAI.

2. **Model parallelism across nodes.** When a model doesn't fit on one accelerator, vLLM splits it across several. That requires a distributed runtime underneath, and Ray is the one vLLM uses. A 0.5 B model never needs this, but a 70 B model spanning multiple accelerators does.

3. **Heterogeneous scheduling, the real reason Ray is here.** Ray schedules on *custom resources*. A task can request `{"CPU": 4, "GPU": 1, "accelerator_type:RTX": 1}` and it will run only where that hardware exists. With NVIDIA, AMD and Intel accelerators in the same cluster, matching work to hardware becomes a scheduling rule rather than manual placement.

Ray Serve and KServe can be used together:

| | KServe (§15) | Ray Serve |
|---|---|---|
| Unit of thought | A model, declared in YAML | A Python application graph |
| Who writes it | Platform/ops | ML engineers |
| Scaling | HPA per model | per-deployment, inside Ray |
| Multi-node model parallelism | Delegates to the engine (which uses Ray) | Native |
| Coexist? | Yes — a `RayService` can sit behind a KServe endpoint, and KServe's own multi-node serving uses Ray underneath |

ML is machine learning, and HPA is Kubernetes' Horizontal Pod Autoscaler.

Here we start a `RayCluster`, prove it schedules work across pods, and stop. Using Ray Serve as the primary serving path is a natural follow-on experiment.

### What you will do

- **Install the KubeRay operator** (Step 17.1), through Flux.

- **Create a small `RayCluster`** (Step 17.2), sized for CPU-only workers.

- **Prove it schedules** (Step 17.3). Twenty small tasks should run on more than one pod. This is the checkpoint.

- **See what changes with accelerators** (Step 17.4). Nothing to run, just the shape §18 fills in.

📌 The Ray and KubeRay documentation goes into more detail:

- [The KubeRay Helm charts](https://ray-project.github.io/kuberay-helm/), the chart repository Step 17.1 installs from. Its README covers installing the CRDs separately.

---

## Step 17.1 — The KubeRay operator

```
head$ cd ~/ochami-lab-flux
head$ cat > infrastructure/controllers/kuberay.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: kuberay
  namespace: flux-system
spec:
  url: https://ray-project.github.io/kuberay-helm/
  interval: 1h
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kuberay-operator
  namespace: kuberay-system
spec:
  interval: 1h
  targetNamespace: kuberay-system
  install:
    createNamespace: true
  chart:
    spec:
      chart: kuberay-operator
      version: "1.6.0"
      sourceRef:
        kind: HelmRepository
        name: kuberay
        namespace: flux-system
EOF
head$ cat > infrastructure/controllers/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - kserve-source.yaml
  - kserve.yaml
  - kuberay.yaml
EOF
head$ git add -A && git commit -m "Install KubeRay operator 1.6.0" && git push
head$ flux reconcile kustomization infrastructure --with-source
head$ kubectl -n kuberay-system get pods
```

The chart installs both the operator and the CRDs for `RayCluster`, `RayJob`, `RayService` and `RayCronJob`. If your cluster separates permissions for CRDs and operators, you can install the CRDs first with `kubectl create -k` and pass `--skip-crds` to the chart (see the KubeRay chart README).

---

## Step 17.2 — A small `RayCluster`

This cluster is sized for our CPU-only workers. The resource requests are small on purpose: the goal is to see scheduling work, not to run a heavy job.

```
head$ mkdir -p apps/ray
head$ cat > apps/ray/raycluster.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ray
---
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: och-ray
  namespace: ray
spec:
  rayVersion: "2.56.0"
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
    template:
      spec:
        containers:
          - name: ray-head
            image: rayproject/ray:2.56.0
            ports:
              - { containerPort: 6379,  name: gcs }
              - { containerPort: 8265,  name: dashboard }   # Ray dashboard
              - { containerPort: 10001, name: client }
            resources:
              requests: { cpu: "1", memory: 3Gi }
              limits:   { cpu: "2", memory: 4Gi }
  workerGroupSpecs:
    - groupName: cpu-workers
      replicas: 1
      minReplicas: 1
      maxReplicas: 3
      template:
        spec:
          containers:
            - name: ray-worker
              image: rayproject/ray:2.56.0
              resources:
                requests: { cpu: "1", memory: 3Gi }
                limits:   { cpu: "2", memory: 4Gi }
EOF
head$ cat > apps/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - inference/qwen05b.yaml
  - ray/raycluster.yaml
EOF
head$ git add -A && git commit -m "A small CPU RayCluster" && git push
head$ flux reconcile kustomization apps --with-source
head$ kubectl -n ray get rayclusters,pods
```

⚠ **`rayVersion` and the image tag must match.** A mismatch causes obscure GCS (Global Control Store) connection failures rather than a clear error. Both are set to `2.56.0` above; update them together when you upgrade.

⚠ **Ray head pods need more memory than you might expect.** The head runs the GCS, the dashboard and the autoscaler. With less than about 3 GiB it can be OOM-killed (out of memory), which looks like a network failure. If quota is tight, reduce memory on the worker group rather than the head.

---

## Step 17.3 — Prove it schedules

```
head$ kubectl -n ray exec -it deploy/och-ray-head -- python -c "
import ray; ray.init(address='auto')
print('nodes:', len(ray.nodes()))
print('resources:', ray.cluster_resources())

@ray.remote
def where(): 
    import socket; return socket.gethostname()

print('tasks ran on:', set(ray.get([where.remote() for _ in range(20)])))
"
```

---

## ✅ Checkpoint

This output hasn't been captured from a live run yet, but you should see `nodes: 2`, a `resources` dictionary with a `CPU` entry, and **more than one hostname** after `tasks ran on:` (one starting with `och-ray-head-` and another with `och-ray-cpu-workers-`).

Seeing two different hostnames in that set proves the work was shared across pods. Notice too that `ray.cluster_resources()` has **no `GPU` key**. §18 adds that on real hardware, and seeing its absence now makes the difference concrete.

You can open the Ray dashboard using the SSH tunnel pattern from §13.5:

```
head$   kubectl -n ray port-forward svc/och-ray-head-svc 8265:8265
devbox$ ssh -i ~/.ssh/och_ed25519 -N -L 8265:localhost:8265 rocky@${OCH_HEAD_FIP}
# then open http://localhost:8265
```

Step 5.5 already opened port 8265 in the security group for this.

---

## Step 17.4 — What this becomes with accelerators

There is nothing to run here today—this is the structure §18 fills in. Once nodes have GPUs and a device plugin advertises them, each worker group targets a specific class of hardware:

```yaml
  workerGroupSpecs:
    - groupName: rtx-workers
      replicas: 2
      template:
        spec:
          nodeSelector:
            nvidia.com/gpu.product: NVIDIA-RTX-PRO-6000-Blackwell
          containers:
            - name: ray-worker
              image: rayproject/ray:2.56.0-gpu
              resources:
                limits:
                  nvidia.com/gpu: 4
    - groupName: mi210-workers
      # …amd.com/gpu: 2, on the AMD nodes
    - groupName: gaudi-workers
      # …habana.ai/gaudi: 4, on a Gaudi node
```

A workload then requests what it needs, and Ray places it:

```python
@ray.remote(num_gpus=1, accelerator_type="NVIDIA_RTX_PRO_6000")
def generate(prompt): ...
```

This is heterogeneous scheduling, and it is the main reason to add Ray rather than relying on KServe alone.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| Head pod `Pending`, `Insufficient memory` | The head needs about 3 GiB (the ⚠ in Step 17.2). Shrink the worker group instead |
| Workers never join, with GCS connection errors in the worker logs | `rayVersion` doesn't match the image tag, or the head's Service doesn't resolve. Check with `kubectl -n ray get svc` |
| `ray.init(address='auto')` fails inside the head pod | The head hasn't finished starting. Check `kubectl -n ray logs deploy/och-ray-head` |
| Dashboard blank over the tunnel | `dashboard-host: "0.0.0.0"` is missing from `rayStartParams`. It defaults to localhost |
| `RayCluster` created, but no pods | The operator isn't running. Check `kubectl -n kuberay-system get pods`, then `flux get helmreleases -A` |
| Everything `Pending` after adding Ray | The cluster is out of capacity. Ray and vLLM together need more than two small workers. Set `qwen05b` to `minReplicas: 0` for now, or add a worker (§9.3) |

Next: [§18 — Heterogeneous Hardware](18-heterogeneous-hardware.md)
