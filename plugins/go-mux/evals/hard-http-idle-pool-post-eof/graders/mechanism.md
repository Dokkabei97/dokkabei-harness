---
type: llm
focus: last_message
---

All three of the following are required for PASS:
(a) Pool size: names the concrete default `DefaultMaxIdleConnsPerHost` = 2 (Transport.MaxIdleConnsPerHost zero value means 2) as the reason reuse fails at ~150 concurrency — connections beyond 2 idle per host are closed on return — and prescribes a custom Transport (e.g. cloned from http.DefaultTransport) with MaxIdleConnsPerHost raised to roughly the normal per-host concurrency, with MaxIdleConns (default 100 total) at least that large.
(b) Idle timeout mismatch: states the DefaultTransport IdleConnTimeout is 90 seconds while the ALB idle timeout defaults to 60 seconds, so the client reuses connections the load balancer already closed, and prescribes a client IdleConnTimeout shorter than the LB's (e.g. ~50s).
(c) GET-vs-POST asymmetry: explains that net/http's Transport automatically retries a request that fails on a reused (stale) idle connection only when the request is replayable/idempotent — GET/HEAD/OPTIONS/TRACE, or a request carrying an `Idempotency-Key` / `X-Idempotency-Key` header (with no body or a rewindable body via GetBody) — so the GET failures are silently retried while POST surfaces the error. Mentioning the Idempotency-Key header (or an explicit application-level idempotent retry) as a remedy satisfies the remedy part.
FAIL if any of (a), (b), (c) is missing; if the default per-host idle value is stated as anything other than 2; or if the GET/POST difference is attributed only to something else (e.g. "POST bodies are larger", "ALB treats POST differently", "GET is cached").
