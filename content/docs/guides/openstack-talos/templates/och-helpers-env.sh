# och-helpers-env.sh — the och_* shell helpers for this tutorial.
#
#   devbox$ cp <this-tutorial>/templates/och-helpers-env.sh ~/och/och-helpers-env.sh
#
# ~/och/och-env.sh sources this file. Keeping them apart matters:
#
#   och-vars-env.sh       YOUR values. Filled in over §3, appended to by §6.5
#                   (OCH_HEAD_FIP) and §6.6 (OCH_PROV_IF). NEVER replace wholesale
#                   once you have started filling it in.
#
#   och-helpers-env.sh   No values, only functions. ALWAYS safe to replace wholesale,
#                   at any point, with no risk to anything you have set. That is
#                   the entire reason it is a separate file.
#
# So when this tutorial improves a helper, the upgrade is one `cp` — not a
# three-way merge against a file you have been editing for a week.
#
# Nothing here creates or deletes cloud resources. Each function either prints
# the command it runs or is short enough to read. Run `och_help`.
# All named och_* so `och_unload` can find and remove every one of them again.
# ─────────────────────────────────────────────────────────────────────────────

# ─── och_help — what is loaded, and where everything lives ────────────────────
och_help() {
  cat <<'HELP'
OpenCHAMI lab helpers (all functions are och_*; all variables are OCH_*)

  och_help           this text
  och_env            show every OCH_* variable currently set
  och_check          verify och-vars-env.sh is fully filled in and the API answers
  och_reach          is the Keystone endpoint reachable at all? (VPN check —
                    a dropped tunnel looks exactly like a bad password)
  och_vpn            ssh to the head hangs — is the VPN down, or has your
                    address changed and left och-sg-head behind? (manual §19)
  och_login_head     ssh to the head node as rocky, key and address supplied.
                    With arguments, runs them there and returns:
                      och_login_head 'systemctl --failed'
                    NOT the same as och_login, which is an OpenStack password.
  och_config         show which OpenStack config files exist and which is in use
  och_whoami         which project and user the current credentials resolve to
  och_tunnel_up      forward the cluster API here over ssh (§13.5). Backgrounds
                    itself; safe to run twice. Sets nothing you must clean up
                    by hand — see och_tunnel_down
  och_tunnel_down    close it. Uses the ssh control socket, so it closes THE
                    tunnel rather than whatever ssh happens to match a pattern
  och_tunnel_status  is it up, and does the API answer through it? These are two
                    different failures and it reports them separately
                    OCH_TUNNEL_DEBUG=1 och_tunnel_up  runs it in the foreground
                    with -vvv, when you need ssh to say why it died
  och_login          prompt once for a password into OS_PASSWORD (stops the
                    per-command prompting when using clouds.yaml without a
                    stored password — manual Appendix A)
  och_admin          (Appendix A, optional) elevate to the admin cloud entry: prompts for the password,
                    marks the prompt red, and EXPIRES after OCH_ADMIN_TTL (900s).
                    Never run tofu or ansible while elevated.
  och_member         drop back: clears OS_PASSWORD, restores OS_CLOUD and prompt
  och_clean_os       unset every OS_* except OS_CLOUD (fixes openrc/clouds.yaml
                    mixing — manual §2.2)
  och_flavors        check the three flavors we use exist (manual §3.5)
  och_nodes          print the node map: name / xname / mac / ip / role
  och_unload         unset every OCH_* variable and every och_* function

Where configuration lives:

  ~/.config/openstack/clouds.yaml   connection settings, selected by $OS_CLOUD
  ~/.config/openstack/secure.yaml   optional; secrets only, merged over the above
  ~/och/och-vars-env.sh                    YOUR values — never re-copy from the template
  ~/och/och-helpers-env.sh                these functions — always safe to re-copy
  ~/openrc.sh       the alternative to clouds.yaml — never both

openstacksdk searches for clouds.yaml in this order, first match winning:
  $OS_CLIENT_CONFIG_FILE, ./clouds.yaml (CURRENT DIRECTORY), ~/.config/openstack/,
  /etc/openstack/

The effective, merged configuration is always:  openstack configuration show
HELP
}

