---
title: Use Change Streams for Real-Time Event-Driven Architecture
impact: LOW
impactDescription: Real-time data streaming without polling, with fault-tolerant resume capability
tags: change-streams, real-time, event-driven, resume-token, cdc
---

## Use Change Streams for Real-Time Event-Driven Architecture

Change Streams provide a real-time stream of data changes (insert, update, delete, replace) on a collection, database, or entire deployment. They replace polling patterns with efficient, event-driven processing.

**Incorrect (polling for changes with repeated queries):**

```javascript
// Polling every second for new orders — wasteful and has latency
setInterval(async () => {
  const newOrders = await db.orders.find({
    createdAt: { $gte: lastChecked },
    processed: false
  }).toArray();
  for (const order of newOrders) {
    await processOrder(order);
  }
  lastChecked = new Date();
}, 1000);
// Executes a query every second even when no new data exists
// 1 second latency between insert and detection
// Risk of missing documents if processing takes > 1 second
```

**Correct (change stream with resume token for fault tolerance):**

```javascript
// Open a change stream with filtering
const pipeline = [
  { $match: {
    operationType: { $in: ["insert", "update"] },
    "fullDocument.status": "pending"
  }}
];

const changeStream = db.collection("orders").watch(pipeline, {
  fullDocument: "updateLookup"  // include the full document on updates
});

// Store resume token for fault tolerance
let resumeToken = await loadResumeToken();  // load from persistent storage

if (resumeToken) {
  // Resume from where we left off after a crash
  const changeStream = db.collection("orders").watch(pipeline, {
    resumeAfter: resumeToken,
    fullDocument: "updateLookup"
  });
}

// Process changes as they happen — near-zero latency
changeStream.on("change", async (change) => {
  try {
    console.log("Change detected:", change.operationType, change.documentKey);
    await processOrder(change.fullDocument);

    // Persist resume token after successful processing
    await saveResumeToken(change._id);  // _id IS the resume token
  } catch (err) {
    console.error("Processing failed:", err);
    // Don't update resume token — will retry on restart
  }
});

changeStream.on("error", (err) => {
  console.error("Change stream error:", err);
  // Reconnect with last saved resume token
});
```

Change stream requirements:
- Requires a replica set or sharded cluster (not standalone)
- Oplog must be large enough to cover the resume window
- Use `startAfter` instead of `resumeAfter` if the resume token's document was invalidated

Reference: [Change Streams](https://www.mongodb.com/docs/manual/changeStreams/)
