#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# och-status.sh — "where am I in this tutorial?"
#
#   devbox$ source ~/och/och-env.sh
#   devbox$ bash ~/och/och-status.sh
#
# Probes the live state of the project and maps it onto section numbers, then
# prints the first thing that is not done yet.
#
# STRICTLY READ-ONLY. Every OpenStack call is a `list` or a `show`; there is no
# create, set, delete or reboot anywhere in this file, and nothing outside the
# ${OCH_PREFIX}- namespace is inspected. Safe to run at any time, including
# mid-section, and safe to run on a shared cloud.
#
# Takes ~30 seconds: it batches one `list` per resource type rather than a
# `show` per object.
#
# Head-node checks (§§7-8) are attempted over SSH only if the head is
# reachable; if it is not, they are reported as "unknown", never as failed.
# ---------------------------------------------------------------------------

P="${OCH_PREFIX:-och}"
PASS=0; FAIL=0; UNKNOWN=0
FIRST_TODO=""; FIRST_TODO_HINT=""

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_b=$'\033[1m'; c_0=$'\033[0m'
[ -t 1 ] || { c_g=; c_r=; c_y=; c_b=; c_0=; }

ok()   { printf '  %s[ok]%s   %-42s %s\n'   "$c_g" "$c_0" "$1" "${2-}"; PASS=$((PASS+1)); }
no()   { printf '  %s[TODO]%s %-42s %s\n'   "$c_r" "$c_0" "$1" "${2-}"; FAIL=$((FAIL+1))
         [ -z "$FIRST_TODO" ] && { FIRST_TODO="$3"; FIRST_TODO_HINT="$1 — ${2-}"; }; }
huh()  { printf '  %s[?]%s    %-42s %s\n'   "$c_y" "$c_0" "$1" "${2-}"; UNKNOWN=$((UNKNOWN+1)); }
warn() { printf '  %s[warn]%s %-42s %s\n'   "$c_y" "$c_0" "$1" "${2-}"; }
hdr()  { printf '\n%s%s%s\n' "$c_b" "$1" "$c_0"; }

# ── §§2–3 identity ──────────────────────────────────────────────────────────
hdr "§§2–3 — identity and reconnaissance"

# `token issue` asks for a SCOPED token, which some deployments refuse for
# application-credential auth ("Application credentials cannot request a scope").
# So try it, but fall back to an ordinary read rather than declaring auth broken.
PROJ=$(openstack token issue -c project_id -f value 2>/dev/null)
if [ -z "$PROJ" ]; then
    if openstack catalog list -f value -c Name >/dev/null 2>&1; then
        ok "credentials" "authenticated ('token issue' unavailable — normal for app creds)"
        PROJ=""
    else
        no "credentials" "openstack cannot authenticate" "§2.6"
        printf '\n%sStop here.%s Nothing else can be probed until the CLI authenticates.\n' "$c_r" "$c_0"
        printf 'Keystone said:\n'; openstack catalog list -f value -c Name 2>&1 | sed 's/^/  /' | head -5
        printf 'Then check OS_CLOUD (%s) against your clouds.yaml — see §2.6.\n' "${OS_CLOUD:-unset}"
        exit 1
    fi
else
    ok "credentials" "project $PROJ"
fi

# ── Does THIS shell hold admin? ───────────────────────────────────────────
# Informational only. §2.6 uses one credential with your own roles, which is
# fine. Appendix A (optional) splits everyday work from admin; this tells you
# which you are holding. A 403 from the probe means "not admin".
UID_=$(openstack token issue -c user_id -f value 2>/dev/null)
if [ -z "$UID_" ] || [ -z "$PROJ" ]; then
    ADMPROBE="skip"
else
    ADMPROBE=$(openstack role assignment list --user-id "$UID_" --project-id "$PROJ" \
                 --names -f value 2>&1)
fi
if printf '%s\n' "$ADMPROBE" | grep -qiE 'forbidden|policy .*not allow|403'; then
    ok "credential scope" "not admin"
elif printf '%s\n' "$ADMPROBE" | grep -qw admin; then
    warn "credential scope" "this shell holds admin — fine; Appendix A shows how to split it off"
