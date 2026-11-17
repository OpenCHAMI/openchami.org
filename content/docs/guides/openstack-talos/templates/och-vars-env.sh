# och-vars-env.sh — every value this tutorial needs that depends on your OpenStack
# cloud. On the DEVBOX, at ~/och/och-vars-env.sh.
#
# You do not source this file directly. ~/och/och-env.sh — the entry point — does,
# and §3 puts that in ~/.bashrc so it comes back at every login:
#
#   devbox$ cp <this-tutorial>/templates/och-vars-env.sh ~/och/och-vars-env.sh
#   devbox$ source ~/och/och-env.sh
#
# ═════════════════════════════════════════════════════════════════════════════
# WHICH FILE IS SAFE TO RE-COPY, AND WHICH IS NOT
# ═════════════════════════════════════════════════════════════════════════════
#
#   THIS FILE (och-vars-env.sh)  holds YOUR values. Once you have started filling
#                           it in, NEVER replace it wholesale from the template —
#                           you would lose every answer from §3, plus the
#                           values §6.5 and §6.6 append later.
#
#   och-helpers-env.sh       holds only functions, no values. ALWAYS safe to
#                           re-copy wholesale, at any time, with no risk. When
#                           the tutorial improves a helper, that is a one-line
#                           `cp` and nothing of yours is touched.
#
#   och-env.sh               a dispatcher, no values either. ALWAYS safe.
#
# That separation is the whole reason there are three files, and it is why this
# one is not called och-env.sh: the file you re-copy without thinking and the
# file you must never re-copy should not have adjacent names.
#
# 🛑 UPGRADING FROM A SINGLE-FILE ~/och/och-env.sh? RENAME BEFORE YOU COPY.
#    That file held your values; the new och-env.sh does not. Copying the new
#    one over it destroys §3's answers.
#
#      devbox$ mv ~/och/och-env.sh ~/och/och-vars-env.sh          # keep your values
#      devbox$ mv ~/och/och-helpers.sh ~/och/och-helpers-env.sh   # if present
#      devbox$ cp <this-tutorial>/templates/och-env.sh ~/och/   # now the dispatcher
#      devbox$ source ~/och/och-env.sh && och_check
#
# (If your old file also defines och_* functions, delete them from it — the later
# definition wins, so a stale copy shadows nothing, but it is confusing to read.)
#
# ═════════════════════════════════════════════════════════════════════════════
# HOW THIS FILE GETS FILLED IN — three regions, in this order
# ═════════════════════════════════════════════════════════════════════════════
#
#   REGION 1  (§2.6)   OS_CLOUD only. Needed before any OpenStack command works.
#   REGION 2  (§3)   Recon results. These are the OUTPUT of the §3 commands,
#                      so they stay <PLACEHOLDER> while you are running them.
#                      That is expected — never pass a <…> to a command.
#   REGION 3           Fixed by the tutorial. Do not change without reading §5
#                      and §7; several are hardcoded into OpenCHAMI configs.
#
# Then §6.5 appends OCH_HEAD_FIP and §6.6 appends OCH_PROV_IF, at the very end.
#
# Verify with:  och_check     (from och-helpers-env.sh)
#
# Do NOT verify with `grep -c '<' ~/och/och-vars-env.sh` — the comments above and below
# contain '<' of their own, so the count is never 0 even when every value is
# filled in. och_check inspects the OCH_* VALUES instead.

# ═══ REGION 1 — YOUR VALUE. Identity (§2.5–§2.6) ══════════════════════════════
# Which clouds.yaml entry to use. Must be project-scoped to ochami-lab.
#
# This has to match a key under `clouds:` in your clouds.yaml. If you get
# "Cloud ochami-lab was not found", the name here and the name in the file
# disagree — list what you actually have:
#
#   devbox$ python3 -c 'import openstack.config as c; \
#             print("\n".join(sorted(c.OpenStackConfig().get_cloud_names())))'
#
# and either set OS_CLOUD to one of those names, or rename the entry in
# clouds.yaml. openstacksdk looks in $OS_CLIENT_CONFIG_FILE, then ./clouds.yaml
# (relative to your CURRENT DIRECTORY — a surprising one), then
# ~/.config/openstack/clouds.yaml, then /etc/openstack/clouds.yaml.
export OS_CLOUD=ochami-lab

