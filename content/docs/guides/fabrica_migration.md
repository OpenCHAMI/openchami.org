---
title: "Migration to Fabrica Services"
linktitle: "Fabrica Migration"
description: "Learn how to migrate from legacy services (BSS/cloud-init) to the new, fabrica-generated services (boot-service/metadata-service)"
slug: "fabrica-migration"
summary: ""
date: 2026-08-06T16:10:18-06:00
lastmod: 2026-08-07T18:00:00-06:00
contributors: ["Devon Bautista"]
draft: false
weight: 100
toc: true
---
<!-- vi: set tw=80 sw=2 sts=2: -->

This guide describes how to migrate an existing OpenCHAMI deployment made with
a release before v0.2.0 to the services shipped in v0.2.0. The source
deployment uses the legacy Boot Script Service (BSS), cloud-init server,
Hydra, and OPAAL. The destination uses the Fabrica-generated `boot-service`
and `metadata-service`, with TokenSmith providing tokens.

The procedure deliberately migrates service data through the APIs instead of
copying databases between unrelated implementations. It also preserves SMD and
the existing cluster inventory.

{{< callout context="caution" title="Plan a Maintenance Window" icon="outline/alert-triangle" >}}
This is a service replacement, not a zero-downtime rolling upgrade. Do not
provision, reconfigure, or reboot managed nodes during the migration. Schedule
a maintenance window and test the procedure on a copy of the deployment first.
{{< /callout >}}

## What Changes in v0.2.0

The following services and administrative interfaces change:

| Before v0.2.0 | v0.2.0 | Data location |
| --- | --- | --- |
| `bss.service` and `bss-init.service` | `boot-service.service` | BSS PostgreSQL data becomes boot-service file-backed resources |
| `cloud-init-server.service` | `metadata-service.service` | Legacy cloud-init data becomes metadata-service file-backed resources |
| Hydra, OPAAL, and their helper units | `tokensmith.service` | New TokenSmith keys and bootstrap credentials are generated |
| `/boot/v1/*` | `/boot-service/*` | HAProxy removes the `/boot-service/` prefix before proxying |
| `/cloud-init/*` | `/metadata-service/*` | HAProxy removes the `/metadata-service/` prefix before proxying |
| `ochami bss ...` | `ochami boot ...` | The client uses the boot-service resource API |
| `ochami cloud-init ...` | `ochami metadata ...` | The client uses the metadata-service resource API |

There are also two important packaging changes:

- Packaged Quadlets move from `/etc/containers/systemd/` to
  `/usr/share/containers/systemd/`.
- Packaged native Systemd units move from `/etc/systemd/system/` to
  `/usr/lib/systemd/system/`.

Files below `/etc/containers/systemd/` now represent administrator-owned
Quadlets and overrides. An old Quadlet there takes precedence over a packaged
v0.2.0 Quadlet. To prevent a mixed deployment, the v0.2.0 RPM refuses to
install while recognized old OpenCHAMI Quadlets remain in that directory.

{{< callout context="caution" title="Do Not Copy Service Databases" icon="outline/alert-triangle" >}}
BSS stores its resources in PostgreSQL, while boot-service uses file-backed
Fabrica resources. The two cloud-init implementations also have different
resource and storage schemas. Do not mount `bssdb`, `cloud-init-data`, or an
old database file as a new service's data directory. Export logical resources,
convert them, and import them through the new APIs.
{{< /callout >}}

## Migration Overview

The migration has these phases:

1. Inventory the running deployment.
2. Export logical BSS and cloud-init data.
3. Stop OpenCHAMI and make physical backups.
4. Convert the exported resources.
5. Remove the old package-owned units without deleting data volumes.
6. Install and configure v0.2.0.
7. Start the new services and import the converted resources.
8. Validate the APIs and perform a canary boot.

The examples use these variables. Set them for the local deployment before
starting:

```bash
export CLUSTER_NAME=demo
export CLUSTER_FQDN=demo.openchami.cluster
export CLUSTER_URL=https://${CLUSTER_FQDN}:8443
export PROVISIONING_IP=172.16.0.254
export MIGRATION_DIR=${HOME}/openchami-migration-$(date +%Y%m%d-%H%M%S)
mkdir -p "${MIGRATION_DIR}"/{export,converted,backup,inventory}
chmod 700 "${MIGRATION_DIR}"
```

Commands that use `ochami` assume its cluster configuration and access-token
environment variable are already set. For the example cluster, the variable is
`DEMO_ACCESS_TOKEN`.

## 1. Inventory the Existing Deployment

Record the software versions and current health before changing anything:

```bash
rpm -q openchami | tee "${MIGRATION_DIR}/inventory/rpm-version.txt"
ochami version | tee "${MIGRATION_DIR}/inventory/ochami-version.txt"
systemctl list-dependencies openchami.target \
  | tee "${MIGRATION_DIR}/inventory/openchami-dependencies.txt"
systemctl --failed \
  | tee "${MIGRATION_DIR}/inventory/failed-units.txt"
systemctl is-active firewalld \
  | tee "${MIGRATION_DIR}/inventory/firewalld-state.txt"
sudo podman ps --all \
  | tee "${MIGRATION_DIR}/inventory/podman-containers.txt"
sudo podman volume ls \
  | tee "${MIGRATION_DIR}/inventory/podman-volumes.txt"
sudo podman secret ls \
  | tee "${MIGRATION_DIR}/inventory/podman-secrets.txt"
ochami config show \
  | tee "${MIGRATION_DIR}/inventory/ochami-config.yaml"
```

