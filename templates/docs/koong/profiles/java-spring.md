# Java / Spring Boot Profile

> Loaded only when the project stack is detected as java-spring (build.gradle / build.gradle.kts / pom.xml present).
> Universal principles live in core-principles.md; security doctrine in security.md; testing doctrine in testing.md. This file adds ONLY Java/Spring-specific rules.
> Class names in code examples (`Order`, `Customer`, `Product`, etc.) use a generic domain — replace with the project's actual domain classes.

---

## §1 Stack & Commands

Assumed stack: **Java + Spring Boot + Gradle**. Always use the **`./gradlew`** wrapper. Never use Maven (`mvn ...`). For exact versions and dependencies, read `build.gradle` (or `build.gradle.kts`) and the project spec.

```bash
# Build & Run
./gradlew build                                    # Full build + tests
./gradlew clean build -x test                      # Clean build without tests
./gradlew bootRun --args='--spring.profiles.active=local'   # Run with specific profile

# Test & Coverage
./gradlew test                                     # Run all tests
./gradlew test --tests "com.example.order.*"       # Run by package
./gradlew test --tests "*PaymentTest"              # Run by class name pattern
./gradlew test --info                              # Verbose logs
./gradlew test --rerun-tasks                       # Force re-run ignoring cache
./gradlew jacocoTestReport                         # Coverage report (HTML: build/reports/jacoco/test/html/index.html)
./gradlew jacocoTestCoverageVerification           # Verify 80% threshold

# Formatting
./gradlew spotlessApply                            # Apply formatting (required before commit)
./gradlew spotlessCheck                            # Check formatting (for CI)

# Database (PostgreSQL)
psql -h localhost -U <user> -d <database>          # Connect (\dt list tables, \d+ <table> details)
SELECT * FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 10;  # Migration history
```

### Post-Implementation Verification Combo (Required)

After implementing a feature and completing the test loop, run:

```bash
./gradlew spotlessApply compileJava test jacocoTestReport
```

If any step fails, return to implementation and fix the production code. Do not bypass or force-pass checks.

---

## §2 Package Structure — Domain-Based

**Layer-based packages (`controller/`, `service/`, `repository/` at the top level) are forbidden.** Use domain-based packages:

```text
com.example.
├── auth/             # Authentication (email / social / JWT)
├── user/             # User profile / settings
├── order/            # Orders  (…one package per business domain: product, payment, notification, admin, …)
├── monitoring/       # Monitoring / health / metrics
├── scheduler/        # Schedulers
├── outbox/           # Transactional outbox
├── infra/            # Shared adapters (idempotency, lock, async, push)
└── common/           # Shared response envelope, exceptions, principal
```

Each domain package internally (create only what is needed):

```text
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

Rules:
- **No direct cross-domain dependencies.** Never import another domain's entity or repository.
- Cross-domain communication goes through **public service calls** or **outbox event publishing** only.
- Shared response/exception/principal lives in `common`. Never recreate these classes inside a domain.
- Add a one-line header comment at the top of every new file explaining its role (e.g., `// OrderService: domain service responsible for order creation, retrieval, and cancellation.`). Avoid redundant comments where code is clear.

---

## §3 Layer Responsibilities

### Controller (HTTP Layer)
- `@RestController` + `@RequestMapping("/domain-root")`
- Responsibilities: HTTP I/O, input validation (`@Valid`), principal extraction, service delegation, response envelope wrapping.
- **Forbidden**: business logic, transaction boundaries, direct repository calls, `try-catch` (delegate to the global handler). Keep controllers thin.

### Service (Business Logic Layer)
- `@Service` + `@RequiredArgsConstructor`
- Responsibilities: business rules, transaction boundaries, orchestrating repositories and external adapters.
- Class-level default `@Transactional(readOnly = true)`; write methods get an explicit `@Transactional`.
- Always return **DTOs / records** — never entities.

### Repository (Persistence Layer)
- Spring Data JPA `JpaRepository` interface. Read/write only — **no business logic**.
- Complex queries: `@Query` + JPQL (native SQL only when truly necessary).
- Prevent N+1 with `@EntityGraph(attributePaths = {...})` or `JOIN FETCH` (§7).

### Entity (Persistence Model)
- `@Entity` + mapping annotations. **Never expose directly in API responses** — always convert to DTOs.

