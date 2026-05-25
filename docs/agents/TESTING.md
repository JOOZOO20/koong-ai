# TESTING.md

> **This document is the single source of truth for test code conventions and the automation workflow.**
> Designed to work unchanged when copied into any project.
> Class names in code examples (`Order`, `Customer`, `Product`, etc.) use a generic domain — replace with your project's actual domain classes.
>
> Covers both backend (Java/Spring Boot) and frontend tests.
> Read only the sections relevant to your task type.

---

## Section Guide (Read This First)

| Task | Sections to Read |
|---|---|
| **Backend tests** (JUnit5 / Mockito / Spring Boot Test) | **§0 Automation Workflow (common) + §1–§5** |
| **Frontend tests** | **§0 Automation Workflow (common) + §6–§9** |
| Automation flow only (both environments) | §0 only |

If you are unsure which environment your task belongs to, ask the user. It is rare for a single PR to change code in both environments.

---

## §0. Autonomous Code ↔ Test Verification Loop (Common to Backend and Frontend)

This project enforces a strict, self-healing autonomous workflow to ensure production code is always backed by passing tests. The agent must execute this loop seamlessly without stopping for human intervention.

### 0.1 Step-by-Step Autonomous Lifecycle

> [Phase 2: Implementation] ➔ [Phase 3: Test Generation] ➔ [Phase 4: Self-Healing]
> ┌──────────────────────┐    ┌────────────────────────┐   ┌────────────────────────┐
> │ 1. Write core logic  │    │ 1. Read business code  │   │ 1. Run tests           │
> │ 2. Check conventions │ ➔  │ 2. Draft tests         │ ➔ │ 2. Parse error logs    │
> │ 3. spotlessApply     │    │ 3. Apply edge cases    │   │ 3. Refactor and re-run │
> └──────────────────────┘    └────────────────────────┘   └────────────────────────┘

- **No Pausing:** Transition immediately from Phase 2 to Phase 3. Do not ask the user for permission to start testing. Do NOT use `/fork`.
- **Self-Healing Requirement:** If tests fail in Phase 4, you must autonomously analyze the error logs, fix the production code or the tests, and run `./gradlew test` again until success. Do not ask the user for help unless you are fundamentally stuck after multiple attempts.

---

# Backend Tests (§1–§5)

## §1. Backend General Principles

### 1.1 Test Philosophy (FIRST)
- **F**ast — run quickly
- **I**ndependent — each test is independent
- **R**epeatable — consistent regardless of environment
- **S**elf-Validating — pass/fail is unambiguous
- **T**imely — written immediately after production code (§0 [2])

### 1.2 Coverage Goals
- Full bundle: **80% or above** (enforced by `./gradlew jacocoTestCoverageVerification`)
- Core business logic (payment, auth, authorization, balance calculation): **100% recommended**
- Exception handling paths must always be covered
- Entity/DTO/Configuration classes are excluded from JaCoCo (configured in build.gradle)

### 1.3 Naming Conventions

Choose one of the following formats and use it consistently within a module:

> // Format A (English): methodName_condition_expectedResult
> @Test
> void saveUser_whenValidInput_returnsSavedUser() { }
> 
> @Test
> void saveUser_whenEmailDuplicated_throwsBusinessException() { }
> 
> // Format B (DisplayName): readability-first
> @Test
> @DisplayName("Throws BusinessException when registering with a duplicate email")
> void register_duplicateEmail_throws() { }

Recommendation: **`@DisplayName` with descriptive English text** + concise English method name. DisplayName appears directly in test reports, improving readability.

### 1.4 BDD Structure (Given-When-Then)

All tests follow this structure:

> @Test
> @DisplayName("Throws BusinessException when creating an order for an out-of-stock product")
> void createOrder_insufficientStock_throws() {
>     // Given
>     Long customerId = 1L;
>     Product product = Product.builder()
>             .id(100L).name("Keyboard").stockQuantity(0).build();
>     when(productRepository.findById(100L)).thenReturn(Optional.of(product));
> 
>     // When & Then
>     assertThatThrownBy(() -> orderService.create(customerId, List.of(new OrderItemRequest(100L, 1))))
>             .isInstanceOf(BusinessException.class)
>             .hasFieldOrPropertyWithValue("errorCode", ErrorCode.ORDER_INSUFFICIENT_STOCK);
> }

