---
type: llm
focus: last_message
---

PASS if the reply sizes shards by data volume using a 10–50GB-per-shard guideline (e.g. 50GB/day → about 1–2 primaries per daily index, so 10 primaries of ~5GB is over-sharding), AND recommends ILM rollover by primary shard size (max_primary_shard_size around 50gb, optionally min_primary_shard_size) or an equivalent size-based rollover/data stream approach.
FAIL if it keeps or increases 10 primaries per day without addressing per-shard size, or gives a shard count with no size-based reasoning.