### Model (DTO)
- Separate into `request/` and `response/`. **Use `record` by default** (immutable, auto equals/hashCode, compact constructor for validation). Use `class + @Builder` only when record is truly insufficient.

---

## §4 Java Idioms

### 4.1 Lombok Rules

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
| `@EqualsAndHashCode` | — | — | (if needed, `of = "id"` explicitly) | — |

**`@Data` on a JPA Entity is strictly forbidden**: its auto-generated `equals()`/`hashCode()` uses all fields, triggering lazy-loading proxies (`LazyInitializationException`) and infinite loops on collection fields. Write entity `equals`/`hashCode` explicitly using only the PK.

### 4.2 Constructor Injection Required

Field injection (`@Autowired private ...`) and setter injection are **forbidden**.

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderService {
    private final OrderRepository orderRepository;
    private final OutboxEventPublisher outboxPublisher;
}
```

Reasons: immutability (`final`), circular dependencies detected at startup, `new OrderService(mock, mock)` in tests, official Spring recommendation.

### 4.3 Single-Class Services — No ServiceImpl Split

Write business services as a **single class**. Do not create `XxxService` interface + `XxxServiceImpl` — it violates YAGNI. An interface is justified only when **multiple real implementations exist** (e.g., `PaymentGateway` with `StripeGateway`/`TossGateway`, push APNs/FCM, OAuth Google/Kakao/Apple, STT providers) or a Strategy pattern is clearly needed. Name such interfaces by intent: `XxxAdapter`, `XxxProvider`, `XxxVerifier`, `XxxStrategy`.

---

## §5 Exceptions & API Envelope

### 5.1 Exception Hierarchy

One project-wide shared hierarchy — **no per-domain base exceptions**:
- `<Project>Exception` (base, extends RuntimeException)
- `BusinessException` — business rule violations (insufficient balance, duplicates)
- `AuthException` — authentication/authorization
- `SystemException` — external system / infrastructure failures
- Domains add only specific exceptions extending these (e.g., `DuplicateEmailException extends BusinessException`).

Check `com.<project>.common.exception` for the actual base exception name.

### 5.2 Global Handler & Error Codes

- One global `@RestControllerAdvice` handler. Never create per-domain handlers; never `try-catch` in controllers.
- New domain exceptions: add an `@ExceptionHandler` to the global handler or verify auto-mapping via the base exception.
- Use an `ErrorCode` enum (e.g., `AUTH_001`, `ORDER_002`). Clients branch on enum codes, never on message strings.

### 5.3 ApiResponse Envelope

All controllers use the **single project-wide envelope class**. Never create a new envelope per domain.

```text
- success: boolean              # true/false
- code: ErrorCode (enum)        # identifier
- message: String               # human-readable message
- data: T                       # payload (on success)
- errors: List<FieldError>      # validation errors (on failure)
```

```java
@PostMapping
public ApiResponse<OrderResponse> create(@Valid @RequestBody OrderCreateRequest req,
                                         @AuthenticationPrincipal AuthenticatedPrincipal principal) {
    return ApiResponse.success(orderService.create(principal.userId(), req));
}
```

Rules:
- All controller return types use `ApiResponse<T>` (except exceptional async/stream cases).
- Error responses are built by the global handler only — including validation failures (`MethodArgumentNotValidException`).

---

## §6 Validation & Transactions

### 6.1 Input Validation

- Bean Validation annotations on all controller input DTOs (`@NotNull`, `@NotBlank`, `@Email`, `@Size`, `@Min`, `@Max`, `@Pattern`).
- `@Valid` is required on controller method parameters.
- Business rules (insufficient balance, duplicates) are validated in the Service layer → `BusinessException`.
- Record DTOs may normalize/validate in the compact constructor:

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

### 6.2 Transaction Policy

- Service class level: `@Transactional(readOnly = true)` default; write methods get explicit `@Transactional`.
- Transaction boundaries belong in the Service layer only — never on controllers or repositories.
- Combining multiple domain operations: do not import across domains — decouple via **outbox events**.
- Entities with `@Version` optimistic locking: use a retry helper on `OptimisticLockException`.

---

## §7 Database & Flyway

### 7.1 No-Lock Login/Activity Tracking

- **Never UPDATE `users.last_login_at` on login** — it is a row-level write-lock bottleneck. Track logins with INSERT-only `user_login_logs`.
- Same principle for other "last activity" columns: append-only log tables; Redis/cache for hot counters.

### 7.2 N+1 Prevention (Required)

For 1:N relationship queries always use one of: `@EntityGraph(attributePaths = {...})`, JPQL `JOIN FETCH`, or a separate batch query + in-memory join. **Accessing lazy fields inside a loop is forbidden** and caught in code review.

```java
// ❌ Forbidden
orders.forEach(o -> o.getOrderItems().size());  // N+1

