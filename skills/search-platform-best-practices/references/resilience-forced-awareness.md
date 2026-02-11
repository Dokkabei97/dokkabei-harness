---
title: Use Forced Awareness to Handle Availability Zone Failures Correctly
impact: MEDIUM
impactDescription: Prevents replica over-allocation during AZ outage, maintains redundancy when AZ recovers
tags: resilience, forced-awareness, availability-zone, fault-tolerance, recovery
---

## Use Forced Awareness to Handle Availability Zone Failures Correctly

Without forced awareness, when an AZ goes down, Elasticsearch promotes unassigned replicas and creates new copies on surviving nodes. This fills up surviving nodes and leaves no redundancy for a second failure. Forced awareness keeps replicas unassigned during AZ outage, preserving cluster stability.

**Incorrect (standard awareness — over-allocation on AZ failure):**

```json
// Standard awareness without "force"
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone"
  }
}
// zone-b goes down: ES tries to allocate zone-b's replicas to zone-a
// zone-a nodes get double the shards → disk and memory pressure
// If zone-a also struggles, cascading failure
```

**Correct (forced awareness preserves stability):**

```json
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone",
    "cluster.routing.allocation.awareness.force.zone.values": "zone-a,zone-b,zone-c"
  }
}
// zone-b goes down: replicas for zone-b stay UNASSIGNED (yellow health)
// zone-a and zone-c continue serving with their existing shards
// When zone-b recovers, shards are allocated back — clean recovery

// Monitor unassigned shards during outage
GET /_cat/shards?v&h=index,shard,prirep,state,node&s=state
// UNASSIGNED shards are expected during AZ outage with forced awareness
```

Reference: [Forced awareness](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-cluster.html#forced-awareness)
