# och-head-inference-env.sh — how to reach the model endpoint, on the HEAD node.
#
# Lives at ~/och-head-inference-env.sh. Created in §16.3a.
#
# 📌 NOTHING HAS TO BE HOOKED UP. ~/och-head-env.sh — the entry point, on the
# head since §7.1 — already looks for this exact name, and ~/.bashrc sources
# that. Writing the file IS the installation step. That is the whole reason the
# entry point lists its dependants by name rather than each file chaining to
# the next: before this split, §16 had to edit §12's file, which was hooked
# into §7's, and the only way to know what a login shell loaded was to open
# three files in order.
#
# WHY THIS FILE EXISTS. GW, GWPORT and HOST are shell variables, so every
# reconnect drops them — and an empty one fails in a way that names nothing:
#
#     curl http://:/v1/chat/completions      → exits in 8 ms, no error
#     curl -H "Host: "                        → 404 from Envoy
#
# Both read as a broken cluster. They are an empty variable, and the first
# does not even look like a failure: it looks like a very fast success.
#
# WHY FUNCTIONS RATHER THAN EXPORTS. Unlike TALOSCONFIG, these three are
# DISCOVERED, not chosen, and any of them can change without you doing
# anything:
#
#   GW      a node IP from the Gateway's status. Changes with the node set
#   GWPORT  a NodePort in 30000-32767. Reassigned if the Envoy Service is
#           ever recreated — which happens if the EnvoyProxy changes
#   HOST    from the HTTPRoute, so it is per-model and per-namespace
#
# Freezing them into a static file would give you three plausible values
# that are quietly wrong after any of those events, which is worse than
# having none. So this file re-derives them instead.

# och_infer [inferenceservice] [namespace]
#   Derive and export GW, GWPORT, HOST and MODEL. Defaults to §16's model.
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

  # Report exactly which one is missing. "It didn't work" is not a diagnosis.
  if [ -z "$GW" ] || [ -z "$GWPORT" ] || [ -z "$HOST" ]; then
    echo "och_infer: incomplete — GW='${GW}' GWPORT='${GWPORT}' HOST='${HOST}'" >&2
    echo "  empty GW      → no Gateway address: kubectl -n kserve get gateway" >&2
    echo "  empty GWPORT  → no Envoy Service:   kubectl get svc -A -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway" >&2
    echo "  empty HOST    → no HTTPRoute:       kubectl -n ${ns} get httproute" >&2
    return 1
  fi

  echo "MODEL=${MODEL}  endpoint=http://${GW}:${GWPORT}  Host: ${HOST}"
}

# och_ask "prompt" [max_tokens]
#   One-line chat completion through the Gateway. Re-derives if needed.
och_ask() {
  local prompt="${1:-Say hello.}" max="${2:-64}" payload
  [ -n "$GW" ] && [ -n "$GWPORT" ] && [ -n "$HOST" ] || och_infer >/dev/null || return 1

  # Built with jq so a prompt containing quotes or newlines cannot break it.
  payload=$(jq -n --arg m "$MODEL" --arg p "$prompt" --argjson n "$max" \
    '{model:$m, messages:[{role:"user",content:$p}], max_tokens:$n, temperature:0.2}')

  curl -s "http://${GW}:${GWPORT}/v1/chat/completions" \
       -H 'Content-Type: application/json' -H "Host: ${HOST}" \
       -d "$payload" | jq -r '.choices[0].message.content // .'
}

# och_ask_raw — same request, but show status line and headers rather than
# parsing. Reach for this the moment `och_ask` prints a jq parse error: that
# means the body was not JSON, and only the headers say which layer replaced
# it. An Envoy timeout and a 404 look identical through `jq`.
och_ask_raw() {
  local prompt="${1:-Say hello.}" max="${2:-8}" payload
  [ -n "$GW" ] || och_infer >/dev/null || return 1
  payload=$(jq -n --arg m "$MODEL" --arg p "$prompt" --argjson n "$max" \
    '{model:$m, messages:[{role:"user",content:$p}], max_tokens:$n, temperature:0.2}')
  curl -s -i -m 120 "http://${GW}:${GWPORT}/v1/chat/completions" \
       -H 'Content-Type: application/json' -H "Host: ${HOST}" -d "$payload"
}

# Derive on login, quietly. Three kubectl calls, ~1 s. It stays silent and
# non-fatal when the cluster is down or §16 has not run yet, so a broken
# cluster never blocks a login shell. Comment this line out if the delay
# annoys you and call och_infer by hand instead.
och_infer >/dev/null 2>&1 || true
