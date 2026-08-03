# koong Security Doctrine (security.md)

> **The single security standard every koong agent follows when writing and reviewing code.**
> Rule ID scheme: `SEC-N` (absolute rules) / `SEC-A` (authn·authz) / `SEC-I` (input) / `SEC-D` (data·dependencies)
> / `SEC-S` (secrets) / `SEC-E` (external calls) / `SEC-P` (payments·money) / `SEC-M` (migrations) / `SEC-O` (ops·infra).
> Every security finding MUST cite a rule ID. A real issue with no matching rule → report as `SEC-X` (doctrine gap).
> Stack-specific library choices: §C table + your stack profile §Security.

---

## A. Absolute Rules — violation is always a BLOCKER

| ID | Rule |
|---|---|
| SEC-N1 | Every endpoint declares public/protected **explicitly in code**. Never rely on framework defaults. |
| SEC-N2 | Every user-facing path that reads/writes a resource by ID enforces **ownership (or tenant membership) server-side**. |
| SEC-N3 | Secrets (JWT keys, DB passwords, API keys) are **never committed** — not in code, not in yaml, not in `.env` files in git. Env vars / secret manager only. |
| SEC-N4 | SQL / shell commands / file paths are **never built by string concatenation with user input**. Parameter binding only. |
| SEC-N5 | Passwords are stored with **BCrypt/Argon2/scrypt only**. Reversible or fast-hash storage (MD5/SHA-x/plaintext) is forbidden. |
| SEC-N6 | **Amounts are recomputed server-side** from DB prices. Client-supplied amounts, prices, and discounts are never trusted. |
| SEC-N7 | Every money-moving path (payment, transfer, points) uses an **idempotency key + a single transaction**. |
| SEC-N8 | Stack traces, internal exception messages, and raw external-API responses are **never returned to clients**. |
| SEC-N9 | PII (email, phone, card, tokens, 주민번호) **never appears unmasked in logs**. Masking table: §B-Data D1. |
| SEC-N10 | Applied migration files are **never edited**. Data-destroying DDL is forbidden without a documented backup/backfill plan. |

---

## B. Checklists by Domain

### Authentication & Authorization (SEC-A)