# ─── och_env — what is set right now ──────────────────────────────────────────
och_env() {
  # compgen is a bash builtin; the `env` fallback keeps this working elsewhere.
  local names
  names=$(compgen -v 2>/dev/null | grep '^OCH_' | sort) \
    || names=$(env | sed -n 's/^\(OCH_[A-Za-z0-9_]*\)=.*/\1/p' | sort)
  local n
  for n in $names; do
    printf '  %-22s %s\n' "$n" "${!n}"
  done
  printf '  %-22s %s\n' OS_CLOUD "${OS_CLOUD:-(unset)}"
  printf '  %-22s %s\n' OS_PASSWORD \
    "$([ -n "${OS_PASSWORD:-}" ] && echo '(set)' || echo '(unset)')"
}

# ─── och_reach — is the endpoint even reachable? ──────────────────────────────
# Distinguishing "cannot reach Keystone" from "Keystone rejected me" matters more
# than it sounds. If you reach the API over a VPN and the tunnel drops, the CLI
# does NOT say "network down" — it reports an authentication failure.
#
# Prints ok | unreachable | ? and returns 0 | 1 | 2. TCP-only, no auth, no deps
# beyond bash — deliberately, so it works when everything else is failing.
och_reach() {
  local url host port
  url="${1:-$(openstack configuration show -c auth.auth_url -f value 2>/dev/null)}"
  [ -n "$url" ] || { echo "?"; return 2; }
  host=${url#*://}; host=${host%%/*}
  case "$host" in
    *:*) port=${host##*:}; host=${host%%:*} ;;
    *)   case "$url" in https:*) port=443 ;; *) port=80 ;; esac ;;
  esac
  if timeout 5 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    echo "ok"; return 0
  fi
  echo "unreachable"; return 1
}

# ─── och_vpn — ssh to the head hangs: is it the tunnel, or your address? ──────
# The two failures look identical from here (a hang, never a refusal), but they
# have different fixes, and one of them cannot be diagnosed from this VM at all.
#
# The trick is that the Keystone endpoint and the head node are reached over the
# SAME tunnel, but only the head is filtered by a security group. So:
#
#   API ok + head ok    nothing wrong with the network; look at the head itself
#   API ok + head DEAD  the tunnel is up and your source address changed
#   API dead            the VPN is down; reconnect
#
# Probes TCP/22 rather than pinging, because a project that allowed tcp/22 but
# not icmp would otherwise look broken when it is fine.
och_vpn() {
  local api fip head_state
  api=$(och_reach)
  fip="${OCH_HEAD_FIP:-}"

  printf '  %-22s %s\n' 'Keystone endpoint' "$api"
  printf '  %-22s %s\n' 'OCH_ADMIN_CIDR'     "${OCH_ADMIN_CIDR:-(unset)}"

  if [ -z "$fip" ]; then
    printf '  %-22s %s\n\n' 'OCH_HEAD_FIP' '(unset)'
    echo "  Cannot probe the head until OCH_HEAD_FIP is set — that is manual §6.5."
    return 2
  fi

  if timeout 5 bash -c "exec 3<>/dev/tcp/$fip/22" 2>/dev/null; then
    head_state=open
  else
    head_state=NO_ANSWER
  fi
  printf '  %-22s %s\n\n' "$fip tcp/22" "$head_state"

  if [ "$api" != ok ]; then
    echo "  ✗ The Keystone endpoint is unreachable — the VPN itself is down."
    echo "    Reconnect it, then re-run. Note that once it is down the openstack"
    echo "    CLI reports an AUTHENTICATION failure, not a network error, so do"
    echo "    not go looking for a bad password."
    return 3
  fi

  if [ "$head_state" = open ]; then
    echo "  ✓ Tunnel up, and och-sg-head still matches your source address."
    echo "    If ssh still hangs, the problem is on the head node, not the path."
    return 0
  fi

  echo "  ✗ The tunnel is UP but the head does not answer on tcp/22."
  echo "    Almost always: your VPN address changed and och-sg-head, which is"
  echo "    scoped to a /32, no longer matches you. Many VPNs hand out a"
  echo "    different address on every reconnect."
  echo
  echo "    That address exists only on your LAPTOP — this VM sits behind its"
  echo "    NAT and cannot see it. Run this THERE, not here:"
  echo
  printf "      ifconfig \$(route -n get %s | awk '/interface/{print \$2}') \\\\\n" "$fip"
  echo   "        | awk '/inet /{print \$2}'"
  echo
  echo "    Then add a rule for it, confirm ssh works, and only then delete the"
  echo "    stale one — manual §19, 'OCH_ADMIN_CIDR is not durable'."
  return 1
}

