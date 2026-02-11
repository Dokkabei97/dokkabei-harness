---
title: Configure Shard Allocation Awareness for Rack and Zone Fault Tolerance
impact: MEDIUM
impactDescription: Prevents data loss when an entire rack or availability zone fails
tags: resilience, shard-allocation, awareness, zone, rack, fault-tolerance
---

## Configure Shard Allocation Awareness for Rack and Zone Fault Tolerance

Without allocation awareness, Elasticsearch may place a primary shard and its replica on the same rack or AZ. If that rack/AZ fails, both copies are lost. Allocation awareness ensures primary and replica shards are distributed across failure domains.

**Incorrect (no awareness — primary and replica on same rack):**

```yaml
# No allocation awareness configured
# ES places shards based on disk space and shard count alone
# Primary and replica of shard 0 could both land on rack-a
# Rack-a power failure = both copies of shard 0 lost
```

**Correct (allocation awareness across zones):**

```yaml
# Each node declares its zone
# elasticsearch.yml on nodes in zone-a
node.attr.zone: zone-a

# elasticsearch.yml on nodes in zone-b
node.attr.zone: zone-b
```

```json
// Enable allocation awareness
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone"
  }
}
// ES now ensures primary and replica are in different zones
```

For forced awareness (prevents allocation when a zone is unavailable):

```json
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone",
    "cluster.routing.allocation.awareness.force.zone.values": "zone-a,zone-b"
  }
}
// If zone-b goes down, replicas that belong in zone-b stay UNASSIGNED
// rather than doubling up in zone-a (which would leave no redundancy when zone-b returns)
```

Reference: [Shard allocation awareness](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-cluster.html#shard-allocation-awareness)
