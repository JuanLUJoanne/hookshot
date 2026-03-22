# Hookshot

Hookshot is a mountable Rails Engine that adds production-grade webhook delivery to any Rails 8 application. It handles the infrastructure that makes webhooks reliable in production: signing, retries, idempotency, per-attempt audit trails, dead-lettering, and a circuit breaker state machine — none of which you want to rebuild per-project. Every significant design decision is documented as an ADR in `docs/adr/`.

## Features

- **HMAC-SHA256 signing** — every delivery is signed with a per-endpoint secret; the signed string binds the Unix timestamp to the payload body (`timestamp.payload`) so a captured signature cannot be replayed with a different body or after the tolerance window closes
- **Exponential backoff with jitter** — failed deliveries retry with `delay = base_delay × 2^attempt + rand(0..jitter_max)`, capped at a configurable ceiling; jitter prevents thundering-herd against a recovering receiver when many endpoints fail at the same time
- **Dead-letter queue** — deliveries that exhaust all retry attempts are moved to `hookshot_dead_letters` with the total attempt count, reason, and a link to every individual attempt record
- **Immutable per-attempt audit trail** — each delivery attempt is its own `Delivery` record containing the HTTP status, response body, request headers sent, latency in milliseconds, and any network error message; nothing is overwritten between retries
- **Atomic fan-out dispatch** — a single `Hookshot.trigger` call creates the `Event`, all `Delivery` records, and all `DeliveryJob` enqueues inside one database transaction; Solid Queue's DB-backed design means a rolled-back transaction also discards the jobs, preventing orphaned deliveries
- **Idempotent triggers** — supply an `idempotency_key` to `Hookshot.trigger`; re-triggering with the same key returns the existing `Event` without creating duplicates or re-dispatching
- **Replay-attack protection** — `SignatureVerifier` rejects requests whose `X-Hookshot-Timestamp` is more than 5 minutes old, independently of the signature check
- **Circuit breaker state** — endpoints track `consecutive_failures`, `circuit_opened_at`, and a three-value status (`active`, `paused`, `circuit_open`); paused and circuit-open endpoints are skipped entirely at dispatch time, creating no `Delivery` records
- **Configurable HTTP timeouts** — connect and read timeouts are set on every `Net::HTTP` request; a slow receiver cannot stall queue workers indefinitely

## Installation

Add the gem to your `Gemfile`:

```ruby
gem "hookshot"
```

```
bundle install
```

Install and run the engine migrations:

```
bundle exec rails hookshot:install:migrations
bundle exec rails db:migrate
```

This creates five tables: `hookshot_endpoints`, `hookshot_subscriptions`, `hookshot_events`, `hookshot_deliveries`, and `hookshot_dead_letters`.

Mount the engine in `config/routes.rb` (required for the Phase 2 dashboard; no routes are active in Phase 1):

```ruby
Rails.application.routes.draw do
  mount Hookshot::Engine, at: "/hookshot"
end
```

Add Solid Queue to your application if it is not already configured — Hookshot's transactional dispatch guarantee depends on a DB-backed queue adapter.

## Quick Start

**1. Register an endpoint and subscribe it to one or more event types:**

```ruby
endpoint = Hookshot::Endpoint.create!(
  url: "https://your-customer.example.com/webhooks"
)
# endpoint.secret is auto-generated as SecureRandom.hex(32).
# Share it with your customer so they can verify inbound signatures.

Hookshot::Subscription.create!(
  endpoint:   endpoint,
  event_type: "order.created"   # lowercase, dot-separated
)
```

An endpoint can hold multiple subscriptions. Event type strings must match `[a-z_]+(\.[a-z_]+)*` — for example `order.created`, `payment.failed`, `user.subscription.cancelled`.

**2. Trigger a webhook from anywhere in your application:**

```ruby
event = Hookshot.trigger("order.created", payload: { order_id: 42, total: "99.99" })
# => #<Hookshot::Event id: 1, status: "dispatched", ...>
```