# ─── och_login_head — ssh to the head node, and diagnose it when it won't ─────
# Interactive with no arguments; with arguments, runs them on the head and comes
# straight back — och_login_head 'systemctl --failed' is the common case.
och_login_head() {
  local user="${OCH_HEAD_USER:-rocky}"
  local key="${OCH_SSH_KEY:-$HOME/.ssh/och_ed25519}"

  if [ -z "${OCH_HEAD_FIP:-}" ]; then
    echo "OCH_HEAD_FIP is not set — source ~/och/och-env.sh (§6.5 appends it)." >&2
    return 1
  fi
  if [ ! -f "$key" ]; then
    echo "No SSH key at $key. Override with OCH_SSH_KEY, or see §3." >&2
    return 1
  fi

  # ConnectTimeout is here for one specific reason: a security group that no
  # longer matches your VPN address DROPS packets rather than refusing them, so
  # without it this hangs indefinitely and is indistinguishable from a dead
  # instance. Ten seconds turns a mystery into a diagnosis.
  ssh -o ConnectTimeout=10 -i "$key" "${user}@${OCH_HEAD_FIP}" "$@"
  local rc=$?

  # 255 is ssh's own "could not connect", as opposed to a command that ran on the
  # head and exited non-zero. Only the former implicates the tunnel.
  if [ "$rc" -eq 255 ]; then
    echo "" >&2
    echo "ssh could not reach ${OCH_HEAD_FIP}. If it timed out rather than being" >&2
    echo "refused, your VPN address has probably changed: run och_vpn, then see" >&2
    echo "section 19 of the tutorial." >&2
  fi
  return $rc
}

# ─── och_tunnel_* — reach the cluster API from here (§13.5) ───────────────────
# The provisioning wire has no external route. 172.16.0.x is reachable only
# from the head node, and §13.5 argues at length against changing that: an
# API server on a campus network is a liability. So we forward two ports over
# the SSH connection we already trust.
#
#   6443 -> the Kubernetes API on the control plane
#   8080 -> port 80 on the control plane, where a Gateway will eventually listen
#
# The state handle is an SSH CONTROL SOCKET, not a PID file. That distinction
# matters: -O check asks the running master directly, so there is nothing to go
# stale. A PID file survives reboots, gets reused by an unrelated process, and
# then confidently reports a tunnel that does not exist.
OCH_TUNNEL_SOCK="${OCH_TUNNEL_SOCK:-$HOME/.ssh/och-tunnel.sock}"

# DEBUGGING: set OCH_TUNNEL_DEBUG=1 to run in the FOREGROUND with -vvv. Use this
# when the tunnel appears to die and you want ssh to say why rather than guess:
#
#   devbox$ OCH_TUNNEL_DEBUG=1 och_tunnel_up 2>&1 | tee /tmp/tun.log
#
# Read it for these, which mean different things:
#   channel N: new direct-tcpip / free    one connection through the tunnel,
#                                         opened and closed. Normal churn — you
#                                         get a pair of these per kubectl call
#   read failed ... Broken pipe           the LOCAL end went away (kubectl
#                                         finished or was interrupted). Normal
#   Connection to ... closed by remote    the head's sshd hung up
#   client_loop: send disconnect          the path dropped it (VPN/NAT)
#   Killed by signal 2                    something sent it SIGINT — usually a
#                                         Ctrl-C in the terminal it was running in
#
# The port-listener channel (opened once, at startup) staying alive is what
# proves the tunnel is up. Per-connection channels coming and going is the
# tunnel WORKING, and is the single most misread thing in this output.

# kubectl has to be told where the cluster is. Set this only when the file is
# actually present, so sourcing before §13.5 does not leave KUBECONFIG pointing
# at a path that is not there — which fails in a way that reads like a broken
# cluster rather than a missing file.
if [ -f "${OCH_KUBECONFIG:-$HOME/och/kubeconfig}" ]; then
  export KUBECONFIG="${OCH_KUBECONFIG:-$HOME/och/kubeconfig}"
fi