else
    huh "credential scope" "could not determine (harmless)"
fi

# och-vars-env.sh completeness. Distinguish "unset" from "still a <placeholder>".
env_check() {
    local var="$1" need="$2" sect="$3" val="${!1-}"
    if [ -z "$val" ]; then
        if [ "$need" = required ]; then no "och-vars-env.sh: $var" "not set at all" "$sect"
        else warn "och-vars-env.sh: $var" "not set (needed by $sect)"; fi
    elif case "$val" in *'<'*'>'*) true;; *) false;; esac; then
        if [ "$need" = required ]; then no "och-vars-env.sh: $var" "still a placeholder: $val" "$sect"
        else warn "och-vars-env.sh: $var" "still a placeholder (needed by $sect)"; fi
    else
        ok "och-vars-env.sh: $var" "$val"
    fi
}
env_check OCH_EXT_NET      required "§3"
env_check OCH_HEAD_IMAGE   required "§3"
env_check OCH_FLAVOR_HEAD  required "§3 / §6.2"
env_check OCH_ADMIN_CIDR   required "§3 / §5.5"
env_check OCH_FIRMWARE     later    "§9"
env_check OCH_FLAVOR_CP    later    "§9"
env_check OCH_FLAVOR_WORKER later   "§9"

# One batch of listings, reused throughout.
NETS=$(openstack network list -f value -c Name 2>/dev/null)
SUBNETS=$(openstack subnet list -f value -c Name 2>/dev/null)
ROUTERS=$(openstack router list -f value -c Name 2>/dev/null)
PORTS=$(openstack port list -f value -c Name 2>/dev/null)
SGS=$(openstack security group list -f value -c Name 2>/dev/null)
SERVERS=$(openstack server list -f value -c Name -c Status 2>/dev/null)
IMAGES=$(openstack image list -f value -c Name 2>/dev/null)
VOLUMES=$(openstack volume list -f value -c Name 2>/dev/null)
KEYS=$(openstack keypair list -f value -c Name 2>/dev/null)
FIPS=$(openstack floating ip list -f value -c 'Floating IP Address' -c 'Fixed IP Address' 2>/dev/null)
FLAVORS=$(openstack flavor list -f value -c Name 2>/dev/null)

has() { printf '%s\n' "$2" | grep -qx -- "$1"; }

# Flavor existence, separately from the och-vars-env.sh check above.
if [ -n "${OCH_FLAVOR_HEAD-}" ] && case "$OCH_FLAVOR_HEAD" in *'<'*) false;; *) true;; esac; then
    if has "$OCH_FLAVOR_HEAD" "$FLAVORS"; then
        ok "head flavor" "$OCH_FLAVOR_HEAD"
        DISK=$(openstack flavor show "$OCH_FLAVOR_HEAD" -c disk -f value 2>/dev/null)
        [ -n "$DISK" ] && [ "$DISK" -lt 40 ] 2>/dev/null && \
            warn "head flavor disk" "${DISK}GB < 40GB — §6.2 wants a Cinder volume for /data"
    else
        no "head flavor" "$OCH_FLAVOR_HEAD does not exist — create it, or ask for it (§3.5)" "§3"
    fi
fi

# ── §5 networks and ports ──────────────────────────────────────────────────
hdr "§5 — networks, subnets and ports"

has "$P-ext" "$NETS"        && ok "network $P-ext" || no "network $P-ext" "missing" "§5.1"
has "$P-ext-subnet" "$SUBNETS" && ok "subnet $P-ext-subnet" || no "subnet $P-ext-subnet" "missing" "§5.1"

if has "$P-router" "$ROUTERS"; then
    GW=$(openstack router show "$P-router" -c external_gateway_info -f value 2>/dev/null)
    case "$GW" in
        *network_id*) ok "router $P-router" "external gateway set" ;;
        *)            no "router $P-router" "exists but no external gateway" "§5.1" ;;
    esac
else
    no "router $P-router" "missing" "§5.1"
fi