Hookshot fans out to every active endpoint subscribed to `"order.created"`, creating one `Delivery` and enqueuing one `DeliveryJob` per endpoint within a single transaction. The HTTP POST is made asynchronously by Solid Queue.

To make the trigger safe to retry after an application crash, pass a stable idempotency key:

```ruby
Hookshot.trigger(
  "order.created",
  payload:         { order_id: 42, total: "99.99" },
  idempotency_key: "order-42-created"
)
# Calling this again with the same key returns the original Event — no duplicate dispatch.
```

**3. Verify the signature on the receiving end:**

```ruby
# In a Rails controller on the receiving application:
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def receive
    valid = Hookshot::Services::SignatureVerifier.valid?(
      payload:   request.body.read,
      signature: request.headers["X-Hookshot-Signature"],
      timestamp: request.headers["X-Hookshot-Timestamp"],
      secret:    ENV["WEBHOOK_SECRET"]   # the value of endpoint.secret
    )

    return head :unauthorized unless valid

    # process request.parsed_body ...
    head :ok
  end
end
```

Every delivery sets four request headers:

| Header | Example value | Notes |
|---|---|---|
| `X-Hookshot-Signature` | `sha256=a1b2c3...` | HMAC-SHA256 of `"#{timestamp}.#{body}"` |
| `X-Hookshot-Timestamp` | `1710364800` | Unix seconds; reject if >5 min old |
| `X-Hookshot-Delivery` | `550e8400-...` | Unique per attempt; use for your own idempotency |
| `X-Hookshot-Event` | `order.created` | The event type string |

`X-Hookshot-Delivery` is unique per attempt, so if Hookshot retries a delivery your endpoint can distinguish the retry from the original using this header.

## Configuration

Create `config/initializers/hookshot.rb`:

```ruby
Hookshot.configure do |config|
  # How many total attempts before a delivery is dead-lettered.
  # Attempt 1 is the initial delivery; attempts 2–N are retries.
  config.max_retries      = 8          # default: 8

  # Retry delay formula: base_delay * (2 ^ attempt) + rand(0..jitter_max)
  config.retry_base_delay = 15         # seconds; default: 15
  config.retry_max_delay  = 3_600      # cap in seconds; default: 3600 (1 hour)
  config.jitter_max       = 5          # random seconds added per retry; default: 5

  # Active Job queue that DeliveryJob and RetryJob are placed on.
  config.queue_name       = :webhooks  # default: :webhooks

  # Net::HTTP timeouts for each outbound request.
  config.connect_timeout  = 5          # seconds; default: 5
  config.read_timeout     = 10         # seconds; default: 10
end
```

With the defaults, retry delays grow roughly as: 30 s → 65 s → 125 s → 245 s → 485 s → 965 s → 1925 s → 3600 s (capped). The full retry window is approximately 2.5 hours.

## How It Works

`Hookshot.trigger` delegates to `Services::EventDispatcher`, which opens a single database transaction: it creates an `Event` record, marks it `dispatched`, queries for all `active` endpoints that have a `Subscription` for the given event type, creates one `Delivery` per endpoint in `pending` status, and enqueues a `DeliveryJob` for each delivery ID before the transaction commits. Because Solid Queue writes jobs as rows in the same PostgreSQL database, the enqueue participates in the same ACID transaction — if anything in the block fails, no jobs fire for records that do not exist. `DeliveryJob` hands off to `Services::DeliveryExecutor`, which generates an HMAC-SHA256 signature, POSTs the JSON payload via `Net::HTTP` with the configured timeouts, and writes the complete request and response audit record to the `Delivery` row regardless of outcome. If the response is outside 2xx or a network exception is raised, `Services::RetryPolicy` checks whether `attempt_number >= max_retries`: below the threshold it schedules a `RetryJob` with an exponential backoff delay; at or above the threshold it creates a `DeadLetter` record and marks the parent `Event` as `failed`. Each retry creates a new `Delivery` row — attempt 1 got 503, attempt 2 timed out, attempt 3 succeeded — so the complete history is preserved and queryable without touching earlier records.