// ✅ Recommended
@Query("SELECT o FROM OrderEntity o LEFT JOIN FETCH o.orderItems WHERE o.id IN :ids")
List<OrderEntity> findAllWithItemsByIdIn(@Param("ids") List<Long> ids);
```

### 7.3 Indexes & Timestamps

- FK columns must have an index. Compound indexes for frequent column combinations (e.g., `(customer_id, order_date)`).
- **Partial indexes** to index only active rows (e.g., `WHERE deleted_at IS NULL`) — also enables re-registration with a soft-deleted email under a unique constraint.
- All timestamp columns: `TIMESTAMPTZ`. Application level: `Instant` (UTC) or `OffsetDateTime` by default; `LocalDateTime` only for explicit user-local semantics.

### 7.4 Soft Delete Pattern

- `is_deleted` (boolean) + `deleted_at` (timestamp) columns.
- `@SQLDelete` converts DELETE to UPDATE; `@SQLRestriction` (or `@Where`) auto-excludes soft-deleted rows.
- Provide `findByXxxIncludingDeleted()` to bypass the filter for re-registration/recovery.
- Pitfalls: `findById` on a soft-deleted row returns not-found (intercepted by `@SQLRestriction`); inconsistent soft-delete inclusion in count queries causes logic bugs.

### 7.5 Flyway Migrations

- Location: `src/main/resources/db/migration/`
- Filename: `V{number}__{snake_case_description}.sql` (e.g., `V42__add_order_status_index.sql`)
- **Never modify existing (applied) migration files.** Always add a new version number. Force-updating checksums in `flyway_schema_history` is a production incident waiting to happen — fix forward with a new migration.
- Application order follows the filename number; duplicate numbers are not allowed.
- Use `baseline-on-migrate=true` to join an already-running DB.
- Migrations with data-loss risk (column drop, data delete) require a backup/validation plan and separate review.
- DDL must follow §7.1–7.4 rules (soft delete, partial index, TIMESTAMPTZ, FK indexes).
- In multi-agent projects each agent may have an assigned migration number range — check the project document.

---

## §8 Spring Profiles & Config

- `application.yaml` — common config + default profile
- `application-local.yaml` (or `application-dev.yaml`) — local development
- `application-test.yaml` — tests (H2, Flyway disabled recommended)
- `application-prod.yaml` — production (externalized env vars)
- Secrets (JWT secret, DB password, API keys) must **never be hardcoded in yaml or code** — use env vars or an external secret manager.
- Docker: multi-stage builds (build stage → runtime stage); specify `linux/amd64` explicitly when building on Apple Silicon for x86 servers. CI credentials via GitHub Actions secrets or OIDC — never hardcoded.

---

## §9 Logging / OpenAPI / Formatting

### Logging
- SLF4J + Logback via `@Slf4j`. `System.out.println` / `e.printStackTrace()` are forbidden.
- Levels: `ERROR` system/external failure, data inconsistency · `WARN` abnormal but auto-recoverable · `INFO` key business events · `DEBUG` troubleshooting detail.
- Sensitive info masking: email → `t***@example.com`, token → first 8 chars only, payment/SSN → never log.

### OpenAPI / Swagger
- Springdoc OpenAPI. Controller class: `@Tag(name = "domain", description = "...")`; method: `@Operation(summary, description)`; `@ApiResponses` as needed.
- `@Schema(description = "...")` on DTO fields.
- Exclude non-public APIs (actuator, admin internals) from OpenAPI or put them in a separate group.

### Formatting
- **Spotless + Google Java Format** (configured in `build.gradle`). Run `./gradlew spotlessApply` immediately before committing; CI fails PRs on `spotlessCheck`.

---

## §10 Testing (Java Specifics)

General testing doctrine (FIRST, coverage goals, prohibitions) lives in testing.md. This section covers Java/Spring specifics.

Coverage: full bundle **80%+** (enforced by `jacocoTestCoverageVerification`); core business logic (payment, auth, balance) 100% recommended; exception paths always covered. Entity/DTO/Configuration classes are excluded from JaCoCo in build.gradle.

Prohibitions (Java specifics): no `Thread.sleep()` (use Awaitility), no `System.out.println`, no real external API calls, cleanup via `@Transactional` or `@AfterEach`, no unexplained `@Disabled`.

### 10.1 Naming & BDD

Recommended: **`@DisplayName` with descriptive English text** + concise English method name (`methodName_condition_expectedResult`). All tests follow Given-When-Then, separated by blank lines:

```java
@Test
@DisplayName("Throws BusinessException when creating an order for an out-of-stock product")
void createOrder_insufficientStock_throws() {
    // Given
    Long customerId = 1L;
    Product product = Product.builder()
            .id(100L).name("Keyboard").stockQuantity(0).build();
    when(productRepository.findById(100L)).thenReturn(Optional.of(product));

    // When & Then
    assertThatThrownBy(() -> orderService.create(customerId, List.of(new OrderItemRequest(100L, 1))))
            .isInstanceOf(BusinessException.class)
            .hasFieldOrPropertyWithValue("errorCode", ErrorCode.ORDER_INSUFFICIENT_STOCK);
}
```

### 10.2 Service Unit Tests (Mockito)

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock private OrderRepository orderRepository;
    @Mock private ProductRepository productRepository;
    @Mock private OutboxEventPublisher outboxPublisher;

    @InjectMocks private OrderService orderService;

    @Test
    @DisplayName("Stock is decremented and OrderCreated event is published when order is created")
    void create_success() {
        // Given
        Product product = Product.builder().id(100L).stockQuantity(10).build();
        when(productRepository.findById(100L)).thenReturn(Optional.of(product));
        when(orderRepository.save(any(Order.class))).thenAnswer(i -> i.getArgument(0));

        // When
        Order saved = orderService.create(1L, List.of(new OrderItemRequest(100L, 3)));

        // Then
        assertThat(product.getStockQuantity()).isEqualTo(7);
        verify(orderRepository, times(1)).save(any(Order.class));
        verify(outboxPublisher, times(1)).publish(any(OrderCreatedEvent.class));
    }
}
```

