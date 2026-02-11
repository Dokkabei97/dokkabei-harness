---
title: Use _cat APIs for Quick Cluster Diagnostics
impact: LOW-MEDIUM
impactDescription: Human-readable cluster status at a glance for rapid troubleshooting
tags: monitoring, cat, diagnostics, troubleshooting, quick-check
---

## Use _cat APIs for Quick Cluster Diagnostics

The `_cat` APIs return human-readable tabular output, ideal for quick terminal-based diagnostics. Use them for rapid cluster health checks before diving into detailed JSON APIs.

**Essential _cat commands:**

```json
// Cluster health overview
GET /_cat/health?v
// epoch  timestamp cluster status node.total node.data shards pri relo init unassign

// Node overview with key metrics
GET /_cat/nodes?v&h=name,node.role,heap.percent,ram.percent,cpu,load_1m,disk.used_percent
// name    node.role heap.percent ram.percent cpu load_1m disk.used_percent
// data-1  d         65           82          12  2.5     58

// Index health and size
GET /_cat/indices?v&h=index,health,status,pri,rep,docs.count,store.size&s=store.size:desc
// Show largest indices first

// Shard distribution
GET /_cat/shards?v&h=index,shard,prirep,state,node,store&s=store:desc

// Pending tasks (cluster state updates)
GET /_cat/pending_tasks?v
// If tasks are backed up, master node may be overloaded

// Thread pool status (watch for rejections)
GET /_cat/thread_pool?v&h=node_name,name,active,queue,rejected&s=rejected:desc

// Recovery progress
GET /_cat/recovery?v&active_only=true

// Segment count per shard
GET /_cat/segments/products?v&h=index,shard,segment,size
```

Tip: Add `?format=json` to get JSON output for programmatic use, or `?help` to see all available columns.

Reference: [cat APIs](https://www.elastic.co/guide/en/elasticsearch/reference/current/cat.html)
