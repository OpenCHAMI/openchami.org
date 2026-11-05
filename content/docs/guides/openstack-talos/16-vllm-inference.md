---
title: "§16 — Serving an LLM with vLLM"
description: "This is the goal of the whole tutorial. You serve a small language model through KServe, and send it a question over HTTP."
slug: "16-vllm-inference"
date: 2026-10-21
lastmod: 2026-10-21
weight: 160
toc: true
draft: false
---
> ⏱ **About 30 minutes**, most of it downloading the model · on the head node, committing to Git · creates a vLLM runtime and a model endpoint you can talk to
>
> - **What this chapter is for.** This is the goal of the whole tutorial. You serve a small language model through KServe, and send it a question over HTTP. You finish with an OpenAI-compatible endpoint that answers.
>
> - **What you will learn.** What vLLM adds over a plain inference loop, how to check a container image's arguments before you deploy it, and why a fluent wrong answer still passes the checkpoint.
>
> - **Don't skip it.** Every earlier chapter exists to make this one work.

---

## Introduction

### vLLM is an inference engine

vLLM takes model weights and a request, and produces tokens. It is the usual choice over a plain PyTorch loop because of throughput. Three features matter:

- **PagedAttention.** vLLM stores the KV (key-value) cache in fixed-size blocks, like pages of virtual memory. Without it, each sequence needs one large contiguous block. Fragmentation then limits how many requests can run at once.

- **Continuous batching.** A new request joins the running batch as soon as any sequence finishes. It doesn't wait for the whole batch. On a busy server this gives several times the throughput.

- **An OpenAI-compatible API**, with `/v1/chat/completions`, `/v1/completions` and `/v1/models`. Application frameworks such as LangGraph and CrewAI already speak the OpenAI API, so they can use vLLM unchanged.

### The reality check: we have no GPUs

Real inference hardware has NVIDIA, AMD or Intel accelerators. Our OpenStack project has none. So this chapter runs vLLM on CPU. Be clear about what that does and doesn't prove:

| Proves | Does not prove |
|---|---|
| The whole control path: Flux → KServe → runtime → pod → Gateway → HTTP | Anything about performance |
| The `InferenceService` abstraction and its scaling | GPU scheduling, device plugins, MIG (Multi-Instance GPU), or memory sizing |
| An OpenAI-compatible endpoint the application layer can target | multi-GPU or multi-node parallelism |
| That fluent English comes back over HTTP | **That anything it says is true** — see the checkpoint |

Ours took about 8 seconds for a reply capped at 80 tokens. That is single-digit tokens per second, on a server CPU with no AVX-512. For scale, a modern accelerator serving an 8 B (8-billion-parameter) model is quoted in the thousands of tokens per second. A CPU-only compute node manages the low hundreds. §18 is where performance becomes a real subject.

vLLM's own documentation notes that the CPU backend is built for prototyping rather than production throughput, which is exactly how we use it here.

### A small model that needs no secrets

We serve `Qwen/Qwen2.5-0.5B-Instruct`. It suits this cluster for four reasons:

- **It is about 1 GB of weights**, so it downloads and loads in minutes.

- **It keeps 30 GB nodes workable.** The disk goes on the vLLM CPU image, not on the weights. Before you move to a larger model, check the node's free image filesystem. The kubelet starts evicting pods at 15% free, well before the disk is full.

- **It is instruction-tuned**, so `/v1/chat/completions` gives sensible output.

- **It isn't gated on Hugging Face.** No access token means no secret to manage, so §14's "nothing secret in Git" rule still holds.

Gemma-2B or Llama-3-8B are natural next steps. Both are *gated*. They need a Hugging Face token, which means a Kubernetes Secret, which means SOPS (Secrets OPerationS, §14.4). Move to them once the plumbing works. Only the model name and the token change.

If 0.5 B is still too slow on CPU, there is room below it. All of these are Apache 2.0 and ungated, so swapping is a one-line change to `storageUri`. Surveyed 10 Aug 2026:

