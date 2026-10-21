---
title: "§19 — Troubleshooting"
description: "Finding which layer is broken when you don't yet know. Each chapter's own Common failures table covers problems local to that step."
slug: "19-troubleshooting"
date: 2026-10-21
lastmod: 2026-10-21
weight: 190
toc: true
draft: false
---
> ⏱ **A reference chapter** · read it when something breaks · creates nothing
>
> - **What this chapter is for.** Finding *which* layer is broken when you don't yet know. Each chapter's own Common failures table covers problems local to that step. This one covers the whole stack.
>
> - **What you will learn.** How to find the lowest broken layer quickly, the five failures you are most likely to hit, and why SSH to the head node can stop working weeks later without you changing anything.
>
> - **Skip it if** everything works. Come back when it doesn't.

---

## Introduction

### Start with the map

Most "the cluster is broken" reports turn out to be a single failed hop. [The full network map](diagrams/full-network-map.svg) shows every hop between your keyboard and a Talos node in one diagram; spotting the broken hop on the map is faster than guessing from symptoms.

### If it was working and has been idle, check the certificate first

The OpenCHAMI TLS (Transport Layer Security) certificate lasts 24 hours. Step 7.9c installs a systemd timer to renew it automatically, but if you skipped that step or the timer hasn't fired, everything behind port 8443 stops working. Check the certificate expiry before investigating anything else:

```
head$ echo | openssl s_client -connect ${OCH_CLUSTER_FQDN}:8443 -servername ${OCH_CLUSTER_FQDN} 2>/dev/null | openssl x509 -noout -dates
```

If it has expired, run `sudo systemctl start openchami-cert-renew.service` to renew it immediately, then restart `coresmd` with `sudo systemctl restart coresmd-coredhcp coresmd-coredns` (which reads the CA certificate only at startup, as covered in §7).

### What you will do

- **Find the lowest broken layer** (Diagnose by layer, from the bottom). One list of commands, from inference down to OpenStack.

- **Match the symptom against the five common failures**, each with its checks in order.

- **Look in the right logs** for the layer you found (Where to look, by layer).

- **Rule out the things that only look broken**, before you change anything.

- **If SSH to the head node has stopped on its own**, read the last section, about `OCH_ADMIN_CIDR`.

---

## Diagnose by layer, from the bottom

Find the lowest broken layer before changing anything. Work down this list and start investigating at the first failure:

```
head$ # ── Layer 6: inference ────────────────────────────────────────────────
head$ kubectl -n inference get inferenceservice
head$ # ── Layer 5: Kubernetes workloads ─────────────────────────────────────
head$ kubectl get pods -A | grep -v -E 'Running|Completed'
head$ flux get all
head$ # ── Layer 4: Kubernetes cluster ───────────────────────────────────────
head$ kubectl get nodes
head$ # ── Layer 3: Talos machines ───────────────────────────────────────────
head$ talosctl -n 172.16.0.1 health
head$ # ── Layer 2: OpenCHAMI control plane ──────────────────────────────────
head$ systemctl is-active openchami.target && ochami smd service status | jq -c .
head$ # ── Layer 1: OpenStack substrate ──────────────────────────────────────
devbox$ openstack server list -c Name -c Status
devbox$ openstack port list --network ${OCH_PREFIX}-prov -c Name -c Status
```

---

## The five failures you are most likely to hit

These are ranked by how often they came up during our own runs and by what the OpenStack networking setup makes most likely.

### 1. A node network-boots but never gets an address

**Symptom:** the iPXE banner appears in the console log, followed by `Configuring (net0 …)......` and a timeout—or the node gets an address in `172.16.0.200–250`.

This is the most common failure and has four likely causes. Each check is quick, so run through them **in this order**:

```
devbox$ openstack subnet show ${OCH_PREFIX}-prov-subnet -c enable_dhcp -f value
        # must be False. If True, Neutron's DHCP is racing CoreDHCP (§5.2)

devbox$ openstack port show ${OCH_PREFIX}-node1-prov -c port_security_enabled -f value
        # must be False, or the head's DHCP replies are dropped (§5.3)

head$   systemctl is-active coresmd-coredhcp
head$   journalctl -u coresmd-coredhcp | tail -20
        # must show "Cache updated with N EthernetInterfaces and N Components"

head$   ochami smd component get | jq -r '.Components[]|select(.Type=="Node")|.ID'
        # the node's MAC must be in SMD (§8)
```

An address in the `172.16.0.2xx` range means CoreDHCP answered the request, so the network and DHCP server are working—it just didn't recognise the node's MAC address. Check SMD (State Management Database, §8) for a missing entry or a MAC mismatch between the Neutron port and the inventory.

### 2. Talos hangs at `downloading installer`

**Symptom:** the console reaches `downloading installer image ghcr.io/…` and stays there.

First check these settings on the head node:

