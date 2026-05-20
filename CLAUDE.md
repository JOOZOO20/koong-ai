# CLAUDE.md

> **This document is a universal guide covering project auto-discovery, the user's standard tool stack, and common troubleshooting patterns.**
> Designed to work unchanged when copied into any project.
> Project-specific domain knowledge does not belong here — the agent discovers it by reading the project's own files via the §1 auto-discovery procedure.

---

## §1. Project Context Auto-Discovery Procedure

Before starting any task, the agent **always runs the following procedure to understand the current project context**. Running it once at the start of a conversation is sufficient (do not repeat within the same conversation).

### 1.1 Required Scans (Always Run These 4)

1. **`README.md`** — Understand the project's purpose, stack, and basic run instructions.
2. **Project-specific documents** — Read any of the following that exist (skip if absent):
   - `docs/agents/PROJECT.md` or `docs/agents/V2_PROJECT.md` or equivalent — progress, multi-agent ownership, project-specific conventions
   - `*backend_spec*.md`, `*backend-spec*.md`, `*technical_spec*.md` — stack versions, domain model, API contracts
   - `*prd*.md`, `*function_prd*.md`, `*requirements*.md` — functional requirements
   - `*frontend*.md` — frontend plan (for frontend tasks)
3. **`build.gradle`** (or `build.gradle.kts` / `pom.xml` / `package.json`) — Verify actual dependency versions and build configuration.
4. **`src/main/resources/application*.yml`** (or equivalent config) — Check active profiles, externalized config, and enabled features.

### 1.2 Recommended Scans (Run When Relevant)

These help quickly understand the domain structure. Run only when the task relates to the relevant area.

- **Package structure** — `find src/main/java -type d | head -50` to list domain packages.
- **`package-info.java` files** — `find src/main/java -name 'package-info.java' -exec cat {} \;` to read package purpose descriptions.
- **Latest 5 migrations** — `ls -lt src/main/resources/db/migration | head -10` to understand recent schema changes.
- **OpenAPI docs** — Check API contracts if `/v3/api-docs` or Swagger UI is enabled.
- **1–2 existing controllers/services** — Read code similar to the target domain to understand coding style and patterns.

### 1.3 Post-Discovery Report (Optional)

Before starting large tasks, or when the user explicitly requests it, summarize the discovered context and confirm with the user:

```
[Project Context Discovery Result]
- Project: <name from README>
- Stack: <stack from build.gradle / spec>
- Package structure: <domain-based / layer-based>
- Progress: <current phase from PROJECT.md>
- Work area: <domain related to the user's request>
Is it OK to proceed with this understanding?
```

May be skipped for routine single-task work (routing table alone is sufficient).

### 1.4 Absolute Rules

- This document (`CLAUDE.md`) contains **only the general guide for the user's standard tool stack**. **Do not add project-specific domain knowledge here** — that belongs in the project-specific documents read by §1.1.
- When copying this document to a new project, keep §1 unchanged. Update §2–§3 only if the new project uses a different stack.

---

## §2. User's Standard Tool Stack Guide

[MODULARITY NOTE: This section defines the primary tech stack infrastructure. For project-specific details, versions, and specialized configurations, always defer to `docs/agents/v2-project.md`. If this framework is applied to a different stack ecosystem (e.g., Node.js, Python, Go), swap the contents of §2.1 and §2.2 with the corresponding discovery guidelines.]

### 2.1 Standard Stack (Abstract Definition)

Refer to `docs/agents/v2-project.md` for the active programming language, framework versions, database vendor, and precise migration tool configuration used in this repository.

### 2.2 Common Commands

#### Build & Run
```bash
./gradlew build                                    # Full build + tests
./gradlew clean build -x test                      # Clean build without tests
./gradlew bootRun                                  # Run with default profile
./gradlew bootRun --args='--spring.profiles.active=local'   # Run with specific profile
```

#### Test & Coverage
```bash
./gradlew test                                     # Run all tests
./gradlew test --tests "com.example.order.*"       # Run by package
./gradlew test --tests "*PaymentTest"              # Run by class name pattern
./gradlew test --info                              # Verbose logs
./gradlew test --rerun-tasks                       # Force re-run ignoring cache
./gradlew jacocoTestReport                         # Coverage report (HTML: build/reports/jacoco/test/html/index.html)
./gradlew jacocoTestCoverageVerification           # Verify 80% threshold
```

