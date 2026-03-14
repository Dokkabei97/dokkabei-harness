---
title: Use Bucket Pattern for Time-Series and High-Volume Event Data
impact: HIGH
impactDescription: 10-50x fewer documents, smaller indexes, better query performance
tags: bucket-pattern, time-series, event-data, iot, schema-design
---

## Use Bucket Pattern for Time-Series and High-Volume Event Data

The Bucket Pattern groups time-series or event data into fixed-size "bucket" documents instead of one document per event. This dramatically reduces document count and index size.

**Incorrect (one document per event):**

```javascript
// 1M events per day = 1M documents
db.sensorData.insertOne({ sensorId: "s1", ts: new Date(), temp: 22.5 });
db.sensorData.insertOne({ sensorId: "s1", ts: new Date(), temp: 22.6 });
// ... 1M insertions/day, 1M index entries
```

**Correct (bucket pattern — group events):**

```javascript
// Group into hourly buckets — 24 documents/day instead of 1M
db.sensorBuckets.updateOne(
  {
    sensorId: "s1",
    bucketStart: new Date("2024-01-15T10:00:00Z"),
    count: { $lt: 1000 }  // max 1000 readings per bucket
  },
  {
    $push: { readings: { ts: new Date(), temp: 22.5 } },
    $inc: { count: 1 },
    $min: { bucketStart: new Date("2024-01-15T10:00:00Z") },
    $max: { bucketEnd: new Date() }
  },
  { upsert: true }
);

// Index on bucket level — 10-50x smaller
db.sensorBuckets.createIndex({ sensorId: 1, bucketStart: -1 });
```

For MongoDB 5.0+, consider Time Series Collections as a native alternative:

```javascript
db.createCollection("sensorData", {
  timeseries: {
    timeField: "ts",
    metaField: "sensorId",
    granularity: "minutes"
  },
  expireAfterSeconds: 86400 * 90  // auto-expire after 90 days
});
```

Reference: [Bucket Pattern](https://www.mongodb.com/blog/post/building-with-patterns-the-bucket-pattern)
