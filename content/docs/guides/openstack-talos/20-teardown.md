---
title: "§20 — Teardown"
description: "Give the cloud resources back when you aren't using the cluster, deleting them in the order OpenStack needs."
slug: "20-teardown"
date: 2026-10-21
lastmod: 2026-10-21
weight: 200
toc: true
draft: false
---
> ⏱ **About 10 minutes** · on the devbox, plus a few commands on the head node · deletes what §5–§9 created
>
> - **What this chapter is for.** You give the resources back when you aren't using the cluster. You finish with the nodes stopped, the nodes deleted, or the whole project empty of `och-` resources, depending on how far you go.
>
> - **What you will learn.** The order OpenStack needs things deleted in, which of the three depths suits you, and why the separate ports from §5.4 make coming back cheap.
>
> - **Skip it if** you are still using the cluster. Come back whenever you stop, because the instances hold quota the whole time they exist.

---

## Introduction

### Teardown is also a test

If tearing down and rebuilding the cluster is quick, the setup is doing its job. Running instances hold quota and consume cloud capacity, so release them when you stop. As §12.7 showed, rebuilding the Kubernetes nodes later requires no changes on the OpenCHAMI head node.

### Order matters

Neutron refuses to delete any resource that is still in use, so each step clears the way for the next:

![Teardown in eight steps, in order. First the instances, then the floating IP, then the ports, then the router interfaces, then the router. Then the subnets, then the networks, and last the security groups, the keypair, the images and the volumes. Each step removes something the next one would otherwise be refused for, because Neutron will not delete a resource that is still in use. Only resources carrying the och- prefix are deleted, and the external network is never touched: we attached to it, we do not own it.](diagrams/20-teardown-order.svg)

*The order Depth C follows. Each arrow removes something the next step would otherwise be refused for.*

<details>
<summary>ASCII version</summary>

```
   instances  →  floating IP  →  ports  →  router interfaces  →  router
                                        →  subnets  →  networks
                                        →  security groups, keypair, images, volumes
```

</details>

### Delete only what you created

🛑 **Everything this tutorial created carries the `och-` prefix.** If `openstack server list` shows resources without that prefix, leave them alone—they belong to someone else in the project, even if you have permission to delete them. Likewise, never touch `${OCH_EXT_NET}`: we attached our router to it, but we don't own it.

### What you will do

- **Choose a depth** (Decide how far to go). Stop the nodes, delete the nodes, or delete everything.

- **Run that depth** (Depth A, B or C).

- **Clean up outside OpenStack** (And the things that are not in OpenStack). Two of these are credentials.

- **Prove you gave it back** (the checkpoint).

📌 The OpenStack documentation goes into more detail:

- [The OpenStack command-line client](https://docs.openstack.org/python-openstackclient/latest/), for every `delete`, `remove` and `unset` command on this page.

---

## Decide how far to go

Everything here runs on the devbox, apart from the `head$` lines. Load your environment first:

```
devbox$ cd ~/och && source och-env.sh
```

There are three useful depths:

| Depth | What it costs to come back | Do this when |
|---|---|---|
| **A. Stop the nodes** | Minutes — they boot from disk | Pausing for the day |
| **B. Delete the nodes, keep the head** | ~30 min (§§12.1–12.6) | Done with the Kubernetes layer, still working on OpenCHAMI |
| **C. Delete everything** | ~2 hours (§§5–12) | Finished, or handing quota back |

Depth B is usually the sweet spot: the head node keeps all the setup from §§7–11, while freeing the compute nodes that reinstall in minutes.

---

## Depth A — stop the nodes

Shut Kubernetes down cleanly first, then stop the instances:

```
head$   talosctl -n 172.16.0.1,172.16.0.2,172.16.0.3 shutdown
devbox$ openstack server list -c Name -c Status     # wait for SHUTOFF
```

If a node doesn't power off on its own, stop it from Nova (OpenStack's compute service):

```
devbox$ for n in ${OCH_PREFIX}-cp1 ${OCH_PREFIX}-w1 ${OCH_PREFIX}-w2; do
    openstack server stop "$n"; done
devbox$ openstack server list -c Name -c Status
```

📌 Nothing needs changing before you stop a node. Once installed, the nodes boot Talos directly from their own disks (§12), so stopping and starting them is an ordinary power cycle.

To resume:

```
devbox$ for n in ${OCH_PREFIX}-cp1 ${OCH_PREFIX}-w1 ${OCH_PREFIX}-w2; do
    openstack server start "$n"; done
head$   kubectl get nodes         # etcd recovers; give it a couple of minutes
```

⚠ **Start the control-plane node first.** Otherwise the workers will report `NotReady` until the control plane comes up.

---

## Depth B — delete the nodes, keep the head

```
devbox$ for n in ${OCH_PREFIX}-cp1 ${OCH_PREFIX}-w1 ${OCH_PREFIX}-w2; do
    openstack server delete "$n" --wait; done
```

Your MAC-pinned ports remain in place. Because §5.4 created them as standalone resources rather than inline with the instances, `server delete` detaches and releases them instead of destroying them:

```
devbox$ openstack port list --network ${OCH_PREFIX}-prov -c Name -c Status -c 'MAC Address'
```

