---
title: Configure Persistent Volume Claims with Appropriate Storage Classes
impact: LOW-MEDIUM
impactDescription: Ensures data persistence across pod restarts and correct disk performance per tier
tags: k8s, storage, pvc, persistent-volume, storage-class
---

## Configure Persistent Volume Claims with Appropriate Storage Classes

Elasticsearch data must survive pod restarts. Without proper PVC configuration, data is lost on pod eviction. Storage class selection determines disk performance (SSD vs HDD).

**Incorrect (emptyDir — data lost on pod restart):**

```yaml
# emptyDir is ephemeral — data deleted when pod dies
podTemplate:
  spec:
    volumes:
    - name: data
      emptyDir: {}
```

**Correct (PVC with storage class per tier):**

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
spec:
  nodeSets:
  - name: data-hot
    count: 3
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 500Gi
        storageClassName: gp3-ssd    # Fast SSD for hot tier
  - name: data-warm
    count: 3
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 2Ti
        storageClassName: st1-hdd    # Cheaper storage for warm tier
```

Storage class recommendations:

| Cloud | Hot Tier | Warm/Cold Tier |
|-------|---------|---------------|
| AWS | gp3 / io2 | st1 / sc1 |
| GCP | pd-ssd | pd-standard |
| Azure | Premium SSD | Standard HDD |

Important: Set `allowVolumeExpansion: true` in the StorageClass to allow online volume resizing.

Reference: [Volume claim templates](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html)
