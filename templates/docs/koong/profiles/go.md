# Go Profile

> Loaded only when stack detected as go (go.mod present).
>
> This profile adds **Go-specific rules only**. Universal principles live in
> `core-principles.md`, the security doctrine (SEC-* rule IDs) in `security.md`, and the
> universal test doctrine in `testing.md`. Where this profile cites a SEC-* ID, it is
> showing the Go **implementation** of that rule — the rule itself is defined in `security.md`.

---

## §1. Tooling & Commands

**Verification combo** (run after every implementation task; all steps must pass):

```bash
gofmt -l . && go vet ./... && go test ./... && go build ./...
```

- `gofmt -l .` must print **nothing**. If it lists files, run `gofmt -w .` — never hand-format.
- If `.golangci.yml` / `.golangci.yaml` exists, also run `golangci-lint run ./...` and treat findings as build failures. Respect the project's linter config; don't add or disable linters as a side effect of a feature task.
- At PR level, run `govulncheck ./...` (see §7).

**go.mod discipline**:
- Run `go mod tidy` after adding/removing imports; commit `go.mod` and `go.sum` together. A dirty `go.sum` in review means tidy wasn't run.
- Never edit `go.mod` require lines by hand — use `go get module@version`.
- Do not bump the `go` directive version casually; match the project's CI toolchain.

---

## §2. Project Structure

```text
.
├── cmd/
│   └── api/
│       └── main.go        # wiring only: config, DB, router, graceful shutdown
├── internal/              # private packages — the default home for all app code
│   ├── order/             # domain package: handler, service, repository for orders
│   ├── user/
│   ├── auth/
│   ├── platform/          # shared infrastructure adapters (db, mail, push)
│   └── httpx/             # shared HTTP plumbing: envelope, middleware, errors
├── migrations/            # SQL migrations (golang-migrate / goose)
├── go.mod
└── go.sum
```

Rules:
- **`cmd/<app>/main.go`** stays thin: load config, construct dependencies, start the server. All logic lives in `internal/`.
- **`internal/` by default.** The compiler enforces privacy — nothing outside the module can import it. Only create a top-level `pkg/` when code is genuinely intended for external consumers; **do not cargo-cult `pkg/`** for ordinary app code.
- **Domain-based packages** (`internal/order`, `internal/user`), not layer-based (`internal/handlers`, `internal/services`). A domain package contains its handler, service, repository, and types together.
- Package names: **short, lowercase, no underscores, no plurals** — `order`, not `orderService` or `order_utils`. The package name is part of every call site: `order.New(...)` reads well, `orderpkg.NewOrderService(...)` does not.
- **No `util`, `common`, `helpers`, `shared` dumping grounds.** Name packages by what they provide (`clock`, `pagination`, `money`). A package you can't name concretely is a package that shouldn't exist.
- No circular imports (the compiler forbids them anyway) — if two domains need each other, the design is wrong: extract the shared concept or invert with an interface.

---

## §3. Go Idioms

**Errors are values.** Handle every error at the call site; never `_` an error silently.

```go
// ✅ Wrap with context using %w so callers can unwrap
order, err := s.repo.FindByID(ctx, id)
if err != nil {
    return nil, fmt.Errorf("find order %d: %w", id, err)
}
```

- Check with `errors.Is` (sentinels) and `errors.As` (typed errors) — never string-match `err.Error()`.
- **Sentinel errors sparingly**: a few well-known ones per package (`var ErrNotFound = errors.New("order: not found")`). For errors carrying data, define a struct type implementing `error`.
- **No `panic` in library/domain code** — return errors. `panic` is acceptable only for truly unrecoverable programmer errors at startup (bad config wiring); HTTP middleware must `recover` so one request cannot kill the process.

**Interfaces**:
- **Accept interfaces, return structs.** Constructors return `*OrderService`, not an interface.
- **Interfaces are defined at the consumer side**, next to the code that uses them — not in the package that implements them, and not in a central `interfaces` package:

```go
// internal/order/service.go — the CONSUMER declares what it needs
type Repository interface {
    FindByID(ctx context.Context, id int64) (*Order, error)
    Save(ctx context.Context, o *Order) error
}

type Service struct{ repo Repository }
```

- Keep interfaces **small (1–3 methods)**. A 10-method interface is a class hierarchy wearing a disguise. Single-method interfaces compose best.

**context.Context**:
- First parameter of every function that does I/O, always named `ctx`: `func (s *Service) Create(ctx context.Context, ...)`.
- Propagate it through every layer down to the driver call. Never `context.Background()` mid-stack; never store a `Context` in a struct field.

**Concurrency**:
- **Goroutines need an owner**: every `go` statement must have a defined answer to "who waits for this, and how does it stop?" Fire-and-forget goroutines leak.
- Fan-out with `golang.org/x/sync/errgroup`:

```go
g, ctx := errgroup.WithContext(ctx)
for _, id := range ids {
    g.Go(func() error { return s.process(ctx, id) })
}
if err := g.Wait(); err != nil { return err }
```

- **Channels for transferring ownership of data / signaling; mutex for protecting shared state.** Guarding a map with a channel, or building a pipeline out of mutexes, are both smells.

**Misc**:
- Make **zero values useful**: `var buf bytes.Buffer` works; design your types the same way where practical.
- `defer` for cleanup, immediately after acquiring the resource (`defer f.Close()`, `defer tx.Rollback()`).
- **Named return values sparingly** — only for short functions where they aid doc clarity; never with naked `return` in long bodies.

---

## §4. HTTP Service Conventions

**Detect the router the project uses** (echo, chi, gin, or stdlib `net/http` with 1.22+ pattern routing) and follow it. Do not introduce a second framework.

Layering is identical to `core-principles.md`: **handler → service → repository**.

- **Thin handlers**: decode + validate input, call one service method, encode the response. No business logic, no SQL.
- **Request/response DTO structs** per endpoint, validated at the boundary — `go-playground/validator` tags if the project uses it, otherwise a manual `Validate() error` method:

```go
type CreateOrderRequest struct {
    Items []OrderItemIn `json:"items" validate:"required,min=1,max=50,dive"`
    Memo  string        `json:"memo"  validate:"max=500"`
}
```

  Decode strictly where possible: `dec := json.NewDecoder(r.Body); dec.DisallowUnknownFields()` (mass-assignment defense, SEC-A4). Never unmarshal request bodies directly into DB entity structs.
- Services return domain errors (`ErrNotFound`, `*ValidationError`); a **single centralized error handler** (echo `HTTPErrorHandler`, chi middleware, or a shared `respondError` helper) maps them to the project's **single error envelope** — handlers never hand-build ad-hoc error JSON, clients branch on `code`, not message text.
- **Middleware** for cross-cutting concerns only: auth (populates principal into context), request logging, panic recovery, request ID. Order matters: recovery outermost, then logging, then auth.
- **Graceful shutdown** is required in every `main.go`:

```go
ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
defer stop()

srv := &http.Server{Addr: ":8080", Handler: router, ReadHeaderTimeout: 5 * time.Second}
go func() { _ = srv.ListenAndServe() }()

<-ctx.Done()
shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()
_ = srv.Shutdown(shutdownCtx)
```

  Always set `ReadHeaderTimeout` / `ReadTimeout` — the zero value means "wait forever" (slowloris).

---

## §5. Persistence

- **Prefer `database/sql` (+ pgx driver) or `sqlc`** (generated type-safe queries) over a heavy ORM. **GORM is acceptable if the project already uses it** — follow the incumbent, don't migrate.
- **Placeholders always** (SEC-N4). String-building SQL with user input is forbidden in any form:

```go
// ❌ Injection
rows, _ := db.QueryContext(ctx, "SELECT * FROM orders WHERE user_id = "+userID)
// ✅
rows, err := db.QueryContext(ctx, "SELECT * FROM orders WHERE user_id = $1", userID)
```

  Identifiers (table/column names) can't be placeholders — if dynamic, whitelist against a fixed map, never interpolate input.
- **Migrations via golang-migrate or goose** (follow whichever is present). **Never edit an applied migration** — fix forward with a new numbered migration. Up and down files in pairs. Destructive changes (drop column/table) need a stated backup/rollback plan in the PR.
- **Transactions**: explicit `Tx` owned by the service layer, with the defer-rollback pattern — rollback after commit is a harmless no-op, so the error path is always covered:

```go
tx, err := s.db.BeginTx(ctx, nil)
if err != nil {
    return fmt.Errorf("begin tx: %w", err)
}
defer tx.Rollback() //nolint:errcheck — no-op after successful Commit

if err := s.repo.SaveTx(ctx, tx, order); err != nil {
    return fmt.Errorf("save order: %w", err)
}
if err := tx.Commit(); err != nil {
    return fmt.Errorf("commit: %w", err)
}
```

- Always `defer rows.Close()` and check `rows.Err()` after the scan loop.

---

## §6. Testing (Go-Specific)

Universal doctrine (FIRST, Given-When-Then, coverage thresholds, never weaken tests) is in `testing.md`. Go additions:

**Table-driven tests are the canonical pattern** — use them for anything with more than one case:

```go
func TestCalculateDiscount(t *testing.T) {
    tests := []struct {
        name    string
        total   int64
        want    int64
        wantErr error
    }{
        {name: "below threshold gets none", total: 9_999, want: 0},
        {name: "at threshold gets 10 percent", total: 10_000, want: 1_000},
        {name: "negative total rejected", total: -1, wantErr: ErrInvalidTotal},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got, err := CalculateDiscount(tt.total)
            if !errors.Is(err, tt.wantErr) {
                t.Fatalf("err = %v, want %v", err, tt.wantErr)
            }
            if got != tt.want {
                t.Errorf("got %d, want %d", got, tt.want)
            }
        })
    }
}
```

- **`t.Run` subtests** always — named cases give precise failure output and selective runs (`go test -run TestX/at_threshold`).
- **`t.Parallel()`** where cases don't share mutable state. Verify safety with `go test -race ./...` (run race detector in CI at minimum).
- **testify is optional** — respect the project. If it isn't already a dependency, plain `if got != want` with `t.Errorf` is the standard; don't add assertion libraries for one test.
- **Handlers via `httptest`**: `httptest.NewRequest` + `httptest.NewRecorder` for unit-level, `httptest.NewServer` for full round-trips.
- **Interfaces + hand-written fakes over mock frameworks.** Consumer-side interfaces (§3) are small, so a fake is a few lines:

```go
type fakeRepo struct{ orders map[int64]*Order }
func (f *fakeRepo) FindByID(_ context.Context, id int64) (*Order, error) {
    o, ok := f.orders[id]
    if !ok { return nil, ErrNotFound }
    return o, nil
}
```

- **No `time.Sleep` in tests** — it's flaky at any duration. Synchronize with channels/`sync.WaitGroup`; on Go 1.24+ use `testing/synctest` for time-dependent concurrency; inject a clock (`func() time.Time` field) instead of calling `time.Now()` in domain code.
- **DB integration tests with testcontainers-go** (real Postgres in Docker), gated behind `testing.Short()` or a build tag so `go test ./...` stays fast.
- Coverage: `go test -coverprofile=cover.out ./... && go tool cover -func=cover.out`. Thresholds per `testing.md`.

---

## §7. Security Implementation Table

Go bindings for the `security.md` doctrine:

| Rule | Requirement | Go implementation |
|---|---|---|
| SEC-N5 | Password hashing | `golang.org/x/crypto/bcrypt` — `bcrypt.GenerateFromPassword(pw, bcrypt.DefaultCost)`; compare with `bcrypt.CompareHashAndPassword`. Never sha256/md5 for passwords. |
| SEC-A5 | JWT validation | `github.com/golang-jwt/jwt/v5` — parse with `jwt.WithValidMethods([]string{"HS256"})` (algorithm pinned) and `jwt.WithExpirationRequired()`. Never accept the token's own `alg` header unchecked. |
| SEC-A7 | Rate limiting | `golang.org/x/time/rate` — per-IP + per-account `rate.Limiter` in middleware on login/signup/password-reset. |
| SEC-O1 | CORS | `github.com/rs/cors` (or router equivalent) with an **explicit `AllowedOrigins` list** from config. `AllowedOrigins: ["*"]` with credentials is forbidden. |
| SEC-D2 | Dependency scanning | `govulncheck ./...` in CI — it reports only vulnerabilities in **reachable** code paths, so its findings are actionable and must be fixed, not filed away. |

Also: secrets from env/secret manager only — never in code or committed files; crypto randomness from `crypto/rand`, never `math/rand`, for tokens/IDs with security meaning.

---

## §8. Troubleshooting Table

| Symptom | Root cause | Fix |
|---|---|---|
| `panic: assignment to entry in nil map` | Declared map never initialized (`var m map[string]int`) | `m := make(map[string]int)` or literal; nil maps are read-only |
| All goroutines in a loop see the last element | Loop variable capture — Go **pre-1.22** shares one variable per loop | On old toolchains: `id := id` shadow copy or pass as argument; 1.22+ fixed per-iteration scoping — check the `go` directive before assuming |
| `if err != nil` is true but `err` "is" nil | Nil interface vs nil pointer: a typed nil pointer stored in an `error` interface is non-nil | Return literal `nil` on success, never a possibly-nil concrete pointer as `error` |
| Memory/goroutine count climbs steadily | Goroutine leak — blocked on channel/ctx that never closes, missing `cancel()` | Every goroutine needs an exit path; `defer cancel()` on every `context.WithTimeout/WithCancel`; watch `runtime.NumGoroutine()` in tests |
| `time.Parse` returns zero time or wrong values | Layout confusion — Go layouts are the reference time `2006-01-02 15:04:05`, not `YYYY-MM-DD` | Use the reference-time layout or constants like `time.RFC3339`; a layout like `"2026-01-02"` silently misparses |
| JSON field is always zero / input silently ignored | `json.Unmarshal` ignores unknown fields and unexported/untagged fields without error | Check struct tags match the payload (case, spelling); use `DisallowUnknownFields` at API boundaries (§4); fields must be exported |
| `http: superfluous response.WriteHeader call` | Handler wrote status twice, usually writing after an error response already sent | `return` immediately after every error response |
| Race detector fires only in CI | Unsynchronized shared state exposed by `t.Parallel()` | Treat every `-race` report as a real bug; guard with mutex or restructure ownership — never "fix" by removing `t.Parallel()` |

---

## §9. Deprecated / Do-Not-Follow Patterns

- ❌ `io/ioutil` (deprecated) → `os.ReadFile`, `io.ReadAll`
- ❌ `github.com/dgrijalva/jwt-go` (abandoned, CVE-laden) → `golang-jwt/jwt/v5` (§7)
- ❌ Layer-based packages (`handlers/`, `models/`, `services/` at top level) → §2 domain-based
- ❌ Central `interfaces` package / producer-side interfaces → §3 consumer-side, small
- ❌ `panic`/`log.Fatal` inside request handling or libraries → §3 return errors
- ❌ Global `var DB *sql.DB` reached into by packages → inject via constructors
- ❌ `time.Sleep` synchronization in tests → §6 channels / synctest / injected clock
- ❌ `math/rand` for tokens, `errors.New` string matching, `fmt.Errorf` without `%w` when callers need to unwrap
