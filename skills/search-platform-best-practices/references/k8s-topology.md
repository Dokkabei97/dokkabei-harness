---
title: Use Node Affinity and Topology Spread for Fault-Tolerant Pod Placement
impact: LOW-MEDIUM
impactDescription: Prevents all ES pods from landing on the same node/zone, ensuring AZ fault tolerance
tags: k8s, topology, affinity, spread, fault-tolerance, scheduling
---

## Use Node Affinity and Topology Spread for Fault-Tolerant Pod Placement

Without topology constraints, Kubernetes may schedule all ES data pods on the same physical node or availability zone. If that node/zone fails, all data is inaccessible.

**Correct (topology spread across AZs):**

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
spec:
  nodeSets:
  - name: data
    count: 6
    podTemplate:
      spec:
        topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              elasticsearch.k8s.elastic.co/cluster-name: production
              elasticsearch.k8s.elastic.co/node-set: data
        affinity:
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector:
                  matchLabels:
                    elasticsearch.k8s.elastic.co/cluster-name: production
```

This ensures:
- Pods spread evenly across AZs (`topologySpreadConstraints`)
- Pods prefer different physical hosts (`podAntiAffinity`)
- Combine with ES shard allocation awareness for complete AZ protection

Set ES allocation awareness to match K8s topology:

```yaml
config:
  node.attr.zone: "${ZONE}"
  cluster.routing.allocation.awareness.attributes: zone
```

Reference: [Advanced scheduling](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-advanced-node-scheduling.html)