Separate Given/When/Then visually with blank lines.

### 1.5 Absolute Prohibitions
- ❌ Test execution order dependency
- ❌ Real external API calls (email, payment, LLM, push)
- ❌ Hardcoded absolute paths
- ❌ `Thread.sleep()` — use `Awaitility` for async verification
- ❌ `System.out.println` — use `@Slf4j` or assertion messages
- ❌ Missing cleanup after tests — use `@Transactional` or `@AfterEach` cleanup
- ❌ Leaving `@Disabled` without explanation — always include a reason and TODO

---

## §2. Backend Unit Tests

### 2.1 Service Layer Tests

> @ExtendWith(MockitoExtension.class)
> class OrderServiceTest {
> 
>     @Mock private OrderRepository orderRepository;
>     @Mock private ProductRepository productRepository;
>     @Mock private OutboxEventPublisher outboxPublisher;
> 
>     @InjectMocks private OrderService orderService;
> 
>     @Test
>     @DisplayName("Stock is decremented and OrderCreated event is published when order is created")
>     void create_success() {
>         // Given
>         Long customerId = 1L;
>         Product product = Product.builder().id(100L).stockQuantity(10).build();
>         when(productRepository.findById(100L)).thenReturn(Optional.of(product));
>         when(orderRepository.save(any(Order.class))).thenAnswer(i -> i.getArgument(0));
> 
>         // When
>         Order saved = orderService.create(customerId, List.of(new OrderItemRequest(100L, 3)));
> 
>         // Then
>         assertThat(product.getStockQuantity()).isEqualTo(7);
>         verify(orderRepository, times(1)).save(any(Order.class));
>         verify(outboxPublisher, times(1)).publish(any(OrderCreatedEvent.class));
>     }
> }

Verification checklist:
- ✅ Happy path
- ✅ Business rules (insufficient balance, unauthorized access, duplicates)
- ✅ Exception handling (which exception, which ErrorCode)
- ✅ Dependency call count and arguments (`verify`)
- ✅ State after transaction rollback scenario

### 2.2 Using Mocks

- `@Mock` — replace a dependency with a mock
- `@InjectMocks` — the subject under test (mocks auto-injected). Works automatically with the Constructor Injection pattern (`BACKEND_CONVENTIONS.md` §5.1).
- Avoid excessive mocking. Never mock the domain logic under test itself.
- `verify` only for key side effects (save, event publish). Skip trivial verifications like getter calls.

### 2.3 Util / Domain Object Tests

Test pure functions, validation logic, and value objects by direct instantiation — no Spring context needed:

> class OrderStatusTest {
>     @ParameterizedTest
>     @CsvSource({
>         "CREATED, PAID, true",
>         "PAID, SHIPPED, true",
>         "SHIPPED, DELIVERED, true",
>         "DELIVERED, PAID, false",
>         "CANCELLED, PAID, false"
>     })
>     void canTransitionTo(OrderStatus from, OrderStatus to, boolean expected) {
>         assertThat(from.canTransitionTo(to)).isEqualTo(expected);
>     }
> }

Use `@ParameterizedTest` + `@CsvSource` / `@ValueSource` / `@NullAndEmptySource` to cover boundary values efficiently.

---

## §3. Backend Repository Tests

### 3.1 @DataJpaTest

> @DataJpaTest
> class UserCredentialsRepositoryTest {
> 
>     @Autowired private TestEntityManager em;
>     @Autowired private UserCredentialsRepository repository;
> 
>     @Test
>     @DisplayName("Re-registration is possible with a deleted user's email due to partial unique index")
>     void uniqueEmail_excludesSoftDeleted() {
>         // Given
>         UserCredentialsEntity deleted = UserCredentialsEntity.builder()
>                 .email("test@example.com").passwordHash("...")
>                 .deletedAt(Instant.now()).build();
>         em.persistAndFlush(deleted);
> 
>         // When
>         UserCredentialsEntity reRegister = UserCredentialsEntity.builder()
>                 .email("test@example.com").passwordHash("...").build();
>         em.persistAndFlush(reRegister);
> 
>         // Then
>         List<UserCredentialsEntity> all = repository.findAllByEmail("test@example.com");
>         assertThat(all).hasSize(2);
>     }
> }

