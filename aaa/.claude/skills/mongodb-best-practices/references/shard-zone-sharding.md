---
title: Use Zone Sharding for Geographic Data Locality
impact: MEDIUM
impactDescription: Data residency compliance and lower latency for multi-region deployments
tags: zone-sharding, geographic-locality, data-residency, multi-region, compliance
---

## Use Zone Sharding for Geographic Data Locality

Zone sharding pins data ranges to specific shards based on shard key values. This enables geographic data locality (keeping user data near users) and compliance with data residency regulations (GDPR, data sovereignty laws).

**Incorrect (data randomly distributed across global shards):**

```javascript
// Without zones, Korean user data may live on US or EU shards
sh.shardCollection("myApp.users", { region: 1, _id: 1 });
// Data distributed randomly — Korean users experience high latency
// May violate data residency requirements (GDPR, PIPA)
```

**Correct (zone sharding for data locality):**

```javascript
// 1. Shard the collection with region in the shard key
sh.shardCollection("myApp.users", { region: 1, _id: 1 });

// 2. Add shards to zones based on geographic location
sh.addShardToZone("shard-kr-1", "korea");
sh.addShardToZone("shard-kr-2", "korea");
sh.addShardToZone("shard-eu-1", "europe");
sh.addShardToZone("shard-eu-2", "europe");
sh.addShardToZone("shard-us-1", "america");

// 3. Define zone ranges — map shard key values to zones
sh.updateZoneKeyRange(
  "myApp.users",
  { region: "KR", _id: MinKey },
  { region: "KR", _id: MaxKey },
  "korea"
);
sh.updateZoneKeyRange(
  "myApp.users",
  { region: "EU", _id: MinKey },
  { region: "EU", _id: MaxKey },
  "europe"
);
sh.updateZoneKeyRange(
  "myApp.users",
  { region: "US", _id: MinKey },
  { region: "US", _id: MaxKey },
  "america"
);

// 4. Application sets region at insert time
db.users.insertOne({
  _id: ObjectId(),
  region: "KR",  // determines which zone (shard) stores this document
  name: "Kim Minsu",
  email: "kim@example.com"
});
// This document is guaranteed to be stored on shard-kr-1 or shard-kr-2
```

Zone sharding considerations:
- Shard key MUST include the zone field as a prefix
- Zone ranges must not overlap
- Uneven zone sizes can cause hotspots — monitor chunk distribution
- Combine with read preference `nearest` for lowest latency reads

Reference: [Zone Sharding](https://www.mongodb.com/docs/manual/core/zone-sharding/)
