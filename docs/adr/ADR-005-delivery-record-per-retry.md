# ADR-005: New Delivery Record per Retry Attempt

## Status: Accepted

## Context

When a webhook delivery fails and must be retried, Hookshot needs to track the full attempt history. Two structural models were considered for representing this history in the database.

The choice affects query simplicity, auditability, debugging ergonomics, and the ability to answer operational questions like: "Why did delivery to endpoint X ultimately succeed on attempt 4? What happened on attempts 1–3?"

## Options Considered

1. **Mutate the existing Delivery record** — On each retry, update the single `hookshot_deliveries` row in place (increment `attempt_number`, overwrite `status`, `response_status`, `response_body`, `error_message`, `duration_ms`).
   - Pros: One row per logical delivery; simpler JOIN queries; smaller table.
   - Cons: History is destroyed on each update. Operators can only see the last attempt. Post-incident analysis ("was the timeout on attempt 2 or attempt 3?") is impossible. The `idempotency_key` on the delivery row (used as the `X-Hookshot-Delivery` header) becomes ambiguous — the same key is sent on every retry, which could confuse receiving endpoints that use it for their own idempotency.

2. **New Delivery row per attempt** — `RetryJob` creates a fresh `Delivery` record with `attempt_number: original.attempt_number + 1`. Each row is an immutable record of exactly one HTTP attempt.
   - Pros: Complete, queryable audit trail — every attempt's status, response, headers, timing, and error message is preserved. Receiving endpoints get a unique `X-Hookshot-Delivery` header per attempt, enabling their idempotency logic to distinguish retries from the original. Simplifies `RetryJob` (no partial-update logic). Immutable rows are easier to reason about under concurrent job execution.
   - Cons: More rows in `hookshot_deliveries`. A delivery that exhausts all 8 retries produces 9 rows (1 initial + 8 retries). Queries that want "the latest status for a delivery" need `ORDER BY attempt_number DESC LIMIT 1`. A future index on `(event_id, endpoint_id, attempt_number)` covers this efficiently.

## Decision

**Create a new `Delivery` record for each retry attempt.**

`RetryJob` creates a sibling row:

```ruby
Delivery.create!(
  event:          original.event,
  endpoint:       original.endpoint,
  attempt_number: original.attempt_number + 1,
  scheduled_at:   Time.current,
)
```

`DeliveryExecutor` then operates on this new record exactly as it does for an initial delivery, keeping the retry and initial-delivery code paths identical.

The `DeadLetter` record links to the final (highest `attempt_number`) `Delivery`, providing a clear "this is where it ended" pointer without requiring a scan.

## Trade-offs Accepted

- `hookshot_deliveries` grows at O(attempts) per logical delivery rather than O(1). Indexes on `event_id`, `endpoint_id`, and `attempt_number` keep queries fast; a periodic archival job (future work) can prune old rows.
- "Current status" queries require `ORDER BY attempt_number DESC LIMIT 1` rather than a direct row lookup. This is a known pattern and is encapsulated at the query layer, not scattered across the codebase.