Rules:
- Default: H2 in-memory.
- For PostgreSQL-specific features (partial index, JSONB, `TIMESTAMPTZ`): use TestContainers (§3.2).
- Each test auto-rolls back via `@Transactional` (default `@DataJpaTest` behavior).

### 3.2 TestContainers (PostgreSQL)

For testing PG-specific features (partial index / JSONB / window functions):

> @SpringBootTest
> @Testcontainers
> @ActiveProfiles("test")
> class DatabaseIntegrationTest {
> 
>     @Container
>     static PostgreSQLContainer<?> postgres =
>             new PostgreSQLContainer<>("postgres:15-alpine")
>                     .withDatabaseName("testdb")
>                     .withUsername("test").withPassword("test");
> 
>     @DynamicPropertySource
>     static void properties(DynamicPropertyRegistry r) {
>         r.add("spring.datasource.url", postgres::getJdbcUrl);
>         r.add("spring.datasource.username", postgres::getUsername);
>         r.add("spring.datasource.password", postgres::getPassword);
>     }
> }

Expensive to start — use only when H2 is genuinely insufficient.

### 3.3 What to Verify

- Partial unique index behavior (soft-delete re-registration case)
- `@EntityGraph` / `JOIN FETCH` N+1 elimination (`statistics.getPrepareStatementCount()`)
- Soft delete filter (`@SQLRestriction`) behaves as intended
- Timezone column conversion (`TIMESTAMPTZ` ↔ `Instant`)

---

## §4. Backend Controller / Integration Tests

### 4.1 @WebMvcTest (Controller Unit)

Fast controller slice test:

> @WebMvcTest(OrderController.class)
> @Import(SecurityTestConfig.class)
> class OrderControllerTest {
> 
>     @Autowired private MockMvc mockMvc;
>     @MockBean private OrderService orderService;
> 
>     @Test
>     @WithMockAuthenticatedUser(userId = 1L)
>     @DisplayName("GET /orders/{id} response conforms to ApiResponse standard envelope")
>     void getOrder_envelopeFormat() throws Exception {
>         when(orderService.findById(1L, 42L)).thenReturn(
>                 new OrderResponse(42L, "PAID", BigDecimal.valueOf(50000), List.of()));
> 
>         mockMvc.perform(get("/orders/{id}", 42L))
>                 .andExpect(status().isOk())
>                 .andExpect(jsonPath("$.success").value(true))
>                 .andExpect(jsonPath("$.code").value("OK"))
>                 .andExpect(jsonPath("$.data.id").value(42))
>                 .andExpect(jsonPath("$.data.status").value("PAID"));
>         }
> }

Check:
- HTTP status code
- ApiResponse envelope fields (`success`, `code`, `message`, `data`, `errors`)
- Standard error response on validation failure
- Auth/authz branching (`@WithMockUser` or project-defined custom annotation, e.g., `@WithMockAuthenticatedUser`)

### 4.2 @SpringBootTest (Full Integration)

Full context + MockMvc + real Service/Repository:

> @SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
> @AutoConfigureMockMvc
> @ActiveProfiles("test")
> @Transactional
> class OrderIntegrationTest {
> 
>     @Autowired private MockMvc mockMvc;
>     @Autowired private OrderRepository orderRepository;
> 
>     @Test
>     @WithMockAuthenticatedUser(userId = 1L)
>     @Sql("/test-data/order-initial.sql")
>     @DisplayName("Full flow: order creation → stock decrement → outbox event published")
>     void create_endToEnd() throws Exception {
>         String body = """
>             {
>               "items": [{"productId": 100, "quantity": 2}],
>               "idempotencyKey": "test-key-1"
>             }
>             """;
> 
>         mockMvc.perform(post("/orders")
>                         .contentType(MediaType.APPLICATION_JSON)
>                         .content(body))
>                 .andExpect(status().isOk())
>                 .andExpect(jsonPath("$.success").value(true));
> 
>         assertThat(orderRepository.findAll()).hasSize(1);
>     }
> }

