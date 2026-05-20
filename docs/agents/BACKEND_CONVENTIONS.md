# BACKEND_CONVENTIONS.md

> **This document is the single source of truth for Java/Spring Boot backend production code conventions.**
> Designed to work unchanged when copied into any project.
> Class names in code examples (`Order`, `Customer`, `Product`, etc.) use a generic domain — replace with your project's actual domain classes.
>
> For exact stack versions, domain models, and API contract details, refer to the project-specific spec.
> Test conventions → `TESTING.md` | git/PR conventions → `WORKFLOW.md` | tool guide & troubleshooting → `CLAUDE.md`

---

## 1. Technology Stack (General)

This document assumes a **Java + Spring Boot + Gradle** stack. For exact version numbers and additional dependencies, see the project-specific spec or README.

Common commands are in `CLAUDE.md` §2.2. Always use the **`./gradlew`** wrapper for build/test/formatting. Never use Maven (`mvn ...`).

---

## 2. Package Structure — Domain-Based (Recommended)

**Layer-based packages (`controller/`, `service/`, `repository/` at the top level) are not recommended.** As the project grows, domain cohesion breaks and boundaries blur. Use **domain-based package structure** instead.

```text
// The example below uses a generic e-commerce domain. Replace with your project's domain names.

com.example.
├── auth/             # Authentication (email / social / JWT)
├── user/             # User profile / settings
├── order/            # Orders
├── product/          # Products
├── inventory/        # Inventory
├── payment/          # Payments
├── shipping/         # Shipping
├── notification/     # Notifications
├── support/          # Customer support
├── admin/            # Admin
├── monitoring/       # Monitoring / health / metrics
├── scheduler/        # Schedulers
├── outbox/           # Transactional outbox
├── infra/            # Shared adapters
│   ├── idempotency/  # @Idempotent + aspect
│   ├── lock/         # Distributed lock
│   ├── async/        # AsyncConfig, executors
│   └── push/         # External push / messaging adapters
└── common/           # Shared response envelope, exceptions, principal
```

Each domain package is organized internally as follows (create only what is needed):

```
com.example.order/
├── controller/       # OrderController
├── service/          # OrderService (single class)
├── repository/       # OrderRepository, OrderItemRepository
├── entity/           # OrderEntity, OrderItemEntity
├── model/
│   ├── request/      # Input DTOs (record)
│   └── response/     # Output DTOs (record)
├── exception/        # Domain-specific exceptions (if any)
└── package-info.java # Package description
```

**Rules**:
- **No direct cross-domain dependencies.** Never import another domain's entity or repository directly.
- Cross-domain communication must go through **public service calls** or **outbox event publishing** only.
- Shared response/exception/principal lives in the project's `common` package. Never recreate these classes inside a domain.

---

## 3. Layer Responsibilities

### 3.1 Controller (HTTP Layer)
- `@RestController` + `@RequestMapping("/domain-root")`
- Responsibilities: HTTP I/O, input validation (`@Valid`), principal extraction, service delegation, response envelope wrapping
- **Forbidden**: business logic, transaction boundary declaration, direct repository calls
- Keep controllers thin.

### 3.2 Service (Business Logic Layer)
- `@Service` + `@RequiredArgsConstructor`
- Responsibilities: business rules, transaction boundaries, orchestrating repositories and external adapters
- **Transaction policy**:
  - Class-level default: `@Transactional(readOnly = true)`
  - Write methods: explicit `@Transactional`
- Always return **DTOs / records** — never return entities directly.

### 3.3 Repository (Persistence Layer)
- Spring Data JPA `JpaRepository` interface
- Responsibilities: read/write. **No business logic.**
- Complex queries: `@Query` + JPQL (native SQL only when truly necessary)
- Prevent N+1 with `@EntityGraph(attributePaths = {...})` or `JOIN FETCH` (see §10.2)

### 3.4 Entity (Persistence Model)
- `@Entity` + mapping annotations
- **Never expose directly in API responses** — always convert to DTOs first
- Lombok rules: see §4

