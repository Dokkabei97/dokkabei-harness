---
type: llm
focus: last_message
---

PASS if the reply recommends setting refresh_interval to -1 and number_of_replicas to 0 for the initial load AND explicitly says to restore both afterwards (and/or wait for green before switching traffic), AND sizes bulk requests by bytes (a few MB to tens of MB, tuned by doubling until throughput plateaus) rather than by a fixed document count.
FAIL if it omits restoring the settings after the load, or sizes bulk only by document count.
