---
title: Automate Snapshot/Restore with SLM for Disaster Recovery
impact: MEDIUM
impactDescription: Ensures point-in-time recovery capability with automated, policy-driven backups
tags: resilience, snapshot, restore, slm, backup, disaster-recovery
---

## Automate Snapshot/Restore with SLM for Disaster Recovery

Without automated snapshots, cluster failure or accidental deletion results in permanent data loss. Snapshot Lifecycle Management (SLM) automates backup scheduling, retention, and cleanup.

**Incorrect (manual, ad-hoc snapshots):**

```json
// Manually triggered — often forgotten, inconsistent schedule
PUT /_snapshot/my_backup/snapshot_20240115
{ "indices": "products,orders" }
// No retention policy — old snapshots fill up storage
// No verification — snapshot might be corrupted
```

**Correct (SLM automated policy):**

```json
// Step 1: Register snapshot repository
PUT /_snapshot/s3_backup
{
  "type": "s3",
  "settings": {
    "bucket": "elasticsearch-backups",
    "region": "ap-northeast-2",
    "base_path": "production"
  }
}

// Step 2: Create SLM policy
PUT /_slm/policy/nightly-backup
{
  "schedule": "0 30 1 * * ?",
  "name": "<nightly-snap-{now/d}>",
  "repository": "s3_backup",
  "config": {
    "indices": ["*"],
    "ignore_unavailable": true,
    "include_global_state": false
  },
  "retention": {
    "expire_after": "30d",
    "min_count": 5,
    "max_count": 50
  }
}

// Verify snapshots are working
GET /_slm/policy/nightly-backup
POST /_slm/policy/nightly-backup/_execute

// Restore from snapshot
POST /_snapshot/s3_backup/nightly-snap-2024.01.15/_restore
{
  "indices": "products",
  "rename_pattern": "(.+)",
  "rename_replacement": "restored_$1"
}
```

Reference: [Snapshot lifecycle management](https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-lifecycle-management.html)