```
head$ sysctl net.ipv4.ip_forward                       # must be 1        (§7.2)
head$ sudo nft list chain ip nat postrouting           # or:
head$ sudo firewall-cmd --query-masquerade             # must be yes      (§7.12)
head$ grep -A3 nameservers ~/talos/worker.yaml         # 1.1.1.1 present? (§10.6)
```

A third cause is easy to miss: port security on the head node's own provisioning port. Because masquerading forwards packets whose source IP isn't the port's own, Neutron's anti-spoofing rules will drop them unless port security is disabled:

```
devbox$ openstack port show ${OCH_PREFIX}-head-prov -c port_security_enabled -f value
```

### 3. Everything authenticated returns `500` or `401`

A `401` error is almost always an expired token (tokens last one hour):

```
head$ export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

A `500` error on authenticated calls—while unauthenticated reads still work—is a startup race where SMD started before the OIDC (OpenID Connect) signing keys were ready (Step 7.10):

```
head$ sudo podman logs smd 2>&1 | grep -i jwtauth
head$ sudo systemctl restart smd
```

### 4. A service is still using an old certificate or key

Several OpenCHAMI services load their certificates or keys only at startup. After any certificate change, restart them:

```
head$ sudo systemctl restart coresmd-coredhcp coresmd-coredns
head$ sudo systemctl restart opaal haproxy
head$ sudo systemctl restart smd
```

The telltale symptom is `x509: certificate signed by unknown authority` in `journalctl -u coresmd-coredhcp`, accompanied by nodes falling back to bootloop leases.

### 5. Nothing changes when you commit

**Symptom:** you push to the Flux repository, and the cluster ignores it.

```
head$ flux get sources git          # is the repo being fetched?
head$ flux get kustomizations -A    # any Ready=False?
head$ flux reconcile kustomization flux-system --with-source
head$ flux logs --level=error --all-namespaces
```

Flux's default reconcile interval is 10 minutes. Note that if `infrastructure` is failing, `apps` will stay `Ready=False`—that is `dependsOn` doing its job rather than a separate fault.

---

## Where to look, by layer

Check your shell environment first. Two of the most alarming errors in this tutorial happen simply because an environment variable is unset in a fresh `ssh` session:

| Symptom | Cause |
|---|---|
| `talosctl` → `error constructing client: failed to determine endpoints` | `TALOSCONFIG` unset |
| `kubectl` → `The connection to the server localhost:8080 was refused` | `KUBECONFIG` unset; `localhost:8080` is kubectl's built-in default |

Run `echo $TALOSCONFIG $KUBECONFIG` to check that both variables are set. Step 12.3 adds them to your shell profile so this doesn't happen in new sessions.

| Layer | Logs / status |
|---|---|
| OpenStack | `openstack server show <n> -c fault -f json`, `openstack console log show <n>`, `openstack server event list <n>` |
| Node boot | `openstack console log show <node> --lines 200` — the *only* window into a Talos node's **network** boot. It stops at `kexec_core: Starting new kernel` and never resumes; an installed node has no serial console at all. If the log is frozen there, that is not the fault — reach for `talosctl` |
| OpenCHAMI | `systemctl --failed`, `journalctl -eu <service>`, `sudo podman logs <container>`, `systemctl list-dependencies openchami.target` |
| BSS answers | `curl -s "http://172.16.0.254:8081/boot/v1/bootscript?mac=<MAC>"` — impersonate the node |
| S3 assets | `curl -s -o /dev/null -r 0-0 -w "%{http_code}" http://172.16.0.254:7070/boot-images/talos/<file>` — expect `206` |
| Talos | `talosctl -n <ip> dmesg`, `… logs <service>`, `… health`, `… get members`, `… dashboard` |
| Kubernetes | `kubectl get events -A --sort-by=.lastTimestamp`, `kubectl describe pod <p>` |
| Flux | `flux get all`, `flux logs --level=error -A` |
| vLLM | `kubectl -n inference logs <pod> -c kserve-container`, and `-c storage-initializer` for download failures |

---

## Two habits worth adopting

**Impersonate the node.** You can test most of the boot chain directly from the head node without booting a VM. Query BSS (Boot Script Service) for the node's boot script, fetch the files over HTTP the way iPXE would, and check the DHCP cache. That is why the checkpoints in §9, §10 and §11 exist: booting a node takes minutes, whereas `curl` takes a second.

**After a messy start, restart the service.** OpenCHAMI services run as stateless containers, and several of them read their configuration only once at startup. Restarting a service is quick and safe, and it resolved several issues during our own runs.

---

## Things that look broken but are not

| Looks wrong | Actually fine |
|---|---|
| `A dependency job for openchami.target failed` on the very first start | An expected startup race. Wait, and start it again (Step 7.10) |
| PVC (persistent volume claim) `Pending` with `WaitForFirstConsumer` | That is how local-path binds. It waits for a pod |
| `apps` Kustomization `Ready=False` while `infrastructure` is broken | `dependsOn` doing its job |
| A Talos node reboots straight to disk without touching iPXE | Correct after Step 12.2. Talos installed itself, and stays |
| `ray.cluster_resources()` has no `GPU` key | Correct, because there are no GPUs (Step 17.3, §18) |
| A few tokens per second from vLLM | Correct on CPU (§16) |
| `talosctl version` shows only a Client | The node's API isn't up yet. Wait, or check it booted |

