---
title: Use Native Time Series Collections for IoT and Metric Data
impact: LOW
impactDescription: 10-40x storage reduction and optimized time-based queries with native engine
tags: time-series, timeseries-collection, iot, metrics, columnar-compression
---

## Use Native Time Series Collections for IoT and Metric Data

MongoDB 5.0+ provides native Time Series collections optimized for time-stamped data. They use columnar compression and automatic bucketing for dramatically better storage efficiency and query performance compared to regular collections.

**Incorrect (regular collection for time-series data):**

```javascript
// Regular collection — each measurement is a full BSON document
db.metrics.insertOne({
  sensorId: "temp_sensor_01",
  timestamp: new Date(),
  temperature: 22.5,
  humidity: 65,
  location: "Building A, Floor 3"
});
// 1M readings/day = 1M documents with repeated metadata
// Storage: ~200 bytes/doc x 1M = 200MB/day
// Index overhead: significant for timestamp + sensorId
```

**Correct (native time series collection):**

```javascript
// Create time series collection with proper configuration
db.createCollection("metrics", {
  timeseries: {
    timeField: "timestamp",          // required: the time field
    metaField: "metadata",           // optional: fields that rarely change
    granularity: "minutes"           // expected interval between measurements
    // granularity options: "seconds" | "minutes" | "hours"
  },
  expireAfterSeconds: 86400 * 365    // auto-expire after 1 year
});

// Insert with metadata grouped for optimal compression
db.metrics.insertOne({
  metadata: { sensorId: "temp_sensor_01", location: "Building A, Floor 3" },
  timestamp: new Date(),
  temperature: 22.5,
  humidity: 65
});

// Bulk insert for better performance
db.metrics.insertMany([
  { metadata: { sensorId: "temp_sensor_01" }, timestamp: new Date(), temperature: 22.5 },
  { metadata: { sensorId: "temp_sensor_01" }, timestamp: new Date(), temperature: 22.6 },
  { metadata: { sensorId: "temp_sensor_02" }, timestamp: new Date(), temperature: 21.8 }
]);
// Storage: columnar compression reduces to ~20 bytes/measurement = 20MB/day (10x less)
// MongoDB automatically creates internal buckets — no manual bucket pattern needed
```

Time-range queries are automatically optimized:

```javascript
// Efficient time-range query on time series collection
db.metrics.aggregate([
  { $match: {
    "metadata.sensorId": "temp_sensor_01",
    timestamp: { $gte: new Date("2024-06-01"), $lt: new Date("2024-06-02") }
  }},
  { $group: {
    _id: { $dateToString: { format: "%Y-%m-%d %H:00", date: "$timestamp" } },
    avgTemp: { $avg: "$temperature" },
    maxTemp: { $max: "$temperature" },
    minTemp: { $min: "$temperature" }
  }},
  { $sort: { _id: 1 } }
]);

// Create secondary index on metadata fields
db.metrics.createIndex({ "metadata.sensorId": 1, timestamp: 1 });
```

Reference: [Time Series Collections](https://www.mongodb.com/docs/manual/core/timeseries-collections/)