och_tunnel_up() {
  local user="${OCH_HEAD_USER:-rocky}"
  local key="${OCH_SSH_KEY:-$HOME/.ssh/och_ed25519}"
  local cp="${OCH_CP_IP:-172.16.0.1}"

  if [ -z "${OCH_HEAD_FIP:-}" ]; then
    echo "OCH_HEAD_FIP is not set — source ~/och/och-env.sh (§6.5 appends it)." >&2
    return 1
  fi
  if [ ! -f "$key" ]; then
    echo "No SSH key at $key. Override with OCH_SSH_KEY, or see §3." >&2
    return 1
  fi

  if ssh -S "$OCH_TUNNEL_SOCK" -O check "${user}@${OCH_HEAD_FIP}" 2>/dev/null; then
    echo "tunnel already up — nothing to do."
    return 0
  fi

  # ExitOnForwardFailure is the important flag. Without it, a local port that is
  # already taken produces a warning and a connection that succeeds while
  # forwarding nothing — so kubectl fails against whatever else owns that port,
  # and the error blames the cluster.
  # ServerAlive* keeps the connection from being silently reaped. An idle SSH
  # session sends nothing, and NAT on the VPN path will eventually drop the
  # mapping — after which the tunnel is dead but the local listener is still
  # bound, so kubectl hangs rather than failing. Probing every 30s keeps the
  # mapping warm, and giving up after 3 missed probes turns a dead tunnel into
  # a closed socket, which fails fast and honestly.
  # OCH_TUNNEL_DEBUG=1 swaps -f -M (background, control socket) for -vvv in the
  # foreground. Deliberately not both: a backgrounded ssh cannot show you its
  # own death, which is the thing you are usually trying to see.
  local mode
  if [ -n "${OCH_TUNNEL_DEBUG:-}" ]; then
    mode="-vvv"
    echo "debug mode: running in the foreground. Ctrl-C ends the tunnel." >&2
  else
    mode="-f -M -S $OCH_TUNNEL_SOCK"
  fi

  # shellcheck disable=SC2086  # $mode is deliberately word-split
  ssh -N $mode \
      -o ExitOnForwardFailure=yes \
      -o ConnectTimeout=10 \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      -i "$key" \
      -L "${OCH_TUNNEL_API:-6443}:${cp}:6443" \
      -L "${OCH_TUNNEL_HTTP:-8080}:${cp}:80" \
      "${user}@${OCH_HEAD_FIP}" || {
    echo "tunnel failed to start. If it said 'Address already in use', something" >&2
    echo "already holds ${OCH_TUNNEL_API:-6443} or ${OCH_TUNNEL_HTTP:-8080} — an" >&2
    echo "earlier tunnel started outside these helpers, most likely." >&2
    return 1
  }

  echo "tunnel up:"
  echo "  localhost:${OCH_TUNNEL_API:-6443}  -> ${cp}:6443  Kubernetes API"
  echo "  localhost:${OCH_TUNNEL_HTTP:-8080} -> ${cp}:80    gateway (nothing listening until §15)"
  [ -n "${KUBECONFIG:-}" ] && echo "  KUBECONFIG=$KUBECONFIG"
  return 0
}

och_tunnel_down() {
  local user="${OCH_HEAD_USER:-rocky}"
  if [ -z "${OCH_HEAD_FIP:-}" ]; then
    echo "OCH_HEAD_FIP is not set — source ~/och/och-env.sh." >&2
    return 1
  fi
  if ssh -S "$OCH_TUNNEL_SOCK" -O exit "${user}@${OCH_HEAD_FIP}" 2>/dev/null; then
    echo "tunnel closed."
  else
    echo "no tunnel was running."
  fi
}

och_tunnel_status() {
  local user="${OCH_HEAD_USER:-rocky}" out
  if [ -z "${OCH_HEAD_FIP:-}" ]; then
    echo "OCH_HEAD_FIP is not set — source ~/och/och-env.sh." >&2
    return 1
  fi
  out=$(ssh -S "$OCH_TUNNEL_SOCK" -O check "${user}@${OCH_HEAD_FIP}" 2>&1)
  if [ $? -ne 0 ]; then
    echo "tunnel down — run och_tunnel_up."
    return 1
  fi
  echo "tunnel up  ($out)"

  # An established tunnel proves ssh reached the head. It does NOT prove the
  # API answers: the control plane could be down behind a perfectly good
  # forward. Ask the API itself, and keep the two failures distinguishable.
  if command -v kubectl >/dev/null 2>&1; then
    if kubectl get --raw=/readyz >/dev/null 2>&1; then
      echo "API    ok  (readyz passed through the tunnel)"
    else
      echo "API    NOT answering — the tunnel is fine, the cluster or kubeconfig is not"
    fi
  else
    echo "kubectl not installed here — see §13.5"
  fi
}

