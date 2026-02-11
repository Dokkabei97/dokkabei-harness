---
title: Use Searchable Snapshots for Cost-Effective Cold and Frozen Tier Storage
impact: MEDIUM
impactDescription: 90% storage cost reduction for cold data while maintaining search capability
tags: lifecycle, searchable-snapshot, frozen, cold, object-storage, cost
---

## Use Searchable Snapshots for Cost-Effective Cold and Frozen Tier Storage

Searchable snapshots store index data in object storage (S3, GCS, Azure Blob) instead of local disk, with optional local caching. Data remains searchable at higher latency but dramatically lower cost.

**Incorrect (keeping old data on local SSDs):**

```json
// 2 years of logs on NVMe SSDs
// 10TB × $200/TB/month = $2,000/month for rarely-searched data
```

**Correct (searchable snapshots for cold/frozen data):**

```json
// Step 1: Register snapshot repository
PUT /_snapshot/s3_repo
{
  "type": "s3",
  "settings": {
    "bucket": "es-searchable-snapshots",
    "region": "ap-northeast-2"
  }
}

// Step 2: Mount as searchable snapshot (full copy — cold tier)
POST /_snapshot/s3_repo/snapshot_2024_q1/_mount?storage=full_copy
{
  "index": "logs-2024-q1",
  "renamed_index": "logs-2024-q1-cold"
}
// Full copy: cached locally, faster search, uses local disk

// Step 3: Or mount as partially cached (frozen tier — minimal local storage)
POST /_snapshot/s3_repo/snapshot_2024_q1/_mount?storage=shared_cache
{
  "index": "logs-2024-q1",
  "renamed_index": "logs-2024-q1-frozen"
}
// Shared cache: only fetches needed data from object store on demand
// Minimal local disk usage — most cost-effective
```

Cost comparison for 10TB of data:

| Storage Method | Monthly Cost | Search Latency |
|---------------|-------------|----------------|
| NVMe SSD (hot) | ~$2,000 | <100ms |
| Searchable snapshot (full_copy) | ~$300 | 200-500ms |
| Searchable snapshot (shared_cache) | ~$30 | 2-10s |
| S3 only (not searchable) | ~$23 | N/A |

Include in ILM for automatic transition:

```json
"frozen": {
  "min_age": "90d",
  "actions": {
    "searchable_snapshot": {
      "snapshot_repository": "s3_repo"
    }
  }
}
```

Reference: [Searchable snapshots](https://www.elastic.co/guide/en/elasticsearch/reference/current/searchable-snapshots.html)