- `@InjectMocks` works automatically with constructor injection (§4.2).
- Verify happy path, business rules, exceptions (+ ErrorCode), and key side effects only (`verify` for save/publish — skip trivial getter checks). Never mock the domain logic under test.
- Pure functions / value objects: direct instantiation, `@ParameterizedTest` + `@CsvSource` / `@ValueSource` / `@NullAndEmptySource` for boundary values — no Spring context.

### 10.3 Repository Tests — @DataJpaTest + TestContainers

Default: H2 in-memory with auto-rollback (`@DataJpaTest` default). For PostgreSQL-specific features (partial index, JSONB, `TIMESTAMPTZ`, window functions) use TestContainers — expensive to start, use only when H2 is genuinely insufficient:

```java
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class DatabaseIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:15-alpine")
                    .withDatabaseName("testdb")
                    .withUsername("test").withPassword("test");

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
    }
}
```

What to verify: partial unique index behavior (soft-delete re-registration), `@EntityGraph`/`JOIN FETCH` N+1 elimination (`statistics.getPrepareStatementCount()`), `@SQLRestriction` filter behavior, `TIMESTAMPTZ` ↔ `Instant` conversion.

### 10.4 Controller / Integration Tests

`@WebMvcTest` for fast controller slices:

```java
@WebMvcTest(OrderController.class)
@Import(SecurityTestConfig.class)
class OrderControllerTest {

    @Autowired private MockMvc mockMvc;
    @MockBean private OrderService orderService;

    @Test
    @WithMockAuthenticatedUser(userId = 1L)
    @DisplayName("GET /orders/{id} response conforms to ApiResponse standard envelope")
    void getOrder_envelopeFormat() throws Exception {
        when(orderService.findById(1L, 42L)).thenReturn(
                new OrderResponse(42L, "PAID", BigDecimal.valueOf(50000), List.of()));

        mockMvc.perform(get("/orders/{id}", 42L))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data.id").value(42));
    }
}
```