# ═══ REGION 2 — YOUR VALUES. Recon results (§3) ════════════════════════════
# Every line down to REGION 3 is an answer you discover and write in yourself.
# The external network that hands out floating IPs (openstack network list --external)
export OCH_EXT_NET='<EXT_NET>'

# The network YOUR DEVBOX APPEARS FROM, as the HEAD NODE sees it. Every SSH and
# ICMP rule in §5.5 is scoped to this, and §13.5's tunnel comes from here too.
#
# ⚠ `curl -s ifconfig.me` IS ONLY THE RIGHT ANSWER IF THE FLOATING-IP NETWORK IS
#   PUBLICLY ROUTABLE. Check first:
#
#     devbox$ openstack subnet list --network ${OCH_EXT_NET} -c Subnet -f value
#
#   - public range   -> curl -s ifconfig.me is correct; use it, as a /32
#   - private range (10.x / 172.16-31.x / 192.168.x) -> it is NOT correct
#
#   A private range usually means you reach floating IPs over a VPN. With a
#   split-tunnel VPN, ifconfig.me goes out your local line and reports your
#   home/office address, while traffic to the floating IPs goes down the tunnel
#   and arrives from a different address. A /32 of the wrong one blocks the only
#   path you use, and the symptom is an SSH TIMEOUT in §6.6 against a head node
#   that booted perfectly. See §3 for how to find the tunnel-side address.
#
#   The range your VPN hands client addresses out from is a good value here.
#   Ask whoever runs the VPN for it.
#
#   Confirm empirically after your first successful login:
#     head$ sudo journalctl -u sshd | grep -i accepted | tail -3
#
# ⚠ Never 0.0.0.0/0. An open SSH port is found by scanners within minutes, and
#   automation should refuse this value deliberately.
#
# ⚠ A /32 HERE GOES STALE ON ITS OWN. It records where you appeared from when
#   you wrote it, so a VPN reconnect, an expired DHCP lease, or moving between
#   networks invalidates it without you changing anything. The symptom is an
#   SSH *timeout* to a head node that is perfectly healthy — see §19 and
#   §19.
#
#   TWO DEFENSIBLE CHOICES, see §3 and §19:
#     - THE POOL RANGE (the default here): the VPN's client range. One
#       value that survives every reconnect. RFC1918 and unroutable from the
#       internet, so it does not widen who can reach port 22 — only the VPN's
#       own authentication does that.
#     - THE /32 YOU MEASURED: the actual dynamic address the VPN client assigned
#       to your laptop this session. Tightest scope, records each session in the
#       rule list, depends on nobody else's facts — but re-issue every reconnect.
#   Measure the address either way: that is how you know you are on the tunnel,
#   and an address outside the pool range means the pool assumption has changed.
#
#   Write masks out in full: 198.51.100.0/24, never 10.11/16.
export OCH_ADMIN_CIDR='<YOUR_ADMIN_CIDR>'     # the VPN's client range, or a measured /32

# Glance image for the head node: Rocky Linux 9, x86_64.
# Use the image's *exact* name as it appears in `openstack image list`, e.g.
# 'Rocky-9.6'. Names with spaces are why this is quoted.
#
# ⚠ USE THE UUID INSTEAD IF THE NAME IS NOT UNIQUE. Glance does not enforce
#   unique image names, and clouds routinely end up with several — a maintained
#   one plus somebody's upload, or two revisions of the same release. The symptom
#   looks like this:
#
#     $ openstack image show Rocky-9.6 -c properties -f value
#     More than one Image exists with the name 'Rocky-9.6'.
#
#   `server create --image <ambiguous name>` fails the same way in §6.4. Pick one
#   deliberately and pin it by ID:
#
#     $ openstack image list --name 'Rocky-9.6' -f value -c ID -c Name -c Status
#     $ for i in $(openstack image list --name 'Rocky-9.6' -f value -c ID); do
#         openstack image show $i -c name -c visibility -c owner -c created_at \
#           -c min_disk -c properties -f yaml; done
#
#   Prefer the newer, and check `owner`: an image owned by our own project is
#   somebody's upload, not the cloud's maintained one. An ID also cannot start
#   silently resolving to a different image later, which a name can.
export OCH_HEAD_IMAGE='<ROCKY9_IMAGE_NAME_OR_UUID>'

# Firmware type of that image — from `openstack image show … -c properties`,
# look for hw_firmware_type. Decides which iPXE artifact §9 builds.
#   'bios' → ipxe.iso        'uefi' → ipxe.efi in an ESP image
export OCH_FIRMWARE='<bios|uefi>'