## Circuit Breaker

Each `Hookshot::Endpoint` carries three fields that support circuit breaker behaviour:

| Field | Type | Purpose |
|---|---|---|
| `status` | enum | `active`, `paused`, or `circuit_open` |
| `consecutive_failures` | integer | Running count of sequential delivery failures |
| `circuit_opened_at` | datetime | When the circuit last transitioned to open |

Endpoints with status `paused` or `circuit_open` are excluded from dispatch entirely — `EventDispatcher` only queries `status_active` endpoints, so no `Delivery` records are created and no jobs are enqueued for them. Automatic state transitions (opening the circuit after N consecutive failures, and probing for recovery via a half-open probe) are planned for Phase 2. You can manage state manually in the interim:

```ruby
endpoint.status_circuit_open!   # stop deliveries immediately
endpoint.status_active!         # re-enable after the receiver recovers
endpoint.status_paused!         # suspend without implying a fault
```

## Dead Letter Queue

When `RetryPolicy` determines that `delivery.attempt_number >= config.max_retries`, it creates a `DeadLetter` record linking the final `Delivery`, the `Event`, and the `Endpoint`, records the total attempt count and the timestamp of the last attempt, and marks the parent `Event` as `failed`.

Inspect dead letters:

```ruby
Hookshot::DeadLetter.includes(:endpoint, :event).each do |dl|
  puts [
    dl.endpoint.url,
    dl.event.event_type,
    "#{dl.total_attempts} attempts",
    dl.reason,
    dl.last_attempted_at
  ].join("  |  ")
end
```

Dead letters carry one of three `reason` values: `max_retries_exceeded`, `circuit_open`, or `manual`.

To re-enqueue a dead-lettered delivery for another attempt:

```ruby
dl = Hookshot::DeadLetter.find(id)

delivery = Hookshot::Delivery.create!(
  event:          dl.event,
  endpoint:       dl.endpoint,
  attempt_number: dl.total_attempts + 1,
)

Hookshot::DeliveryJob.perform_later(delivery.id)
```

A one-click replay UI is planned for the Phase 2 dashboard.

## Architecture Decisions

| ADR | Question | Decision |
|---|---|---|
| [ADR-001](docs/adr/ADR-001-mountable-rails-engine.md) | Standalone service or Rails Engine? | Mountable Engine — zero operational overhead for the target audience |
| [ADR-002](docs/adr/ADR-002-transactional-dispatch.md) | How to keep jobs and DB records consistent? | Single transaction wrapping event + deliveries + enqueue; only safe because Solid Queue is DB-backed |
| [ADR-003](docs/adr/ADR-003-exponential-backoff-with-jitter.md) | How to space out retries? | Exponential backoff with full jitter; prevents thundering herd |
| [ADR-004](docs/adr/ADR-004-net-http-over-faraday.md) | Which HTTP client? | `Net::HTTP` from stdlib; no extra dependencies in a gem with a wide install base |
| [ADR-005](docs/adr/ADR-005-delivery-record-per-retry.md) | Mutate the Delivery row on retry, or create a new one? | New row per attempt; preserves immutable audit trail |

## Development

```
bundle install
```

Set up the test database (requires PostgreSQL):

```
cd spec/dummy && bundle exec rake db:create db:migrate
```

Run the full test suite from the project root:

```
bundle exec rspec
```

215 examples, 0 failures. The suite covers all models, services, and jobs with unit specs, and the complete delivery pipeline — dispatch, retry, dead-lettering, idempotency, fan-out, circuit-open skipping, and network failure handling — with 43 integration specs backed by WebMock-stubbed HTTP.

## License

[MIT](MIT-LICENSE)