All five node ports should still appear with status `DOWN`.

That is why we created the ports separately: each node's MAC address still maps to the same IP and xname in SMD (State Management Database) and BSS (Boot Script Service). Recreating the cluster is just a matter of running Step 9.3 and §12 again without touching the head node.

---

## Depth C — delete everything

Delete the instances first:

```
devbox$ openstack server list -c Name -f value | grep "^${OCH_PREFIX}-" \
          | xargs -r -n1 openstack server delete --wait
```

Then the floating IP:

```
devbox$ openstack server remove floating ip ${OCH_PREFIX}-head ${OCH_HEAD_FIP} 2>/dev/null || true
devbox$ openstack floating ip delete ${OCH_HEAD_FIP}
```

Then the ports:

```
devbox$ openstack port list -c Name -f value | grep "^${OCH_PREFIX}-" \
          | xargs -r -n1 openstack port delete
```

Then the router. Detach the subnet and clear the external gateway before deleting it:

```
devbox$ openstack router remove subnet ${OCH_PREFIX}-router ${OCH_PREFIX}-ext-subnet
devbox$ openstack router unset --external-gateway ${OCH_PREFIX}-router
devbox$ openstack router delete ${OCH_PREFIX}-router
```

Then the subnets and networks:

```
devbox$ openstack subnet delete ${OCH_PREFIX}-ext-subnet ${OCH_PREFIX}-prov-subnet
devbox$ openstack network delete ${OCH_PREFIX}-ext ${OCH_PREFIX}-prov
```

Then everything else we created:

```
devbox$ openstack security group delete ${OCH_PREFIX}-sg-head ${OCH_PREFIX}-sg-api 2>/dev/null || true
devbox$ openstack keypair delete ${OCH_PREFIX}-key
devbox$ openstack image list --private -c Name -f value | grep "^${OCH_PREFIX}-" \
          | xargs -r -n1 openstack image delete
devbox$ openstack volume list -c Name -f value | grep "^${OCH_PREFIX}-" \
          | xargs -r -n1 openstack volume delete
```

⚠ **We match images by prefix rather than by a fixed list of names.** Filtering by prefix catches every image you uploaded (such as `och-ipxe-disk` and any extras), whereas a hardcoded list would miss anything you added later. Because the `grep` matches your prefix, check the list before running the delete command.

---

## And the things that are not in OpenStack

These local files and credentials are easy to overlook:

```
devbox$ openstack application credential delete och-ochami-proto     # §2.5
devbox$ rm -f ~/och/*.sh ~/.ssh/och_ed25519*
devbox$ sed -i '/och\/och-env\.sh/d' ~/.bashrc                        # §3's activation line
devbox$ limactl delete openstack-devbox                             # if you're done entirely
```

The `limactl` line applies only if you run the CLI in a Lima VM; skip it otherwise.

📌 `rm ~/och/*.sh` removes all four devbox scripts (`och-env.sh`, `och-vars-env.sh`, `och-helpers-env.sh` and `och-status.sh`). Removing the `.bashrc` line as well prevents "file not found" warnings on future logins.

If you are keeping the head node but cleaning up its environment scripts, remove `~/och-head-*.sh` and the `.bashrc` line there too:

```
head$ rm -f ~/och-head-*.sh
head$ sed -i '/och-head-env\.sh/d' ~/.bashrc
```

Keep your Flux Git repository—it records everything you deployed, and you can point your next cluster straight at it. If you want Flux on a running cluster to stop reconciling, suspend it instead:

```
head$ flux suspend kustomization --all
```

---

## ✅ Checkpoint — prove you gave it back

```
devbox$ openstack server list
devbox$ openstack port list
devbox$ openstack network list
devbox$ openstack floating ip list
devbox$ openstack volume list
devbox$ openstack image list --private
devbox$ openstack security group list
```

After Depth C, none of these commands should list any `och-` resources. Anything left behind holds quota that someone else in the project can't use.

```
devbox$ openstack quota show -f value -c instances -c cores -c ram
```

Compare this output with what you recorded in [Step 3.3](03-openstack-project.md#step-33--check-your-quota). Your project usage should be back where it started.

---

## Common failures

| Symptom | Cause and fix |
|---|---|
| `Network … has ports still in use` | Delete the ports first. Check with `openstack port list --network <net>` |
| `Router … has ports still in use` | Run `router remove subnet` and `router unset --external-gateway` before deleting |
| `Port … is currently in use` | An instance still holds it. Check with `openstack port show <p> -c device_id` |
| `Subnet has allocated IPs` | A port survives somewhere. It may be a DHCP port from before §5.2's `--no-dhcp` |
| `Image is in use` | An instance built from it hasn't finished deleting. Wait, then try again |
| Volume stays `deleting` for ever | It is still attached. Run `openstack server remove volume <server> <volume>` |

---

## Coming back

| From depth | Restart at |
|---|---|
| A | `openstack server start`, control-plane node first |
| B | §9.3 (create node instances), then §12 |
| C | §5. If you expect to rebuild often, consider automating it as Infrastructure-as-Code |

Next: [§21 — Summary](21-summary.md)
