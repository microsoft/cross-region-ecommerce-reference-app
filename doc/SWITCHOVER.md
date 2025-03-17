# Switchover Procedure

The switchover procedure involves the following steps:

* Start the Secondary AKS Cluster: required only if the secondary cluster is stopped, in passive state.

* Sync and Elevate Databases and Caches: The SQL Database and Redis Cache are synchronized with their replicas in the secondary region. Then, the secondary instances are elevated to the primary role.

* Reconfigure Traffic: The Azure Front Door profile is reconfigured to route traffic to the services in the secondary region.

If any service is already migrated to the secondary region when starting the switchover, they will suffer no modifications. After a successful switchover, the app will serve the traffic and handle the data in the failover region.


# Usage

The switchover script requires three parameters:

* The resource group name containing the services to switchover
* The region from which to switchover
* The region to which to switchover

Start the procedure using:

`./2-switchover.sh -rg=rg-name --from=primary-region --to=secondary-region`
