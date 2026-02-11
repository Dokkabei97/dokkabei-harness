---
title: Configure PodDisruptionBudget to Prevent Simultaneous Node Evictions
impact: LOW-MEDIUM
impactDescription: Prevents cluster downtime during node drains, upgrades, and maintenance
tags: k8s, pdb, pod-disruption-budget, availability, maintenance
---

## Configure PodDisruptionBudget to Prevent Simultaneous Node Evictions

During Kubernetes node maintenance (drain, upgrade), multiple ES pods can be evicted simultaneously, causing data unavailability. PDB ensures only one pod is disrupted at a time.

**Incorrect (no PDB — multiple pods evicted simultaneously):**

```yaml
# No PDB configured
# kubectl drain node-1 evicts all ES pods on node-1 at once
# If 2 data pods are on node-1, 2 primary shards move simultaneously
# Cluster may go RED during the drain
```

**Correct (PDB ensures controlled disruption):**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: elasticsearch-data-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      elasticsearch.k8s.elastic.co/cluster-name: production
      elasticsearch.k8s.elastic.co/node-set: data-hot

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: elasticsearch-master-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      elasticsearch.k8s.elastic.co/cluster-name: production
      elasticsearch.k8s.elastic.co/node-set: master
```

ECK automatically creates PDBs, but verify they exist:

```bash
kubectl get pdb -l elasticsearch.k8s.elastic.co/cluster-name=production
```

Reference: [Pod disruption budgets](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-pod-disruption-budget.html)