#### Formatting
```bash
./gradlew spotlessApply                            # Apply formatting (required before commit)
./gradlew spotlessCheck                            # Check formatting (for CI)
```

#### Docker
```bash
docker build -t <image-name> .                     # Build image
docker run --rm -p 8080:8080 <image-name>          # Run container (--rm needs prior approval per AGENTS.md §3.2)
docker compose up -d                               # Start compose in background
docker compose logs -f <service>                   # Follow logs
```

#### Database (PostgreSQL)
```bash
psql -h localhost -U <user> -d <database>          # Connect
\dt                                                # List tables
\d+ <table>                                        # Show table details
SELECT * FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 10;  # Migration history
```

### 2.3 Flyway Migration Rules (General)

- Location: `src/main/resources/db/migration/`
- Filename: `V{number}__{snake_case_description}.sql` (e.g., `V42__add_order_status_index.sql`)
- **Never modify existing migration files.** Always add a new version number.
- Application order follows the number in the filename. Duplicate numbers are not allowed.
- Use `baseline-on-migrate=true` to join an already-running DB.
- Migrations that may cause data loss (column drop, data delete) require a backup/validation plan and separate review.

See `BACKEND_CONVENTIONS.md` §11 for detailed DB rules (soft delete, partial index, TIMESTAMPTZ, FK indexes).

### 2.4 Spring Profile Policy (General)

- `application.yaml` — Common config + default profile
- `application-local.yaml` (or `application-dev.yaml`) — Local development
- `application-test.yaml` — Tests (H2, Flyway disabled recommended)
- `application-prod.yaml` — Production (externalized env vars)
- Secrets (JWT secret, DB password, API keys) must never be hardcoded in yaml or code — use env vars or an external secret manager.

### 2.5 Docker / GitHub Actions (General)

- `Dockerfile` should use multi-stage builds (build stage → runtime stage).
- Specify `linux/amd64` platform explicitly (required when building on Apple Silicon for x86 servers).
- GitHub Actions workflows live under `.github/workflows/`.
- Use GitHub Actions secrets or OIDC role assumption for credentials. Never hardcode in code.

---

## §3. Common Troubleshooting Patterns

> General debugging patterns for Java/Spring Boot projects. For project-specific edge cases, refer to the project-specific document discovered in §1.

### 3.1 JWT / Spring Security Authentication Issues

| Symptom | Suspect |
|---|---|
| 401 Unauthorized — all requests | `SecurityFilterChain` `authorizeHttpRequests` config; `JwtAuthenticationFilter` not registered in chain |
| 403 Forbidden — specific requests | `@PreAuthorize`, `hasRole/hasAuthority` logic; principal missing required authority |
| Token sent but not authenticated | `Authorization: Bearer <token>` header format; token subject doesn't match `UserDetails.username` |
| Expired token still passes | Server NTP clock drift; `JwtParser` expiry validation not enabled |
| Login works but next request breaks | `SecurityContext` not stateless (`SessionCreationPolicy.STATELESS`); CORS config |

Debugging tips:
- Add `log.debug` to `JwtAuthenticationFilter` to trace token subject / extracted username / `loadUserByUsername` result.
- Enable `logging.level.org.springframework.security=DEBUG` in `application.yml` for detailed security chain logs.

### 3.2 Flyway Migration Issues

| Symptom | Action |
|---|---|
| Fails when joining an existing DB | `flyway.baseline-on-migrate=true`, `flyway.baseline-version=<last applied version>` |
| Checksum mismatch after migration | **Never edit existing migration files.** Force-updating checksums in `flyway_schema_history` is a production incident waiting to happen. Fix with a new migration. |
| Duplicate version number | Conflict. Renumber one of them. |
| Migration takes too long | Use `CREATE INDEX CONCURRENTLY` (Postgres) for index creation; schedule large table changes in a maintenance window. |
| Applied but `validate` fails | Consider `flyway repair` (use with extreme caution in production). |