has "$P-prov" "$NETS" && ok "network $P-prov" || no "network $P-prov" "missing" "§5.2"
if has "$P-prov-subnet" "$SUBNETS"; then
    DHCP=$(openstack subnet show "$P-prov-subnet" -c enable_dhcp -f value 2>/dev/null)
    if [ "$DHCP" = False ]; then ok "subnet $P-prov-subnet" "enable_dhcp=False"
    else no "subnet $P-prov-subnet" "enable_dhcp=$DHCP — MUST be False (§5.2)" "§5.2"; fi
else
    no "subnet $P-prov-subnet" "missing" "§5.2"
fi

if has "$P-head-prov" "$PORTS"; then
    PS=$(openstack port show "$P-head-prov" -c port_security_enabled -f value 2>/dev/null)
    IP=$(openstack port show "$P-head-prov" -c fixed_ips -f value 2>/dev/null)
    [ "$PS" = False ] && ok "port $P-head-prov" "port security off" \
                      || no "port $P-head-prov" "port_security_enabled=$PS — must be False (§5.3)" "§5.3"
    case "$IP" in
        *"${OCH_HEAD_PROV_IP:-172.16.0.254}"*) ok "  its fixed IP" "${OCH_HEAD_PROV_IP:-172.16.0.254}" ;;
        *) no "  its fixed IP" "not ${OCH_HEAD_PROV_IP:-172.16.0.254} — this is how the head gets its address (§6)" "§5.4" ;;
    esac
else
    no "port $P-head-prov" "missing" "§5.4"
fi

NODEPORTS=$(printf '%s\n' "$PORTS" | grep -c "^${P}-node[0-9]*-prov$")
[ "$NODEPORTS" -ge 1 ] && ok "node ports" "$NODEPORTS of 5" \
                       || no "node ports" "none found" "§5.4"

# §5.5 — the group, and the binding, which is the failure that looks like something else.
if has "$P-sg-head" "$SGS"; then
    RULES=$(openstack security group rule list "$P-sg-head" -f value 2>/dev/null)
    SSHR=$(printf '%s\n' "$RULES" | grep -c '22:22\|22 ')
    OPEN=$(printf '%s\n' "$RULES" | grep -c '0\.0\.0\.0/0.*22:22')
    ok "security group $P-sg-head" "$SSHR SSH rule(s)"

    # Show WHICH source addresses are permitted. The rule existing tells you
    # nothing useful; the CIDR it is scoped to is the whole question, and it is
    # what §6.6 succeeds or times out on.
    SSHCIDRS=$(printf '%s\n' "$RULES" | grep '22:22\|tcp' \
               | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | sort -u | tr '\n' ' ')
    if [ -n "$SSHCIDRS" ]; then
        printf '  %s[ok]%s   %-42s %s\n' "$c_g" "$c_0" "  SSH permitted from" "$SSHCIDRS"
        # och-vars-env.sh must AGREE with reality, or §19's diagnosis starts from a lie.
        if [ -z "${OCH_ADMIN_CIDR-}" ] || case "${OCH_ADMIN_CIDR-}" in *'<'*'>'*) true;; *) false;; esac; then
            warn "  but OCH_ADMIN_CIDR" "unset/placeholder — och-vars-env.sh does not record the above"
            printf '        %s\n' "Backfill it so §19's check has something true to compare against:"
            printf '        %s\n' "  sed -i \"s|^export OCH_ADMIN_CIDR=.*|export OCH_ADMIN_CIDR='${SSHCIDRS%% *}'|\" ~/och/och-vars-env.sh"
        else
            case "$SSHCIDRS" in
                *"$OCH_ADMIN_CIDR"*) ok "  OCH_ADMIN_CIDR agrees" "$OCH_ADMIN_CIDR" ;;
                *) warn "  OCH_ADMIN_CIDR disagrees" "och-vars-env.sh says $OCH_ADMIN_CIDR, rule says $SSHCIDRS" ;;
            esac
        fi
    fi
    [ "$OPEN" -gt 0 ] && printf '  %s[STOP]%s %-42s %s\n' "$c_r" "$c_0" \
        "SSH open to 0.0.0.0/0" "delete that rule — §5.5"
    printf '%s\n' "$RULES" | grep -q 'tcp' || \
        warn "  its rules" "no tcp rule found — SSH will time out in §6.6"
