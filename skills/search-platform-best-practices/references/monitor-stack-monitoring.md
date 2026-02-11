---
title: Set Up Stack Monitoring with Metricbeat for Production Visibility
impact: LOW-MEDIUM
impactDescription: Continuous metrics collection enables trend analysis, alerting, and capacity planning
tags: monitoring, stack-monitoring, metricbeat, kibana, metrics
---

## Set Up Stack Monitoring with Metricbeat for Production Visibility

While `_cat` and `_nodes/stats` provide point-in-time snapshots, continuous monitoring with Metricbeat + Kibana (or equivalent) enables trend analysis, alerting, and capacity planning.

**Correct (Metricbeat-based monitoring):**

```yaml
# metricbeat.yml on each Elasticsearch node
metricbeat.modules:
- module: elasticsearch
  metricsets:
    - node
    - node_stats
    - cluster_stats
    - index
    - index_summary
    - shard
    - ml_job
  period: 10s
  hosts: ["https://localhost:9200"]
  username: "monitoring_user"
  password: "${ES_MONITOR_PWD}"
  ssl.certificate_authorities: ["/path/to/ca.crt"]
  xpack.enabled: true

output.elasticsearch:
  hosts: ["https://monitoring-cluster:9200"]
  username: "beats_writer"
  password: "${BEATS_PWD}"
```

```json
// Alternative: internal collection (simpler but loads production cluster)
PUT /_cluster/settings
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true,
    "xpack.monitoring.collection.interval": "10s"
  }
}
// Prefer Metricbeat for production — ships metrics to a separate monitoring cluster
```

Key dashboards to monitor in Kibana Stack Monitoring:
- **Overview**: Cluster health, node count, shard count
- **Nodes**: Heap usage, CPU, disk per node
- **Indices**: Document count, index rate, search rate
- **JVM**: GC frequency, heap usage trends
- **Thread pools**: Queue sizes, rejection rates

Reference: [Monitor a cluster](https://www.elastic.co/guide/en/elasticsearch/reference/current/monitor-elasticsearch-cluster.html)