### 3.5 Model (DTO)
- Separate into `request/` and `response/`
- **Use `record` by default** (immutable, auto equals/hashCode, compact constructor for validation)
- Only use `class + @Builder` when `record` is truly insufficient (e.g., builder pattern is essential)

---

## 4. Lombok Usage Rules

| Annotation | Service/Component | DTO (class) | Entity | Record DTO |
|---|---|---|---|---|
| `@RequiredArgsConstructor` | ✅ Required | — | — | — |
| `@Getter` | (usually unnecessary) | ✅ | ✅ | — (record auto) |
| `@Setter` | ❌ Forbidden | ❌ Forbidden | ❌ Forbidden in principle | — |
| `@Builder` | — | ✅ Recommended | ✅ Recommended | — |
| `@NoArgsConstructor` | — | (if JPA requires) | ✅ JPA requires | — |
| `@AllArgsConstructor` | — | (paired with Builder) | (paired with Builder) | — |
| `@Slf4j` | ✅ | — | — | — |
| **`@Data`** | ❌ | ⚠️ Discouraged (use record) | **❌ Strictly Forbidden** | — |
| `@EqualsAndHashCode` | — | — | (if needed, use `of = "id"` explicitly) | — |

**Key forbidden item**: **`@Data` on JPA Entity is strictly forbidden.**

Reason: `@Data`'s auto-generated `equals()`/`hashCode()` uses all fields, which triggers lazy loading proxies causing `LazyInitializationException`, and collection fields in hashCode calculations cause infinite loops and performance degradation. Entity `equals`/`hashCode` should be written explicitly using only the PK field.

---

## 5. Dependency Injection and Service Structure

### 5.1 Constructor Injection Required

**Field Injection (`@Autowired private XxxRepository ...`) is forbidden. Setter Injection is forbidden.** Always use:

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderService {
    private final OrderRepository orderRepository;
    private final OrderItemRepository orderItemRepository;
    private final OutboxEventPublisher outboxPublisher;
    // ...
}
```

Reasons: guarantees immutability (`final`), detects circular dependencies at startup, allows `new OrderService(mock, mock, mock)` instantiation in tests, official Spring and IDE recommendation.

### 5.2 Service Structure — Single Class by Default; Extract Interface Only for Multiple Implementations

**Default rule**: write regular business services as a **single class**. Do not create unnecessary `XxxService` interface + `XxxServiceImpl` split. It violates YAGNI and makes IDE navigation tedious.

```java
// ✅ Recommended
@Service
@RequiredArgsConstructor
public class ProductService {
    public Product findById(Long id) { ... }
}
```

**When an interface is justified**:
- **External provider/adapter** — when multiple real implementations exist, e.g., STT (Gemini/OpenAI), receipt verifier (Apple/Google), push provider (APNs/FCM), OAuth verifier (Google/Kakao/Apple), payment gateway (Stripe/Toss/KakaoPay).
- **When a Strategy pattern is clearly needed.**
- Use names that reveal intent: `XxxAdapter`, `XxxProvider`, `XxxVerifier`, `XxxStrategy`, etc.

```java
// ✅ Justified interface — genuinely multiple implementations
public interface PaymentGateway {
    PaymentResult charge(PaymentRequest request);
}

@Component
public class StripeGateway implements PaymentGateway { ... }

