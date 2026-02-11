---
title: Use _tasks API to Monitor and Cancel Long-Running Operations
impact: LOW-MEDIUM
impactDescription: Identifies stuck reindex, search, and merge operations that block cluster resources
tags: monitoring, tasks, long-running, cancel, reindex, operations
---

## Use _tasks API to Monitor and Cancel Long-Running Operations

Long-running operations (reindex, force merge, large scrolls) can consume resources indefinitely. The `_tasks` API monitors active operations and allows cancellation of stuck or runaway tasks.

**Monitor running tasks:**

```json
// List all running tasks
GET /_tasks?detailed=true&actions=*reindex,*forcemerge,*scroll

// Group by parent task
GET /_tasks?group_by=parents

// Find long-running tasks (running > 60s)
GET /_tasks?actions=*&detailed=true
// Check "running_time_in_nanos" for each task

// Monitor specific reindex task
GET /_tasks/oTUltX4IQMOUUVeiohTt8A:12345
```

**Cancel stuck operations:**

```json
// Cancel a specific task
POST /_tasks/oTUltX4IQMOUUVeiohTt8A:12345/_cancel

// Cancel all reindex tasks
POST /_tasks/_cancel?actions=*reindex

// Cancel tasks running longer than expected
POST /_tasks/_cancel?actions=*search&nodes=data-1
```

Best practice: Always submit long-running operations asynchronously:

```json
// Reindex with wait_for_completion=false
POST /_reindex?wait_for_completion=false
{
  "source": { "index": "old" },
  "dest": { "index": "new" }
}
// Returns task ID immediately — monitor via _tasks API
```

Reference: [Task management](https://www.elastic.co/guide/en/elasticsearch/reference/current/tasks.html)