Check: HTTP status, envelope fields (`success`, `code`, `message`, `data`, `errors`), standard error response on validation failure, auth/authz branching.

`@SpringBootTest` for full integration: `webEnvironment = RANDOM_PORT` + `@AutoConfigureMockMvc` + `@ActiveProfiles("test")` + `@Transactional` (auto-rollback). External systems (payment, push, LLM) via `@MockBean`; pre-load data with `@Sql`.

Idempotency test pattern:

```java
@Test
@DisplayName("Calling twice with the same Idempotency-Key processes only once")
void create_idempotency() throws Exception {
    String body = """{ "items": [{"productId": 100, "quantity": 1}] }""";
    for (int i = 0; i < 2; i++) {
        mockMvc.perform(post("/orders")
                .header("Idempotency-Key", "key-1")
                .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk());
    }
    assertThat(orderRepository.findAll()).hasSize(1);  // created only once
}
```

### 10.5 Fixtures, Auth Annotation, Clock, Test Config

**Fixtures** — `XxxFixture` (final class, private constructor, static factory methods) per domain in the test package; defaults are the "valid minimum", tests override only fields they care about:

```java
public static OrderEntity order(Long customerId, BigDecimal total) {
    return OrderEntity.builder()
            .customerId(customerId).totalAmount(total)
            .status(OrderStatus.CREATED).createdAt(Instant.now())
            .build();
}
```

**Custom auth annotation** — if the project uses a custom `Principal`, `@WithMockUser` is insufficient; use the project's annotation (typically `@WithMockAuthenticatedUser(userId = 1L, role = "ADMIN")`, found in the test `support`/`test.security` package).

**Clock injection** — for time-dependent logic, inject `Clock` and use `clock.instant()` in production code instead of `Instant.now()`/`LocalDate.now()` directly. In tests, register a `@TestConfiguration` with a `@Bean @Primary Clock` returning `Clock.fixed(Instant.parse("2026-01-15T09:00:00Z"), ZoneOffset.UTC)`.

**application-test.yml** — H2 (PostgreSQL mode) + `create-drop` + Flyway disabled (except when testing migration SQL itself):

```yaml
spring:
  datasource:
    url: jdbc:h2:mem:testdb;MODE=PostgreSQL;DB_CLOSE_DELAY=-1
    driver-class-name: org.h2.Driver
  jpa:
    hibernate:
      ddl-auto: create-drop
    properties:
      hibernate:
        show_sql: false
  flyway:
    enabled: false
logging:
  level:
    com.example: DEBUG
    org.hibernate.SQL: WARN
```

---

## §11 Security Implementation (Spring Specifics)

Security doctrine and rule IDs live in security.md — this section maps them to Spring mechanisms.

- **SecurityFilterChain**: explicitly declare every new endpoint as public or protected in `authorizeHttpRequests`. Never rely on implicit defaults. Stateless APIs: `SessionCreationPolicy.STATELESS`.
- **Passwords** (SEC-N5): `BCryptPasswordEncoder` from Spring Security. Never MD5/SHA/plaintext.
- **JWT** (SEC-A5): jjwt 0.12+ API — `Jwts.parser().verifyWith(key)...`; validate expiry, issuer, and signature. Secrets from env vars only.
- **Rate limiting**: bucket4j on auth-sensitive endpoints (login, signup, password reset).
- **CORS**: a single explicit `CorsConfigurationSource` bean — no wildcard origins with credentials.
- **SQL**: JPA parameter binding only. Never build SQL by string concatenation.
- **Sensitive data** (passwords, tokens, PII, payment info): never in logs, API responses, or external notifications (Slack/Discord). Apply masking (§9).
- **Dependency audit**: `./gradlew dependencyCheckAnalyze` if the OWASP Dependency-Check plugin is present in build.gradle; otherwise report the tool as missing rather than skipping silently.

---

## §12 Troubleshooting

### 12.1 JWT / Spring Security

| Symptom | Suspect |
|---|---|
| 401 Unauthorized — all requests | `SecurityFilterChain` `authorizeHttpRequests` config; `JwtAuthenticationFilter` not registered in chain |
| 403 Forbidden — specific requests | `@PreAuthorize`, `hasRole/hasAuthority` logic; principal missing required authority |
| Token sent but not authenticated | `Authorization: Bearer <token>` header format; token subject doesn't match `UserDetails.username` |
| Expired token still passes | Server NTP clock drift; `JwtParser` expiry validation not enabled |
| Login works but next request breaks | `SecurityContext` not stateless (`SessionCreationPolicy.STATELESS`); CORS config |

