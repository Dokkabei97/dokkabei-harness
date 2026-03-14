# Section Definitions

This file defines the rule categories for MongoDB best practices. Rules are automatically assigned to sections based on their filename prefix.

---

## 1. Query Performance (query)
**Impact:** CRITICAL
**Description:** Slow queries, collection scans, inefficient filter patterns. The most common source of MongoDB performance issues. Covers covered queries, projection optimization, selective filtering, and sort optimization.

## 2. Indexing Strategy (index)
**Impact:** CRITICAL
**Description:** Index design, compound index field ordering (ESR rule), partial indexes, TTL indexes, and index maintenance. The foundation of MongoDB query performance.

## 3. Schema Design (schema)
**Impact:** CRITICAL
**Description:** Document structure, embedding vs. referencing, document size limits, schema validation, and anti-patterns. Fundamental decisions that affect every operation.

## 4. Aggregation Pipeline (agg)
**Impact:** HIGH
**Description:** Pipeline stage ordering, $lookup optimization, memory limits, and efficient aggregation patterns. Critical for complex data processing.

## 5. Connection Management (conn)
**Impact:** HIGH
**Description:** Connection pool sizing, retry logic, timeout configuration, and driver best practices. Essential for application reliability and scalability.

## 6. Data Modeling Patterns (model)
**Impact:** MEDIUM-HIGH
**Description:** Advanced modeling patterns including bucket, computed, extended reference, outlier, and subset patterns. Proven solutions for common MongoDB data challenges.

## 7. Security & Authentication (security)
**Impact:** MEDIUM-HIGH
**Description:** Authentication mechanisms, RBAC, field-level encryption, and injection prevention. Security fundamentals for production deployments.

## 8. Replication & High Availability (repl)
**Impact:** MEDIUM
**Description:** Replica set configuration, read preference strategies, write concern settings. Ensures data durability and high availability.

## 9. Sharding (shard)
**Impact:** MEDIUM
**Description:** Shard key selection, targeted vs. scatter-gather queries, zone sharding. Critical for horizontal scaling of large datasets.

## 10. Monitoring & Diagnostics (monitor)
**Impact:** LOW-MEDIUM
**Description:** Using explain plans, database profiler, currentOp, and performance diagnostics tools. Essential for ongoing performance management.

## 11. Advanced Features (advanced)
**Impact:** LOW
**Description:** Change streams, full-text search, time series collections, multi-document transactions, and other advanced MongoDB capabilities.
