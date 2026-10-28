---
type: llm
focus: last_message
---

Ground truth: JDK-8281181 ("CPU Shares Ignored When Computing Active Processor Count") — fixed in JDK 19 and backported to 17.0.5 (and 11.0.17). Older JDKs converted cgroup cpu.shares (k8s CPU requests; 2 CPU → 2048 shares, 2048/1024 = 2) into the active processor count. From 17.0.5 on, shares are ignored, so with no CPU quota (no CPU limit) the JVM sees all host CPUs (64). 43 GC threads = ParallelGCThreads ergonomics for 64 CPUs.

PASS only if the reply does ALL of:
1. Identifies the cause as the JDK no longer using CPU shares / CPU requests to compute availableProcessors, and ties this behavior change to the 17.0.4 → 17.0.12 update range (it must say the change was introduced/backported in a 17 update; naming 17.0.5 or JDK-8281181 is ideal but saying "a 17.0.x update in that range backported the JDK 19 change" is acceptable).
2. Explains that without a CPU limit (quota) the JVM therefore falls back to the host/node CPU count.
3. Recommends `-XX:ActiveProcessorCount=<n>` (n ≈ the request, e.g. 2) as the fix that does not require a CPU limit.

FAIL if it attributes the change to UseContainerSupport being disabled, to a cgroup v1/v2 detection bug or regression, or claims the JVM honors CPU requests by design; FAIL if it gives only generic advice (set CPU limits, tune thread pools individually) without the CPU-shares change.