Debug: `log.debug` in `JwtAuthenticationFilter` (token subject / extracted username / `loadUserByUsername` result); `logging.level.org.springframework.security=DEBUG`.

### 12.2 Flyway

| Symptom | Action |
|---|---|
| Fails when joining an existing DB | `flyway.baseline-on-migrate=true`, `flyway.baseline-version=<last applied version>` |
| Checksum mismatch after migration | **Never edit existing migration files.** Fix forward with a new migration; force-updating `flyway_schema_history` checksums is a production incident waiting to happen |
| Duplicate version number | Conflict — renumber one of them |
| Migration takes too long | `CREATE INDEX CONCURRENTLY` (Postgres); schedule large table changes in a maintenance window |
| Applied but `validate` fails | Consider `flyway repair` (extreme caution in production) |

### 12.3 Soft Delete Pitfalls

- `findById` on a soft-deleted row is intercepted by `@SQLRestriction` and returns not-found — use `findByXxxIncludingDeleted()` for recovery flows.
- Inconsistent soft-delete inclusion in count queries causes business logic bugs.

### 12.4 N+1 Detection

Symptom: list API unusually slow; the same SELECT repeats N times in logs.
1. Enable `org.hibernate.SQL=DEBUG` + `org.hibernate.orm.jdbc.bind=TRACE`.
2. Typical culprit: lazy 1:N association accessed in a loop via `getXxxList()`.
3. Fix: `@EntityGraph`, JPQL `JOIN FETCH`, or a separate batch query (§7.2).

### 12.5 Transaction Misbehavior

| Symptom | Suspect |
|---|---|
| `@Transactional` has no effect | Private method / self-invocation within the same class / final class (proxy not created) |
| `LazyInitializationException` | Lazy collection accessed outside transaction — fetch or convert to DTO inside the service |
| Rollback not happening | Default rolls back only `RuntimeException`; checked exceptions need `rollbackFor = ...` |
| Write attempt on read-only transaction | Class-level `readOnly=true` default; write method needs its own `@Transactional` |

### 12.6 External Systems

- Every external call **must have a timeout**. Indefinite waits cause outages.
- Critical paths (payment, SMS, email) need an **idempotency key**.
- Isolate failures with circuit breaker, fallback, or outbox — never cascade.
- Never expose external system responses directly to the client (stack trace / internal ID leakage).

### 12.7 Env Vars / Secrets

| Symptom | Check |
|---|---|
| Works locally, fails in production (NPE / auth failure) | Verify env vars actually injected in production (`echo $VAR` inside the container) |
| `${VAR}` placeholder in yaml not resolved | Env var name typo; active profile not set |
| Password printed in logs | `logging.level` config; entity `toString()` exposing fields — check `@ToString.Exclude` |

### 12.8 Build / Dependency

| Symptom | Action |
|---|---|
| Build behaving unexpectedly with cache | `./gradlew --no-build-cache clean build` or clear `~/.gradle/caches/` |
| Spotless auto-fix differs from intent | Check `.editorconfig` vs Spotless config; IDE auto-format conflict |
| Tests pass individually, fail together | Shared state (`@DirtiesContext`, static variables, missing DB cleanup) |
| OOM only in CI | Gradle daemon memory (`org.gradle.jvmargs`), JVM heap (`-Xmx`) tuning |

---

## §13 Deprecated Rules (Do Not Follow)

The following rules from older guide documents are incorrect by modern Java/Spring standards or outdated:

- ❌ `@Data` on Entity → §4.1 forbidden
- ❌ Field Injection (`@Autowired private`) → §4.2 forbidden
- ❌ Forced Service interface + ServiceImpl split → §4.3 single class by default
- ❌ Maven usage → §1 Gradle only
- ❌ `result: String ("SUCCESS"/"ERROR")` ApiResponse format → §5.3 boolean + enum-based envelope
- ❌ UPDATE `users.last_login_at` on login → §7.1 append-only log
- ❌ Layer-based packages (`controller/`, `service/` at top level) → §2 domain-based
