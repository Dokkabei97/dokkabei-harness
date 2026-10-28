---
type: llm
focus: last_message
---

This case checks a version-specific framework capability. Judge only the final reply.

Ground truth: with a synchronous (Unit-returning) listener the container commits offsets based on the listener method returning; `scope.launch` returns immediately, so offsets are committed before handle() finishes — a restart loses in-flight records and exceptions inside the coroutine never reach the container error handler. Since Spring Kafka 3.2, @KafkaListener methods may have async return types — CompletableFuture<?>, Mono<?> and Kotlin `suspend` functions; when detected, the container automatically sets AckMode to MANUAL with out-of-order commits and acks when the async operation completes, and an error completion goes to the container error handler (retry/DLT). Minimal fix: make the listener `suspend fun onMessage(...)` and call `handler.handle(...)` directly (drop the custom scope/launch).

PASS only if the reply:
1. Explains that the offset is committed when the listener returns, i.e. before the launched coroutine completes (so records are lost and failures bypass the error handler), AND
2. Recommends a `suspend fun` listener (or returning CompletableFuture/Mono) and states that Spring Kafka 3.2+ natively supports async/suspend listeners, acknowledging on completion (auto MANUAL ack / out-of-order commit) with failures routed to the error handler.

Ordering trade-off is legitimate: with async/suspend listeners the container keeps delivering the next records while earlier ones are in flight (out-of-order completion), so per-partition processing order is no longer guaranteed. A reply that recommends `runBlocking` (or another synchronous wait) as the primary fix BECAUSE ordering matters, while correctly presenting the Spring Kafka 3.2+ suspend/async listener as the alternative, satisfies item 2 and should PASS.

FAIL if the only fix offered is runBlocking, a hand-rolled manual Acknowledgment passed into launch, or "process synchronously" without identifying the native suspend-listener support at all; or if it claims suspend listeners are unsupported in this version.