else
    no "security group $P-sg-head" "missing" "§5.5"
fi

if has "$P-head-ext" "$PORTS"; then
    SGIDS=$(openstack port show "$P-head-ext" -c security_group_ids -f value 2>/dev/null)
    NSG=$(printf '%s\n' "$SGIDS" | tr -d "[]',' " | tr ' ' '\n' | grep -c '[0-9a-f]')
    if [ -n "$SGIDS" ] && [ "$NSG" -ge 1 ]; then
        WANT=$(openstack security group show "$P-sg-head" -c id -f value 2>/dev/null)
        case "$SGIDS" in
            *"$WANT"*) ok "port $P-head-ext" "bound to $P-sg-head" ;;
            *) no "port $P-head-ext" "carrying a group that is NOT $P-sg-head (probably 'default' — §5.5)" "§5.5" ;;
        esac
    else
        no "port $P-head-ext" "no security group bound — §5.5 binds it" "§5.5"
    fi
else
    no "port $P-head-ext" "missing" "§5.4"
fi

# ── §6 the head node ───────────────────────────────────────────────────────
hdr "§6 — the head node instance"

has "$P-key" "$KEYS" && ok "keypair $P-key" || no "keypair $P-key" "missing" "§6.1"
has "$P-head-data" "$VOLUMES" && ok "volume $P-head-data" "(optional, §6.7)" || true

HEADSTATUS=$(printf '%s\n' "$SERVERS" | awk -v n="$P-head" '$1==n {print $2}')
if [ -n "$HEADSTATUS" ]; then
    if [ "$HEADSTATUS" = ACTIVE ]; then ok "instance $P-head" "ACTIVE"
    else no "instance $P-head" "status $HEADSTATUS" "§6.4"; fi

    HFIP=$(openstack server show "$P-head" -f value -c addresses 2>/dev/null)
    case "$HFIP" in
        *10.*|*,*) ok "  addresses" "$HFIP" ;;
        *)         warn "  addresses" "$HFIP" ;;
    esac
    printf '%s\n' "$FIPS" | grep -q . && ok "  floating IP allocated" \
        || no "  floating IP" "none allocated" "§6.5"
else
    no "instance $P-head" "not created" "§6.4"
fi

# ── §§7-8 on the head, only if reachable ───────────────────────────────────
hdr "§§7–8 — OpenCHAMI on the head (over SSH)"

HEAD_IP="${OCH_HEAD_FIP-}"
[ -z "$HEAD_IP" ] && HEAD_IP=$(printf '%s\n' "$FIPS" | awk 'NF>1 {print $1; exit}')

if [ -z "$HEAD_IP" ] || [ -z "$HEADSTATUS" ]; then
    huh "head reachability" "no floating IP yet — nothing to probe"
elif ! timeout 8 ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 -i ~/.ssh/och_ed25519 "rocky@$HEAD_IP" true 2>/dev/null; then
    huh "head reachability" "SSH to $HEAD_IP failed — see §6.6 / §19"
    printf '        %s\n' "Not necessarily broken: OCH_ADMIN_CIDR may not match the address the"
    printf '        %s\n' "head sees (§3), or your VPN may be down. Console log still works:"
    printf '        %s\n' "  openstack console log show $P-head --lines 40"