Identify files that can shadow the v0.2.0 package:

```bash
sudo ls -la /etc/containers/systemd \
  | tee "${MIGRATION_DIR}/inventory/etc-quadlets.txt"
sudo ls -la /etc/systemd/system \
  | tee "${MIGRATION_DIR}/inventory/etc-systemd-units.txt"
```

Do not assume every file in these directories belongs to OpenCHAMI. Record any
unrelated containers and local site modifications so that only the old
package-owned OpenCHAMI files are removed later.

Check that the legacy services can still answer requests. Fix export-blocking
problems before proceeding:

```bash
ochami bss service status | jq
ochami smd service status | jq
ochami cloud-init defaults get -F json-pretty | jq
```

{{< callout context="note" title="Set token" icon="outline/info-circle" >}}
The `cloud-init` command above requires a token. Set it with:

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc gen_access_token)
```

{{< /callout >}}

## 2. Export Legacy Data

Logical exports are the source of truth for the new services. Physical volume
backups made later are primarily for rollback.

### 2.1 Export BSS Boot Parameters

Export all BSS boot parameter records as JSON and YAML:

```bash
ochami bss boot params get -F json-pretty \
  | tee "${MIGRATION_DIR}/export/bss-bootparameters.json" >/dev/null
ochami bss boot params get -F yaml \
  | tee "${MIGRATION_DIR}/export/bss-bootparameters.yaml" >/dev/null
jq 'length' "${MIGRATION_DIR}/export/bss-bootparameters.json" \
  | tee "${MIGRATION_DIR}/inventory/bss-record-count.txt"
```

Inspect every record. Pay particular attention to:

- duplicate or overlapping MAC, host, and NID selectors;
- non-numeric values in `nids`;
- kernel, initrd, and `root=live:` URLs;
- parameters containing the old `/cloud-init` URL; and
- embedded BSS `cloud-init`, `phone-home`, or generated `meta` fields.

The embedded BSS cloud-init fields are not boot-service configuration and must
not be copied into a `BootConfiguration`.

### 2.2 Export Cloud-Init Cluster Defaults

```bash
ochami cloud-init defaults get -F json-pretty \
  | tee "${MIGRATION_DIR}/export/cloud-init-defaults.json" >/dev/null
ochami cloud-init defaults get -F yaml \
  | tee "${MIGRATION_DIR}/export/cloud-init-defaults.yaml" >/dev/null
```

The defaults can contain SSH public keys and environment-specific URLs. Protect
the export directory accordingly.

### 2.3 Export Every Cloud-Init Group

The legacy service exposes all group definitions at its administrative groups
endpoint. Using the externally routed URL preserves the same authentication and
TLS behavior used by other administrative clients:

```bash
curl --fail --silent --show-error \
  -H "Authorization: Bearer ${DEMO_ACCESS_TOKEN}" \
  "${CLUSTER_URL}/cloud-init/admin/groups" \
  | jq --sort-keys . \
  | tee "${MIGRATION_DIR}/export/cloud-init-groups.json" >/dev/null
jq 'length' "${MIGRATION_DIR}/export/cloud-init-groups.json" \
  | tee "${MIGRATION_DIR}/inventory/cloud-init-group-count.txt"
```

This relies on `openchami-cert-trust.service` having installed the OpenCHAMI CA
in the system trust store. If the cluster CA is not in the system trust store,
add `--cacert <path-to-cluster-ca>` with the correct local path. Do not use
`--insecure` for a production migration.

The endpoint returns an object keyed by group name. Preserve both the key and
each object's `name`, `description`, `meta-data`, `file`, and `versions` values.

### 2.4 Recover Node-Specific Overrides

The legacy v1.3.0 cloud-init administrative API can set instance overrides but
does not provide a list or get endpoint for the raw override records. Therefore,
use these sources in descending order of reliability:

1. Original IaC files or commands used to create the overrides.
2. Configuration-management history, shell history, or Git history.
3. A backup of the legacy service storage for forensic recovery.
4. Rendered per-node metadata, used only as a last-resort reconstruction.

When impersonation is enabled, capture rendered metadata for nodes known to
have overrides:

```bash
NODE=x1000c0s0b0n0
ochami cloud-init node get meta-data "${NODE}" -F yaml \
  | tee "${MIGRATION_DIR}/export/rendered-${NODE}-metadata.yaml" >/dev/null
```

Rendered metadata combines defaults, SMD data, group data, and instance
overrides. It is useful for comparison, but it is not a lossless export of the
raw override. Manually identify fields that were genuinely node-specific.

{{< callout context="caution" title="Do Not Guess at Overrides" icon="outline/alert-triangle" >}}
If the provenance of a value is uncertain, omit it from the first import and
record it for review. Importing a rendered cluster default as a node override
can permanently mask future default changes for that node.
{{< /callout >}}

### 2.5 Preserve SMD Inventory Inputs

SMD remains PostgreSQL-backed in v0.2.0 and should continue using the existing
`postgres-data` volume. Preserve the original discovery files under
`/etc/openchami/data` and capture useful API output as an additional check:

```bash
ochami smd component get -F json-pretty \
  | tee "${MIGRATION_DIR}/export/smd-components.json" >/dev/null