| Model | Params | Weights | Notes |
|---|---|---|---|
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5 B | ~1 GB | **What this chapter uses.** The smallest size that reliably holds a conversation |
| `HuggingFaceTB/SmolLM2-360M-Instruct` | 360 M | ~720 MB | The useful floor. Noticeably faster on CPU; summarises and chats, weak at reasoning |
| `HuggingFaceTB/SmolLM2-135M-Instruct` | 135 M | ~270 MB | ~4× faster again, but output often fails to make sense. Use it to prove the *plumbing*, not to demo |

Both SmolLM2 sizes are `LlamaForCausalLM` models. vLLM has long supported that architecture, as [a vLLM maintainer confirmed](https://github.com/vllm-project/vllm/issues/14576). So no runtime change is needed.

⚠ **Going smaller doesn't save meaningful disk space.** Moving from 0.5 B down to 135 M saves less than a gigabyte, whereas the vLLM CPU container image is several times larger. If disk space is tight, use a larger flavor—dropping to 135 M sacrifices coherent output without solving the storage constraint.

### What you will do

- **Define a vLLM runtime for CPU** (Step 16.1). KServe's own runtimes target GPUs, so you write one.

- **Check the image's arguments before deploying it** (Step 16.1a). Thirty seconds on the head node, instead of a crash loop on a worker.

- **Declare the model** (Step 16.2), as an `InferenceService` committed to Git for Flux to apply.

- **Ask it something** (Step 16.3), first straight to the pod and then through the Gateway.

- **Save the endpoint lookup as shell helpers** (Step 16.3a), so it still works after you log out.

- **Get an answer from the model** (the checkpoint), and record a first throughput figure.

📌 The vLLM and Hugging Face documentation go into more detail:

- [The vLLM documentation](https://docs.vllm.ai/), including its CPU backend and the `vllm serve` arguments.

- [The vLLM CPU release images](https://gallery.ecr.aws/q9t5s3a7/vllm-cpu-release-repo), for the tags you can use in Step 16.1.

- [The `Qwen2.5-0.5B-Instruct` model card](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) on Hugging Face.

---

## Step 16.1 — A `ServingRuntime` for vLLM on CPU

KServe ships runtimes aimed at GPUs, so we define a CPU one. On real hardware you define one runtime for each accelerator family.

```
head$ cd ~/ochami-lab-flux
head$ cat > infrastructure/configs/vllm-cpu-runtime.yaml << 'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: ClusterServingRuntime
metadata:
  name: vllm-cpu
spec:
  annotations:
    prometheus.kserve.io/port: "8000"
    prometheus.kserve.io/path: "/metrics"
  supportedModelFormats:
    - name: huggingface
      version: "1"
      autoSelect: false        # opt in explicitly; don't shadow the GPU runtimes
      priority: 1
  protocolVersions:
    - v2
    - v1
  containers:
    - name: kserve-container
      # Official vLLM CPU release image. Tag surveyed 15 Aug 2026: v0.27.1,
      # linux/amd64, built 11 Aug 2026, 1.77 GB compressed across 12 layers.
      # Tags: https://gallery.ecr.aws/q9t5s3a7/vllm-cpu-release-repo
      # NO `command:` — the image's entrypoint is ["vllm", "serve"] and the
      # model is a POSITIONAL argument. See §16.1a before changing this.
      image: public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.27.1
      args:
        - /mnt/models               # positional: `vllm serve <model_tag>`
        - --served-model-name={{.Name}}
        - --port=8000
        - --host=0.0.0.0
        - --dtype=bfloat16          # fall back to float32 if the CPU lacks bf16
        - --max-model-len=2048      # keep the KV cache small; CPU RAM is the limit
      env:
        # vLLM's CPU backend needs an explicit KV-cache budget, in GiB. It is
        # taken from ordinary RAM, so it must fit inside the pod's memory limit
        # ALONGSIDE the weights.
        - name: VLLM_CPU_KVCACHE_SPACE
          value: "4"
        # NO VLLM_CPU_OMP_THREADS_BIND. It takes a list of CPU IDs ("0-3"),
        # not "all", and a wrong value kills the engine at startup. A CPU
        # *limit* is a quota, not a pinning — the container still sees every
        # host thread — so any list we hard-coded here would be a guess.
      ports:
        - containerPort: 8000
          protocol: TCP
      volumeMounts:
        # vLLM's API server and its engine are SEPARATE PROCESSES that talk
        # over a shared-memory ring buffer. Kubernetes gives every pod a
        # 64 MiB /dev/shm; vLLM wants 160 MiB and refuses to start without it.
        - name: dshm
          mountPath: /dev/shm
      resources:
        requests:
          cpu: "2"
          memory: 8Gi
        limits:
          cpu: "4"
          memory: 12Gi
  volumes:
    - name: dshm
      emptyDir:
        medium: Memory      # a RAM disk, not the node's filesystem
        sizeLimit: 2Gi
EOF
```

🛑 **The `/dev/shm` mount is not optional. Without it, Step 16.2's pod crash-loops.** Kubernetes gives each pod 64 MiB of shared memory, a default inherited from Docker. That is too small for anything that uses shared memory heavily, and PyTorch data loaders hit it too. vLLM asks for 160 MiB, and its error message states the number.

⚠ **`medium: Memory` comes out of the pod's RAM, not the node's disk.** The 2 GiB above counts against the 12 GiB limit, alongside the weights and the KV cache. It is generous on purpose, because the need grows with parallelism. If memory is tight, `512Mi` still clears the 160 MiB comfortably.

Key settings in the runtime:

- **`/mnt/models` as a bare positional argument.** `vllm serve` takes the model first and everything else as options. KServe's storage initialiser puts the downloaded weights at this path.

- **`--dtype=bfloat16`** halves memory compared with float32. It needs CPU support for bf16 (bfloat16). If the pod dies with an unsupported-dtype error, use `float32` and double the memory request.

- **`--max-model-len=2048`** limits the context length. The KV cache grows with context, and on CPU it shares RAM with the weights. A long context is what runs you out of memory, not the model size.

- **`VLLM_CPU_KVCACHE_SPACE`** is specific to CPU, and in practice required. It is a *reservation*. Its 4 GiB, plus about 1 GB of weights, plus overhead, is why the memory limit is 12 GiB.

- **`{{.Name}}`** is filled in by KServe with the `InferenceService` name. So the model name in the API matches the object name.

### Step 16.1a — Interrogate the image before you deploy it

🛑 **Check the image on the head node first. It takes thirty seconds, instead of a `CrashLoopBackOff` after a 1.8 GB pull onto a worker.** vLLM exits with an error on any argument it doesn't recognise. In Kubernetes, that is a pod that starts and dies at once, with nothing useful in `kubectl describe`. The head node already runs podman:

```
head$ sudo podman run --rm public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.27.1 --help 2>&1 | head -12
usage: vllm serve [model_tag] [options]

Launch a local OpenAI-compatible API server to serve LLM
completions via HTTP. Defaults to Qwen/Qwen3-0.6B if no model is specified.
…
```

Notice the first line: in `vllm serve [model_tag]`, the model path is a **positional** argument, and the container image's entrypoint already supplies `vllm serve`. That is why the runtime above sets `args` without overriding `command`.

Then confirm that every flag you pass exists in *this* tag:

```
head$ sudo podman run --rm public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.27.1 \
        --help=all 2>&1 | grep -E '^\s*--(dtype|max-model-len|served-model-name|host|port)\b'
  --host HOST           Host name. (default: None)
  --port PORT           Port number. (default: 8000)
  --dtype {auto,bfloat16,float,float16,float32,half}
  --max-model-len MAX_MODEL_LEN
  --served-model-name SERVED_MODEL_NAME [SERVED_MODEL_NAME ...]
```

📌 The `--dtype` line lists every value you are allowed to use. `bfloat16` is there, and so is the `float32` fallback. `auto` would also work, and picks the type from the model's own config.

⚠ **Remove any flag that doesn't appear in `--help`.** Older vLLM guides pass `--device=cpu` and `--disable-log-requests`, both of which have been removed in current releases (vLLM now detects the CPU platform automatically and leaves request logging off by default). Passing either flag causes the container to exit immediately:

```
head$ sudo podman run --rm --entrypoint python3 \
        public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.27.1 \
        -m vllm.entrypoints.openai.api_server --help 2>&1 \
      | grep -E 'disable-log-requests|max-model-len|served-model-name|--device'
                     [--max-model-len MAX_MODEL_LEN]
                     [--served-model-name SERVED_MODEL_NAME [SERVED_MODEL_NAME ...]]
                     [--device-ids DEVICE_IDS]
```

📌 The older `python3 -m vllm.entrypoints.openai.api_server` form still works. It shares the same argument parser, so the grep above finds the same flags. The image is built around the `vllm serve` entrypoint, though, so this chapter uses that.

📌 1.77 GB compressed is roughly 4–5 GB on disk. Each node pulls it once, through the head node's NAT (network address translation). That dwarfs the ~1 GB of model weights.

🛑 **Environment variables have no `--help`, so you can only test them by starting the process.** For example, `VLLM_CPU_OMP_THREADS_BIND=all` looks reasonable, but vLLM parses the value as a list of CPU IDs. The engine dies at startup:

```
(EngineCore pid=62)   File "…/vllm/utils/cpu_resource_utils.py", line 118, in parse_id_list
(EngineCore pid=62)     result.append(int(part))
(EngineCore pid=62) ValueError: invalid literal for int() with base 10: 'all'
```

So keep a runtime's environment as small as you can. A stale flag shows up in `--help`. A stale environment variable only shows up when the pod fails.

---

## Step 16.2 — The `InferenceService`

```
head$ mkdir -p apps/inference
head$ cat > apps/inference/qwen05b.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: inference
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen05b
  namespace: inference
  annotations:
    # Belt and braces: §15 set Standard cluster-wide, but being explicit here
    # means this manifest behaves the same on a cluster that didn't.
    serving.kserve.io/deploymentMode: Standard
spec:
  predictor:
    minReplicas: 1          # never scale to zero: reloading weights is expensive
    maxReplicas: 2
    model:
      runtime: vllm-cpu
      modelFormat:
        name: huggingface
      # KServe's HuggingFace storage initialiser downloads the repo into
      # /mnt/models before the runtime container starts.
      storageUri: hf://Qwen/Qwen2.5-0.5B-Instruct
      resources:
        requests:
          cpu: "2"
          memory: 8Gi
        limits:
          cpu: "4"
          memory: 12Gi
EOF
head$ cat > apps/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - inference/qwen05b.yaml
EOF
head$ cat > infrastructure/configs/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - kserve-gateway.yaml
  - vllm-cpu-runtime.yaml
EOF
head$ git add -A && git commit -m "Serve Qwen2.5-0.5B-Instruct on vLLM CPU via KServe" && git push
head$ flux reconcile kustomization infrastructure --with-source
head$ flux reconcile kustomization apps --with-source
```

Watch it come up. The first start downloads about 1 GB of weights through the head node's NAT, then loads them. Give it several minutes:

```
head$ kubectl -n inference get inferenceservice -w
head$ kubectl -n inference get pods
head$ kubectl -n inference logs -l serving.kserve.io/inferenceservice=qwen05b \
        -c kserve-container -f
```

You are waiting for vLLM's startup banner, then `Application startup complete` and `Uvicorn running on http://0.0.0.0:8000`.

---

## Step 16.3 — Ask it something

Get the endpoint the Gateway assigned:

```
head$ kubectl -n inference get inferenceservice qwen05b
NAME      URL                                          READY  AGE
qwen05b   http://qwen05b.inference.<gateway-address>   True   6m
```

First, test the model on its own. Port-forward straight to the pod, which skips the routing:

```
head$ kubectl -n inference port-forward \
        svc/qwen05b-predictor 8000:80 &
head$ curl -s http://localhost:8000/v1/models | jq .
```

Then test it through the Gateway, which is what an application would do.

⚠ **You need an address *and* a port.** §15.3 exposes the Gateway as a `NodePort`, because this cluster has no `LoadBalancer` implementation. So the address is a node's IP, and the port is in the range `30000–32767`, not 80:

```
head$ GW=$(kubectl -n kserve get gateway kserve-ingress-gateway \
             -o jsonpath='{.status.addresses[0].value}')
head$ GWPORT=$(kubectl get svc -A \
             -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway \
             -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}')
head$ echo "${GW}:${GWPORT}"

head$ HOST=$(kubectl -n inference get httproute \
             -o jsonpath='{.items[0].spec.hostnames[0]}')
head$ echo "GW=$GW  GWPORT=$GWPORT  HOST=$HOST"
GW=172.16.0.3  GWPORT=30791  HOST=qwen05b-inference.example.com
```

⚠ **Check all three are set before going further.** An empty variable gives a confusing failure, not an obvious one. You get `http://172.16.0.3:/v1/…`, or a request with no `Host` header, and neither says what is wrong.

⚠ **The `Host:` header is not optional.** KServe routes by hostname, so a request to the Gateway's IP without it gets a 404 from Envoy. The name is a *routing key*, and it is never looked up in DNS. KServe builds it from its `domainTemplate` (`{{.Name}}-{{.Namespace}}.{{.IngressDomain}}`) and the chart's default domain.

📌 There are two `HTTPRoute`s, and `items[0]` is the right one. KServe creates `qwen05b`, the top-level service, and `qwen05b-predictor`, the component. Use the first. The second skips the routing layer you are trying to test.

Now the request:

```
head$ curl -s http://${GW}:${GWPORT}/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -H "Host: ${HOST}" \
    -d '{
      "model": "qwen05b",
      "messages": [
        {"role": "user", "content": "In two sentences, what is OpenCHAMI for?"}
      ],
      "max_tokens": 80,
      "temperature": 0.2
    }' | jq -r '.choices[0].message.content'
```

🛑 **`parse error: Invalid numeric literal` means you got an Envoy error page, not JSON.** Almost always, §15.3's `BackendTrafficPolicy` is missing. The request then hit Envoy's default 15-second timeout partway through generating. Two commands tell a routing fault from a timeout:

```
head$ curl -s -i -m 30 http://${GW}:${GWPORT}/v1/models -H "Host: ${HOST}" | head -6
head$ curl -s -i -m 120 http://${GW}:${GWPORT}/v1/chat/completions \
    -H 'Content-Type: application/json' -H "Host: ${HOST}" \
    -d '{"model":"qwen05b","messages":[{"role":"user","content":"Say hello."}],"max_tokens":8}' | tail -3
```

- **The first generates nothing, so it returns in milliseconds.** `200 OK` means **routing is fine**.

- **The second generates eight tokens, which takes well under 15 seconds.** If that works and eighty tokens doesn't, the problem is the timeout, not the route.

⚠ **When a response fails to parse, drop `| jq` and add `-i`.** `jq` can only tell you the body wasn't JSON. The headers tell you which layer sent it.

### Step 16.3a — Make the endpoint survive a logout

🛑 **Those three variables disappear with the shell, and an empty one fails in a way that looks like success.** Come back tomorrow, run the `curl` from your history, and you get this:

```
head$ time curl -s http://${GW}:${GWPORT}/v1/chat/completions … | jq -r '…'

real    0m0.008s
```

It returns in **eight milliseconds** with no output and no error because `curl` immediately rejects the malformed `http://:/v1/chat/completions` URL without sending a request.

Write the helpers into a file the shell already picks up:

```
head$ cat > ~/och-head-inference-env.sh << 'EOF'
och_infer() {
  local isvc="${1:-qwen05b}" ns="${2:-inference}"
  GW=$(kubectl -n kserve get gateway kserve-ingress-gateway \
         -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  GWPORT=$(kubectl get svc -A \
         -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway \
         -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
  HOST=$(kubectl -n "$ns" get httproute "$isvc" \
         -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
  MODEL="$isvc"
  export GW GWPORT HOST MODEL
  if [ -z "$GW" ] || [ -z "$GWPORT" ] || [ -z "$HOST" ]; then
    echo "och_infer: incomplete — GW='${GW}' GWPORT='${GWPORT}' HOST='${HOST}'" >&2
    return 1
  fi
  echo "MODEL=${MODEL}  endpoint=http://${GW}:${GWPORT}  Host: ${HOST}"
}
och_ask() {
  local prompt="${1:-Say hello.}" max="${2:-64}" payload
  [ -n "$GW" ] && [ -n "$GWPORT" ] && [ -n "$HOST" ] || och_infer >/dev/null || return 1
  payload=$(jq -n --arg m "$MODEL" --arg p "$prompt" --argjson n "$max" \
    '{model:$m, messages:[{role:"user",content:$p}], max_tokens:$n, temperature:0.2}')
  curl -s "http://${GW}:${GWPORT}/v1/chat/completions" \
       -H 'Content-Type: application/json' -H "Host: ${HOST}" \
       -d "$payload" | jq -r '.choices[0].message.content // .'
}
och_infer >/dev/null 2>&1 || true
EOF
head$ source ~/och-head-env.sh
head$ och_infer
head$ och_ask "In two sentences, what is OpenCHAMI for?" 80
```

📌 There is no hook to add. `~/och-head-env.sh`, the entry point §7.1 put on the head node, already looks for this exact filename, and `~/.bashrc` sources it. So writing the file installs it. The helpers reach every shell, including the non-interactive `ssh head '…'` that scripts use. A fuller version, with comments and an `och_ask_raw` for debugging, is in [`templates/och-head-inference-env.sh`](templates/och-head-inference-env.sh).

🛑 **It goes in `~`, next to `och-head-vars-env.sh` and `och-head-talos-env.sh`, not in `~/ochami-lab-flux`.** That directory is the Flux Git repository. A shell file there would be pushed to the GitOps repository, where it doesn't belong. There is no `~/och` on the head node either. That path is the devbox's.

⚠ **Why shell functions instead of static exports?** Unlike `TALOSCONFIG` (a fixed file path you chose in §12), all three endpoint values are discovered from the cluster and can change when resources are recreated or rescheduled:

- **`GWPORT` changes** if the Envoy Service is ever recreated.

- **`GW` follows** whichever nodes are running.

- **`HOST` is different** for each model.

📌 `och_infer` names the empty variable instead of just failing. Each has a different cause, in a different namespace: no Gateway address, no Envoy Service, or no HTTPRoute.

---

## ✅ Checkpoint

Captured 15 Aug 2026 on `och-head`, served from `nid0003`:

```
head$ och_infer
MODEL=qwen05b  endpoint=http://172.16.0.3:30791  Host: qwen05b-inference.example.com

head$ time och_ask "In two sentences, what is OpenCHAMI for?" 80
OpenCHAMI stands for "China Information Security Management System," which is an
open-source platform designed to promote and enhance the security of China's
information systems through collaborative efforts among government agencies,
private enterprises, and academic institutions.

real    0m8.039s
```

🛑 **That answer is completely wrong, and the checkpoint still passes.** OpenCHAMI has nothing to do with China. The model has never seen the acronym, so it invented fluent, confident text. **A 0.5 B model does this. It is not a fault in anything you built.**

⚠ **The test is "coherent English arrived over HTTP", not "the answer is true".** Every layer between an OpenStack instance and this reply is being tested. None of them could make the answer correct. For a reply you can check, ask something the model can do, such as `"Write a haiku about winter"` or `"Summarise: <two sentences you supply>"`. Reasoning and recall need a bigger model, and that needs the accelerators §18 covers.

📌 The reply took about 8 seconds, for a request capped at 80 tokens. For the exact rate, ask the API rather than counting words. vLLM reports it:

```
head$ curl -s http://${GW}:${GWPORT}/v1/chat/completions \
    -H 'Content-Type: application/json' -H "Host: ${HOST}" \
    -d '{"model":"qwen05b","messages":[{"role":"user","content":"Say hello."}],"max_tokens":20}' \
    | jq '.usage'
```

Divide `completion_tokens` by the wall-clock time, and write the result down. It is the "before" figure that §18's accelerators will be measured against.

When `och_ask` returns a response, the entire stack has worked end to end:

1. An OpenStack instance booted iPXE from its own root disk.

2. CoreDHCP identified it from SMD (State Management Database).

3. BSS (Boot Script Service) told it to boot Talos.

4. Talos installed itself over that disk and joined Kubernetes.

5. Flux applied KServe and a vLLM runtime from Git.

6. KServe pulled a model and started a pod.

7. A Gateway routed an OpenAI-compatible request to it.

8. A language model answered.

Every one of those steps has a bare-metal equivalent.

Record these alongside it:

```
head$ kubectl -n inference get pods -o wide      # which node is serving?
head$ kubectl top pods -n inference              # what is it actually using?
head$ curl -s http://${GW}:${GWPORT}/metrics -H "Host: …" | grep -E 'vllm.*(throughput|latency)'
```

vLLM exports Prometheus metrics on the same port, including time to first token, tokens per second and KV cache use. Capture a baseline now. It becomes the "before" number when accelerators arrive.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| Pod `ImagePullBackOff` | The tag in Step 16.1 no longer exists, or the node can't reach `public.ecr.aws` through the head node's NAT (§7.12) |
| Pod starts, dies at once, and the log names a flag | A vLLM argument was renamed or removed in this tag. Step 16.1a catches this in thirty seconds on the head node |
| `unrecognized arguments: --device=cpu` or `--disable-log-requests` | Both flags are gone from current vLLM. Remove them from `args` |
| `CrashLoopBackOff`, exit code 1, dies after ~40 s | `/dev/shm` is Kubernetes' default 64 MiB, and vLLM needs 160 MiB. Add an `emptyDir` with `medium: Memory` at `/dev/shm`. Check with `--tail=80`, because the real error is in the `EngineCore` process, below the `APIServer` traceback |
| `ValueError: invalid literal for int() with base 10: 'all'` | `VLLM_CPU_OMP_THREADS_BIND` takes CPU *IDs*, not `all`. Remove the variable |
| `Init:OOMKilled` on `storage-initializer` | KServe's default limit is 1 GiB, against a ~1 GB model. §15.2 sets `kserve.storage.resources.limits.memory: 4Gi`. If you skipped it, this is where it shows. You can't set it from the `InferenceService` |
| `parse error: Invalid numeric literal` from `jq` | The body is an Envoy error page, not JSON. Almost always, §15.3's `BackendTrafficPolicy` is missing and the request hit the default 15 s route timeout |
| Changed the `ServingRuntime`, and nothing happened | It is a template. Run `kubectl -n inference delete pod -l serving.kserve.io/inferenceservice=qwen05b` to build a new pod from it |
| `InferenceService` stuck at `Ready=False`, with no pods | `defaultDeploymentMode` is `Serverless`. See §15's checkpoint |
| Storage-initialiser pod fails with DNS or TLS errors | The node can't reach `huggingface.co`. Check the head node's NAT (§7.12) or the Talos nameservers (§10.6) |
| Pod OOMKilled (out of memory) while loading | Lower `--max-model-len`, lower `VLLM_CPU_KVCACHE_SPACE`, or raise the memory limit. On CPU these three share the same RAM |
| `Unsupported dtype bfloat16` | The CPU lacks bf16. Use `--dtype=float32` and double the memory |
| Pod `Pending`, `Insufficient cpu` | The request is bigger than any single worker flavor. Reduce it, or add a bigger worker (§9.3) |
| `curl` returns 404 from the Gateway | The `Host:` header is missing or wrong |
| `curl` hangs, then times out | The model is still loading. Watch the container logs |
| Answers are gibberish | You used a base model with a chat endpoint, not an `-Instruct` one |
| Answers are fluent but factually wrong | **Not a fault.** A 0.5 B model invents confidently. The checkpoint tests the path, not the truth of the reply |
| Very slow (seconds per token) | Expected on CPU. Confirm the pod got its full CPU limit |

Next: [§17 — Ray and KubeRay](17-kuberay.md)
