# Testing Doctrine

> Universal test rules for every stack. Framework specifics: see your stack profile §Testing.

---

## §1. Philosophy: FIRST

- **F**ast — the suite runs in seconds or minutes, never hours. Slow tests stop being run.
- **I**ndependent — every test passes alone and in any order. No test reads state another test wrote.
- **R**epeatable — same result on every machine, every timezone, every run. No flakiness tolerated: a flaky test is a failing test.
- **S**elf-validating — pass/fail is decided by assertions, never by a human reading logs.
- **T**imely — tests are written in the same task as the production code, before the task is declared done. "Tests later" means never.

---

## §2. The Iron Rule

> ## 테스트가 실패하면 프로덕션 코드를 고친다.
> ## When a test fails, fix the production code.

This is the #1 rule of this harness. A failing test is a signal that the product is wrong, not that the test is inconvenient.

**NEVER**, under any circumstances:
- weaken an assertion to make it pass (`toBe(3)` → `toBeGreaterThan(0)`),
- delete or comment out a failing test,
- mark it skipped/disabled to get a green run,
- change the expected value to whatever the broken code currently returns.

```text
❌ Test expects fee = 250, code returns 300
   → change the test to expect 300           # laundering a bug into green
✅ Test expects fee = 250, code returns 300
   → find why the fee calculation drifted and fix the calculation
```

The only time a test itself may be changed is when the **specification** changed and the test now asserts outdated behavior — and then the change must be explained in the commit. If you are stuck after multiple genuine fix attempts, report the failure honestly; do not launder it into green.

---

## §3. Coverage Targets

- **80%** line coverage overall (enforced by the project's coverage gate).
- **100%** for money movement, auth/authz decisions, and balance/amount calculation paths — a missed branch here is an incident, not a gap.
- **Exception paths must be covered**: every custom exception a service can throw has at least one test asserting the exception type/error code.
- Generated code, framework config, and pure DTO/schema declarations are excluded from the metric — do not pad coverage with tests of getters.
- Coverage is a floor, not a goal: 80% of the right things beats 95% of trivia.

---

## §4. Structure

- Every test reads as **Given-When-Then**, with the three blocks separated by blank lines. Comments (`// Given`) are optional; the blank-line rhythm is not.
- **One behavior per test.** If the name needs "and", split it.
- **Names state condition + expected result**, so the failure report reads as a specification:
  - ❌ `testCreateOrder`, `it('works')`
  - ✅ `createOrder_insufficientStock_throwsBusinessError`, `it('returns 403 when a member edits another member\'s post')`

```text
test "creating an order for an out-of-stock product raises INSUFFICIENT_STOCK":
    # Given
    product = aProduct(stock: 0)
    repository.willReturn(product)

    # When / Then
    expect createOrder(customerId, [item(product.id, qty: 1)])
        to raise BusinessError with code INSUFFICIENT_STOCK
```

---

## §5. What to Test per Layer

**Business logic (services/domain):**
- Happy path with side-effect verification (what was saved, what event was published — verify key collaborator calls, not trivia).
- Every business rule violation: insufficient balance, duplicates, invalid state transitions.
- Exception **type and error code**, not just "it throws".

**Persistence:**
- Constraints actually enforced: unique indexes (including partial/soft-delete variants), FK behavior.
- Soft-delete filters: deleted rows excluded from default queries, reachable by the explicit bypass query.
- N+1 checks on list queries with relations (statement-count assertions or query logs).

**API:**
- Status codes per branch: success, validation failure, unauthenticated, forbidden, not found.
- Response envelope shape on both success and error — clients depend on it.
- Validation failures return the standard error format with field-level detail.
- **Authorization branching is mandatory**: 401 without credentials, 403 for the wrong role, and **404 (not 403) for another user's resource** where the project hides existence — assert whichever contract the project defines, per endpoint.

---

## §6. Absolute Prohibitions

- ❌ **Test order dependence** — any shared sequence coupling between tests.
- ❌ **Real external API calls** — payment, email, push, LLM, third-party HTTP. Always fake/mock at the boundary.
- ❌ **Sleep-based waiting** — no fixed sleeps around async work; use explicit condition waits or fake clocks.
- ❌ **Hardcoded absolute paths** — breaks on every other machine and in CI.
- ❌ **Shared mutable state without cleanup** — DB rows, static/global variables, temp files must be rolled back or torn down after each test.
- ❌ **Unexplained skipped tests** — every skip carries a reason and a TODO with an owner; a bare skip is a deleted test in disguise.

---

## §7. Test Data

- Build fixtures through **factory functions** (`aUser()`, `anOrder()`) with **valid-minimum defaults**: the smallest data that passes validation. Tests override only the fields they care about — that override *is* the documentation of what the test is about.

```text
❌ Every test builds a full user inline (12 fields of noise, 1 field of intent)
✅ aUser(email: "dup@example.com")   # everything else is the valid minimum
```
- **Deterministic time**: production code under test never calls `now()` directly; it uses an injected clock/time source, and tests fix it to a known instant. A test that fails at midnight or month-end is a design bug.
- **Deterministic randomness**: inject or seed random sources (IDs, tokens, shuffles) so failures are reproducible.

---

## §8. Edge Cases (Required Checklist)

Every feature's test set must cover the applicable items:

- **Boundaries**: 0, 1, max, max+1, negative — especially on quantities, amounts, and limits.
- **Empty/null inputs**: empty string, empty collection, absent optional fields.
- **Duplicates & concurrent submission**: double-click/retry scenarios — unique constraint violations surface as the defined business error; idempotency keys process once.
- **Pagination limits**: page 0/last/beyond-last, page size at and above the cap.
- **Unicode & long strings**: multi-byte text (한글, emoji), strings at and past the length limit.

If an item genuinely does not apply, skip it knowingly — not by forgetting.