ochami smd group get -F json-pretty \
  | tee "${MIGRATION_DIR}/export/smd-groups.json" >/dev/null
```

If the installed `ochami` version does not accept those output flags, use the
equivalent command supported by that version. The PostgreSQL backup in the next
section remains the authoritative SMD backup.

### 2.6 Checksum the Logical Exports

```bash
sha256sum "${MIGRATION_DIR}"/export/* \
  | tee "${MIGRATION_DIR}/inventory/export-sha256.txt"
```

Copy the migration directory to storage outside the head node before the
cutover.

## 3. Stop Services and Make Physical Backups

Stop OpenCHAMI to obtain a consistent backup:

```bash
sudo systemctl stop openchami.target
systemctl is-active openchami.target
```

The second command should report `inactive`.

Back up configuration and unit files while preserving ownership, modes, ACLs,
xattrs, and SELinux labels:

```bash
sudo tar --acls --xattrs --selinux -C / -cpf \
  "${MIGRATION_DIR}/backup/etc-openchami.tar" etc/openchami
sudo tar --acls --xattrs --selinux -C / -cpf \
  "${MIGRATION_DIR}/backup/etc-containers-systemd.tar" \
  etc/containers/systemd
sudo tar --acls --xattrs --selinux -C / -cpf \
  "${MIGRATION_DIR}/backup/etc-systemd-system.tar" etc/systemd/system
sudo chown "$(whoami):" "${MIGRATION_DIR}"/backup/etc-{openchami,containers-systemd,systemd-system}.tar
```

### 3.1 Back Up PostgreSQL

Start only PostgreSQL, create a logical dump, then stop it again:

```bash
sudo systemctl start postgres.service
sudo podman exec postgres pg_dumpall -U ochami \
  > "${MIGRATION_DIR}/backup/postgres-pg_dumpall.sql"
sudo systemctl stop postgres.service
```

If the local deployment uses another PostgreSQL superuser, substitute it. Check
the dump before continuing:

```bash
test -s "${MIGRATION_DIR}/backup/postgres-pg_dumpall.sql"
sha256sum "${MIGRATION_DIR}/backup/postgres-pg_dumpall.sql"
```

Also back up the stopped Podman volume. Determine its actual mount point rather
than assuming a storage-driver path:

```bash
POSTGRES_VOLUME=postgres-data
sudo podman volume inspect "${POSTGRES_VOLUME}" \
  | tee "${MIGRATION_DIR}/inventory/postgres-volume.json" >/dev/null
POSTGRES_MOUNT=$(sudo podman volume inspect "${POSTGRES_VOLUME}" \
  --format '{{ .Mountpoint }}')
sudo tar --acls --xattrs --selinux -C "${POSTGRES_MOUNT}" -cpf \
  "${MIGRATION_DIR}/backup/postgres-data.tar" .
sudo chown "$(whoami):" "${MIGRATION_DIR}/backup/postgres-data.tar"
```

Confirm the volume name from `podman volume ls`; some installations prefix or
otherwise customize generated volume names.

### 3.2 Back Up Other Persistent Volumes

At minimum, preserve the legacy `cloud-init-data` volume and the certificate
volumes. A reusable loop can back up each known volume:

```bash
for volume in cloud-init-data acme-certs haproxy-certs \
  step-ca-db step-ca-home step-root-ca; do
  if sudo podman volume exists "${volume}"; then
    mountpoint=$(sudo podman volume inspect "${volume}" \
      --format '{{ .Mountpoint }}')
    sudo tar --acls --xattrs --selinux -C "${mountpoint}" -cpf \
      "${MIGRATION_DIR}/backup/${volume}.tar" .
    sudo chown "$(whoami):" "${MIGRATION_DIR}/backup/${volume}.tar"
  fi
done
```

These archives are rollback artifacts. Do not restore `cloud-init-data` into
`metadata-service-data`.

## 4. Convert the Exported Resources

Perform conversion before removing the old package. Keep converted resources
under `${MIGRATION_DIR}/converted` and review them in version control or with a
second administrator when possible.

### 4.1 Run the Offline Conversion Script

OpenCHAMI provides an offline converter based on the same approach as the
`ochami-discovery-old2new.py` inventory converter. It reads the exports created
in section 2 and does not connect to or modify either deployment.

Download it from this site and inspect it before running it:

```bash
curl --fail --location \
  https://openchami.org/scripts/openchami-resources-old2new.py \
  -o "${MIGRATION_DIR}/openchami-resources-old2new.py"
chmod 755 "${MIGRATION_DIR}/openchami-resources-old2new.py"
python3 "${MIGRATION_DIR}/openchami-resources-old2new.py" --help
```

JSON conversion uses only the Python standard library. Create a Python virtual
environment and install PyYAML to read or write YAML:

```bash
python3 -m venv "${MIGRATION_DIR}/venv"
source "${MIGRATION_DIR}/venv/bin/activate"
pip install PyYAML
```

Convert the complete export bundle:

```bash
python3 "${MIGRATION_DIR}/openchami-resources-old2new.py" \
  --bundle "${MIGRATION_DIR}/export" \
  --output-dir "${MIGRATION_DIR}/converted" \
  --metadata-url \
    "http://${PROVISIONING_IP}:8081/metadata-service" \
  --out-format yaml
```

The converter recognizes these input files:

- `bss-bootparameters.json`;
- `cloud-init-defaults.json`;
- `cloud-init-groups.json`; and
- optional `cloud-init-instance-overrides.json`, assembled from the raw
  overrides recovered in section 2.4.

It writes:

- `boot-configurations.yaml`;
- `cluster-defaults.yaml`;
- `groups.yaml`;
- `instance-info.yaml` when raw overrides were supplied; and
- `migration-report.json`.

Review every generated resource and every warning in `migration-report.json`.
The script reports dropped legacy fields, invalid NIDs and MACs, duplicate boot
selectors, inferred URLs, unsupported overrides, and other conversions that
need an administrator's decision. It does not validate templates against a
running metadata-service.

By default, non-string values in legacy group metadata stop conversion because
modern `metaData` accepts strings. After reviewing those values, explicitly
allow deterministic JSON stringification when appropriate:

```bash
python3 "${MIGRATION_DIR}/openchami-resources-old2new.py" \
  --bundle "${MIGRATION_DIR}/export" \
  --output-dir "${MIGRATION_DIR}/converted" \
  --metadata-url \
    "http://${PROVISIONING_IP}:8081/metadata-service" \
  --out-format yaml \
  --stringify-metadata
```

Use `--strict` to reject all warnings and emit no converted files. In bundle
mode, the absence of the optional raw instance-override file is itself a
warning, because the administrator must confirm whether overrides existed.

The converter can also process one resource type through standard input and
output, matching the discovery converter's workflow:

```bash
python3 "${MIGRATION_DIR}/openchami-resources-old2new.py" \
  --resource boot \
  --metadata-url \
    "http://${PROVISIONING_IP}:8081/metadata-service" \
  --report "${MIGRATION_DIR}/converted/boot-report.json" \
  < "${MIGRATION_DIR}/export/bss-bootparameters.json" \
  > "${MIGRATION_DIR}/converted/boot-configurations.json"
```

The following sections explain each transformation so that the generated files
can be reviewed rather than trusted blindly.

Don't forget to exit the Python virtual environment when finished running the
script:

```bash
deactivate
```

### 4.2 Convert BSS Records to Boot Configurations

Each BSS record becomes one named `BootConfiguration`. Map fields as follows:

| BSS field | BootConfiguration field | Action |
| --- | --- | --- |
| `hosts` | `hosts` | Preserve valid xnames or patterns |
| `macs` | `macs` | Preserve and normalize MAC addresses |
| `nids` | `nids` | Convert strings to integers; review failed conversions |
| `kernel` | `kernel` | Preserve and test the URL |
| `initrd` | `initrd` | Preserve and test the URL |
| `params` | `params` | Preserve, but replace the metadata-service URL |
| none | `name` | Add a unique, meaningful resource name |
| none | `profile` | Optional; use for operational profiles such as `debug` |
| none | `priority` | Optional, from 0 through 100 |
| `cloud-init`, `meta` | none | Do not import |

For example, this legacy record:

```yaml
kernel: http://172.16.0.254:7070/boot-images/vmlinuz
initrd: http://172.16.0.254:7070/boot-images/initramfs.img
params: root=live:http://172.16.0.254:7070/boot-images/compute.squashfs ip=dhcp cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
macs:
  - 52:54:00:be:ef:01
```

becomes an import file like this:

```yaml
---
- name: compute-default
  kernel: http://172.16.0.254:7070/boot-images/vmlinuz
  initrd: http://172.16.0.254:7070/boot-images/initramfs.img
  params: root=live:http://172.16.0.254:7070/boot-images/compute.squashfs ip=dhcp cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/metadata-service
  macs:
    - 52:54:00:be:ef:01
```

Boot-service allows configurations without selectors as catch-all defaults.
Exact MAC matches score above NID, host, group, and catch-all matches. Review
overlaps so a migrated record does not unexpectedly supersede another record.

Use separate import files for logically distinct profiles or node classes. Do
not mechanically assign every legacy record the same name.

### 4.3 Convert Cluster Defaults

Map the legacy keys to their underscore-separated modern names:

| Legacy | Modern |
| --- | --- |
| `base-url` | `base_url` |
| `cloud-provider` | `cloud_provider` |
| `availability-zone` | `availability_zone` |
| `cluster-name` | `cluster_name` |
| `short-name` | `short_name` |
| `nid-length` | `nid_length` |
| `public-keys` | `public_keys` |

`boot-subnet` and `wg-subnet` do not have direct `ClusterDefaults` fields in
metadata-service v0.2.1. Record them separately and migrate their behavior
through network or WireGuard configuration if still needed.

Create `${MIGRATION_DIR}/converted/cluster-defaults.yaml`:

```yaml
---
- name: cluster-defaults
  description: Migrated cluster defaults
  base_url: http://172.16.0.254:8081/metadata-service
  cloud_provider: OpenCHAMI
  region: ""
  availability_zone: ""
  cluster_name: demo
  short_name: de
  nid_length: 2
  public_keys:
    - ssh-ed25519 AAAA... administrator@example
```

Only one intended cluster-default resource should normally be active. Importing
multiple competing defaults makes later behavior difficult to reason about.

### 4.4 Convert Groups and Templates

Map each legacy group as follows:

| Legacy group field | Modern group field |
| --- | --- |
| object key or `name` | `name` |
| `description` | `description` |
| `file.content` | `template` |
| `meta-data` | `metaData` |
| `versions` | no direct import; preserve in the migration archive |

The modern template is always plain text. If `file.encoding` is `base64`,
decode `file.content` before placing it in `template`:

```bash
jq -r '.compute.file.content' \
  "${MIGRATION_DIR}/export/cloud-init-groups.json" \
  | base64 --decode \
  | sudo tee "${MIGRATION_DIR}/converted/compute-cloud-config.yaml" >/dev/null
```

For `file.encoding: plain`, copy the content without base64 decoding.

Modern `metaData` values are strings. Legacy `meta-data` can contain arbitrary
JSON values. Flatten, stringify, or move nested objects and arrays into a
different configuration mechanism instead of assuming they will import
unchanged.

A converted group import file has this form:

```yaml
---
- name: compute
  description: Compute node configuration
  metaData:
    scheduler: slurm
  template: |
    ## template: jinja
    #cloud-config
    users:
      - name: root
        ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
    disable_root: false
```

Metadata-service validates templates when they are created or updated. A
template must both render against the supported context and produce valid
YAML. Review legacy variables carefully. The modern context includes flat node
fields as well as `ds.meta_data`, `ds.vendor_data`, and custom values from
`metaData`, but not every legacy variable is necessarily available.

### 4.5 Convert Instance Overrides

Each known raw legacy override becomes an `InstanceInfo` resource:

| Legacy | Modern |
| --- | --- |
| `id` | `name` and `instance_id` |
| `instance-id` | `instance_id` |
| `local-hostname` | `local_hostname` |
| `hostname` | `hostname` |
| `cloud-init-base-url` | `cloud_init_base_url` |
| `public-keys` | `public_keys` |

Legacy `cluster-name`, `region`, `availability-zone`, `cloud-provider`, and
`instance-type` fields do not all have direct per-instance equivalents in
metadata-service v0.2.1. Keep cluster-wide values in `ClusterDefaults`; document
other intentional behavior changes.

Example:

```yaml
---
- name: x1000c0s0b0n0
  description: Migrated node override
  instance_id: x1000c0s0b0n0
  local_hostname: compute1
  hostname: compute1
  cloud_init_base_url: http://172.16.0.254:8081/metadata-service
  public_keys: []
```

## 5. Remove the Legacy Package Files

Confirm that `openchami.target` is still stopped and no OpenCHAMI containers
are running:

```bash
systemctl is-active openchami.target
sudo podman ps
```

Uninstall the old RPM. This removes package-owned old Quadlets more safely than
deleting the directory by hand:

```bash
sudo dnf remove openchami
```

{{< callout context="caution" title="Keep Volumes and Migration Files" icon="outline/alert-triangle" >}}
Do not run `podman volume prune`, `podman system prune`, or delete
`postgres-data`. The existing PostgreSQL volume contains SMD inventory and is
required by the upgraded deployment.
{{< /callout >}}

After uninstalling, inspect `/etc/containers/systemd/`. Remove or move aside
only stale OpenCHAMI package files that remain after comparing them with the
backup:

```bash
ls -la /etc/containers/systemd
```

The v0.2.0 RPM checks for old OpenCHAMI `.container`, `.network`, and `.volume`
files in this directory and aborts if it finds them. Site overrides and
unrelated Quadlets may remain, provided they do not shadow an OpenCHAMI unit.

Also inspect RPM preservation files before installation:

```bash
ls -la /etc/openchami/configs
```

Keep `.rpmsave` files for comparison. Do not copy the complete old
`openchami.env` over the v0.2.0 version because it contains obsolete BSS,
Hydra, and OPAAL settings.

## 6. Install OpenCHAMI v0.2.0

Download the release RPM and verify the checksum published with the release:

```bash
curl --fail --location --remote-name \
  https://github.com/OpenCHAMI/release/releases/download/v0.2.0/openchami-0.2.0.rpm
echo 'b3e68d4a85feeba13121d8910cdbd944a500ac9e48c8ab14ff4f0d41d2fc96c9  openchami-0.2.0.rpm' \
  | sha256sum --check
sudo dnf install ./openchami-0.2.0.rpm
```

{{< callout context="caution" title="Check the Host Firewall" icon="outline/alert-triangle" >}}
The v0.2.0 RPM post-install script stops `firewalld`. Compare its state with
`inventory/firewalld-state.txt`. If site policy requires it, re-enable it only
after configuring all ports required by the OpenCHAMI provisioning, DNS, API,
object-storage, and registry services.
{{< /callout >}}

If installation reports old Quadlets, do not bypass the check. Compare each
reported file with the backup, remove or convert the stale file, and retry.

Confirm the new package layout:

```bash
rpm -ql openchami | less
ls -la /usr/share/containers/systemd
ls -la /usr/lib/systemd/system/openchami.target
```

Expected new resources include:

- `boot-service.container` and `boot-service-data.volume`;
- `metadata-service.container` and `metadata-service-data.volume`;
- `tokensmith.container` and `tokensmith.volume`; and
- a new `openchami.target` without BSS, cloud-init, Hydra, or OPAAL.

## 7. Merge Site Configuration

The following sections after 7.1 refer to configuration files in
`/etc/openchami/configs`. Refer to the config files there (as well as any
`.rpmsave` files if using DNF/RPM) when merging configs.

### 7.1 Restore the Cluster FQDN

v0.2.0 manages site-specific certificate names with administrator drop-ins
under `/etc/containers/systemd/`:

```bash
sudo openchami-certificate-update update "${CLUSTER_FQDN}"
```

Do not restore old modified `acme-*.container` files. Inspect the generated
drop-in and then reload Systemd:

```bash
ls -la /etc/containers/systemd/acme-.container.d
sudo systemctl daemon-reload
```

### 7.2 Update CoreSMD

#### CoreDHCP

CoreSMD must be v0.6.1 or newer. That release changed plugin parameters from
positional arguments to named multiline values. Preserve the site's interface,
router, DNS, subnet, lease, and address-pool choices while using this form:

```yaml
server4:
  listen:
    - "%virbr-openchami"
  plugins:
    - server_id: 172.16.0.254
    - dns: 172.16.0.254
    - router: 172.16.0.254
    - netmask: 255.255.255.0
    - coresmd: |
        svc_base_uri=https://demo.openchami.cluster:8443
        ipxe_uri=http://172.16.0.254:8081/boot-service/bootscript
        ca_cert=/root_ca/root_ca.crt
        cache_valid=30s
        lease_time=1h
        single_port=false
    - bootloop: |
        lease_file=/tmp/coredhcp.db
        script_path=default
        lease_time=5m
        ipv4_start=172.16.0.200
        ipv4_end=172.16.0.250
```

The important endpoint is
`http://<provisioning-IP>:8081/boot-service/bootscript`. Do not retain the old
base URL that made CoreSMD chainload `/boot/v1/bootscript`.

Note that the order of the key-value pairs above (and in the `coredhcp.yaml`
installed by the package) matches the order of the old, ordered values. This
means that you only need prepend the keys to the values when changing to the
new format for `coresmd` and `bootloop` (if applicable).

If you need to assign hostnames or modify any host-specific DHCP options,
you'll need to use CoreSMD [rich
rules](https://github.com/OpenCHAMI/coresmd/blob/main/examples/coredhcp/rules.md).

#### CoreDNS

The CoreDNS Corefile format has not changed. It is save to copy the `.rpmsave`
file back into the Corefile.

### 7.3 Review HAProxy and Environment Changes

Merge local HAProxy changes into the v0.2.0 configuration. The new routes are:

- `/boot-service/` to `boot-service:8081`;
- `/metadata-service/` to `metadata-service:8080`; and
- `/tokensmith/` to `tokensmith:8080`.

**If this file does not have an `.rpmsave` file (e.g. was not modified), no
config merge is necessary.** The new package will have correct paths
configured.

Reapply site customizations with Quadlet drop-ins when possible. Do not restore
the old BSS, cloud-init, Hydra, or OPAAL backends.

Compare the old and new `openchami.env` files field by field. Preserve valid SMD,
Smallstep, and site settings, but use the v0.2.0 TokenSmith variables and remove
obsolete legacy service variables.

## 8. Start and Verify the New Services

Reload generated units and start OpenCHAMI:

```bash
sudo systemctl daemon-reload
sudo systemctl start openchami.target
systemctl list-dependencies openchami.target
```

The target should contain `boot-service`, `metadata-service`, and `tokensmith`,
and should not contain BSS, cloud-init-server, Hydra, or OPAAL units.

Check every required service:

```bash
for service in postgres smd tokensmith boot-service metadata-service haproxy \
  coresmd-coredhcp; do
  systemctl --no-pager --full status "${service}.service"
done
```

If a service fails, inspect its own log and the first failed dependency:

```bash
sudo journalctl -eu tokensmith.service
sudo journalctl -eu boot-service.service
sudo journalctl -eu metadata-service.service
sudo journalctl -eu smd.service
```

Verify that SMD still contains the pre-migration inventory. If it is empty,
stop immediately. Confirm that `postgres.service` mounted the original
`postgres-data` volume rather than creating or selecting a different volume.

Confirm the new persistent volumes and bootstrap secrets exist:

```bash
sudo podman volume inspect boot-service-data metadata-service-data tokensmith-data
sudo podman secret inspect \
  boot-service-bootstrap-token metadata-service-bootstrap-token
```

## 9. Update `ochami` and Authentication

Use an `ochami` version that supports both `boot` and `metadata` (preferably
v0.10.1+). Configure the cluster and boot-service base URI:

```bash
sudo ochami config cluster set --system --default "${CLUSTER_NAME}" \
  cluster.uri "${CLUSTER_URL}"
sudo ochami config --system cluster set "${CLUSTER_NAME}" \
  cluster.boot-service.uri /boot-service
ochami config show
```

The cluster config should have a `boot-service` block with the configured URI,
e.g:

```yaml
clusters:
    - cluster:
        boot-service:
            uri: /boot-service
        enable-auth: true
        uri: https://demo.openchami.cluster:8443
      name: demo
```

Old Hydra/OPAAL tokens cannot be reused. Mint a TokenSmith token:

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc gen_access_token)
```

For a cluster name other than `demo`, export the uppercase
`<CLUSTER_NAME>_ACCESS_TOKEN` variable expected by `ochami`.

Check service health before importing data:

```bash
ochami boot service status | jq
ochami smd service status | jq
curl --fail --silent --show-error \
  "${CLUSTER_URL}/metadata-service/health" | jq
```

## 10. Import the Converted Data

### 10.1 Import Boot Configurations

Import one reviewed file or logical batch at a time:

```bash
ochami boot config add -f yaml \
  -d @"${MIGRATION_DIR}/converted/boot-configurations.yaml"
ochami boot config list -F yaml \
  | sudo tee "${MIGRATION_DIR}/inventory/imported-boot-configurations.yaml" \
    >/dev/null
```

`add` rejects an existing resource. For subsequent changes, get the resource's
UID and use `ochami boot config set <uid>`. Record old-record-to-new-UID mappings
in the migration directory.

Compare the imported count with the BSS export and explain every intentional
difference, such as merged duplicate records or dropped obsolete records.

### 10.2 Import Cluster Defaults

```bash
ochami metadata defaults add -f yaml \
  -d @"${MIGRATION_DIR}/converted/cluster-defaults.yaml"
ochami metadata defaults list -F yaml
```

Verify that `spec.base_url` points to `/metadata-service`, and that the cluster
name, hostname prefix, NID length, and SSH keys match the reviewed export.

### 10.3 Import Groups

```bash
ochami metadata group add -f yaml \
  -d @"${MIGRATION_DIR}/converted/groups.yaml"
ochami metadata group list -F yaml \
  | sudo tee "${MIGRATION_DIR}/inventory/imported-groups.yaml" >/dev/null
```

Treat a template-validation failure as a conversion problem. Do not weaken or
skip validation simply to complete the import. Check the template variable,
plain-text decoding, indentation, and rendered YAML.

### 10.4 Import Instance Overrides

Import only reviewed raw overrides reconstructed in section 4.4:

```bash
ochami metadata instance add -f yaml \
  -d @"${MIGRATION_DIR}/converted/instance-info.yaml"
ochami metadata instance list -F yaml
```

Command nouns can vary between early `ochami` versions. If `metadata instance`
is unavailable, use the generated metadata-service client or the modern
`/instanceinfos` resource API documented by the service. Do not fall back to
the legacy `ochami cloud-init node set` command against v0.2.0.

## 11. Validate the Migrated Configuration

Complete all checks before allowing managed nodes to reboot.

### 11.1 Validate Boot Artifacts and Selection

List the modern configurations and test every referenced artifact URL:

```bash
ochami boot config list -F json-pretty \
  | sudo tee "${MIGRATION_DIR}/inventory/final-boot-configurations.json" \
    >/dev/null
jq -r '.[] | .spec.kernel, .spec.initrd' \
  "${MIGRATION_DIR}/inventory/final-boot-configurations.json" \
  | while read -r url; do
      [ -n "${url}" ] && curl --fail --head "${url}"
    done
```

Request a boot script for at least one node in every node class or profile
(replace MAC address with one from your inventory):

```bash
curl --fail --silent --show-error \
  "http://${PROVISIONING_IP}:8081/boot-service/bootscript?mac=52:54:00:be:ef:01"
```

Check that the selected kernel, initrd, and kernel parameters are correct and
that no parameter still contains `/cloud-init`.

### 11.2 Validate Metadata Rendering

Metadata-service identifies a node from its request IP through SMD. From an
administrative host, supply a representative provisioning IP with
`X-Forwarded-For` only when the service or trusted proxy permits this testing
method:

```bash
NODE_IP=172.16.0.1
for endpoint in meta-data vendor-data network-config; do
  curl --fail --silent --show-error \
    -H "X-Forwarded-For: ${NODE_IP}" \
    "http://${PROVISIONING_IP}:8081/metadata-service/${endpoint}"
done
curl --fail --silent --show-error \
  -H "X-Forwarded-For: ${NODE_IP}" \
  "http://${PROVISIONING_IP}:8081/metadata-service/compute.yaml"
```

Verify:

- the instance ID, hostname, NID, IP address, and MAC address;
- all expected SMD group memberships;
- the `/metadata-service` base URL;
- SSH public keys and other sensitive configuration;
- successful rendering of every group template; and
- valid cloud-init YAML and network configuration.

Compare representative output with the rendered legacy metadata captured in
section 2.4. Differences should be understood and documented.

### 11.3 Check Logs and Stale Paths

```bash
sudo journalctl --since "1 hour ago" \
  -u boot-service -u metadata-service -u tokensmith -u smd \
  --no-pager
sudo grep -R -nE '/cloud-init|/boot/v1|bss|hydra|opaal' \
  /etc/openchami /etc/containers/systemd
```

Some archived migration files may intentionally contain old strings. Active
configuration and imported boot parameters should not.

## 12. Perform a Canary Boot

Choose a noncritical node that represents a common configuration. Follow its
console through the entire boot and verify that it:

1. Receives the expected address from CoreDHCP.
2. Downloads the iPXE loader and chainload script.
3. Requests `/boot-service/bootscript`.
4. Downloads the expected kernel and initrd.
5. Downloads the expected root image.
6. Requests cloud-init data below `/metadata-service`.
7. Applies the expected hostname, SSH keys, users, files, and network settings.
8. Appears healthy after boot.

Keep the canary running long enough to catch delayed configuration errors. Then
expand the cutover one node group or hardware class at a time. Retain all
backups until every node class has booted successfully and the site has passed
its normal acceptance tests.

## Rollback

Rollback returns the deployment to the exact pre-migration RPM and physical
data. It does not translate writes made to the new services back into BSS or
the legacy cloud-init service.

1. Stop the modern target:

   ```bash
   sudo systemctl stop openchami.target
   ```

2. Export any new boot-service or metadata-service changes that must be
   preserved for a later migration attempt.

3. Remove v0.2.0 without pruning Podman data:

   ```bash
   sudo dnf remove openchami
   ```

4. Reinstall the exact previous OpenCHAMI RPM.

5. Restore `/etc/openchami`, old Quadlets, and old native units from the backup.

6. If PostgreSQL changed or is damaged, restore the stopped `postgres-data`
   volume or the `pg_dumpall` backup. Do not overwrite a healthy volume without
   first preserving its current state.

7. Restore other legacy volumes only when needed, then repair labels:

   ```bash
   sudo restorecon -RFv /etc/openchami /etc/containers/systemd
   sudo systemctl daemon-reload
   sudo systemctl start openchami.target
   ```

8. Verify BSS, cloud-init, SMD, `/boot/v1/bootscript`, and `/cloud-init` before
   rebooting any nodes.

## Troubleshooting

### The v0.2.0 RPM Refuses to Install

The RPM found an old OpenCHAMI Quadlet in `/etc/containers/systemd`. Compare
that file with the backup. Remove the stale package file or replace a genuine
site customization with a drop-in. Do not bypass the check or delete unrelated
Quadlets.

### The Wrong Container Image or Unit Starts

Use these commands to see the generated unit and source paths:

```bash
systemctl cat boot-service.service
systemctl cat metadata-service.service
systemctl show boot-service.service -p FragmentPath -p DropInPaths
```

A same-named Quadlet in `/etc/containers/systemd` can override the packaged
file in `/usr/share/containers/systemd`.

### Configuration Changes Are Missing

RPM configuration files use `noreplace` semantics. Inspect `.rpmnew` and
`.rpmsave` files under `/etc/openchami/configs` and merge them deliberately.
Do not replace new configuration wholesale with the legacy files.

### CoreDHCP Fails to Start

Confirm CoreDHCP is v0.6.1 or newer and that `coresmd` and `bootloop` use named
multiline parameters. Check indentation, the network interface, CA path, SMD
URL, and provisioning IP:

```bash
sudo journalctl -eu coresmd-coredhcp.service
```

### Boot-Service Has No Configurations

The BSS PostgreSQL database is not read by boot-service. Import the converted
`BootConfiguration` resources and confirm the `boot-service-data` volume is
writable. Do not copy BSS database files into the volume.

### A Node Selects the Wrong Boot Configuration

Review overlapping selectors, profiles, and priorities. Exact MAC matches have
greater selection weight than NIDs, hosts, groups, and catch-all defaults. Use
representative bootscript requests to test each class before rebooting nodes.

### A Metadata Group Is Rejected

Check whether `file.content` was base64-decoded, whether the modern template
context contains every referenced variable, and whether the rendered result is
valid YAML. The new service stores `spec.template` as plain text.

### Metadata-Service Cannot Identify a Node

Verify the request source IP, HAProxy forwarding, SMD interfaces, SMD group
membership, and TokenSmith access to SMD. A container-network or NAT address in
place of the node's provisioning address prevents correct identity resolution.

### SMD Appears Empty

Stop the migration before rediscovering nodes. Confirm which Podman volume is
mounted at `/var/lib/postgresql/data`, compare it with the pre-migration volume
inspection, and restore the database only after preserving the current state.

### TokenSmith Bootstrap Fails

Inspect `tokensmith.service` first, then the consuming service. Confirm the
TokenSmith volume is writable and that the expected bootstrap Podman secret was
created. Old Hydra/OPAAL credentials and tokens are not valid substitutes.

## References

- [OpenCHAMI release v0.2.0](https://github.com/OpenCHAMI/release/releases/tag/v0.2.0)
- [v0.1.6 to v0.2.0 release comparison](https://github.com/OpenCHAMI/release/compare/v0.1.6...v0.2.0)
- [v0.2.0 packaged Quadlets](https://github.com/OpenCHAMI/release/tree/v0.2.0/systemd)
- [boot-service v0.3.1 API documentation](https://github.com/OpenCHAMI/boot-service/blob/v0.3.1/docs/API.md)
- [boot-service v0.3.1 configuration documentation](https://github.com/OpenCHAMI/boot-service/blob/v0.3.1/docs/CONFIGURATION.md)
- [metadata-service v0.2.1 legacy compatibility](https://github.com/OpenCHAMI/metadata-service/blob/v0.2.1/LEGACY_COMPATIBILITY.md)
- [metadata-service v0.2.1 client guide](https://github.com/OpenCHAMI/metadata-service/blob/v0.2.1/docs/CLIENT_USAGE.md)
- [Legacy OpenCHAMI tutorial](/docs/archive/tutorial-legacy/)
- [Current OpenCHAMI tutorial](/docs/tutorial/)