Verification query:
```sql
SELECT * FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 20;
```

### 3.3 Soft Delete Pattern (General)

Many projects use soft delete instead of hard delete for users and key domains. General pattern:

- `is_deleted` (boolean) + `deleted_at` (timestamp) columns.
- `@SQLDelete` to intercept DELETE queries and convert them to UPDATE.
- `@SQLRestriction` or `@Where` to automatically exclude soft-deleted rows from default queries.
- Provide a `findByXxxIncludingDeleted()` method to bypass the filter for re-registration/recovery scenarios.
- Use a **partial unique index** (`WHERE deleted_at IS NULL`) for unique constraints — allows re-registration with an email after account deletion.

Common pitfalls:
- `findById` on a soft-deleted row is intercepted by `@SQLRestriction` and returns not-found.
- Inconsistent soft-delete inclusion in count queries causes business logic bugs.

### 3.4 Suspected N+1 Query

Symptom: List API response is unusually slow. Logs show the same SELECT repeating N times.

Steps:
1. Enable `org.hibernate.SQL=DEBUG` + `org.hibernate.orm.jdbc.bind=TRACE` to see actual queries.
2. The typical culprit: lazy relationship on a 1:N association called in a loop via `getXxxList()`.
3. Fix: `@EntityGraph(attributePaths = {...})`, JPQL `JOIN FETCH`, or a separate batch query.
4. See `BACKEND_CONVENTIONS.md` §10.4 for detailed rules.

### 3.5 Transaction Misbehavior

| Symptom | Suspect |
|---|---|
| `@Transactional` seems to have no effect | Applied to private method / self-invocation in same class / final class (proxy not created) |
| `LazyInitializationException` | Accessing lazy collection outside transaction — fetch or convert to DTO inside the service |
| Rollback not happening | `@Transactional(rollbackFor = ...)` not specified — default rolls back only `RuntimeException`; checked exceptions need explicit config |
| Write attempt on read-only transaction | Class-level `readOnly=true` default; method needs its own `@Transactional` for write operations |

### 3.6 External System Integration (Email, Push, Payment, etc.)

- All external calls **must have a timeout configured.** Indefinite waits cause production outages.
- Critical paths (payment, SMS, email) need an **idempotency key** to prevent duplicate processing.
- Do not let external system failures cascade into full system failures — isolate with circuit breaker, fallback, or message queue (outbox).
- Never expose external system responses directly to the client (risk of stack trace / internal ID leakage).

### 3.7 Environment Variables / Secrets

| Symptom | Check |
|---|---|
| Works locally, fails in production with NPE / auth failure | Verify env vars are actually injected in production (`echo $VAR` inside the container) |
| `${VAR}` placeholder in yaml not resolved | Env var name typo; active profile not set |
| Password printed in logs | `logging.level` in `application.yml`; entity `toString()` exposing fields — check `@ToString.Exclude` |

### 3.8 Build / Dependency Issues

| Symptom | Action |
|---|---|
| `./gradlew build` behaving unexpectedly with cache | `./gradlew --no-build-cache clean build` or clear `~/.gradle/caches/` (time-consuming) |
| Spotless auto-fix differs from intent | Check `.editorconfig` matches Spotless config; check IDE auto-format conflict |
| Tests pass individually but fail together | Shared state between tests (`@DirtiesContext`, static variables, missing DB cleanup) |
| OOM only in CI | Gradle daemon memory (`org.gradle.jvmargs`), JVM heap (`-Xmx`) tuning |

---

## §4. Copying This Document to a New Project

After copying `CLAUDE.md` to the root of a new project:

1. **Keep §1 unchanged** — it works for any project.
2. **§2.1 Standard Stack** — replace if the new project uses a different stack (e.g., Python/Node); keep as-is for same stack.
3. **§2.2 Command examples** — replace if different stack; keep as-is otherwise.
4. **§3 Troubleshooting** — applies as-is for the same stack; replace with relevant patterns for a different stack.
5. **Never add project-specific domain knowledge to this document** — put it in `docs/agents/PROJECT.md` (or equivalent) and let §1.1 auto-scan it.