# ─── och_check — are we actually ready? ───────────────────────────────────────
och_check() {
  local rc=0 unresolved

  # 1. Placeholders. Every <…> is a §3 answer nobody has written down yet.
  unresolved=$(och_env | grep '<' || true)
  if [ -n "$unresolved" ]; then
    echo "✗ Unresolved placeholders — finish the §3 recon:"
    echo "$unresolved"
    rc=1
  else
    echo "✓ No placeholders left in OCH_* variables"
  fi

  # 2. Can we talk to the API? This is a read-only call.
  if [ -z "${OS_CLOUD:-}" ] && [ -z "${OS_AUTH_URL:-}" ]; then
    echo "✗ Neither OS_CLOUD nor OS_AUTH_URL is set — see 'och_config'"
    rc=1
  elif project=$(openstack token issue -c project_id -f value 2>/dev/null); then
    echo "✓ Authenticated; project_id $project"
  # `token issue` asks Keystone for a SCOPED token, which some deployments refuse
  # for application credentials ("Application credentials cannot request a
  # scope"). So a failure there is not proof that auth is broken — fall back to
  # an ordinary read before accusing the credential of anything.
  elif openstack catalog list -f value -c Name >/dev/null 2>&1; then
    echo "✓ Authenticated (via catalog list; 'token issue' is unavailable —"
    echo "  normal for application-credential auth, and harmless)"
  elif [ "$(och_reach)" != ok ]; then
    echo "✗ Cannot REACH the Keystone endpoint — this is a network problem, not a"
    echo "  credential one. If you use a VPN, it has probably dropped."
    echo "  Reconnect it and re-run; change nothing else."
    rc=1
  else
    echo "✗ Endpoint reachable but authentication refused. Keystone said:"
    openstack catalog list -f value -c Name 2>&1 | sed 's/^/    /' | head -5
    echo "  Then: openstack configuration show | grep -vi 'secret\\|password'"
    echo "  and see manual §2 'Common failures'"
    rc=1
  fi

  return $rc
}

# ─── och_config — which files exist, and which one is winning ─────────────────
och_config() {
  local f
  echo "Config files:"
  for f in "$OS_CLIENT_CONFIG_FILE" ./clouds.yaml \
           ~/.config/openstack/clouds.yaml ~/.config/openstack/secure.yaml \
           /etc/openstack/clouds.yaml; do
    [ -n "$f" ] || continue
    if [ -f "$f" ]; then
      printf '  %-40s exists\n' "$f"
    else
      printf '  %-40s -\n' "$f"
    fi
  done

  echo
  echo "Selected cloud: OS_CLOUD=${OS_CLOUD:-(unset)}"
  echo "Clouds the SDK can see:"
  python3 -c 'import openstack.config as c
print("\n".join("  " + n for n in sorted(c.OpenStackConfig().get_cloud_names())))' \
    2>/dev/null || echo "  (could not read — is the venv active?)"

  echo
  echo "OS_* currently in the environment (should be OS_CLOUD alone, or an"
  echo "openrc's set — never a mixture; see manual §2.2):"
  # Captured into a variable rather than piped, so the "(none)" fallback works:
  # in `env | grep … || echo`, the || binds to the last command of the pipeline,
  # which succeeds even when grep matched nothing.
  local os_vars
  os_vars=$(env | grep '^OS_' | sed 's/^\(OS_PASSWORD=\).*/\1(hidden)/' | sort)
  if [ -n "$os_vars" ]; then
    echo "$os_vars" | sed 's/^/  /'
  else
    echo "  (none)"
  fi
}

# ─── och_whoami — whose credentials are these? ────────────────────────────────
och_whoami() {
  openstack token issue -c project_id -c user_id -c expires -f table
}

