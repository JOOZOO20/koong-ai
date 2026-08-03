# koong Core Principles (core-principles.md)

> **Language-agnostic engineering principles every koong agent follows for every line of code.**
> Language/framework specifics: `profiles/<stack>.md`. Security doctrine: `security.md`. Testing doctrine: `testing.md`. Git behavior: `git-policy.md`.

---

## §1 Scope Discipline (THE FIRST RULE)

**Implement exactly what was asked. Nothing more.**

- The task statement (user request / mini-spec / issue) is the contract. Every hunk in the diff must trace back to it.
- **Forbidden**:
  - Speculative features — "they'll probably want this too."
  - Abstractions before the second implementation exists. No interface with one implementation, no "flexible" parameters nobody asked for, no plugin systems for hypothetical futures.
  - Drive-by refactors — renaming, restructuring, or "cleaning up" code outside the task scope. If you notice debt, note it in the report; don't touch it.
  - Unrequested dependencies, config options, env vars, or feature flags "just in case."
  - Adding features to make a commit or PR look bigger. PR size has no lower bound (git-policy.md §6.1).
- The mini-spec's "이건 안 만들어요" list is a hard contract — koong-scope-auditor flags any code that crosses it.
- **The best code is no code.** When two designs solve the task, pick the one with less surface area.

## §2 Clean Code

- **Naming reveals intent.** A reader should understand what a function does without opening it. No abbreviations that save 3 characters and cost 3 minutes.
- **Small units.** Functions do one thing at one level of abstraction. Extract when a function needs section comments.
- **Early returns over nesting.** Guard clauses first; the happy path reads straight down.
- **Immutability by default.** Mutate only with a reason (measured hot path, framework requirement).
- **No dead code.** Delete, don't comment out — git remembers.
- **Comments explain *why*, never *what*.** If the code needs a *what* comment, rewrite the code. Document constraints the code can't express (invariants, external quirks, deliberate trade-offs).
- **Errors are handled or propagated — never swallowed.** An empty catch block is a bug.
- **Follow the language.** Idiomatic beats clever. Each stack profile defines what idiomatic means; when this document and a profile conflict on style, the profile wins.

## §3 Clean Architecture

Layering (names vary by stack; responsibilities don't):

```
transport (controller / router / handler)
    ↓ DTO in, DTO out — never domain entities
business (service / use-case)
    ↓ owns rules, transactions, orchestration
persistence (repository / DAO)
    ↓ reads and writes — zero business logic
```

- **Dependencies point inward.** Transport depends on business, business on persistence interfaces. Never the reverse. Persistence never imports transport types.
- **Transport is thin**: parse, validate, extract principal, delegate, wrap response. No business rules, no transaction boundaries, no direct persistence calls.
- **Business owns transactions.** Transaction boundaries live in the service layer only.
- **DTOs at boundaries.** Entities/domain models never cross the transport boundary in either direction. Request DTOs are strict whitelists (security.md SEC-A4).
- **Domain-based modules, not layer-based.** `order/`, `user/`, `payment/` — each containing its own transport/business/persistence — not top-level `controllers/`, `services/`.
- **No cross-domain reach-ins.** Domain A never imports domain B's entities or repositories. Cross-domain flows go through public service calls or events (outbox).
- **One global error envelope.** A single response shape, a single global exception handler, stable machine-readable error codes (`DOMAIN_REASON`). Clients branch on codes, never on message strings.

## §4 Production Baseline (non-negotiable defaults)

### Idempotency
- Write APIs with side effects (money, inventory, notifications) accept an idempotency key (`Idempotency-Key` header), stored under a unique constraint; duplicates return the original response. TTL ~24h.
- Webhook handlers are idempotent by event ID.

### Transactions & external calls
- External calls (PG, email, push) happen **outside** DB transactions.
- Cross-domain effects ("order completed → notify, award points") are written as an **outbox record in the same transaction**, published by a separate worker: committed means eventually executed.

### API consistency
- URLs: plural nouns, kebab-case (`/orders/{orderId}/line-items`). No verbs.
- One response envelope everywhere; errors as `{ code: "ORDER_NOT_FOUND", message: ... }`.
- One pagination convention (cursor-based preferred: `?cursor=&size=`, response carries `nextCursor`). `size` capped at 100.
- Time: store UTC, expose ISO-8601 with explicit offset.

### Observability minimum
- Structured (JSON) logs; every request carries a request ID (accept `X-Request-Id` or generate), propagated and logged.
- `/health` liveness public (no dependency checks); detailed readiness non-public.
- 5xx and external-call failures log at ERROR with context (requestId, userId, masked params). Slow queries/calls log at WARN past a threshold.

### Graceful degradation
- Non-core dependency failure (recommendations, notifications) → default/skip and continue. Only core failures (payment, auth) fail the request.
- Every external call: timeout + capped exponential-backoff retry (idempotent paths only) + isolation (circuit breaker or queue).
- Graceful shutdown: on SIGTERM stop accepting, finish in-flight requests.

## §5 Enforcement Model (honest boundaries)

What the harness enforces **deterministically** (scripts and hooks, not prompts):

- Commit/push/PR are hook-blocked without clean evidence from every agent the risk tier requires.
- The risk tier is recomputed by the gate from the diff itself — it cannot be under-declared.
- Evidence can only be recorded by the review agent it belongs to — the hook verifies the caller's identity (`agent_type`). The orchestrator cannot forge it.
- Any file edit after a review changes the diff hash and voids that evidence.
- Security severity counts are parsed from the findings text by script, not self-reported; BLOCKER/MAJOR require fixes or an explicit human waiver on record.
- The state directory, loop-log, and harness files (hooks, settings, agent definitions) are write-protected against agents.
- Commit-pass telemetry is written by the gate hook itself.

What remains **prompt-level** (auditable, not physically impossible): an orchestrator could instruct a reviewer to do a shallow review. Every such prompt is in the session transcript and every report is in the loop-log — gaming the loop is discoverable, attributable, and pointless. Treat the harness as a seatbelt with a black box, not a cage.

## §6 Conventions Follow the Language

Each stack has its own idioms, formatters, and community standards — a koong backend in Go must read like Go, not like Java translated to Go. The detected stack's profile (`profiles/<stack>.md`) is authoritative for structure, naming, tooling, and framework usage. Read it before writing code; when in doubt, match the existing codebase first, the profile second.
