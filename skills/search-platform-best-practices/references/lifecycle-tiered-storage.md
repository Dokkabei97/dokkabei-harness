---
title: Implement Hot-Warm-Cold-Frozen-Delete Data Tier Strategy
impact: MEDIUM
impactDescription: 50-80% storage cost reduction through automatic data tiering
tags: lifecycle, tiered-storage, hot, warm, cold, frozen, cost
---

## Implement Hot-Warm-Cold-Frozen-Delete Data Tier Strategy

Different data ages have different access patterns. Aligning storage tier with access frequency minimizes cost while maintaining search capability on all data.

**Tier design:**

```
Hot (0-7d)    → NVMe SSD, high CPU     → Active writes + real-time search
Warm (7-30d)  → SATA SSD, moderate CPU → Read-only, occasional search
Cold (30-90d) → HDD, low CPU           → Rare search, reduced replicas
Frozen (90d+) → S3/GCS object store    → Searchable snapshots, minimal local storage
Delete (365d) → Purged                 → Compliance retention met
```

```json
// Configure data nodes with tier preferences
// In elasticsearch.yml:
// Hot nodes:  node.roles: [data_hot, data_content]
// Warm nodes: node.roles: [data_warm]
// Cold nodes: node.roles: [data_cold]
// Frozen:     node.roles: [data_frozen]

// Index template automatically routes to hot tier
PUT /_index_template/logs
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "index.routing.allocation.include._tier_preference": "data_hot",
      "index.lifecycle.name": "application-logs"
    }
  }
}

// ILM handles tier transitions automatically (see lifecycle-ilm-policy.md)
```

Cost comparison (approximate):

| Tier | Storage Cost | Search Latency | Storage Type |
|------|-------------|----------------|-------------|
| Hot | $$$$ | <100ms | NVMe SSD |
| Warm | $$$ | 100-500ms | SATA SSD |
| Cold | $$ | 500ms-2s | HDD |
| Frozen | $ | 2-10s | Object Store |

Reference: [Data tiers](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-tiers.html)
