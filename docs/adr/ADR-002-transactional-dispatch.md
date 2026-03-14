# ADR-002: Transactional Dispatch — Event, Deliveries, and Job Enqueue in One Transaction

## Status: Accepted

## Context

When `Hookshot.trigger` is called, three things must happen atomically:

1. An `Event` record is created.
2. One `Delivery` record is created per subscribed endpoint.
3. One `DeliveryJob` is enqueued per delivery.

If steps 1 and 2 succeed but step 3 fails (e.g., a transient error mid-loop), deliveries exist in the database with no corresponding job — they will never be processed unless a reconciliation sweep is run. Conversely, if a job is enqueued before the database records are committed, the job could execute before the delivery row is visible to other connections, causing a `RecordNotFound` on the worker.

## Options Considered

1. **Separate operations, no transaction** — Create the Event, create Deliveries, then enqueue jobs. Simple, but leaves the system in an inconsistent state on any partial failure.

2. **Saga / two-phase approach** — Create records first and commit, then enqueue jobs in a separate step. Add a background sweep to re-enqueue any Deliveries stuck in `pending` for too long.
   - Pros: Avoids holding a DB transaction open while doing non-DB work.
   - Cons: Requires a recovery sweep (cron or queue-based) and accepts a window of inconsistency. More moving parts.

3. **Single database transaction wrapping Event, Deliveries, and job enqueue** — Wrap all three steps in `ActiveRecord::Base.transaction`. If any step fails, everything rolls back: no orphaned records, no phantom jobs.
   - Pros: Atomic by construction. No recovery sweep needed. Solid Queue is DB-backed, so the job insert participates in the same ACID transaction. If the transaction rolls back, the job row is also rolled back.
   - Cons: Holds the connection open slightly longer. Jobs cannot be enqueued until the transaction commits (Solid Queue defers execution until commit, which is the correct behavior).

## Decision

All three steps (create Event, create Deliveries, enqueue DeliveryJobs) are wrapped in a **single `ActiveRecord::Base.transaction`** in `EventDispatcher#call`.

This is only safe because Solid Queue is database-backed. Enqueuing a job is an `INSERT` into `solid_queue_jobs`, which participates in the surrounding transaction. If the transaction rolls back, the job row disappears — no job fires for records that don't exist. Background job adapters backed by external brokers (Redis, SQS) cannot provide this guarantee.

The idempotency check (`Event.find_by(idempotency_key:)`) runs **before** the transaction to avoid unnecessary lock acquisition on the common re-trigger path.

## Trade-offs Accepted

- The design is coupled to Solid Queue's DB-backed architecture. Switching to a Redis-backed adapter (Sidekiq) would break the atomicity guarantee and require adding a recovery sweep.
- DB connection is held open for the full duration of the fan-out loop (one INSERT per subscribed endpoint). For endpoints in the tens-of-thousands, this could become a bottleneck; at that scale, a batched async fan-out strategy would be warranted.
