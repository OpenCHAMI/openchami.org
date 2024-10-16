# Booting Nodes

In previous posts about booting 640 Nodes in five minutes, we've described our 640 node system and how we came to be able to use it for testing.  We've covered the OpenCHAMI software we used and how we deployed it to meet our goals as well as the standards of Los Alamos.  We've covered the CLI interactions we needed to configure OpenCHAMI to support the boot.  If you feel like you're jumping in to the middle here, it is worth going back and reading those posts first.

Like many other HPC systems, our nodes in Badger have no local disks.  The boot process for these nodes relies on a remote filesystem image that can be loaded into memory on each node with any modifications saved to an overlayfs layer on top of the system image.  OpenCHAMI itself doesn't include tooling to build, store, and serve system images.  In keeping with our core principle of modularity, LANL has a solution for these things, but other sites may choose other options.

### Cluster Node Images
OpenCHAMI doesn't provide a way to build cluster images for the nodes to boot. These images must come from something externally. There are a lot of ways to build bootable images and at LANL we have a custom Gitlab pipeline that does this for us. 

A tl;dr version: we use [Buildah](https://buildah.io/) to leverage containers to build and manage our cluster images.

A very, very simple example:

Create a blank container
```bash
CNAME=$(buildah from scratch)
```
Mount it 
```bash
MNAME=$(buildah mount $CNAME)
```
Install some base packages
```bash
dnf groupinstall --installroot=$MNAME minimal-install
dnf install --installroot=$MNAME some-other-list-of-packages
```
Install the kernel and some need dracut stuff:
```bash
dnf install --installroot=$MNAME kernel dracut-live fuse-overlayfs
```
Then rebuld the initrd so that during init it will download the image and mount the rootfs as an in memory overlay
```bash
buildah run -tty $CNAME bash -c " \
    dracut \
    --add "dmsquash-live livenet network-manager" \
    --kver $(basename /lib/modules/*) \
    -N \
    -f \
    --logfile /tmp/dracut.log 2>/dev/null \
    "
```
Then commit it
```bash
buildah commit -t test-image:v1 $CNAME
```
Then you can push it to a remote registry if desired
```bash
buildah push test-image:v1 registry.local/test-image:v1
```

### Container Registry
At LANL we have a deployed Quay instance that we requested an organization on. This let us push our cluster images, which are built outside the cluster management plane, to a place we can then pull from (and reuse images for multiple clusters). This isn't 100% needed for testing OpenCHAMI out, but if you have something similar it does make life a little easier. 

Docker has a [registry image](https://hub.docker.com/_/registry) you can use to spin up your own. You can get lost in the details but a good toy example is to run:
```bash
docker run -d -p 5000:5000 --restart always --name registry registry:2
```
It won't have any TLS setup so if you try to push anything you may need to add `--tls-verify=false` to your `buildah`/`podman` push commands

### Webserver for serving images to the cluster nodes
A simple way to project the kernel and initrd to the cluster nodes is to spin up a basic ngnix container. We've made it a point to not put any "secrets" in our system images so we are not at this moment concerned with protecting the things provided by nginx. You can also host your rootfs here if you want to boot the cluster node image into memory vs. something an NFS based rootfs. 

Using the quadlet method above it becomes a simple addition to our Ansible inventory:
```yaml
  - name: image-server
    image: docker.io/library/nginx:latest
    volumes:
      - /data/domain-images:/usr/share/nginx/html:ro
    ports:
      - 192.168.1.253:8080:80
    pre_start:
      - mkdir -p /data/domain-images
```
Once the container file is in place you can 
```bash
systemctl start image-server
```
and you now have a nginx container that will serve out cluster images stored in `/data/domain-images`.