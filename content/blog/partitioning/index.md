+++
title = 'Exploring Multi-tenacy capabilities in SMD with Groups and Partitions'
date = 2024-01-18T09:27:54-04:00
draft = false
categories = ['Development', 'LANL']
summary = "SMD comes with a built-in partitioning feature that should allow us to partition off certain components through it's API.  In this blog post, we explore how groups and partitions work in practice."
include_toc = true
contributors = ["David J. Allen (LANL)"]
+++


## Background

For the Supercomputing Institute 2024 at LANL, we would like to use Ochami to replace Warewulf for system management. To do so, we would need to introduce a multi-tenant feature into the [SMD microservice](). The idea is to run a single instance of SMD managing multiple clusters at once, but each cluster is only accessible after authentication.

## Using the Partition API

SMD comes with a built-in partitioning feature that should allow us to partition off certain components through it's API. For example, we can view all of the partitions currently in our SMD instance using a `curl` command (assuming you have a local instance of SMD running on port 27779). You can check if SMD is reachable then list all of the existing partitions with the following:

```bash
curl -X GET http://localhost:27779/hsm/v2/service/ready -k
curl -X GET http://localhost:27779/hsm/v2/partitions -k
```

Similiarly, if we already have components loaded, we can query the Redfish endpoints and create a new partition using its `xname` and a POST request.

```bash
curl -X GET http://localhost:27779/hsm/v2/Inventory/RedfishEndpoints -k
curl -X POST http://localhost:27779/hsm/v2/partitions -k -d '{"name": "p1", "description": "this is a partition test",  "tags": ["tag1"], "members": {"ids": ["x0c0s1b0"]}}'
```

Note that the partition name must follow the convention of `p#` or `p#.#` for the partition name and each component can only be added to a single partition. If you try to add a component that's already a part of another partition you will get an error.

```bash
curl -X POST http://localhost:27779/hsm/v2/partitions -k -d '{"name": "p2", "description": "this is a partition test",  "tags": ["tag1"], "members": {"ids": ["x0c0s1b0", "x0c0s3b0"]}}'
{"type":"about:blank","title":"Conflict","detail":"operation would conflict with an existing member in another partition.","status":409}
```

This is a feature of course and not a bug. We will also see how this same xname can be added to a group in the next section as well. 

## Using  the Groups API

The groups API works in a similar manner to the partitions API. Like before, if we want to check for currently available within our SMD instance, we can make the following request:

```bash
curl -X GET http://localhost:27779/hsm/v2/groups
```

Creating new groups is just as easy:

```bash
curl -X POST http://localhost:27779/hsm/v2/groups -d '{"label": "test"}'
```

However, unlike partitions, groups do not have a stringent requirement for using xnames and xnames can be included in multiple groups. Confirm that the group was created:

```bash
curl -X GET http://localhost:27779/hsm/v2/groups/test
```

At this point, there are no members (as xnames) in the new group. Let's try adding the xname that we added in the partition before. This done via the membership API as well, but with groups instead of partitions. However, the endpoint is slightly different for adding groups.

```
curl -X POST http://localhost:27779/hsm/v2/groups/test/members -d '{"ids": "x00s1b0"}' 
```

Now for a quick test. Let's try adding another group, and then add the same xname as above to it.

```
curl -X POST http://localhost:27779/hsm/v2/groups -d '{"label": "test2"}'
curl -X POST http://localhost:27779/hsm/v2/groups/test/members -d '{"id": "x0c0s1b0"}'
```

Both commands should have worked with producing an error and the xname should be in both groups. If we make a group exclusive, then the group would behave more like a partition in that it prevents new groups from adding xnames to it that are contained in the exclusive group. This behavior does not affect making new exclusive groups though.

### How Groups Differ from Partitions

Although groups and partitions may seem very similiar on the surface, their use-cases are fundamentally different. For example, we saw before that we can add one xname to two groups, but not two partitions. 

Looking at both the `Group` and `Partition` data structure, we can see the similiarities by just observing the fields below. The only difference between the structs is the `ExclusiveGroup` field in the `Group` struct, but not the `Partition` struct.

```go
type Group struct {
	Label          string   `json:"label"`
	Description    string   `json:"description"`
	ExclusiveGroup string   `json:"exclusiveGroup,omitempty"`
	Tags           []string `json:"tags,omitempty"`
	Members        Members  `json:"members"` // List of xnames, required.
    ...
}
...
type Partition struct {
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Members     Members  `json:"members"` // List of xname ids, required.
    ...
}
```

That's because groups are intended to be an abstaction for general purposes whereas partitions are meant to be used specifically for separating hardware components. Therefore, partitions have certains hard, intentional constraints that groups do not have.

## How Memberships Work with Partitions

Memberships provide a way to do a reverse lookup to find partitions using xnames. They are automatically created whenever a new partition is created using the partition API. Each membership object contains an ID, list of groups, and a partition name.

```go
type Membership struct {
    ID            string   `json:"id"`
    GroupLabels   []string `json:"groupLabels"`
    PartitionName string   `json:"partitionName"`
}
```

We can view all memberships or memberships in a SMD instance with the following:

```bash
curl -X GET http://localhost:27779/hsm/v2/memberships -k
```

Note that new memberships are automatically created whenever a new partition is created for each xname. After creating a partition, we can add any additional memberships using the membership API:

```bash
curl -X POST http://localhost:27779/hsm/v2/partitions/p1/member -d '{"partition_name": "p1"}' -k
```

However, be aware that this API endpoint is not really well documented if you're looking in `docs/examples.adoc` for more information so there may be some missing details here as well. Now, if we want to see all of the members of a specific partition, like the partition of the component we just added, we can query the `p1` partition:

```bash
curl -X GET http://localhost:27779/hsm/v2/partitions/p1/member -k # partition created earlier
```

That covers the relevant aspects of memberships and how to use them with SMD for our needs.

## Repurposing Memberships for Multi-tenacy

Unfortunately, the membership ID MUST be an xname when creating a new instance and they are created automatically. If we want to be able to look up a specific partition for all components belonging to a user (or whatever), then we would want the ID to be any arbitrary string value (like a user name - `david` - or a partition ID like - `2b2a5899-4e9a-44af-ba3c-4159c033c352`). This can be done by removing (or commenting out) a couple lines of code in the `doPartitionMembersPost` in `cmd/smd-api.go` (starting at ilne 4805 with commit `c95ce488afd9b3b230a1812a752c3c4dd6410039`.

```go
normID := base.NormalizeHMSCompID(memberIn.ID)
if !base.IsHMSCompIDValid(normID) {
    s.lg.Printf("doPartitionMembersPost(): Invalid xname ID.")
    sendJsonError(w, http.StatusBadRequest, "invalid xname ID")
    return
}
```

This will allow the membership ID to be set to any value without checking for an xname. The `normID` should also just be set to the `memberIn.ID` value. Now rebuild the binaries and test adding a new membership.

```bash
make binaries

# set the env vars
export SMD_DBHOST=postgres-smd
export SMD_DBPORT=5432
export SMD_DBUSER=hmsdsuser
export SMD_DBPASS=hmsdsuser
export SMD_DBNAME=hmsds
export SMD_DBOPTS=sslmode=disable
export POSTGRES_PASSWORD=hmsdsuser
export POSTGRES_USER=hmsdsuser
export POSTGRES_DB=hmsds

smd_root=path/to/smd
${smd_root}/smd
```

Or using docker:

```bash
docker build --tag smd:testing ${smd_root}/smd
```
