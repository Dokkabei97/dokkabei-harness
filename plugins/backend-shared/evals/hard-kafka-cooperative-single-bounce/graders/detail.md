---
type: llm
focus: last_message
---

This case checks a version-specific default. Judge only the final reply.

Ground truth (Apache Kafka ConsumerConfig doc, clients 3.0+): the default `partition.assignment.strategy` is `[RangeAssignor, CooperativeStickyAssignor]`; the RangeAssignor (eager) is used because it is first, "but allows upgrading to the CooperativeStickyAssignor with just a single rolling bounce that removes the RangeAssignor from the list." Since this group has never set the property and runs kafka-clients 3.7, every member already advertises CooperativeStickyAssignor, so ONE rolling deploy that sets the strategy to CooperativeStickyAssignor alone is sufficient. The classic two-bounce procedure (add both, then remove eager) is only required when members run an eager-only list (e.g. RangeAssignor alone) or pre-3.0 clients.

PASS only if the reply concludes that a single rolling deploy is enough for this setup, setting the strategy to CooperativeStickyAssignor only, AND justifies it by the 3.x default list already containing CooperativeStickyAssignor (Range first).

FAIL if the reply prescribes the two-rolling-bounce procedure as necessary for this group, states the default is RangeAssignor alone, or tells the user to set only CooperativeStickyAssignor without recognising why that is safe here. Extra advice (static membership via group.instance.id, verifying the effective config in the startup log, rebalance-latency metrics) is fine.
