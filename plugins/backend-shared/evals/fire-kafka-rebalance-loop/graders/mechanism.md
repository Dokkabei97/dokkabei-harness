---
type: llm
focus: last_message
---

PASS if the reply ties the rebalances to processing time between poll() calls exceeding max.poll.interval.ms (default 5 minutes) with max.poll.records (default 500), so the uncommitted batch is reprocessed after reassignment, AND recommends bounding worst-case batch time (lower max.poll.records and/or raise max.poll.interval.ms, short timeouts on the external call), optionally mentioning cooperative-sticky assignment or static membership (group.instance.id).
FAIL if it blames only session.timeout.ms/heartbeats, or never mentions max.poll.interval.ms.