- **A1** Every new/changed route: is it registered in the security config (filter chain / middleware / route guard)? Is its public/protected intent explicit? Default-open frameworks (Express, FastAPI, plain Go handlers) get extra suspicion.
- **A2** Public allowlist is limited to: login, signup, token refresh, health, API docs. Anything else public needs a stated reason.
- **A3** IDOR: handlers taking an ID (path/query/body) use `findByIdAndUserId(...)`-style queries or explicit `resource.ownerId == principal.id` comparison. `findById(id)` alone in a user-facing path is the #1 beginner miss.
- **A4** Privilege escalation via mass assignment: request bodies must never bind `role` / `isAdmin` / `grade` / `balance` fields. Whitelist DTOs only (strict schemas: `extra="forbid"`, `.strict()`, explicit DTO fields).
- **A5** JWT: algorithm pinned in code (never trust the token's `alg` header), `exp` required (access token ≤ 1h recommended), HS256 secret ≥ 256 bits, zero code paths that skip signature verification.
- **A6** Refresh tokens: single-use rotation + reuse detection (reuse → invalidate the whole session family), stored server-side as a hash.
- **A7** Login / password-reset / verification-code endpoints: rate limiting or attempt caps + code expiry. No unlimited tries.
- **A8** Login failure responses are a single message ("아이디 또는 비밀번호가 올바르지 않습니다") — never reveal whether the account exists.
- **A9** Session-based auth: regenerate session ID on login, server-side invalidation on logout, `STATELESS` policy when JWT-based.

### Input Validation (SEC-I)

- **I1** Every request DTO has validation (annotations/schema) including **length upper bounds**.
- **I2** File uploads: extension AND magic-byte double check, size limit, server-generated filename (UUID), stored outside web root or in object storage.
- **I3** Path traversal: user input entering a file path → normalize, then verify it stays under the base directory.
- **I4** Pagination params: `size` upper bound (≤ 100), negatives rejected.
- **I5** Request body size limit at server level (1–10MB typical) — JSON-bomb defense.

### Data (SEC-D)

- **D1** Log masking table: email `t***@x.com` / phone `010-****-1234` / token first 8 chars / card & 주민번호 never logged.
- **D2** Dependency audit runs at the PR gate (§E commands). critical = BLOCKER, high = MAJOR. Tool missing ≠ silent pass — report `[MINOR] 감사 도구 미설정 (SEC-D2)`.
- **D3** Soft-deleted rows are consistently excluded from queries and aggregates (a forgotten filter is an authz bypass).
- **D4** API response DTOs contain no internal fields (password hashes, internal flags, other users' data).

### Secrets (SEC-S)

- **S1** Env-var injection + fail-fast startup validation that required secrets exist.
- **S2** `.gitignore` covers `.env*`, `*.pem`, `*.p12`. **A committed secret has exactly one fix: rotation.** Deleting from history is not sufficient.
- **S3** Test code uses obvious dummies (`test-secret-do-not-use`) — never realistic-looking keys.

### External Calls (SEC-E)

- **E1** Every outbound call has explicit connect/read timeouts.
- **E2** Fetching user-supplied URLs (SSRF): https only, host allowlist, private-IP block (`10.` `172.16.` `192.168.` `169.254.` `localhost`), re-validate after redirects.
- **E3** Webhook receivers: HMAC signature verification + timestamp check + idempotent processing.
- **E4** External failure must not cascade: retry (exponential backoff, capped, idempotent paths only), circuit breaker or outbox isolation.

### Payments & Money (SEC-P)

- **P1** Amount/currency recomputed server-side (SEC-N6). Discounts and coupons validated server-side too.
- **P2** Idempotency key: client-generated UUID stored under a unique constraint; duplicate requests return the original result.
- **P3** Balance mutation is a conditional UPDATE (`WHERE balance >= ?`, affected-rows check) or a lock — inside one transaction.
- **P4** Money types: `BigDecimal` / integer minor units / `decimal`. `float`/`double` forbidden.
- **P5** PG webhooks: verify signature, then **reconcile the paid amount against the order amount** before changing state.
- **P6** Refunds/cancellations are idempotent and verify ownership of the original transaction.

### Migrations (SEC-M)

- **M1** `DROP COLUMN/TABLE`, type narrowing, data `DELETE` → forbidden without a documented backup/backfill plan.
- **M2** Adding `NOT NULL` is 3 steps: add nullable → backfill → add constraint.
- **M3** Index creation on large tables uses `CREATE INDEX CONCURRENTLY` (Postgres) or equivalent.
- **M4** Never edit an applied migration file — new versions only (SEC-N10).

### Infra & Ops (SEC-O)

- **O1** CORS: explicit origin list. `*` + credentials forbidden. Reflecting the request Origin forbidden.
- **O2** Actuator/debug/admin endpoints are non-public (only basic health is public; detailed readiness requires auth).
- **O3** Production config re-check: DEBUG logs off, SQL logs off, API docs exposure reconsidered.
- **O4** Security headers somewhere in the chain (app or proxy): HSTS, X-Content-Type-Options, frame blocking.

---

## C. Per-Stack Implementation Table

| Area | Spring Boot | FastAPI/Python | Next.js/Node | Go |
|---|---|---|---|---|
| Auth skeleton | `SecurityFilterChain` + JWT filter | `Depends(get_current_user)` | `middleware.ts` + jose | router middleware + golang-jwt/v5 |
| Password hash | `BCryptPasswordEncoder` | `passlib[bcrypt]` / argon2-cffi | `bcrypt` | `x/crypto/bcrypt` |
| JWT parse | jjwt 0.12+ `verifyWith` | PyJWT `decode(algorithms=[...])` | jose `jwtVerify` (alg pinned) | `ParseWithClaims` + `WithValidMethods` |
| Input validation | Jakarta `@Valid` DTO | Pydantic v2 `extra="forbid"` | zod `.strict()` | validator tags + manual |
| SQL safety | JPA/QueryDSL binding | SQLAlchemy binding | Prisma/Drizzle (avoid raw) | `database/sql` placeholders |
| Rate limit | bucket4j / gateway | slowapi | `@upstash/ratelimit` / middleware | `x/time/rate` |
| CORS | `CorsConfigurationSource` | `CORSMiddleware` explicit | route/middleware explicit | rs/cors explicit |
| Secrets | env + `@ConfigurationProperties` | pydantic-settings | zod-parsed `process.env` | envconfig + startup check |
| Dep audit | gradle OWASP dependencyCheck | pip-audit | `npm audit --omit=dev` | govulncheck |

---

## D. Beginner Traps Top-15 (❌/✅)

1. Checking the ID but not the owner — ❌ `findById(orderId)` ✅ `findByIdAndUserId(orderId, me)` (SEC-A3)
2. New controller, forgot the security config — ❌ implicitly public ✅ route addition + security config update as one atomic change (SEC-A1)
3. Binding the entity straight from the request body — ❌ `save(userEntity)` ✅ whitelist DTO → map (SEC-A4)
4. JWT secret in yaml — ❌ `secret: mySecretKey123` ✅ `${JWT_SECRET}` + startup validation (SEC-N3)
5. Access token with no/huge expiry — ❌ no `exp` ✅ access 30m–1h + refresh rotation (SEC-A5/A6)
6. Charging the client-sent price — ❌ `pay(req.amount)` ✅ `pay(priceFromDb(product) * qty)` (SEC-N6)
7. Double charge on retry — ❌ plain INSERT ✅ idempotency key with unique constraint (SEC-P2)
8. Race between balance check and deduction — ❌ `if (balance >= x) { balance -= x }` ✅ `UPDATE ... WHERE balance >= x`, fail on 0 rows (SEC-P3)
9. `catch (e) { return e.message }` — ❌ internals leak ✅ error code + generic message; details go to server logs (SEC-N8)
10. `log.info("user={}", user)` dumping PII — ✅ log userId only, mask the rest (SEC-N9)
11. CORS `*` with credentials — ✅ explicit origin list (SEC-O1)
12. Storing uploads under the original filename — ❌ `../../shell.jsp` ✅ UUID name + extension allowlist + magic bytes (SEC-I2)
13. Unlimited password-reset code attempts — ✅ 5-attempt cap + 10-minute expiry (SEC-A7)
14. Server fetching a user-supplied URL as-is (SSRF) — ✅ allowlist + private-IP block (SEC-E2)
15. Dropping a column in one shot — ✅ deprecate → backfill/verify → drop in a later version (SEC-M1)

---

## E. Scripted Gates (deterministic — tools decide, agents translate)

Run at **PR level** by koong-verifier; output goes to `.koong/audit/<sha>.log`; security-auditor maps results to findings.

**Secret scan (every PR, stack-independent):**
```bash
# preferred
gitleaks detect --source . --log-opts="<base>..HEAD" --no-banner --exit-code 1
# fallback heuristic on the diff
git diff <base>...HEAD -U0 | grep -nEi \
  '(api[_-]?key|secret|passwd|password|token|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|eyJhbGciOi'
```
Any hit → `[BLOCKER] (SEC-S2)` with the note: **rotation required**.

**Dependency audit (PR level only — too slow per commit):**

| Stack | Command | BLOCKER | MAJOR |
|---|---|---|---|
| node-nextjs | `npm audit --omit=dev --json` | critical > 0 | high > 0 |
| python | `pip-audit` (via `pipx run pip-audit` if absent) | fixable critical | high |
| java-spring | `./gradlew dependencyCheckAnalyze` if plugin present; else report `[MINOR] 도구 미설정 (SEC-D2)` — never fake results | CVSS ≥ 9 | CVSS 7–9 |
| go | `govulncheck ./...` (reachable vulns only) | reachable critical | any reachable |

---

## F. Severity Rubric & Waivers

- **BLOCKER** — any one of: exploitable by an unauthenticated attacker or against *another user's* data/money (IDOR, missing authz, injection, privilege mass-assignment); money integrity broken (client-trusted amount, missing idempotency on a charge path, non-atomic balance mutation); committed secret; JWT signature/expiry not actually enforced; data-destroying migration without a plan; critical dependency vuln.
- **MAJOR** — exploitable under conditions or missing defense-in-depth on a sensitive path: no login rate limit, broad CORS, stack-trace leakage, unmasked PII logs, missing external-call timeouts, upload gaps without direct RCE, high dependency vulns.
- **MINOR** — hardening/hygiene: security headers, verbose non-sensitive errors, moderate dep vulns, pre-existing (`[기존]`) findings.
- Tie-break: *"If a Toss security reviewer would block the deploy → BLOCKER. Demand a fix in this PR → MAJOR. A follow-up ticket suffices → MINOR."*
- No speculative findings: every finding needs a concrete 실패 시나리오 (specific input → wrong outcome).

**Waivers**: security BLOCKER/MAJOR findings are **never auto-relaxed** by the commit loop. The only path past an unresolved one is an explicit human waiver: the user states "SEC-xx 위험 수용", and the agent records the rule ID + reason + date in `.koong/security-waivers.md` (committed, auditable). The git gate accepts a waived rule ID.
