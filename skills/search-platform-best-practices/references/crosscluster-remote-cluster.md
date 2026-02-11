---
title: Choose Between Seed Node and Proxy Mode for Remote Cluster Connection
impact: MEDIUM
impactDescription: Correct connection mode determines network architecture feasibility and security posture
tags: crosscluster, remote-cluster, seed-node, proxy, network, connection
---

## Choose Between Seed Node and Proxy Mode for Remote Cluster Connection

Remote cluster connections support two modes: seed node (default, direct connections to all nodes) and proxy (single entry point). The choice depends on network topology and security requirements.

**Seed node mode (default — direct connections):**

```json
PUT /_cluster/settings
{
  "persistent": {
    "cluster.remote.production": {
      "mode": "sniff",
      "seeds": ["node1:9300", "node2:9300", "node3:9300"],
      "transport.compress": true
    }
  }
}
// Connecting cluster discovers all nodes via seed nodes
// Opens direct transport connections to every data node
// Best performance: queries go directly to data nodes
// Requires: all data nodes must be network-reachable from connecting cluster
```

**Proxy mode (single entry point):**

```json
PUT /_cluster/settings
{
  "persistent": {
    "cluster.remote.production": {
      "mode": "proxy",
      "proxy_address": "es-proxy.example.com:9443",
      "num_proxy_sockets_per_connection": 18,
      "transport.compress": true
    }
  }
}
// All traffic flows through a single proxy address
// Only one network endpoint needs to be exposed
// Works behind load balancers, firewalls, and service meshes
// Slightly higher latency due to extra hop
```

Comparison:

| Aspect | Seed (sniff) Mode | Proxy Mode |
|--------|------------------|------------|
| Network requirement | All nodes reachable | Only proxy endpoint reachable |
| Performance | Best (direct) | Slight overhead (proxy hop) |
| Security | More ports to expose | Single endpoint |
| Kubernetes/Cloud | Complex (dynamic node IPs) | Natural fit |
| Load balancing | Built-in (direct to nodes) | Depends on proxy |

Recommendation:
- **Same datacenter/VPC**: Seed mode for performance
- **Cross-VPC/cross-cloud**: Proxy mode for simplicity
- **Kubernetes**: Proxy mode with a Service endpoint

Reference: [Remote clusters](https://www.elastic.co/guide/en/elasticsearch/reference/current/remote-clusters.html)
