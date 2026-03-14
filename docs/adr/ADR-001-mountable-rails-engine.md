# ADR-001: Mountable Rails Engine Architecture

## Status: Accepted

## Context

Hookshot needs to be distributed as a reusable library that any Rails application can adopt without modifying the host app's core models or schema. The library must ship its own database tables, background jobs, routes, and (eventually) dashboard UI — all namespaced to prevent collisions with the host app.

Two delivery models were considered: a standalone service (separate process, communicates over HTTP/gRPC) and a mountable Rails engine (gem, shares the host process).

## Options Considered

1. **Standalone microservice** — Hookshot runs as a separate Rails app; host apps communicate via an internal API.
   - Pros: Complete isolation; independent deploys; language-agnostic interface.
   - Cons: Adds operational complexity (service discovery, auth between services, separate database, separate deploy pipeline). Overkill for a library targeting small-to-medium Rails shops that don't already run a service mesh.

2. **Mountable Rails Engine (gem)** — Hookshot is packaged as a Rails Engine, installed via Gemfile, and mounted in `config/routes.rb`. It brings its own migrations, models, jobs, and routes under the `Hookshot::` namespace.
   - Pros: Zero operational overhead — no new processes or infra. Ships with the host app's deploy. Full access to ActiveRecord, ActiveJob, and Solid Queue without bridging layers. Idiomatic Rails pattern (Devise, Spree, etc. use this model). Easy to contribute to and audit.
   - Cons: Tightly coupled to Rails; runs in the host process (a bug in Hookshot could affect the host). Shared database.

## Decision

We build Hookshot as a **mountable Rails Engine**.

The target audience is Rails teams that want production-grade webhook delivery without spinning up new infrastructure. A gem that mounts into their existing app and works with their existing queue (Solid Queue) is the most frictionless path to adoption.

All classes live under the `Hookshot::` module namespace. Database tables use the `hookshot_` prefix. Routes are isolated via `Engine.routes.draw`. Migrations are exposed to the host app via the engine's `initializer`.

## Trade-offs Accepted

- Hookshot is Rails-only. Non-Rails Ruby apps cannot use it.
- Host apps share a database with Hookshot tables. Schema isolation is by convention (prefix), not enforcement.
- A memory leak or bug in Hookshot runs in the host process. Engine gems are a well-understood pattern; the risk is accepted in exchange for zero operational overhead.