# Flavors (openstack flavor list).
#
#   Create the flavors, or ask for them (§3.5). Check each exists before §6:
#     openstack flavor show "$OCH_FLAVOR_HEAD" -c name -c vcpus -c ram -c disk
export OCH_FLAVOR_HEAD='<FLAVOR_HEAD>'        # >=4 vCPU, >=16GB RAM, >=60GB disk
export OCH_FLAVOR_CP='<FLAVOR_CP>'            # >=4 vCPU, >=16GB RAM, >=30GB disk
export OCH_FLAVOR_WORKER='<FLAVOR_WORKER>'    # 8 vCPU, 64GB RAM (vLLM lives here)

# ═══ REGION 3 — TUTORIAL CONSTANTS. Not yours; safe to take from the template ═
# Change these only after reading §5 and §7 — several are hardcoded into the
# OpenCHAMI configs, the node map and the BSS payloads.

# Resource name prefix. Everything we create carries it, so that
# `openstack server list` makes ownership obvious (§3.2).
export OCH_PREFIX=och

# The two networks (§5).
export OCH_EXT_SUBNET_CIDR=192.168.200.0/24   # our side of the routed network
export OCH_PROV_CIDR=172.16.0.0/24            # the provisioning wire

# The head node's address on the provisioning wire. Hardcoded into every
# OpenCHAMI config in §7 — changing it means changing coredhcp.yaml, the
# Corefile, /etc/hosts and every BSS payload.
export OCH_HEAD_PROV_IP=172.16.0.254

# Cluster FQDN: the name on the TLS certificate and in every API URL (§7.2).
export OCH_CLUSTER_NAME=demo
export OCH_CLUSTER_FQDN=demo.openchami.cluster

# Architecture. x86_64 throughout, matching the real hardware (§1).
export OCH_ARCH=amd64                         # Talos/Go naming
export OCH_ARCH_RPM=x86_64                    # RPM naming
export OCH_CONSOLE=ttyS0,115200               # serial console for x86_64

# Object store (Versity S3 gateway) as booting nodes see it (§7.5, §10).
export OCH_OBJ=172.16.0.254:7070

# Talos release to deploy (§10). Pick the latest stable v1.13.x.
export OCH_TALOS_VERSION=v1.13.0

# ─── Node map — the single source of truth (§5, §8, §11) ──────────────────────
# These MAC/IP/xname/role tuples must agree in three places:
#   1. the Neutron ports we create          (§5.4)
#   2. the SMD inventory we load            (§8.1)
#   3. the BSS boot payloads we write       (§11.1)
# Keeping them in sync by hand is the single biggest error source in this
# tutorial — which is precisely what automating it removes, by generating
# all three from one declaration.
#
#   name      xname           nid  mac                  ip            role
#   och-cp1    x1000c0s0b0n0   1    52:54:00:be:ef:01    172.16.0.1    controlplane
#   och-w1     x1000c0s0b1n0   2    52:54:00:be:ef:02    172.16.0.2    worker
#   och-w2     x1000c0s0b2n0   3    52:54:00:be:ef:03    172.16.0.3    worker
#   och-w3     x1000c0s0b3n0   4    52:54:00:be:ef:04    172.16.0.4    worker
#   och-w4     x1000c0s0b4n0   5    52:54:00:be:ef:05    172.16.0.5    worker
#
# We register all five in SMD (§8) but only boot as many as quota allows (§9).
export OCH_CP_MAC=52:54:00:be:ef:01
export OCH_CP_IP=172.16.0.1

# ═════════════════════════════════════════════════════════════════════════════
# END OF YOUR VALUES.  Everything above this line is yours; nothing below is.
# ═════════════════════════════════════════════════════════════════════════════
#
# ⚠ §6.5 and §6.6 APPEND to the end of this file (OCH_HEAD_FIP, OCH_PROV_IF), so
#   values may appear below this line later. That is expected and harmless — they
#   are still yours.
#
# NOTHING ELSE BELONGS BELOW THIS LINE. The och_* helpers are in
# och-helpers-env.sh and are loaded by och-env.sh, the entry point, which sources
# this file first and them second. An earlier version of this file ended by
# sourcing the helpers itself; that made a file you must never re-copy also the
# file that decides what else gets loaded, so the two jobs were separated.
