# ADR-004: Net::HTTP for Webhook Delivery (No Faraday or HTTParty)

## Status: Accepted

## Context

`DeliveryExecutor` must make HTTPS POST requests to external endpoints with configurable timeouts, custom headers, and robust error handling. Several HTTP client libraries are available in the Ruby ecosystem. The choice affects gem weight, dependency surface, error semantics, and long-term maintenance.

## Options Considered

1. **Faraday** — Middleware-based HTTP client with adapter abstraction.
   - Pros: Familiar to many Rails developers; middleware stack is composable; easy retry / logging middleware.
   - Cons: Adds a runtime gem dependency (plus adapter gems like `faraday-net_http`). Hookshot is a gem; every dependency we add becomes a transitive dependency for every host app. Faraday's middleware abstraction is powerful but unnecessary for our narrow use case: one HTTP verb (POST), one endpoint type, fully controlled headers and body.

2. **HTTParty** — Declarative HTTP client, often used in Rails apps.
   - Pros: Familiar, clean DSL.
   - Cons: Same dependency concerns as Faraday. Designed for client-side consumption of APIs; its declarative style doesn't map cleanly to our programmatic, per-request header construction.

3. **Net::HTTP (stdlib)** — Ruby's built-in HTTP library, available without any gem install.
   - Pros: Zero additional dependencies. Explicit timeout configuration (`open_timeout`, `read_timeout`). Full access to raw request/response objects (status code, headers, body) needed for the audit trail. Error classes (`Net::ReadTimeout`, `Net::OpenTimeout`, `SocketError`) are well-known and comprehensive. No magic.
   - Cons: More verbose than Faraday or HTTParty. Lacks built-in retry / middleware — but Hookshot owns that layer (it lives in `RetryPolicy` and `RetryJob`), so this is not a gap.

## Decision

Use **Net::HTTP** from Ruby's standard library.

Hookshot is a gem with a wide potential install base. Adding HTTP client dependencies is a form of opinion-imposition on host apps — if a host already uses Faraday with a custom adapter, adding another Faraday dependency risks version conflicts. Net::HTTP has no such risk.

Our HTTP use case is narrow and well-defined:
- POST a JSON body
- Set four custom headers
- Honour connect and read timeouts
- Capture status, headers, and body for the audit trail
- Rescue five specific network error classes

Net::HTTP covers all of this without a middleware layer. The verbosity cost is contained within `DeliveryExecutor` (~40 lines) and is well-tested.

Timeouts are always set explicitly (`connect_timeout: 5s`, `read_timeout: 10s` by default) and are configurable via `Hookshot.configure`. A delivery that hangs indefinitely is worse than a fast failure — external endpoints must not be able to tie up Solid Queue workers.

## Trade-offs Accepted

- `DeliveryExecutor` is slightly more verbose than equivalent Faraday code. This is a one-time cost, not a recurring one.
- Adding features like HTTP/2, connection pooling, or automatic redirects would require more work than with Faraday. These are not needed for webhook delivery and are explicitly out of scope for Phase 1.