Rules:
- `@Transactional` auto-rollback for DB isolation.
- External systems (payment gateway, push, LLM): use `@MockBean`.
- Pre-load test data with `@Sql`.

### 4.3 Idempotency / Outbox Tests

> @Test
> @DisplayName("Calling twice with the same Idempotency-Key processes only once")
> void create_idempotency() throws Exception {
>     String body = """{ "items": [{"productId": 100, "quantity": 1}] }""";
> 
>     mockMvc.perform(post("/orders")
>             .header("Idempotency-Key", "key-1")
>             .contentType(MediaType.APPLICATION_JSON).content(body))
>             .andExpect(status().isOk());
> 
>     mockMvc.perform(post("/orders")
>             .header("Idempotency-Key", "key-1")
>             .contentType(MediaType.APPLICATION_JSON).content(body))
>             .andExpect(status().isOk());
> 
>     assertThat(orderRepository.findAll()).hasSize(1);  // created only once
> }

---

## §5. Backend Test Data / Fixtures / Helpers

### 5.1 Fixture Classes

> public final class TestFixture {
>     private TestFixture() {}
> 
>     public static UserEntity user(String email) {
>         return UserEntity.builder()
>                 .name("test-user")
>                 .email(email)
>                 .createdAt(Instant.now())
>                 .build();
>     }
> 
>     public static OrderEntity order(Long customerId, BigDecimal total) {
>         return OrderEntity.builder()
>                 .customerId(customerId)
>                 .totalAmount(total)
>                 .status(OrderStatus.CREATED)
>                 .createdAt(Instant.now())
>                 .build();
>     }
> }

Rules:
- Define `XxxFixture` or `XxxTestFixture` per domain (inside the test package).
- Default values are the "valid minimum." Tests should override only the fields they care about.
- Expose only meaningful fields through the builder.

### 5.2 Custom Auth Annotation

`@WithMockUser` creates a default Spring Security `User`. If your project uses a custom `Principal`, a custom annotation is needed. Typical pattern:

> @Test
> @WithMockAuthenticatedUser(userId = 1L, role = "ADMIN")
> void someAdminTest() { ... }

Find the actual annotation name in the `support` or `test.security` folder under your test package.

### 5.3 Clock Injection

For time-dependent logic (streaks, expiration, TTL), inject `Clock` and fix it in tests:

> @TestConfiguration
> public class TestClockConfig {
>     @Bean @Primary
>     public Clock fixedClock() {
>         return Clock.fixed(Instant.parse("2026-01-15T09:00:00Z"), ZoneOffset.UTC);
>     }
> }

In production code, always use `clock.instant()` instead of calling `LocalDate.now()` or `Instant.now()` directly.

### 5.4 Custom AssertJ Assertions

Improve readability for frequently verified domain objects:

> public class OrderAssert extends AbstractAssert<OrderAssert, Order> {
>     public OrderAssert(Order actual) {
>         super(actual, OrderAssert.class);
>     }
>     public static OrderAssert assertThat(Order actual) {
>         return new OrderAssert(actual);
>     }
>     public OrderAssert hasStatus(OrderStatus expected) {
>         isNotNull();
>         if (actual.getStatus() != expected) {
>             failWithMessage("status expected <%s> but was <%s>", expected, actual.getStatus());
>         }
>         return this;
>     }
> }

### 5.5 application-test.yml

> spring:
>   datasource:
>     url: jdbc:h2:mem:testdb;MODE=PostgreSQL;DB_CLOSE_DELAY=-1
>     driver-class-name: org.h2.Driver
>   jpa:
>     hibernate:
>       ddl-auto: create-drop
>     properties:
>       hibernate:
>         show_sql: false
>   flyway:
>     enabled: false
> logging:
>   level:
>     com.example: DEBUG
>     org.hibernate.SQL: WARN

In the test environment, Flyway disabled + JPA `create-drop` is recommended (except when testing migration SQL itself).

---

# Frontend Tests (§6–§9)

> **Note**: The frontend stack and test tools are governed by the project's frontend plan document as the single source of truth.
> This section covers only frontend test writing principles that align with the backend automation workflow (§0).