---

## SSH stops working later: `OCH_ADMIN_CIDR` goes out of date

This failure can happen without you changing anything on the cluster, and it is the most common reason a setup that worked yesterday is unreachable today.

`OCH_ADMIN_CIDR` (Step 3.7) records the IP address you connected from *when you set up the project*. Using a `/32` for that single address is the tightest and safest rule, but also the most fragile. Any of the following can change your source address without warning:

- **A VPN (virtual private network) reconnect** that assigns you a different address.

- **A DHCP lease expiring** on your office or home network.

- **Moving between networks** (office to home, wired to wireless, or another site).

- **Your internet provider rotating a dynamic address.**

The symptom is a connection timeout rather than "permission denied". Because a security group silently drops packets when your source address doesn't match, it looks just like a boot failure, a lost floating IP or a dead head node—even though `openstack server show och-head` reports `ACTIVE` and the console log looks healthy.

Check this first whenever SSH stops working:

```
devbox$ och_vpn
```

📌 If your address has changed and you just want to get back in: find the address the head node sees (below), add a security group rule for it, verify SSH works, and delete the old rule.

That single command distinguishes between two failures that otherwise look identical from the devbox. Both the Keystone (identity) endpoint and the head node are reached over the same network path, but only the head node sits behind your security group. Probing each in turn shows where the connection is stopping:

| Keystone API | Head, tcp/22 | Verdict |
|---|---|---|
| OK | Open | The path is fine — the fault is on the head node |
| OK | **No answer** | The path is up and **your source address has changed** |
| Unreachable | — | The VPN or network path is down; reconnect before anything else |

`och_vpn` prints the verdict, and if your source address has changed, it also prints the command to run **on your laptop** (since a VPN interface on your host isn't visible inside the devbox VM).

To check by hand:

```
devbox$ echo ${OCH_ADMIN_CIDR}                  # what the rule was written for
devbox$ openstack security group rule list ${OCH_PREFIX}-sg-head
devbox$ sudo journalctl -u sshd | grep -i accepted | tail -3   # ON THE HEAD, if you can still reach it
```

⚠ **Use `curl -s ifconfig.me` only if the floating-IP network is publicly routable** (Step 3.7). On a cloud whose external network uses a private range, you reach the head node over a VPN. With split tunnelling, `ifconfig.me` reports your *public* internet address, whereas the head node sees your *VPN* address. Using the public address in the security group rule will lock you out.

The head node's `sshd` log is the authoritative source, which is why Step 6.8 records your known-good source address **while SSH is working**.

If you are already locked out, check your routing table on your laptop rather than inside the devbox. Because the devbox is a VM behind your laptop's NAT, running `ip route get` inside it only shows the VM's private address (such as `192.168.5.15` on Lima), not the address the head node sees. Instead, inspect the VPN interface on the machine running the VPN client:

```
mac$ route -n get <the floating IP> | grep interface     # e.g. utun10
mac$ ifconfig utun10 | grep 'inet '                      # e.g. inet 198.51.100.49
```

On Linux, run `ip route get <the floating IP>` directly on your laptop.

Once you have the address the head node sees, add a new rule for it and update `och-vars-env.sh`:

```
devbox$ export OCH_ADMIN_CIDR='<THE_ADDRESS_OR_RANGE_THE_HEAD_SEES>'
devbox$ openstack security group rule create ${OCH_PREFIX}-sg-head \
    --protocol tcp --dst-port 22 --remote-ip ${OCH_ADMIN_CIDR} --description SSH
devbox$ sed -i "s|^export OCH_ADMIN_CIDR=.*|export OCH_ADMIN_CIDR='${OCH_ADMIN_CIDR}'|" ~/och/och-vars-env.sh
```

Once SSH works again, find the old rule's ID with `openstack security group rule list ${OCH_PREFIX}-sg-head` and delete it. Otherwise the security group accumulates every address you have ever used, leaving port 22 open to whoever gets that lease next.

⚠ **If you find yourself updating a `/32` rule frequently, use your VPN or campus subnet range instead.** Your network administrator can tell you the CIDR range the VPN pool hands out so a single rule covers every session. On a private VPN range, only hosts already connected to that VPN can reach the network anyway, and they would still need your SSH private key to log in.

A `/32` remains the best choice for a short session or on a cloud with publicly routable floating IPs; the trade-off is updating the rule when your IP changes.

🛑 **Never work around this by opening SSH to `0.0.0.0/0`.** Step 5.5 refuses that deliberately.

Next: [§20 — Teardown](20-teardown.md)
