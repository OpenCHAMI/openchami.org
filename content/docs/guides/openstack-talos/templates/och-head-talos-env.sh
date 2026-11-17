# och-head-talos-env.sh — Talos and Kubernetes client context, on the HEAD node.
#
# Lives at ~/och-head-talos-env.sh. Created in §12.3. You do not source it
# directly and nothing has to be edited to pick it up: ~/och-head-env.sh — the
# entry point, in place since §7.1 — already looks for this name, and ~/.bashrc
# sources that. So every shell, including the non-interactive `ssh head '…'`
# that later sections use, gets it the moment the file exists.
#
# WHY THIS FILE EXISTS. TALOSCONFIG and KUBECONFIG are shell variables, so
# every reconnect drops them, and neither symptom names the cause:
#
#   talosctl → error constructing client: failed to determine endpoints
#   kubectl  → The connection to the server localhost:8080 was refused
#
# Both read as a broken cluster. They are an empty variable.
#
# NOT in och-head-vars-env.sh: that file is generated on the devbox from
# och-vars-env.sh and marked "do not edit by hand" (§7.1), and it is written
# before Talos exists. Keeping the two separate means the values file can be
# regenerated without losing this, and this can be deleted at teardown without
# touching that.
#
# $HOME rather than a literal path so the file survives being copied to a
# head node with a different login name. It is expanded when SOURCED, which
# is why §12.3 writes this with a QUOTED heredoc (<< 'EOF').

export TALOSCONFIG=$HOME/talos/talosconfig
export KUBECONFIG=$HOME/talos/kubeconfig

# What persists WITHOUT this file, and does not belong here:
#   talosctl config endpoint <ip>   ─┐ written into the talosconfig file
#   talosctl config node <ip>       ─┘ itself, so they survive reconnects