@Component
public class TossGateway implements PaymentGateway { ... }
```

---

## 6. Exception Handling

### 6.1 Exception Hierarchy (General Pattern)

Create a project-wide shared exception hierarchy. **Do not create separate base exceptions per domain.**

Recommended structure (names may vary per project):
- `<Project>Exception` (base, extends RuntimeException)
- `BusinessException` — business rule violations (insufficient balance, duplicate registration, etc.)
- `AuthException` — authentication/authorization
- `SystemException` — external system / infrastructure failures
- Each domain adds only domain-specific exceptions extending the above (e.g., `DuplicateEmailException extends BusinessException`)

Check `com.<project>.common.exception` for the actual base exception name in your project.

### 6.2 Global Handler

- Run a **single global handler** with `@RestControllerAdvice`. Never create per-domain handlers.
- New domain exceptions → add `@ExceptionHandler` to the global handler, or verify they are auto-mapped through the base exception.
- Never `try-catch` in controllers. Delegate all exceptions to the global handler.

### 6.3 Error Codes

- Use an `ErrorCode` enum. e.g., `AUTH_001`, `ORDER_002`, `PAYMENT_003`.
- Always return enum codes for client-side branching. Never let clients branch on message strings.

---

## 7. API Response (ApiResponse)

**Core rule**: all controllers use the **single project-wide response envelope class**. **Never create a new envelope per domain.**

Recommended envelope structure (field names may vary per project):

```text
- success: boolean              # true/false
- code: ErrorCode (enum)        # identifier
- message: String               # human-readable message
- data: T                       # payload (on success)
- errors: List<FieldError>      # validation errors (on failure)
```

```java
@RestController
@RequiredArgsConstructor
@RequestMapping("/orders")
public class OrderController {

    private final OrderService orderService;

    @PostMapping
    public ApiResponse<OrderResponse> create(@Valid @RequestBody OrderCreateRequest req,
                                             @AuthenticationPrincipal AuthenticatedPrincipal principal) {
        return ApiResponse.success(orderService.create(principal.userId(), req));
    }
}
```

Rules:
- All controller return types use `ApiResponse<T>` (except exceptional async/stream cases).
- Never return entities directly. Always convert to a DTO record.
- Error responses are built by the global handler. Never build them in a controller.
- Validation failure responses (`MethodArgumentNotValidException`) are also converted to the standard envelope by the global handler.

---

## 8. Input Validation

- Apply Bean Validation annotations to all controller input DTOs (`@NotNull`, `@NotBlank`, `@Email`, `@Size`, `@Min`, `@Max`, `@Pattern`, etc.).
- `@Valid` is required on controller method parameters.
- Business rules (e.g., insufficient balance, duplicate registration) are validated in the Service layer and throw a `BusinessException`.
- Record DTOs can normalize/validate additionally in the compact constructor.

```java
public record OrderCreateRequest(
        @NotNull Long customerId,
        @NotEmpty @Size(max = 50) List<OrderItemRequest> items,
        @Size(max = 500) String memo
) {
    public OrderCreateRequest {
        if (memo != null) {
            memo = memo.trim();
        }
    }
}
```

---

## 9. Transaction Policy

- Apply `@Transactional(readOnly = true)` as the **default at the class level** in services.
- Only **write methods** get an explicit `@Transactional`.
- Transaction boundaries belong in the Service layer. Never put `@Transactional` on controllers or repositories.
- When multiple domain operations need to be combined, do not import across domains — decouple via **outbox events**.
- Entities with optimistic locking (`@Version`) should use a retry helper on `OptimisticLockException`.

---

## 10. Database Rules (Required)

### 10.1 No-Lock Connection Tracking

- **Never UPDATE `users.last_login_at` on login.** This is a row-level write lock bottleneck.
- Track logins with INSERT-only `user_login_logs`.
- Apply the same principle to other "last activity" columns: use append-only log tables; use Redis/cache for frequently updated counters.

### 10.2 N+1 Prevention (Required)

Always use one of the following for 1:N relationship queries:
- `@EntityGraph(attributePaths = {"relation1", "relation2"})`
- JPQL `JOIN FETCH`
- Separate batch query + in-memory join

**Forbidden**: accessing lazy fields inside a loop. This is caught explicitly in code review.

```java
// ❌ Forbidden
orders.forEach(o -> o.getOrderItems().size());  // N+1

