---
title: Configure Rolling Upgrade Strategy for Zero-Downtime ES Updates
impact: LOW-MEDIUM
impactDescription: Safely upgrades Elasticsearch version or configuration without service interruption
tags: k8s, rolling-upgrade, eck, zero-downtime, upgrade
---

## Configure Rolling Upgrade Strategy for Zero-Downtime ES Updates

ECK handles rolling upgrades automatically, but proper configuration ensures zero downtime and data safety during the process.

**Correct (ECK rolling upgrade configuration):**

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
spec:
  version: 8.13.0    # Change version to trigger rolling upgrade
  updateStrategy:
    changeBudget:
      maxSurge: 1       # Allow 1 extra pod during upgrade
      maxUnavailable: 1  # Allow 1 pod to be down during upgrade
  nodeSets:
  - name: master
    count: 3
  - name: data
    count: 5
```

ECK rolling upgrade process:
1. Disables shard allocation on the node being upgraded
2. Performs synced flush
3. Stops the ES pod
4. Starts new pod with updated version/config
5. Waits for the node to join the cluster
6. Re-enables shard allocation
7. Waits for green health
8. Repeats for next node

Monitor upgrade progress:

```bash
# Watch pod updates
kubectl get pods -l elasticsearch.k8s.elastic.co/cluster-name=production -w

# Check ECK operator logs
kubectl logs -n elastic-system statefulset.apps/elastic-operator -f

# Monitor cluster health during upgrade
kubectl exec -it production-es-data-0 -- curl -s localhost:9200/_cluster/health?pretty
```

Pre-upgrade checklist:
- Verify snapshot is recent and restorable
- Check `_cat/health` is green
- Check `_cat/recovery` has no active recoveries
- Read the [ES upgrade guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/setup-upgrade.html) for version-specific notes

Reference: [Upgrade ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-upgrading-eck.html)
