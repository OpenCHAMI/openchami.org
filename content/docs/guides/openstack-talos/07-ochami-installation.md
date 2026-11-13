---
title: "§7 — OpenCHAMI Installation"
description: "You install OpenCHAMI on the head node and start it. You finish with every service running and its two main APIs answering, ready for the nodes."
slug: "07-ochami-installation"
date: 2026-10-21
lastmod: 2026-10-21
weight: 70
toc: true
draft: false
---
> ⏱ **About 30–45 minutes, mostly waiting for container downloads** · briefly on the devbox, then on the head node · installs OpenCHAMI, an S3 store, an image registry and NAT
>
> - **What this chapter is for.** You install OpenCHAMI on the head node and start it. You finish with every service running and its two main APIs answering, ready for the nodes.
>
> - **What you will learn.** What each part of the control plane does, how the head node serves the provisioning network, and which upstream defaults to change before first start.
>
> - **Don't skip it.** Every chapter from §8 onwards talks to these services.

---

## Introduction

### The control plane is a set of small services

On the head node, OpenCHAMI runs as roughly a dozen small containers, each responsible for a single job. These are the ones you will interact with most often:

| Service | What it does |
|---|---|
| **SMD** (State Management Database) | Holds the hardware inventory: each node, its MAC address and its IP (§8 populates this) |
| **BSS** (Boot Script Service) | Serves each node its iPXE boot script (§11 configures the Talos boot payloads) |
| **CoreDHCP**, with the `coresmd` plugin | Leases each node in SMD its assigned IP address and points it at BSS |
| **CoreDNS**, with the `coresmd` plugin | Serves internal DNS records for nodes, such as `de01.openchami.cluster` |
| **haproxy, step-ca and the ACME services** | Terminate TLS (Transport Layer Security) in front of the APIs using a local certificate authority |
| **hydra and opaal** | Issue the OAuth2 / OIDC tokens required for API writes |

Before installing OpenCHAMI itself, you will also set up two helper services:

- **An OCI (Open Container Initiative) container registry on port 5000.** OpenCHAMI uses a local registry when building custom OS images. Even though Talos comes prebuilt, the OpenCHAMI release expects the registry service to be present.

- **The Versity S3 Gateway on port 7070.** This lightweight S3-compatible object store hosts the boot artifacts (the Talos kernel and initramfs uploaded in §10) that nodes download over HTTP during network boot.

🔀 **Deviation: S3 on port 7070, not 9000.** Older OpenCHAMI guides deployed MinIO on port `9000` with static credentials, whereas the current upstream tutorial and release RPM deploy VersityGW on port `7070` with generated credentials. Every S3 URL in this tutorial uses `:7070` — watch out for stale `:9000` references in older upstream docs.

### It installs like any other machine

🔀 **Deviation: almost none.** Installing OpenCHAMI on `och-head` works the same way as on a physical server or local VM. Only three small details come from our environment:

1. Binding CoreDHCP to the provisioning interface name you recorded in §6.6 (Step 7.7).
2. Adding a systemd drop-in so the AWS CLI doesn't trip over OpenStack availability zone names when bootstrapping VersityGW (Step 7.5).
3. Configuring the head node as a NAT (network address translation) router so Talos nodes can pull container images from the internet (Step 7.12).

### The services are managed with systemd

You never need to run `podman run` by hand. Each container is defined by a Podman *quadlet* — a short unit file in `/etc/containers/systemd/` that `systemd` turns into a standard service. You start and stop services with `systemctl`, and inspect their logs with `journalctl`.