// ✅ Recommended
@Query("SELECT o FROM OrderEntity o LEFT JOIN FETCH o.orderItems WHERE o.id IN :ids")
List<OrderEntity> findAllWithItemsByIdIn(@Param("ids") List<Long> ids);
```

### 10.3 Indexes

- FK columns must have an index.
- Compound indexes for frequently queried column combinations (e.g., `(customer_id, order_date)`).
- Partial indexes to reduce index size by indexing only active rows.

### 10.4 Timestamps

- All timestamp columns use `TIMESTAMPTZ` (timezone-aware).
- At the application level, use `Instant` (UTC) or `OffsetDateTime` by default. Use `LocalDateTime` only when user-local time semantics are explicitly required.

---

## 11. Flyway Migrations

- Location: `src/main/resources/db/migration/`
- Filename: `V{number}__{snake_case_description}.sql` (e.g., `V42__add_order_status_index.sql`)
- **Never modify existing migration files.** Always add a new version number.
- DDL must follow §10 rules (soft delete, partial index, TIMESTAMPTZ, FK indexes).
- In multi-agent projects, each agent may have an assigned migration number range — check the project-specific document.
- Migration troubleshooting: see `CLAUDE.md` §3.2.

---

## 12. Security

- Passwords: BCrypt (`Spring Security BCryptPasswordEncoder`).
- JWT secrets, DB passwords, API keys, etc. must be **externalized to environment variables.** Never hardcode in yaml or code.
- Sensitive data (passwords, tokens, PII, payment info) must **not appear in logs, API responses, or external notifications** (Slack, Discord, etc.). Apply masking in logs.
- SQL: use JPA parameter binding. Never build SQL by string concatenation.
- Explicitly declare in `SecurityFilterChain` whether each new endpoint is public or protected.

---

## 13. Logging

- Use SLF4J + Logback. `System.out.println` / `e.printStackTrace()` are forbidden.
- Levels:
  - `ERROR` — system failure, external communication failure, data inconsistency
  - `WARN` — abnormal flow but auto-recoverable
  - `INFO` — key business events (registration, payment, notification sent, etc.)
  - `DEBUG` — detailed info for troubleshooting
- Sensitive info masking: email → `t***@example.com`, token → first 8 chars only, payment/SSN → never log.
- Use `@Slf4j`.

---

## 14. OpenAPI / Swagger

- Use Springdoc OpenAPI. Attach annotations to controllers:
  - Class: `@Tag(name = "domain", description = "...")`
  - Method: `@Operation(summary = "...", description = "...")`
  - Responses: `@ApiResponses(...)` (as needed)
- Use `@Schema(description = "...")` on DTO fields.
- Exclude non-public APIs (actuator, admin internals) from OpenAPI or put them in a separate group.

---

## 15. Code Formatting

- **Spotless + Google Java Format** (configured in `build.gradle`).
- Always run `./gradlew spotlessApply` immediately before committing.
- CI fails PR if `./gradlew spotlessCheck fails`.
- Import ordering, trailing whitespace removal, and newline enforcement are handled automatically by Spotless.

---

## 16. Post-Implementation Verification (Required)

After implementing a feature and completing the multi-agent test loop, run the comprehensive verification combo command to ensure formatting, compilation, tests, and coverage are all flawlessly ready:

```bash
./gradlew spotlessApply compileJava test jacocoTestReport
```

If any step fails, return to the implementation phase and adjust the production code. Do not bypass or force-pass checks.

---

## 17. File Header Comments

Add a one-line comment at the top of every new file explaining its role.

```java
// The example below uses a generic domain. Replace with your project's class names.

// OrderService: domain service responsible for order creation, retrieval, and cancellation.
// Created: 2026-05-20 (feat(order): implement order creation API)
```

Add brief comments near code headers explaining what a feature does and when it was implemented. **Avoid redundant or excessive comments** — omit where the code itself is clear enough.

---

## 18. Deprecated Rules (Do Not Follow)

The following rules from older guide documents are **incorrect by modern Java/Spring standards** or simply outdated:

- ❌ `@Data` on Entity → §4 forbidden
- ❌ Field Injection (`@Autowired private`) → §5.1 forbidden
- ❌ Forced Service interface + ServiceImpl split → §5.2 single class by default
- ❌ Maven usage → §1 Gradle only
- ❌ `result: String (\"SUCCESS\"/\"ERROR\")` ApiResponse format → §7 boolean + enum-based envelope
- ❌ UPDATE `users.last_login_at` on login → §10.1 append-only log
- ❌ Layer-based packages (`controller/`, `service/` at top level) → §2 domain-based
```