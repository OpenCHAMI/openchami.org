+++
title = 'Code Deep Dive: Dynamic Data Persistence for our Control Plane'
date = 2024-07-01T09:27:54-04:00
draft = false
categories = ['Development', 'LANL']
description = "In-depth exploration of the 'In-Memory Working Set with Periodic Snapshots' pattern used in the node-orchestrator project, highlighting its application in HPC system management and the benefits for sysadmins."
include_toc = true
contributors = ["Alex Lovell-Troy"]
summary = "This blog post dives into the 'In-Memory Working Set with Periodic Snapshots' pattern implemented in the node-orchestrator project. Learn how this approach leverages DuckDB and Parquet to efficiently manage control plane data, offering speed and reliability. Discover the advantages for HPC sysadmins, including reduced management overhead and simplified recovery, as well as comparisons to other data storage methods."
slug = "databases-as-antipattern"
lastmod = 2025-11-06T00:00:00+00:00
canonical = "/blog/databases-as-antipattern/"
tags = ["DuckDB", "Parquet", "Snapshots", "Control-plane"]
+++

Welcome to our first code deep dive! Today, we'll explore a development pattern used in our experimental node-orchestrator project. Rather than storing dynamic data in a traditional SQL database, we use DuckDB to maintain a working set in memory and periodically save snapshots in the Parquet file format common to Data Analytics. This approach helps us manage control plane data efficiently and safely.

This pattern is common in situations where the data changes relatively infrequently, but having a rich query engine is still valuable. In HPC system management, the number of nodes in a cluster is unlikely to change for months. The state of these nodes may change from day to day or even hour to hour as they are reconfigured for specific workloads. Both hardware and firmware upgrades can be daily activities as well, but even this rate of change is relatively low for modern data management. Still, as sysadmins label nodes or workload managers allocate them to jobs, there is a steady stream of changes to the metadata of the nodes that we need to track and then query against.

#### The General Pattern - Working Set plus Snapshots

The "Working Set plus Snapshots" pattern is designed to balance the speed of RAM with the durability of persistent storage. Here's how it works: the system keeps the active dataset in memory for rapid access and processing. At regular intervals, the current state of this dataset is "snapshotted" and saved to a more durable storage medium, such as a hard drive. This ensures that, even if the system crashes or experiences a power loss, there is a recent backup of the data that can be restored. This pattern is particularly useful in scenarios where data changes infrequently but needs to be accessed quickly and reliably.

A good analogy for this pattern is found in the gaming industry. Many video games keep the game state data in memory for fast access, allowing for smooth gameplay. Periodically, the game saves this state to disk, creating save points. If something goes wrong—like a crash—the player can resume from the last save point. This combination of fast in-memory access with regular, persistent backups ensures both performance and reliability.

#### Why Use Periodic Snapshots?

While storing data in RAM is fast, it also poses risks. If the computer crashes or restarts, all the data in RAM could be lost. This is where periodic snapshots come into play. A snapshot captures the state of the data at a particular moment in time and saves it to the hard drive. By regularly taking snapshots, we ensure that we have recent backups of our data. If something goes wrong, we can restore the last snapshot and continue from there, minimizing data loss.

#### Why DuckDB and Parquet?

In our node-orchestrator project, we use DuckDB and Parquet to implement this pattern.

- **DuckDB**: DuckDB is a small, fast database that works well with in-memory data. Unlike SQLite or pure in-memory storage, DuckDB can persist data to disk and natively handle Parquet files. This dual capability allows us to benefit from fast in-memory operations while still maintaining durability with disk storage. DuckDB’s integration with Parquet also means we can avoid writing complex code to manage data persistence, reducing the potential for bugs. [Learn more about DuckDB](https://duckdb.org/).

- **Parquet**: Parquet is a columnar storage file format optimized for large-scale data processing. One of its key advantages is that it allows querying of data directly from the files without needing to load everything into memory. This capability is particularly useful for HPC sysadmins who need to perform advanced queries across all available snapshots. For instance, when sysadmins move components around within a system, they can query historical data across snapshots to track the movement of these components without having to design the database specifically for this purpose. [Learn more about Parquet](https://parquet.apache.org/).

#### Benefits for HPC Sysadmins

For sysadmins managing HPC systems, this pattern offers several advantages:

By using an in-memory working set with periodic snapshots, there are fewer components to manage compared to traditional databases. As long as there is an available snapshot, the system can recover from any failure. While some history may be lost if the snapshot is out of date, even an out-of-date snapshot provides enough information to compare the current state of all components with the state from the snapshot.

Recovery is straightforward as long as snapshots are available. This reduces the complexity and time needed to bring systems back online after failures.

Traditional databases like MySQL or Postgres require ongoing maintenance, such as managing database connections, optimizing queries, and ensuring data integrity. This pattern, however, minimizes these concerns by leveraging the simplicity of DuckDB and Parquet.

#### Comparison to Other Storage Methods

There are other approaches to managing data like this. Especially in HPC administration, storing all data in flat files is common. At the scale of a few dozen nodes, this isn't terribly unwieldy. Rewriting a full yaml file that describes all the nodes in full for each update is a little wasteful, but not unreasonably so at ~1000 lines. As the updates increase in frequency and the data itself increases in complexity, more code is needed to ensure consistency of the flat files and support advanced querying. At some point, the code to manage the flat file starts to resemble a simple database engine. Reading and writing large files take time, and searching through them is inefficient. Another common approach is to use a traditional database like MySQL or Postgres. Both include database engines that are well optimized for blistering speed and concurrency. Our use case doesn't benefit from the efficiency of these engines. In addition, there are additional operational concerns for managing another service. We assert that the additional operational complexity, however small is not worth the efficiency gain.

By combining in-memory storage with periodic snapshots, we leverage the speed of RAM and the safety of persistent storage, achieving a balanced approach that meets the needs of HPC system management.

#### Operational Concerns and Failure Modes

Using this pattern, we must consider operational concerns and potential failure modes. One primary concern is memory usage. Keeping large datasets in RAM can be expensive, so we need to balance the size of the working set with the available memory. Another concern is determining the right frequency for snapshots. Taking snapshots too often can slow down the system, while too infrequent snapshots risk losing more data if there is a failure.

Failure modes include RAM failures, where data in memory is lost if the system crashes or loses power. While snapshots mitigate this, some data between snapshots will always be at risk. Another potential issue is snapshot corruption, which can cause problems when restoring data. Regular integrity checks and backups of snapshots can help address this issue.

#### Conclusion

The "In-Memory Working Set with Periodic Snapshots" pattern offers a powerful approach for managing data in HPC systems. By leveraging the speed of in-memory data access and the safety of periodic snapshots, we can ensure our data is both fast to access and protected. Tools like DuckDB and Parquet make this pattern efficient and reliable, reducing the amount of code we need to write and maintain.

{{< blog-cta >}}