The OpenCHAMI release RPM (from [`github.com/OpenCHAMI/release`](https://github.com/OpenCHAMI/release)) installs all of the quadlets alongside their configuration files in `/etc/openchami/`, and groups them under a single target: `openchami.target`.

### The head node is everything on the provisioning network

To the worker nodes on `och-prov`, `172.16.0.254` is the only server on the wire — acting as their DHCP server, DNS server, default gateway and boot server:

| On `172.16.0.254` | Service | What the nodes use it for |
|---|---|---|
| DHCP | CoreDHCP (Step 7.7) | Obtaining an IP lease and the BSS boot script URL |
| DNS, port 53 | CoreDNS (Step 7.8) | Resolving internal cluster hostnames |
| Port 8081, plain HTTP | BSS (Step 7.9b) | Fetching their iPXE boot script |
| Port 7070 | Versity S3 (Step 7.3) | Downloading the Talos kernel and initramfs |
| Default route | NAT (Step 7.12) | Reaching the internet to pull Talos and Kubernetes container images |

CoreDHCP is configured to listen exclusively on `OCH_PROV_IF` (§6.6) so it never answers DHCP requests on the external network.

### Certificates and tokens

OpenCHAMI's APIs sit behind `haproxy` with TLS enabled. A local certificate authority (`step-ca`) issues the TLS certificate over ACME (Automatic Certificate Management Environment) for the cluster's FQDN (fully qualified domain name), which you configure in Step 7.9 before starting the stack. Because that certificate is valid for only 24 hours and the release RPM doesn't renew it automatically, Step 7.9c adds a `systemd` timer to renew it every 8 hours.

Any API call that modifies state requires a JWT (JSON Web Token) from the built-in OIDC (OpenID Connect) services (`hydra` and `opaal`). You generate tokens using the `gen_access_token` helper (Step 7.13); each token lasts **one hour**.

### What you will do

- **Send your variables to the head node** (Step 7.1). Copy your environment variables over SSH and create the working directories.

- **Turn on IP forwarding and name the cluster** (Step 7.2). Enable IPv4 forwarding and add the cluster FQDN to `/etc/hosts`.

- **Install and start the S3 gateway and OCI registry** (Steps 7.3 to 7.5). Install VersityGW, add the region drop-in, and start both services.

- **Install the OpenCHAMI release RPM** (Step 7.6).

- **Configure CoreDHCP and CoreDNS** (Steps 7.7 and 7.8). Point both services at your provisioning interface and SMD.

- **Configure certificates and BSS before first start** (Steps 7.9 to 7.9c). Set the certificate FQDN, point BSS's retry URL at `172.16.0.254:8081`, and add the certificate renewal timer.

- **Start OpenCHAMI** (Step 7.10). Bring up `openchami.target`.

- **Install the `ochami` CLI** (Step 7.11). Install and configure the command-line client on the head node.

- **Make the head node a NAT router** (Step 7.12). Configure `nftables` masquerading so worker nodes can reach the internet.

- **Get an access token** (Step 7.13). Issue a token and verify that SMD and BSS respond.

📌 The OpenCHAMI documentation and upstream projects go into more detail:

- [The OpenCHAMI tutorial](https://openchami.org/docs/tutorial/), Part 1. This chapter follows the upstream sequence with cloud-specific adjustments marked 🔀.

- The OpenCHAMI [release](https://github.com/OpenCHAMI/release), [SMD](https://github.com/OpenCHAMI/smd), [BSS](https://github.com/OpenCHAMI/bss), [coresmd](https://github.com/OpenCHAMI/coresmd) and [`ochami` CLI](https://github.com/OpenCHAMI/ochami) repositories.

- [Podman quadlets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html), for how container unit files map to `systemd` services.

- [The Versity S3 Gateway](https://github.com/versity/versitygw) and [step-ca](https://smallstep.com/docs/step-ca/).

- [CoreDHCP](https://github.com/coredhcp/coredhcp) and [the CoreDNS manual](https://coredns.io/manual/toc/).

- [NAT with nftables](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)), for Step 7.12.

---

## Step 7.1 — Send your variables to the head node

Apart from the `devbox$` commands right below, everything in this chapter runs on the head node over SSH (`ssh -i ~/.ssh/och_ed25519 rocky@${OCH_HEAD_FIP}`).

Rather than retyping your configuration on the head node, generate `och-head-vars-env.sh` directly from the variables in your devbox shell and copy it across alongside `och-head-env.sh`:

```
devbox$ cat > ~/och/och-head-vars-env.sh <<EOF
# Generated from och-vars-env.sh on the devbox — see §7. Do not edit by hand.
export OCH_CLUSTER_NAME=${OCH_CLUSTER_NAME}
export OCH_CLUSTER_FQDN=${OCH_CLUSTER_FQDN}
export OCH_HEAD_PROV_IP=${OCH_HEAD_PROV_IP}
export OCH_PROV_IF=${OCH_PROV_IF}
export OCH_PROV_CIDR=${OCH_PROV_CIDR}
export OCH_OBJ=${OCH_OBJ}
export OCH_ARCH_RPM=${OCH_ARCH_RPM}
export OCH_ARCH=${OCH_ARCH}
export OCH_CONSOLE=${OCH_CONSOLE}
export OCH_TALOS_VERSION=${OCH_TALOS_VERSION}
export OCH_CP_IP=${OCH_CP_IP}
EOF
devbox$ cat ~/och/och-head-vars-env.sh                    # read it before sending it
devbox$ curl -fsSL https://openchami.org/docs/guides/openstack-talos/templates/och-head-env.sh -o ~/och/och-head-env.sh
devbox$ scp -i ~/.ssh/och_ed25519 ~/och/och-head-vars-env.sh ~/och/och-head-env.sh \
            rocky@${OCH_HEAD_FIP}:~/
```

Notice that `EOF` is unquoted so your devbox shell expands `${OCH_...}` into actual values before writing the file. Check the output of `cat ~/och/och-head-vars-env.sh` to make sure no variable expanded to an empty string.

Now, on the head node, source `och-head-env.sh` and add it to `~/.bashrc` so your variables persist across SSH sessions:

```
head$ source ~/och-head-env.sh
head$ echo '[ -f ~/och-head-env.sh ] && . ~/och-head-env.sh' >> ~/.bashrc
head$ echo "${OCH_CLUSTER_FQDN} on ${OCH_PROV_IF}, objects at ${OCH_OBJ}"
demo.openchami.cluster on eth1, objects at 172.16.0.254:7070
```

📌 Just like on the devbox, `och-head-env.sh` automatically sources any `~/och-head-*-env.sh` files present, so later chapters (§12 and §16) can drop in new helper files without editing `~/.bashrc` again.

Finally, create the working directories for the OCI registry and downloaded packages:

```
head$ sudo mkdir -p /data/oci /opt/workdir
head$ sudo chown -R rocky: /data/oci /opt/workdir
```

`/data/oci` backs the local container registry volume, and `/opt/workdir` holds downloaded RPMs. Keeping both outside `/home/rocky` avoids SELinux labelling issues when containers bind-mount host directories.

---

## Step 7.2 — Turn on IP forwarding and name the cluster

Enable IPv4 packet forwarding so the head node can route traffic between `och-prov` and `och-ext`:

```
head$ echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/90-forward.conf
head$ sudo sysctl --system | grep 90-forward -A1
```

Next, add the cluster FQDN (`demo.openchami.cluster`) to `/etc/hosts` pointing at `172.16.0.254`:

```
head$ echo "${OCH_HEAD_PROV_IP} ${OCH_CLUSTER_FQDN}" | sudo tee -a /etc/hosts
```

OpenCHAMI's internal services connect to one another using this FQDN and verify it against the TLS certificate issued in Step 7.9, so the name must resolve locally on the head node.

---

## Step 7.3 — Install the Versity S3 gateway

Download and install the latest `versitygw` quadlet RPM:

```
head$ cd /opt/workdir
head$ latest_versity_url=$(curl -s https://api.github.com/repos/openchami/versitygw-quadlet/releases/latest \
        | jq -r '.assets[] | select(.name | endswith("'"$(rpm --eval '%dist')"'.noarch.rpm")) | .browser_download_url')
head$ curl -L "$latest_versity_url" -o versitygw.rpm
head$ sudo dnf install -y ./versitygw.rpm
```

Here `rpm --eval '%dist'` expands to `.el9`, selecting the Rocky Linux 9 package.

---

## Step 7.4 — Write the registry quadlet

Create `/etc/containers/systemd/registry.container` to run a local OCI registry on port 5000 backed by `/data/oci` (the `:Z` flag sets the SELinux context on the volume):

```
head$ sudo tee /etc/containers/systemd/registry.container > /dev/null << 'EOF'
[Unit]
Description=Image OCI Registry
After=network-online.target
Requires=network-online.target

[Container]
ContainerName=registry
HostName=registry
Image=docker.io/library/registry:latest
Volume=/data/oci:/var/lib/registry:Z
PublishPort=5000:5000

[Service]
TimeoutStartSec=0
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

---

## Step 7.5 — Start the S3 gateway and registry

🔀 **Deviation: add a region drop-in before starting `versitygw-bootstrap`.** When `versitygw-bootstrap` runs the `aws` CLI to create its initial S3 buckets, it does not pass a `--region` flag. By default, the underlying `botocore` library queries the cloud instance metadata service (`169.254.169.254`) for the instance's availability zone (AZ) and strips the last character to guess the region name.

While that heuristic turns an AWS zone like `us-east-1a` into `us-east-1`, it fails on OpenStack clouds whose AZ names don't look like AWS regions. For example, on a zone named `DL-Rack-5`, stripping the last character leaves `DL-Rack-`, which ends in a hyphen and fails validation:

```
Provided region_name 'DL-Rack-' doesn't match a supported format.
```

To prevent `botocore` from querying the OpenStack metadata service, add a `systemd` drop-in that disables metadata lookups and sets the region to `us-east-1`:

```
head$ sudo mkdir -p /etc/systemd/system/versitygw-bootstrap.service.d
head$ sudo tee /etc/systemd/system/versitygw-bootstrap.service.d/10-aws-region.conf <<'EOF'
[Service]
Environment=AWS_EC2_METADATA_DISABLED=true
Environment=AWS_REGION=us-east-1
Environment=AWS_DEFAULT_REGION=us-east-1
EOF
```

Leave the region set to `us-east-1` — it is not a placeholder. VersityGW runs with `VGW_REGION=us-east-1` by default and checks that region in every AWS SigV4 request signature (rejecting mismatches with `AuthorizationHeaderMalformed`). Setting both `AWS_REGION` and `AWS_DEFAULT_REGION` covers both v1 and v2 of the AWS CLI.

Now reload `systemd` and start the registry and S3 gateway services:

```
head$ sudo systemctl daemon-reload
head$ sudo systemctl start registry.service
head$ sudo systemctl enable --now versitygw-gensecrets.service
head$ sudo systemctl start versitygw.service
head$ sudo systemctl enable --now versitygw-bootstrap.service
```

What each step does:

- **`daemon-reload`** runs the Podman quadlet generator to turn the `.container` files into `systemd` services.

- **`versitygw-gensecrets`** generates S3 credentials once and saves them to `/etc/versitygw/secrets.env` (which §10 reads).

- **`versitygw`** starts the S3 gateway on port 7070.

- **`versitygw-bootstrap`** creates the initial S3 users and buckets (safe to re-run if you ever need to restart it).

✅ **Quick check.** Confirm that both services report `active`:

```
head$ for s in versitygw registry; do echo -n "$s: "; systemctl is-active $s; done
versitygw: active
registry: active
```

---

## Step 7.6 — Install the OpenCHAMI release RPM

Download and install the latest `openchami-release` RPM from GitHub:

```
head$ release_json=$(curl -s https://api.github.com/repos/openchami/release/releases/latest)
head$ rpm_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .browser_download_url' | head -n1)
head$ curl -L -o openchami-release.rpm "$rpm_url"
head$ sudo dnf install -y ./openchami-release.rpm
```

Inspect the installed quadlet files and configuration templates before starting the services:

```
head$ ls /etc/containers/systemd/    # ~18 quadlets: smd, bss, coresmd-*, haproxy,
                                     # postgres, step-ca, hydra*, opaal*, acme-*,
                                     # cloud-init-server…
head$ ls /etc/openchami/configs/     # coredhcp.yaml, Corefile, openchami.env
```

---

## Step 7.7 — Configure CoreDHCP

Write `/etc/openchami/configs/coredhcp.yaml`, using the `OCH_PROV_IF` interface name you recorded in §6.6:

```
head$ sudo tee /etc/openchami/configs/coredhcp.yaml > /dev/null << EOF
server4:
  listen:
    - "%${OCH_PROV_IF}"
  plugins:
    - server_id: ${OCH_HEAD_PROV_IP}
    - dns: ${OCH_HEAD_PROV_IP}
    - router: ${OCH_HEAD_PROV_IP}
    - netmask: 255.255.255.0
    - coresmd: https://${OCH_CLUSTER_FQDN}:8443 http://${OCH_HEAD_PROV_IP}:8081 /root_ca/root_ca.crt 30s 1h false
    - bootloop: /tmp/coredhcp.db default 5m 172.16.0.200 172.16.0.250
EOF
head$ cat /etc/openchami/configs/coredhcp.yaml    # confirm real values, not empty strings
```

Key settings in this file:

- **`listen: "%eth1"`** binds CoreDHCP exclusively to the provisioning NIC (`OCH_PROV_IF` from §6.6), ensuring it never answers DHCP requests on the external network.

- **`server_id`, `dns` and `router`** advertise the head node (`172.16.0.254`) as the DHCP server, DNS server and default gateway for every booting node.

- **`coresmd`** polls SMD every 30 seconds for known MAC addresses, leases each known node its assigned IP for 1 hour, and sets its iPXE boot script URL to BSS on `http://172.16.0.254:8081`.

- **`bootloop`** hands unknown MAC addresses a temporary 5-minute lease from `172.16.0.200–250` (the range we excluded from Neutron's allocation pools in §5.2) so uninventoried nodes keep retrying until they are registered in SMD.

---

## Step 7.8 — Configure CoreDNS

Write `/etc/openchami/configs/Corefile`:

```
head$ sudo tee /etc/openchami/configs/Corefile > /dev/null << EOF
.:53 {
    ready
    prometheus 0.0.0.0:9153
    bind ${OCH_HEAD_PROV_IP}

    coresmd {
        smd_url https://${OCH_CLUSTER_FQDN}:8443
        ca_cert /root_ca/root_ca.crt
        cache_duration 30s
        zone openchami.cluster {
            nodes de{02d}
        }
    }
}
EOF
```

Like CoreDHCP, CoreDNS uses the `coresmd` plugin to generate DNS records dynamically from SMD (mapping node 1 to `de01.openchami.cluster`, and so on).

⚠ **Leave CoreDNS without an upstream `forward` clause.** CoreDNS here only resolves internal `.openchami.cluster` names; §10.6 configures public DNS servers in the Talos machine config for pulling external container images, and §10.4 explains why keeping internet DNS out of iPXE avoids boot-time subtleties.

---

## Step 7.9 — Set the certificate's name

Update the ACME and `haproxy` configuration so the local CA issues its TLS certificate for `${OCH_CLUSTER_FQDN}` rather than the host's short hostname:

```
head$ sudo openchami-certificate-update update ${OCH_CLUSTER_FQDN}
```

You can ignore the restart commands printed at the end of its output, since OpenCHAMI is not running yet.

---

## Step 7.9b — Point BSS at an address a *node* can reach

By default, `/etc/openchami/configs/openchami.env` ships with `BSS_IPXE_SERVER=${SYSTEM_URL}`. Update three `BSS_*` variables in that file before starting OpenCHAMI:

```
head$ sudo cp /etc/openchami/configs/openchami.env{,.bak-$(date +%F)}
head$ sudo sed -i \
    -e "s|^BSS_IPXE_SERVER=.*|BSS_IPXE_SERVER=${OCH_HEAD_PROV_IP}:8081|" \
    -e 's|^BSS_CHAIN_PROTO=.*|BSS_CHAIN_PROTO=http|' \
    /etc/openchami/configs/openchami.env
head$ grep -q '^BSS_GW_URI=' /etc/openchami/configs/openchami.env \
    || echo 'BSS_GW_URI=' | sudo tee -a /etc/openchami/configs/openchami.env
head$ grep -E '^BSS_(IPXE_SERVER|CHAIN_PROTO|GW_URI)=' /etc/openchami/configs/openchami.env
BSS_IPXE_SERVER=172.16.0.254:8081
BSS_CHAIN_PROTO=http
BSS_GW_URI=
```

When a node boots before its BSS parameters are ready (as in §9), BSS serves a short retry script telling iPXE to sleep for 10 seconds and re-fetch its boot script. BSS builds that retry URL from these three variables, and all three upstream defaults need adjusting here:

| Variable | Shipped default | Why it fails | Set to |
|---|---|---|---|
| `BSS_IPXE_SERVER` | `${SYSTEM_URL}` | `systemd`'s `EnvironmentFile=` does not expand nested variables, so BSS receives the literal string `${SYSTEM_URL}`, which iPXE expands to an empty string (`https:///…`) | `172.16.0.254:8081` |
| `BSS_CHAIN_PROTO` | `https` | iPXE does not trust the local `step-ca` certificate, and the certificate is issued for the FQDN rather than `172.16.0.254` | `http` |
| `BSS_GW_URI` | *Unset* (defaults to `/apis/bss`) | `/apis/bss` is the legacy Cray CSM API gateway prefix; here nodes talk directly to BSS on `:8081` | **Empty, but explicitly set** (`BSS_GW_URI=`) |

📌 Keep `BSS_GW_URI=` present with an empty value rather than deleting the line: BSS checks it with `os.LookupEnv` and falls back to `/apis/bss` if the variable is unset.

🛑 **Do not change `SYSTEM_URL` itself.** Other services (`opaal.yaml` and `step-ca`) rely on `SYSTEM_URL` being set to `${OCH_CLUSTER_FQDN}`.

---

## Step 7.9c — Install a renewal timer, before anything depends on the certificate

🛑 **The TLS certificate issued by `step-ca` expires after 24 hours, and the release RPM does not renew it automatically.** Once it expires, every OpenCHAMI API call fails with `x509: certificate has expired` while already-booted Kubernetes nodes continue running, making the expiry easy to miss until you next run an `ochami` command.

Create a `systemd` service and timer to renew the certificate every 8 hours:

```
head$ sudo tee /etc/systemd/system/openchami-cert-renew.service > /dev/null << 'EOF'
[Unit]
Description=Renew the OpenCHAMI TLS certificate and reload haproxy
After=openchami.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart acme-register
ExecStart=/usr/bin/systemctl restart acme-deploy
ExecStart=/usr/bin/systemctl restart haproxy
EOF
head$ sudo tee /etc/systemd/system/openchami-cert-renew.timer > /dev/null << 'EOF'
[Unit]
Description=OpenCHAMI TLS certificate renewal (every 8 hours)

[Timer]
OnCalendar=*-*-* 00,08,16:00:00
RandomizedDelaySec=2m
Persistent=true

[Install]
WantedBy=timers.target
EOF
head$ sudo systemctl daemon-reload
head$ sudo systemctl enable --now openchami-cert-renew.timer
```

⚠ **Why renew every 8 hours instead of every 24 hours?** Because `RandomizedDelaySec=2m` adds jitter to each run, renewing only once every 24 hours can occasionally fire a minute *after* the previous 24-hour certificate expires. Running every 8 hours keeps at least 16 hours of validity in reserve at all times.

📌 Note that if the release RPM includes an `openchami-certificate-renewal.timer` unit, enabling it alone does not work because it uses `OnUnitActiveSec=1d` without an initial trigger, so it never fires.

✅ **Verify the renewal service after Step 7.10 starts OpenCHAMI** by running it once manually and checking the certificate's `notAfter` timestamp:

```
head$ sudo systemctl start openchami-cert-renew.service
head$ echo | openssl s_client -connect ${OCH_CLUSTER_FQDN}:8443 -servername ${OCH_CLUSTER_FQDN} 2>/dev/null | openssl x509 -noout -dates
```

---

## Step 7.10 — Start OpenCHAMI

Start `openchami.target`:

```
head$ sudo systemctl start openchami.target
```

Because the first start pulls roughly 18 container images, this command can take several minutes to return. You can watch progress in a second SSH session or `tmux` pane:

```
head$ watch systemctl list-dependencies openchami.target
```

Once the command finishes, verify that the target is `active` and no units failed:

```
head$ systemctl is-active openchami.target && systemctl --failed --no-legend | wc -l
active
0
```

⚠ **If your SSH session drops while `systemctl start` is running**, the startup continues in the background on the head node — check `systemctl is-active openchami.target` after reconnecting.

⚠ **Gotcha: the very first start often reports `A dependency job for openchami.target failed`.** While Podman is pulling images in parallel on first boot, one service (usually `haproxy` or an ACME helper) can time out waiting for another. Simply wait a minute and run `sudo systemctl start openchami.target` a second time; the remaining services will come up cleanly.

⚠ **Gotcha: SMD starting before `hydra`'s signing keys exist.** If SMD starts before `hydra` finishes generating its JWT keys on first boot, unauthenticated reads work but authenticated writes (§8) fail with `500 Internal Server Error` (`jwtauth … nil pointer` in `podman logs smd`). Fix it with `sudo systemctl restart smd`.

⚠ **Gotcha: restart `coresmd` after any certificate change.** Because `coresmd-coredhcp` and `coresmd-coredns` read the root CA certificate only once at startup, always run `sudo systemctl restart coresmd-coredhcp coresmd-coredns` if you ever re-run `openchami-certificate-update`.

---

## Step 7.11 — Install the `ochami` CLI

Download and install the `ochami` CLI RPM:

```
head$ ochami_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest \
        | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
head$ curl -L -o ochami.rpm "$ochami_url"
head$ sudo dnf install -y ./ochami.rpm
head$ ochami version | head -1
```

📌 We select `amd64.rpm` because our head node is `x86_64` (use `arm64.rpm` on an `aarch64` host).

Configure `ochami` to point at your cluster (`echo y` confirms creation of `/etc/ochami/config.yaml`):

```
head$ echo y | sudo ochami config cluster set --system --default \
        ${OCH_CLUSTER_NAME} cluster.uri https://${OCH_CLUSTER_FQDN}:8443
head$ ochami config show
clusters:
    - cluster:
        enable-auth: true
        uri: https://demo.openchami.cluster:8443
      name: demo
default-cluster: demo
log:
    color: auto
    format: rfc3339
    level: warning
timeout: 30s
```

In this configuration:

- **`name: demo` and `uri`** come from `OCH_CLUSTER_NAME` and `OCH_CLUSTER_FQDN`.
- **`default-cluster: demo`** (set by `--default`) lets you omit `--cluster demo` on every command.
- **`--system`** writes the config to `/etc/ochami/config.yaml` so it applies to every user on the head node.

---

## Step 7.12 — Make the head node a NAT router

🔀 **Deviation: required for Talos.** On first boot, Talos pulls its installer image from `ghcr.io/siderolabs/installer` and Kubernetes control-plane images from `registry.k8s.io`. Step 7.7 already configured the head node (`172.16.0.254`) as the nodes' default gateway, and Step 7.2 enabled IPv4 forwarding; now we add outbound source NAT (masquerading) on the head node's external interface.

First, identify the external interface (the NIC holding `192.168.200.x`) and save it to `~/och-head-vars-env.sh`:

```
head$ ip -brief addr | grep -E '192\.168\.200'
head$ export OCH_EXT_IF=eth0          # YOUR value
head$ echo "export OCH_EXT_IF=${OCH_EXT_IF}" >> ~/och-head-vars-env.sh
head$ ping -c1 1.1.1.1
```

Next, check whether `firewalld` is installed and running on your image:

```
head$ command -v firewall-cmd    # silent = not installed
head$ systemctl is-active firewalld
inactive
```

**If `firewalld` is active**, enable masquerading through `firewall-cmd`:

```
head$ sudo firewall-cmd --permanent --add-masquerade
head$ sudo firewall-cmd --reload
```

**Otherwise (the default on Rocky 9 cloud images), use `nftables` in its own table.** Do not edit the default `ip nat` table, because Podman's `netavark` networking stack manages `table ip nat` via `iptables-nft`:

```
head$ sudo nft list table ip nat | head -1
# Warning: table ip nat is managed by iptables-nft, do not touch!
```

Instead, create a separate `twnat` table dedicated to `172.16.0.0/24`:

```
head$ sudo nft add table ip twnat
head$ sudo nft 'add chain ip twnat postrouting { type nat hook postrouting priority srcnat ; }'
head$ sudo nft add rule ip twnat postrouting ip saddr ${OCH_PROV_CIDR} oif "${OCH_EXT_IF}" masquerade
head$ sudo nft list table ip twnat
```

Because `twnat` matches only `172.16.0.0/24` while Podman's rules match `10.88.0.0/16` and `10.89.1.0/24`, the two `postrouting` chains coexist cleanly without interfering with each other.

To make the `twnat` table persist across reboots, write `/etc/sysconfig/nftables.conf` (substituting your own `OCH_PROV_CIDR` and `OCH_EXT_IF` values if they differ from `172.16.0.0/24` and `eth0`):

```
head$ sudo tee /etc/sysconfig/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f
# NAT for the OpenCHAMI provisioning wire (§7.12).
# Deliberately in its own table — `table ip nat` belongs to iptables-nft.
# add-then-delete makes this file idempotent without flushing anything else.
add table ip twnat
delete table ip twnat
table ip twnat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    ip saddr 172.16.0.0/24 oif "eth0" masquerade
  }
}
EOF
head$ sudo systemctl enable --now nftables
```

⚠ **Never put `flush ruleset` in `/etc/sysconfig/nftables.conf`.** Flushing the entire ruleset would wipe out Podman's `NETAVARK` port-forwarding rules for the registry (`:5000`) and VersityGW (`:7070`). Using `add table ip twnat` followed by `delete table ip twnat` resets only our `twnat` table.

⚠ **Remember that NAT for worker nodes also depends on `--disable-port-security` (§5.4)** on `och-head-prov` — without it, Neutron's anti-spoofing filter drops forwarded packets from `172.16.0.0/24`.

Verify that IPv4 forwarding and your masquerade rule are active:

```
head$ sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 1
```

Run the check matching whichever firewall tool you used:

```
head$ sudo firewall-cmd --query-masquerade        # firewalld path only
yes
```

```
head$ sudo nft list chain ip twnat postrouting    # nftables path only
table ip twnat {
	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr 172.16.0.0/24 oif "eth0" masquerade
	}
}
```

Then confirm that Podman's `NETAVARK` rules and the S3 gateway are still intact:

```
head$ sudo nft list table ip nat | grep -c NETAVARK   # -> non-zero: podman's rules intact
head$ sudo podman ps --format '{{.Names}}' | wc -l    # -> 13, unchanged
head$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7070
403
```

⚠ **An HTTP `403` from `http://127.0.0.1:7070` means VersityGW is healthy** (an unauthenticated `GET /` against S3 is supposed to return `403 Forbidden`, so don't use `curl -f` here). You can also test an authenticated S3 listing:

```
head$ sudo AWS_EC2_METADATA_DISABLED=true AWS_REGION=us-east-1 \
        aws --profile vgw-root --endpoint-url http://127.0.0.1:7070 s3 ls
2026-08-03 16:03:48 fabricmanager-bucket
2026-08-03 16:03:46 slurmd-bucket
```

📌 `fabricmanager-bucket` and `slurmd-bucket` are created automatically by `versitygw-bootstrap`; §10.3 will create a `boot-images` bucket for our Talos artifacts.

---

## Step 7.13 — Get an access token

Generate a 1-hour JWT access token and export it as `DEMO_ACCESS_TOKEN` (`<CLUSTERNAME>_ACCESS_TOKEN` in uppercase):

```
head$ export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

Whenever `ochami` returns `401 Unauthorized` in a later chapter, re-run this command to mint a fresh token.

---

## ✅ Checkpoint

First, check that all 19 service units from the release RPM are present:

```
head$ systemctl list-dependencies openchami.target --plain | grep -c '\.service'
19
```

Because `list-dependencies` only lists installed unit files, verify that `openchami.target` is active and that zero services have failed:

```
head$ systemctl is-active openchami.target && systemctl --failed --no-legend | wc -l
active
0
```

You can also inspect the status of every individual service under `openchami.target`:

```
head$ systemctl list-dependencies openchami.target --plain | grep '\.service' \
    | tr -d ' |─├└' \
    | while read -r u; do printf '%-34s %s\n' "$u" "$(systemctl is-active $u)"; done
acme-deploy.service                active
…
step-ca.service                    active
```

⚠ **Why `podman ps` shows 13 running containers rather than 19:** Seven of the 19 units (`acme-register`, `acme-deploy`, `openchami-cert-trust`, `smd-init`, `bss-init`, `hydra-migrate` and `hydra-gen-jwks`) are `Type=oneshot` setup tasks that run once, exit, and stay marked `active` via `RemainAfterExit=yes`. The remaining 11 long-running OpenCHAMI containers plus `registry` and `versitygw` (from Step 7.5) give 13 running containers in `podman ps`:

```
head$ sudo podman ps --format '{{.Names}}' | sort | tr '\n' ' '
bss cloud-init-server coresmd-coredhcp coresmd-coredns haproxy hydra
opaal opaal-idp postgres registry smd step-ca versitygw
```

Finally, query both BSS and SMD through `ochami` to verify TLS, `haproxy`, certificates and Postgres end to end:

```
head$ ochami bss service status | jq -c .
{"bss-status":"running"}

head$ ochami smd service status | jq -c .
{"code":0,"message":"HSM is healthy"}
```

(`HSM` stands for Hardware State Manager, SMD's original Cray name.)

---

## Common failures

| Symptom | Cause / fix |
|---|---|
| `versitygw-bootstrap` exits 255 with `Provided region_name '<something>' doesn't match a supported format` | `botocore` derived an invalid AWS region string from your OpenStack availability zone name. Add the systemd drop-in in Step 7.5 and restart `versitygw-bootstrap.service` |
| `haproxy` fails with `could not resolve address 'opaal'` | Startup ordering race on first boot. Run `sudo systemctl restart opaal haproxy` |
| TLS errors from `ochami` | Certificate FQDN mismatch or expired cert. Re-run Step 7.9, then `sudo systemctl restart acme-deploy coresmd-coredhcp coresmd-coredns` |
| A service stays `activating` for several minutes | Podman is still pulling its container image. Check progress with `journalctl -eu <service>` |
| `500 Internal Server Error` on authenticated API calls | SMD started before `hydra` finished generating its signing keys (Step 7.10). Run `sudo systemctl restart smd` |
| `coredhcp` fails to start with `no such device` | `OCH_PROV_IF` in Step 7.7 does not match your provisioning NIC. Check `ip -brief addr` and regenerate `/etc/openchami/configs/coredhcp.yaml` |
| CoreDHCP is active, but booting nodes never receive DHCP offers | CoreDHCP is bound to the wrong interface, or Neutron DHCP / port security is still enabled on `och-prov` (re-check the §5 checkpoint) |

Next: [§8 — OpenCHAMI Node Inventory](08-ochami-node-inventory.md)
