Finding a development environment for HPC tooling is generally a challenge.  Every cycle we use for development is lost to  science users.  When developers like the team at OpenCHAMI can find dedicated systems, they are generally only a few nodes and often not in production-like environments.

One of the benefits of embedding the development team of OpenCHAMI in the day to day work of the sysadmins that support the systems at LANL is that we sit with the people who are responsible for decomissioning hardware that has gone past its useful life.  When we heard that a 660 Node cluster was soon to be rolled off the floor, we immediatly jumped at the opportunity to test with it.

Badger is an older machine built by Penguin Computing circa 2016.  At the time, it is made up of Relion OCP1930e nodes with three servers per shelf, each one with a pair of Xeon processors in a 1U form factor.  It's a fairly dense configuration with 96 nodes per rack.  At 660 nodes, we're just shy of seven racks.  To string all these CPUs together, Penguin included a 100G OmniPath High Speed Network.  When we originally opened Badger up to science, we described it as a 798 Terraflop machine.  For close to a decade, it was a workhorse for our scientists.

It's important to put that in context.  Today's top HPC systems are being tested at over an Exaflop, a thousand, thousand Terraflops.  The bottom system on the Top500 list from early 2024 is over twice the speed of Badger.  Low-latency interconnects exceed eight times the speed of OmniPath.  And, with the improvements in chip design, we can run the same amount of computing with dramatically lower energy consumption.

Dealing with dated hardware brought with it a set of challenges to our planned development process.  OpenCHAMI typically relies on the ability to probe the BMCs of all nodes through Redfish.  It uses that data to build an inventory without access to the running operating system of the node.  Since the BMCs for Badger's nodes don't support Redfish, that wasn't possible.  OpenCHAMI also has features that allow admins to cryptographically assert and verify the state of nodes before and after jobs.  Without the required TPMs, that wasn't part of our testing either.

To replace the missing Redfish inventory, we built a manual inventory of nodes including all the mac addresses of all the interface cards.  We opted not to attempt any cryptographic verification on Badger.

Read on for part 2 of our series on booting 640 nodes in five minutes.