else
    ok "head reachability" "ssh rocky@$HEAD_IP"
    R=$(timeout 25 ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
        -i ~/.ssh/och_ed25519 "rocky@$HEAD_IP" bash -s 2>/dev/null <<'REMOTE'
echo "PROVIF=$(ip -br addr | awk '/172\.16\.0\.254/ {print $1}')"
echo "QUADLETS=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -ci 'smd\|bss\|coredhcp\|coredns\|step-ca\|hydra\|opaal\|haproxy\|postgres')"
echo "DHCP67=$(sudo ss -ulpn 2>/dev/null | grep -c ':67 ')"
echo "S3=$(sudo ss -ltn 2>/dev/null | grep -c ':7070 ')"
echo "REG=$(sudo ss -ltn 2>/dev/null | grep -c ':5000 ')"
echo "FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)"
echo "MASQ=$(sudo nft list ruleset 2>/dev/null | grep -c masquerade)"
echo "SMD=$(ochami smd component get 2>/dev/null | jq '[.Components[]?|select(.Type=="Node")]|length' 2>/dev/null)"
echo "TALOS=$(ls ~/talos/*.yaml 2>/dev/null | wc -l)"
REMOTE
)
    eval "$(printf '%s\n' "$R" | grep -E '^[A-Z0-9]+=')" 2>/dev/null

    [ -n "${PROVIF-}" ] && ok "  provisioning interface" "$PROVIF (this is OCH_PROV_IF, §6.6)" \
                        || no "  provisioning interface" "no NIC holds 172.16.0.254" "§6.6"
    [ "${QUADLETS:-0}" -ge 5 ] && ok "  OpenCHAMI services" "$QUADLETS running" \
                              || no "  OpenCHAMI services" "${QUADLETS:-0} running" "§7"
    [ "${S3:-0}" -ge 1 ]  && ok "  Versity S3 :7070"  || no "  Versity S3 :7070" "not listening" "§7.5"
    [ "${REG:-0}" -ge 1 ] && ok "  OCI registry :5000" || warn "  OCI registry :5000" "not listening (§7)"
    [ "${DHCP67:-0}" -ge 1 ] && ok "  CoreDHCP on :67" \
                             || no "  CoreDHCP on :67" "nothing serving DHCP — no node can boot" "§7.7"
    [ "${FWD:-0}" = 1 ] && ok "  ip_forward" || no "  ip_forward" "off" "§7.12"
    [ "${MASQ:-0}" -ge 1 ] && ok "  NAT masquerade" || no "  NAT masquerade" "no rule" "§7.12"
    [ "${SMD:-0}" -ge 1 ] 2>/dev/null && ok "  SMD nodes" "${SMD} registered" \
                                      || no "  SMD nodes" "SMD empty or unreachable" "§8.1"
    [ "${TALOS:-0}" -ge 1 ] && ok "  Talos configs present" "$TALOS yaml in ~/talos" \
                            || huh "  Talos configs" "none yet (§10)"
fi

# ── §9 onward ──────────────────────────────────────────────────────────────
hdr "§9 onward — node instances"

has "$P-ipxe-disk" "$IMAGES" && ok "image $P-ipxe-disk" || huh "image $P-ipxe-disk" "not uploaded (§9.2)"
NODES=$(printf '%s\n' "$SERVERS" | grep -cE "^${P}-(cp1|w[0-9]+) ")
[ "$NODES" -ge 1 ] && ok "node instances" "$NODES created" || huh "node instances" "none yet (§9.3)"
printf '%s\n' "$SERVERS" | grep -E "^${P}-(cp1|w[0-9]+) " | grep -q RESCUE && \
    warn "a node is in RESCUE" "unexpected — §9 does not use rescue"

# ── verdict ────────────────────────────────────────────────────────────────
hdr "Summary"
printf '  %s%d ok%s, %s%d to do%s, %s%d unknown%s\n' \
    "$c_g" "$PASS" "$c_0" "$c_r" "$FAIL" "$c_0" "$c_y" "$UNKNOWN" "$c_0"

if [ -z "$FIRST_TODO" ]; then
    printf '\n  %sEverything probed is done.%s Next unprobed work is §10 onward — Talos assets,\n' "$c_g" "$c_0"
    printf '  BSS payloads and the cluster itself, which this script only checks shallowly.\n'
else
    printf '\n  %sStart at: %s%s\n' "$c_b" "$FIRST_TODO" "$c_0"
    printf '  Because: %s\n' "$FIRST_TODO_HINT"
fi

printf '\n  Anything marked [?] is "not reached yet or not visible from here", not a failure.\n'
printf '  Re-run after each section; it is read-only and takes ~30s.\n\n'
