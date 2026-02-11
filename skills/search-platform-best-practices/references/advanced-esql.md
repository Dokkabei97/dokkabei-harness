---
title: Use ES|QL for SQL-Like Analytical Queries
impact: LOW
impactDescription: Familiar SQL-like syntax for analytics, log exploration, and ad-hoc queries
tags: advanced, esql, ppl, sql, analytics, query-language
---

## Use ES|QL for SQL-Like Analytical Queries

ES|QL (Elasticsearch Query Language) provides a pipe-based query language for data exploration and analytics, making complex aggregations more readable than JSON DSL.

**Correct (ES|QL for analytics):**

```json
POST /_query
{
  "query": """
    FROM logs-*
    | WHERE @timestamp > NOW() - 1 HOUR AND level == "ERROR"
    | STATS error_count = COUNT(*), unique_services = COUNT_DISTINCT(service) BY service
    | SORT error_count DESC
    | LIMIT 20
  """
}

// Time-series analysis
POST /_query
{
  "query": """
    FROM metrics-*
    | WHERE @timestamp > NOW() - 24 HOURS
    | EVAL hour = DATE_TRUNC(1 hour, @timestamp)
    | STATS avg_cpu = AVG(cpu_percent), p99_latency = PERCENTILE(latency, 99) BY hour
    | SORT hour
  """
}

// Join-like enrichment
POST /_query
{
  "query": """
    FROM orders
    | WHERE status == "completed"
    | STATS total_revenue = SUM(amount), order_count = COUNT(*) BY region
    | EVAL avg_order_value = total_revenue / order_count
    | SORT total_revenue DESC
  """
}
```

For OpenSearch, use PPL (Piped Processing Language):

```json
POST /_plugins/_ppl
{
  "query": "search source=logs-* | where level='ERROR' | stats count() by service | sort - count()"
}
```

ES|QL advantages over Query DSL for analytics:
- Readable pipe-based syntax
- Built-in EVAL for computed columns
- STATS for aggregation
- No nested JSON structure

Reference: [ES|QL](https://www.elastic.co/guide/en/elasticsearch/reference/current/esql.html)
