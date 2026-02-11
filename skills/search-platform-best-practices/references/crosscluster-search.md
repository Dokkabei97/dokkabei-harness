---
title: Configure Cross-Cluster Search for Multi-Region Federated Queries
impact: MEDIUM
impactDescription: Search across geographically distributed clusters without data replication overhead
tags: crosscluster, ccs, search, multi-region, federation
---

## Configure Cross-Cluster Search for Multi-Region Federated Queries

Cross-cluster search (CCS) allows a single query to search indices across multiple clusters. This enables multi-region architectures where data stays local to each region but can be queried globally.

**Incorrect (replicating all data to a central cluster):**

```json
// Copying all regional data to a central cluster
// 3 regions × 500GB each = 1.5TB replicated centrally
// 2x total storage cost, replication lag, consistency issues
```

**Correct (cross-cluster search — query in place):**

```json
// Step 1: Configure remote clusters on the searching cluster
PUT /_cluster/settings
{
  "persistent": {
    "cluster.remote.cluster_kr": {
      "seeds": ["kr-node1:9300", "kr-node2:9300"],
      "transport.compress": true,
      "skip_unavailable": true
    },
    "cluster.remote.cluster_jp": {
      "seeds": ["jp-node1:9300", "jp-node2:9300"],
      "transport.compress": true,
      "skip_unavailable": true
    }
  }
}

// Step 2: Search across all clusters
GET /local-logs:logs-*,cluster_kr:logs-*,cluster_jp:logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ],
      "must": [
        { "match": { "level": "ERROR" } }
      ]
    }
  }
}
// Searches local cluster + Korea cluster + Japan cluster in one query
// skip_unavailable: true — if one cluster is down, others still return results

// Verify remote cluster connectivity
GET /_remote/info
```

Performance considerations:
- Network latency adds to query time (cross-region = 50-200ms overhead)
- Use `ccs_minimize_roundtrips: true` (default in 7.x+) to reduce network calls
- Filter aggressively to reduce data transferred between clusters
- Consider `skip_unavailable: true` for resilience

Reference: [Cross-cluster search](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-cross-cluster-search.html)
