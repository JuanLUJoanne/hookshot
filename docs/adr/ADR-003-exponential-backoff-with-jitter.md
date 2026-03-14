# ADR-003: Exponential Backoff with Full Jitter for Retry Delays

## Status: Accepted

## Context

When a webhook delivery fails (5xx, timeout, connection error), Hookshot must schedule a retry. The retry delay strategy directly affects:

- **Receiver recovery time** — Too-short delays hammer a receiver that is still recovering, preventing it from coming back up.
- **Thundering herd** — If many endpoints fail simultaneously (e.g., a shared dependency goes down), fixed or pure-exponential delays cause all retries to fire at the same moment, recreating the spike that caused the failure.
- **Latency to success** — Too-long delays make Hookshot useless for time-sensitive events.

## Options Considered

1. **Fixed delay** — Retry every N seconds regardless of attempt count.
   - Pros: Predictable, easy to reason about.
   - Cons: No back-pressure. A struggling receiver is retried at full rate indefinitely. No thundering herd mitigation.

2. **Pure exponential backoff** — `delay = base_delay * 2^attempt`.
   - Pros: Increases back-pressure over time; gives receivers space to recover.
   - Cons: All endpoints that failed together will retry together. At attempt 3, every failure from the same outage fires at the same moment — thundering herd still occurs, just at a lower rate.

3. **Exponential backoff with full jitter** — `delay = base_delay * 2^attempt + rand(0..jitter_max)`, capped at `retry_max_delay`.
   - Pros: Combines exponential back-pressure with randomised spread. Concurrent failures are spread across a time window rather than synchronised. Proven approach (AWS, Stripe, Shopify all use this pattern). Configurable: `retry_base_delay`, `retry_max_delay`, `jitter_max` are all exposed in `Hookshot::Configuration`.
   - Cons: Retry timing is non-deterministic; harder to test precisely (we seed `rand` via `allow(Kernel).to receive(:rand)` in tests).

## Decision

Use **exponential backoff with full jitter**:

```
delay = min(base_delay * 2^attempt + rand(0..jitter_max), retry_max_delay)
```

Defaults:
- `retry_base_delay`: 15 seconds
- `retry_max_delay`: 3600 seconds (1 hour)
- `jitter_max`: 5 seconds
- `max_retries`: 8 attempts

At defaults, delays progress roughly: 30s, 65s, 125s, 245s, 485s, 965s, 1925s, 3600s (capped). Total retry window is approximately 2.5 hours — long enough for most infrastructure incidents to resolve, short enough that operators notice promptly.

All parameters are exposed in `Hookshot.configure` so host applications can tune them for their SLA requirements.

## Trade-offs Accepted

- Retry timing is stochastic. Operators cannot predict the exact moment a retry fires; they can only bound it. This is intentional and desirable.
- `max_retries` currently applies globally. A per-endpoint override (for high-priority endpoints) is left for a future ADR.