# ─── och_login — one password prompt per shell, not per command ───────────────
och_login() {
  # Why this exists: every `openstack` command authenticates from scratch, so a
  # clouds.yaml with no stored password prompts EVERY time (manual §2.2, Option B).
  # Exporting OS_PASSWORD once is the fix that writes nothing to disk.
  local pw
  read -srp "OpenStack password for ${OS_USERNAME:-your account}: " pw
  echo
  if [ -z "$pw" ]; then
    echo "Nothing entered; OS_PASSWORD unchanged."
    return 1
  fi
  export OS_PASSWORD="$pw"
  echo "OS_PASSWORD set for this shell only. Verify with: och_whoami"
}

# ─── och_clean_os — undo openrc/clouds.yaml mixing ───────────────────────────
och_clean_os() {
  # openstacksdk MERGES OS_* env vars on top of the cloud OS_CLOUD selects, so a
  # sourced openrc silently overrides clouds.yaml and produces errors that look
  # like cloud faults (manual §2.2).
  local keep="${1:-$OS_CLOUD}" v
  for v in $(env | sed -n 's/^\(OS_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$v"
  done
  if [ -n "$keep" ]; then
    export OS_CLOUD="$keep"
    echo "OS_* purged. Now: OS_CLOUD=$OS_CLOUD"
  else
    echo "OS_* purged. Nothing set — you will need OS_CLOUD or an openrc."
  fi
  echo "If you meant to use the openrc instead: unset OS_CLOUD; source ~/openrc.sh"
}

# ─── och_flavors — do the three flavors exist? ────────────────────────────────
och_flavors() {
  local f
  for f in "$OCH_FLAVOR_HEAD" "$OCH_FLAVOR_CP" "$OCH_FLAVOR_WORKER"; do
    case "$f" in *'<'*) echo "  $f — not set yet (§3)"; continue ;; esac
    printf '  %-32s ' "$f"
    if openstack flavor show "$f" -c name -f value >/dev/null 2>&1; then
      echo "exists ✓"
    else
      echo "missing — create it, or ask for it (§3.5)"
    fi
  done
}

# ─── och_nodes — the node map, as a table ─────────────────────────────────────
och_nodes() {
  cat <<EOF
  name      xname           nid  mac                ip           role
  ${OCH_PREFIX}-cp1    x1000c0s0b0n0   1    ${OCH_CP_MAC}  ${OCH_CP_IP}   controlplane
  ${OCH_PREFIX}-w1     x1000c0s0b1n0   2    52:54:00:be:ef:02  172.16.0.2   worker
  ${OCH_PREFIX}-w2     x1000c0s0b2n0   3    52:54:00:be:ef:03  172.16.0.3   worker
  ${OCH_PREFIX}-w3     x1000c0s0b3n0   4    52:54:00:be:ef:04  172.16.0.4   worker
  ${OCH_PREFIX}-w4     x1000c0s0b4n0   5    52:54:00:be:ef:05  172.16.0.5   worker

  These MACs must match in three places: Neutron ports (§5.4), the SMD
  inventory (§8.1) and the BSS payloads (§11.1).
EOF
}

# ─── och_admin / och_member — deliberate, visible, time-limited elevation ──────
#
# Optional — only for Appendix A's two-identity setup: a member application
# credential for everything in the tutorial and all automation, and a separate
# admin entry for one considered action at a time. The main path (§2.6) uses
# one entry and never needs these. These two functions make that switch explicit
# instead of remembering which shell you are in.
#
# THREE THINGS THIS DOES THAT `export OS_CLOUD=ochami-lab-admin` DOES NOT:
#
#   1. It marks the prompt, in red. Elevated state you cannot see is elevated
#      state you forget.
#   2. It EXPIRES. After OCH_ADMIN_TTL seconds of prompts it drops you back on its
#      own, so walking away from the keyboard is not a way to stay root.
#   3. It puts OS_PASSWORD and OS_CLOUD back together, so dropping out cannot
#      leave a password behind that a later member command picks up — which is
#      the OS_*-on-top-of-clouds.yaml mixing failure in §2.2.
#
# ⚠ It still holds your password in this shell's environment for up to the TTL.
#   That is a real trade against per-command prompting, and it is the reason for
#   the TTL and the marker. For a one-off command, prefer:
#       openstack --os-cloud ochami-lab-admin <command>
#   For total certainty that nothing persists, prefer the subshell form in Appendix A:
#       ( read -srp "pw: " OS_PASSWORD; echo; export OS_PASSWORD; <commands> )
#
# 🛑 NEVER run `tofu apply`, `tofu destroy` or an Ansible playbook while
#   elevated. The IaC reads the same clouds.yaml, so it would run with admin
#   policy available — which is precisely where a typo stops being local.
export OCH_ADMIN_CLOUD="${OCH_ADMIN_CLOUD:-ochami-lab-admin}"
export OCH_ADMIN_TTL="${OCH_ADMIN_TTL:-900}"        # seconds; 15 minutes

