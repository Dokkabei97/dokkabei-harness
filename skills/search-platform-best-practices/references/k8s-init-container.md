---
title: Set vm.max_map_count via Init Container for Elasticsearch on Kubernetes
impact: LOW-MEDIUM
impactDescription: Prevents Elasticsearch startup failure due to insufficient mmap count
tags: k8s, init-container, vm-max-map-count, sysctl, startup
---

## Set vm.max_map_count via Init Container for Elasticsearch on Kubernetes

Elasticsearch requires `vm.max_map_count` to be at least 262144. The default on most Linux hosts is 65530. Without setting this, ES fails to start with a bootstrap check error.

**Incorrect (ES fails to start):**

```
bootstrap check failure: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

**Correct (init container sets the sysctl):**

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
spec:
  nodeSets:
  - name: data
    count: 3
    podTemplate:
      spec:
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
```

Alternative (node-level DaemonSet — preferred for large clusters):

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: sysctl-setter
spec:
  selector:
    matchLabels:
      app: sysctl-setter
  template:
    spec:
      hostPID: true
      initContainers:
      - name: sysctl
        image: busybox
        securityContext:
          privileged: true
        command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
      containers:
      - name: pause
        image: gcr.io/google_containers/pause
```

On managed Kubernetes (EKS, GKE, AKS), some providers allow setting this via node configuration without privileged containers.

Reference: [Virtual memory](https://www.elastic.co/guide/en/elasticsearch/reference/current/vm-max-map-count.html)
