---
title: Configure ECK Operator Resource Requests and Limits Correctly
impact: LOW-MEDIUM
impactDescription: Prevents OOM kills, CPU throttling, and scheduling failures in Kubernetes
tags: k8s, eck, resources, requests, limits, kubernetes
---

## Configure ECK Operator Resource Requests and Limits Correctly

Without proper resource requests and limits, Kubernetes may schedule ES pods on under-resourced nodes, allow OOM kills, or throttle CPU during critical operations.

**Incorrect (no resource specifications):**

```yaml
# No resources defined — Kubernetes makes unpredictable scheduling decisions
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: production
spec:
  nodeSets:
  - name: data
    count: 3
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          # No resources block — QoS class: BestEffort
          # Pods can be evicted at any time under memory pressure
```

**Correct (explicit resource requests and limits):**

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: production
spec:
  version: 8.12.0
  nodeSets:
  - name: data-hot
    count: 3
    config:
      node.roles: ["data_hot", "data_content"]
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 64Gi
              cpu: "8"
            limits:
              memory: 64Gi
              # No CPU limit — avoid throttling during merges/GC
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms31g -Xmx31g"
  - name: master
    count: 3
    config:
      node.roles: ["master"]
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 8Gi
              cpu: "2"
            limits:
              memory: 8Gi
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms4g -Xmx4g"
```

Key rules:
- **Memory requests = limits** (prevents OOM kills, guarantees QoS class Guaranteed)
- **No CPU limits** (avoids throttling during GC, merges)
- **Heap = 50% of memory limit** (leaves room for filesystem cache and JVM overhead)

Reference: [Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-managing-compute-resources.html)