## §6. Frontend General Principles

### 6.1 Test Types

| Type | Tools (project-specific) | Purpose |
|---|---|---|
| Unit Test | Vitest / Jest, etc. | Utilities / domain functions / pure components |
| Component Test | React Testing Library / Vue Test Utils, etc. | Single component rendering/interaction |
| Integration Test | Above tools + router + state wrapper | Multiple components + routing/state |
| E2E Test | Playwright / Cypress / Detox, etc. | Real user scenarios |

### 6.2 Common Principles
- Follow §0 automation workflow (steps [1]–[6] apply equally).
- Follow §1.4 BDD structure (Given-When-Then).
- Follow §1.5 absolute prohibitions (sleep, real external API calls, execution order dependency).

### 6.3 Naming

> describe('OrderSummary', () => {
>   it('enables the order button when stock is available', () => { /* ... */ });
>   it('shows an out-of-stock message when stock is zero', () => { /* ... */ });
> });

---

## §7. Frontend Unit / Component Tests

### 7.1 Pure Functions
Test domain functions, formatters, and validators directly without a framework:

> describe('formatPrice', () => {
>   it.each([
>     [1000, '$10.00'],
>     [1234567, '$12,345.67'],
>     [0, '$0.00'],
>   ])('formats %d as %s', (input, expected) => {
>     expect(formatPrice(input)).toBe(expected);
>   });
> });

### 7.2 Components
- Verify what the user sees (rendering, interaction).
- Do not verify internal implementation (state names, function names) — it breaks on refactoring.
- Mock targets: API client, router, auth context.

### 7.3 Interaction Verification
Simulate real input with `userEvent` or equivalent:

> it('calls onSubmit when email is entered and submit button is clicked', async () => {
>   const onSubmit = vi.fn();
>   render(<SignupForm onSubmit={onSubmit} />);
> 
>   await userEvent.type(screen.getByLabelText('Email'), 'test@example.com');
>   await userEvent.click(screen.getByRole('button', { name: 'Sign Up' }));
> 
>   expect(onSubmit).toHaveBeenCalledWith({ email: 'test@example.com' });
> });

---

## §8. Frontend Integration Tests

### 8.1 API Mocking
Mock backend responses with MSW (Mock Service Worker) or equivalent:

> const server = setupServer(
>   http.get('/orders/:id', () => HttpResponse.json({
>     success: true, code: 'OK',
>     data: { id: 42, status: 'PAID', totalAmount: 50000 }
>   }))
> );

### 8.2 State + Routing
When testing multiple components + routing + global state together:
- Use the real router (or a router mock)
- Provide isolated global state instances via a test wrapper
- Use `findByXxx` / `waitFor` for async operations (no sleep)

---

## §9. Frontend E2E Tests

### 9.1 Scenarios
Focus on real user flows:
- Login → search products → add to cart → place order → payment
- Start as guest → perform actions → register → verify data migration
- Payment → earn points → redeem points

### 9.2 Environment
- Local: local backend + test DB
- CI: dev/staging backend + test user accounts
- Isolated test users that do not affect production data

### 9.3 Reliability
- No `sleep`. Use explicit waits (`waitForSelector`, `waitForResponse`).
- External payment/push: use sandbox/mock environments.
- Save screenshots/HAR on failure for debugging.

---

# Appendix A. Common Commands

> # Backend
> ./gradlew test                                    # Run all tests
> ./gradlew test --tests "com.example.order.*"      # Module only (replace with your package)
> ./gradlew test --tests "*Idempotency*"            # By keyword
> ./gradlew jacocoTestReport                        # Coverage report (HTML: build/reports/jacoco/test/html/index.html)
> ./gradlew jacocoTestCoverageVerification          # Verify 80% coverage
> ./gradlew test --info                             # Verbose logs
> ./gradlew test --rerun-tasks                      # Force re-run ignoring cache
> 
> # Frontend (examples — see frontend plan document for actual commands)
> npm test                                          # Run all
> npm test -- --watch                               # Watch mode
> npm test -- src/order                             # Directory only
> npm run test:e2e                                  # E2E