# Prompt hook. Not named och_* on purpose — it is machinery, not a command you
# would run — so och_unload removes it explicitly rather than by pattern.
_och_admin_watch() {
  [ -n "${OCH_ADMIN_SINCE-}" ] || return 0
  if [ $(( SECONDS - OCH_ADMIN_SINCE )) -ge "${OCH_ADMIN_TTL:-900}" ]; then
    printf '\n\033[33mtw: admin session expired after %ss — dropping to member.\033[0m\n' \
      "${OCH_ADMIN_TTL}" >&2
    och_member
  fi
}

och_admin() {
  if [ -n "${OCH_ADMIN_SINCE-}" ]; then
    echo "Already elevated (${OCH_ADMIN_CLOUD}). och_member to drop out."
    return 0
  fi

  # Fail before asking for a password if the entry does not exist — otherwise the
  # error arrives after you have typed it, which teaches people to retype blindly.
  if ! python3 -c 'import openstack.config as c; print("\n".join(c.OpenStackConfig().get_cloud_names()))' \
        2>/dev/null | grep -qx "$OCH_ADMIN_CLOUD"; then
    echo "No cloud '$OCH_ADMIN_CLOUD' in your clouds.yaml." >&2
    echo "§2.6 has the entry to add. Cloud names available:" >&2
    python3 -c 'import openstack.config as c; print("  "+"\n  ".join(sorted(c.OpenStackConfig().get_cloud_names())))' 2>/dev/null
    return 1
  fi

  local pw
  read -srp "Password to elevate to ${OCH_ADMIN_CLOUD}: " pw; echo
  [ -n "$pw" ] || { echo "Nothing entered; still member."; return 1; }

  OCH_ADMIN_PREV_CLOUD="${OS_CLOUD-}"
  OCH_ADMIN_PREV_PS1="${PS1-}"
  export OS_CLOUD="$OCH_ADMIN_CLOUD"
  export OS_PASSWORD="$pw"
  pw=

  # Verify now, so a mistyped password fails here and not three commands later
  # as a confusing 401 (§2 Common failures).
  #
  # SHOW the error. An earlier version of this function swallowed stderr and
  # printed "password wrong, or see §2.6", which is a guess dressed as a
  # diagnosis — and it hid a real clouds.yaml problem for three attempts.
  # Whatever Keystone says is more useful than anything we can infer.
  local err
  if ! err=$(openstack token issue -c project_id -f value 2>&1); then
    if [ "$(och_reach)" != ok ]; then
      echo "Elevation failed: the Keystone endpoint is UNREACHABLE." >&2
      echo "  Your password is almost certainly fine. If you use a VPN, it has" >&2
      echo "  probably dropped — reconnect and retry." >&2
      unset OS_PASSWORD
      export OS_CLOUD="$OCH_ADMIN_PREV_CLOUD"
      unset OCH_ADMIN_PREV_CLOUD OCH_ADMIN_PREV_PS1
      return 1
    fi
    echo "Elevation failed — reverting to member. Keystone said:" >&2
    printf '  %s\n' "$err" >&2
    case "$err" in
      *"Could not find user"*|*"Could not find domain"*)
        echo "  → the admin entry is probably missing user_domain_name (§2.6)" >&2 ;;
      *"Could not find project"*|*"project_domain"*)
        echo "  → the admin entry is probably missing project_domain_name (§2.6)" >&2 ;;
      *"cannot request a scope"*)
        echo "  → that entry is an application credential; it must not also set a scope (§2.6)" >&2 ;;
      *401*|*"requires authentication"*)
        echo "  → password or username wrong. Check: openstack configuration show | grep -vi secret" >&2 ;;
    esac
    unset OS_PASSWORD
    export OS_CLOUD="$OCH_ADMIN_PREV_CLOUD"
    unset OCH_ADMIN_PREV_CLOUD OCH_ADMIN_PREV_PS1
    return 1
  fi

  OCH_ADMIN_SINCE=$SECONDS
  if [ -n "${BASH_VERSION-}" ]; then
    PS1='\[\033[41;97m\] ADMIN \[\033[0m\] '"$OCH_ADMIN_PREV_PS1"
    if ! declare -p PROMPT_COMMAND 2>/dev/null | grep -q '^declare -a'; then
      OCH_ADMIN_PREV_PROMPT="${PROMPT_COMMAND-}"
      case "${PROMPT_COMMAND-}" in
        *_och_admin_watch*) : ;;
        '')                PROMPT_COMMAND='_och_admin_watch' ;;
        *)                 PROMPT_COMMAND="${PROMPT_COMMAND%;};_och_admin_watch" ;;
      esac
    fi
  fi

  printf '\033[33m'
  echo "ELEVATED as ${OCH_ADMIN_CLOUD}. Expires in ${OCH_ADMIN_TTL}s, or run och_member."
  echo "Do NOT run tofu or ansible in this shell while elevated."
  printf '\033[0m'
}

och_member() {
  if [ -z "${OCH_ADMIN_SINCE-}" ]; then
    echo "Not elevated. OS_CLOUD=${OS_CLOUD:-unset}"
    return 0
  fi
  unset OS_PASSWORD
  export OS_CLOUD="${OCH_ADMIN_PREV_CLOUD:-ochami-lab}"
  [ -n "${BASH_VERSION-}" ] && [ -n "${OCH_ADMIN_PREV_PS1-}" ] && PS1="$OCH_ADMIN_PREV_PS1"
  if [ -n "${OCH_ADMIN_PREV_PROMPT+x}" ]; then
    if [ -z "$OCH_ADMIN_PREV_PROMPT" ]; then unset PROMPT_COMMAND
    else PROMPT_COMMAND="$OCH_ADMIN_PREV_PROMPT"; fi
  fi
  unset OCH_ADMIN_SINCE OCH_ADMIN_PREV_CLOUD OCH_ADMIN_PREV_PS1 OCH_ADMIN_PREV_PROMPT
  echo "Dropped to member. OS_CLOUD=$OS_CLOUD, OS_PASSWORD cleared."
}

# ─── och_unload — leave no trace ──────────────────────────────────────────────
och_unload() {
  # Drop out of admin FIRST, while och_member and OCH_ADMIN_SINCE still exist —
  # otherwise the OCH_* purge below strips the saved state and you are left with a
  # red ADMIN prompt, a dangling PROMPT_COMMAND hook and no way to restore either.
  [ -n "${OCH_ADMIN_SINCE-}" ] && och_member

  # Unset the variables first (och_env needs to still exist to find them), then
  # the functions, and och_unload itself last.
  local v f names
  names=$(compgen -v 2>/dev/null | grep '^OCH_' | sort) \
    || names=$(env | sed -n 's/^\(OCH_[A-Za-z0-9_]*\)=.*/\1/p' | sort)
  for v in $names; do unset "$v"; done

  # OS_CLOUD is ours too — och-vars-env.sh is what set it.
  unset OS_CLOUD

  # OS_PASSWORD, if och_login put it there. Deliberately unconditional: leaving a
  # password in the environment of a shell you thought you had cleaned is worse
  # than having to type it again.
  unset OS_PASSWORD

  for f in $(compgen -A function 2>/dev/null | grep '^och_' | grep -v '^och_unload$'); do
    unset -f "$f"
  done
  # The prompt hook is deliberately not named och_*, so the pattern above misses it.
  unset -f _och_admin_watch 2>/dev/null
  echo "OCH_* variables and och_* functions removed. Re-run: source ~/och/och-env.sh"
  unset -f och_unload
}

# One line on load, so it is obvious the helpers are there.
#
# ⚠ INTERACTIVE SHELLS ONLY. §3 puts och-env.sh in ~/.bashrc, and bash sources
# .bashrc for non-interactive `ssh devbox '…'` too. Anything printed on stdout
# there is prepended to the stream scp and rsync are reading, and they fail with
# `protocol error` or `unexpected tag` — an error that names neither this line
# nor .bashrc. `$-` holds the shell's option letters; `i` is there only when the
# shell is interactive.
case $- in *i*) echo "OpenCHAMI lab env loaded (OS_CLOUD=${OS_CLOUD:-unset}). Run 'och_help'." ;; esac
