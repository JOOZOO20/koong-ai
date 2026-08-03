# Python Profile

> Loaded only when stack detected as python (pyproject.toml / requirements.txt present).
>
> This profile adds **Python/FastAPI-specific rules only**. Universal principles live in
> `core-principles.md`, the security doctrine (SEC-* rule IDs) in `security.md`, and the
> universal test doctrine in `testing.md`. Where this profile cites a SEC-* ID, it is
> showing the Python **implementation** of that rule — the rule itself is defined in `security.md`.

---

## §1. Tooling & Commands

**Preferred toolchain**: `uv` for dependency/venv management, `ruff` for lint + format, `mypy` for type checking, `pytest` for tests. If the project already uses poetry or plain pip, **respect the existing choice** — never migrate tooling as a side effect of a feature task.

Detect what the project uses before running anything:

| Evidence | Tool in use |
|---|---|
| `uv.lock` | uv (`uv sync`, `uv run <cmd>`) |
| `poetry.lock` | poetry (`poetry install`, `poetry run <cmd>`) |
| only `requirements.txt` | pip + venv (`pip install -r requirements.txt`) |
| `[tool.ruff]` / `ruff.toml` | ruff configured — use its settings, don't override |
| `[tool.mypy]` / `mypy.ini` | mypy configured — don't loosen strictness flags |

**Verification combo** (run after every implementation task; all four must pass):

```bash
ruff check . && ruff format --check . && mypy . && pytest
```

With uv: `uv run ruff check . && uv run ruff format --check . && uv run mypy . && uv run pytest`

Rules:
- Fix lint/type errors in the code, never by sprinkling `# noqa` / `# type: ignore`. A suppression comment requires a justification comment on the same line and should be rare.
- mypy should run strict-ish: at minimum `disallow_untyped_defs`, `no_implicit_optional`, `warn_return_any`. If the project config is stricter, keep it that way.
- Never `pip install` into the global interpreter. Always work inside the project venv.

---

## §2. Project Structure

Use **domain-based modules, not layer-based**. Top-level `routers/`, `services/`, `models/` directories rot as the project grows — group by domain instead:

```text
app/                      # or src/<package>/ — follow the existing layout
├── main.py               # FastAPI app factory, router registration, exception handlers
├── core/
│   ├── config.py         # Settings (pydantic-settings)
│   ├── db.py             # engine, session factory, get_db dependency
│   └── security.py       # password hashing, JWT encode/decode
├── common/               # shared envelope, base exceptions, pagination
├── auth/
│   ├── router.py
│   ├── service.py
│   ├── repository.py
│   ├── schemas.py        # Pydantic request/response models
│   └── exceptions.py
├── order/
│   ├── router.py
│   ├── service.py
│   ├── repository.py
│   ├── models.py         # SQLAlchemy ORM models
│   └── schemas.py
└── ...
```

Rules:
- **No direct cross-domain imports of models/repositories.** Cross-domain calls go through the other domain's service functions.
- Every package directory has an `__init__.py`. Keep them empty or limited to explicit re-exports — no logic, no import-time side effects.
- No `utils.py` dumping ground. Name modules by what they contain (`pagination.py`, `slugify.py`).

**Settings — pydantic-settings, fail fast** (missing secrets must crash at startup, not at first use):

```python
# core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str          # no default → startup fails if env var missing
    jwt_secret: str            # never a default value for secrets
    jwt_expires_minutes: int = 15
    debug: bool = False

settings = Settings()  # raises ValidationError at import time if secrets absent
```

❌ `os.getenv("JWT_SECRET", "dev-secret")` — silent insecure fallback.
✅ Required field with no default — deployment with missing config fails immediately and loudly.

---

## §3. Python Idioms

- **Type hints everywhere.** All function signatures fully annotated. Use PEP 604 syntax: `str | None`, not `Optional[str]`; `list[int]`, not `List[int]`.
- **Pydantic at boundaries, plain classes inside.** Pydantic models for request/response/settings (things that need parsing + validation). Internal value objects and inter-layer data use `@dataclass(frozen=True)` or plain classes — don't pay validation cost where data is already trusted.
- **pathlib over os.path**: `Path(base) / "reports" / name`, not `os.path.join(...)`.
- **f-strings** for formatting. Exception: logging uses lazy `%s` args — `log.info("order %s created", order_id)` — so formatting is skipped when the level is off.
- **Context managers** for anything that opens/locks/connects: `with open(...)`, `with session.begin()`. Never rely on GC for cleanup.
- **Comprehensions over loops** when they stay readable (single condition, single transform). A nested triple comprehension is worse than a loop — clarity wins.
- **EAFP where idiomatic**: `try: return cache[key] except KeyError:` beats check-then-use, which is also race-prone. Use LBYL when the exception path is genuinely exceptional and expensive.
- **No mutable default arguments** — evaluated once at def time:

```python
# ❌ Bug: one shared list across all calls
def add_item(item: str, items: list[str] = []) -> list[str]: ...

# ✅
def add_item(item: str, items: list[str] | None = None) -> list[str]:
    items = items if items is not None else []
```

- **Composition over inheritance.** No deep class hierarchies, no mixin stacks for code reuse. A service is a plain class (or module of functions) that receives its dependencies. `__all__` is optional — don't add it ritually.
- **Small functions.** If a function needs section comments, split it.

---

## §4. Web Framework Conventions

### 4.1 FastAPI (primary framework)

**Routers per domain** — one `APIRouter` per domain module, registered in `main.py`:

```python
# order/router.py
router = APIRouter(prefix="/orders", tags=["orders"])

@router.post("", response_model=ApiResponse[OrderResponse], status_code=201)
async def create_order(
    payload: OrderCreateRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ApiResponse[OrderResponse]:
    order = await order_service.create(db, user.id, payload)
    return ApiResponse.ok(order)
```

Rules:
- **Thin handlers**: parse input, resolve dependencies, call one service function, wrap response. No business logic, no queries in routers.
- **Dependency injection via `Depends`** for auth, DB sessions, settings, pagination — never module-level globals reached into by handlers. `get_current_user` is the only place a token is decoded.
- **Pydantic v2 request models forbid unknown fields** (mass-assignment defense, SEC-A4):

```python
class OrderCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")   # rejects {"is_admin": true} injections
    items: list[OrderItemIn] = Field(min_length=1, max_length=50)
    memo: str | None = Field(default=None, max_length=500)
```

- **`response_model` always set** on every route. It is the output filter — an ORM object leaked without it exposes every column (password hashes included).
- **`async def` only when the body actually awaits.** A sync-only handler declared `async` blocks the event loop when it does blocking I/O; a blocking call inside `async def` stalls every request. Plain `def` handlers run in the threadpool — that is the correct choice for sync libraries.
- **`HTTPException` only in routers/dependencies.** Services raise domain exceptions; exception handlers map them:

```python
# common/exceptions.py
class DomainError(Exception):
    code = "COMMON_001"
    status = 400

class OrderNotFoundError(DomainError):
    code = "ORDER_404"
    status = 404

# main.py — single global error envelope, one handler
@app.exception_handler(DomainError)
async def domain_error_handler(request: Request, exc: DomainError) -> JSONResponse:
    return JSONResponse(status_code=exc.status,
                        content={"success": False, "code": exc.code, "message": str(exc)})
```

Never build ad-hoc error JSON in a handler; never let clients branch on message strings — branch on `code`.

### 4.2 Django (when detected instead)

- **Fat models / services, thin views.** Business rules live on the model or a service module, never in views or templates.
- **DRF serializers at boundaries** with explicit `fields = [...]` — never `fields = "__all__"` (mass assignment, SEC-A4).
- **N+1**: any serializer touching relations needs `select_related` (FK) / `prefetch_related` (M2M, reverse FK) on the queryset. Verify with `django-debug-toolbar` or `assertNumQueries` in tests.
- Migrations: same doctrine as §5 — never edit applied migrations.

---

## §5. Persistence — SQLAlchemy 2.0 + Alembic

**SQLAlchemy 2.0 style only.** No legacy `session.query(...)`:

```python
# ❌ Legacy 1.x style
orders = session.query(Order).filter(Order.user_id == user_id).all()

# ✅ 2.0 style
stmt = select(Order).where(Order.user_id == user_id).order_by(Order.created_at.desc())
orders = (await session.execute(stmt)).scalars().all()
```

- **Parameter binding always** (SEC-N4). SQLAlchemy expressions bind automatically. Raw SQL uses `text()` with bound params — string interpolation into SQL is forbidden in any form:

```python
# ❌ Injection
await session.execute(text(f"SELECT * FROM orders WHERE user_id = {user_id}"))
# ✅
await session.execute(text("SELECT * FROM orders WHERE user_id = :uid"), {"uid": user_id})
```

- **N+1 prevention**: relationships accessed after a list query need eager loading — `selectinload(Order.items)` for collections (default choice), `joinedload(Order.customer)` for to-one. Accessing a lazy relationship in a loop is a review-blocking defect. With `AsyncSession`, un-eager-loaded lazy access doesn't just go slow — it raises `MissingGreenlet`.
- Session lifecycle: one session per request via the `get_db` dependency; the service layer owns transaction boundaries (`async with session.begin()` or explicit commit in the dependency).

**Alembic migrations**:
- **Never edit a migration that has been applied anywhere** (including a teammate's machine or CI). Fix forward with a new revision.
- `alembic revision --autogenerate` output must be **reviewed line by line** — autogenerate misses server defaults, constraint renames, enum value changes, and some index alterations. Treat it as a draft, not a result.
- Adding **NOT NULL to an existing column takes 3 steps** (separate revisions/deploys): (1) add column nullable, (2) backfill data, (3) add the NOT NULL constraint. A single-step NOT NULL on a populated table fails or locks.
- Every `upgrade()` gets a real `downgrade()` unless genuinely impossible — then say why in the docstring.

---

## §6. Testing (Python-Specific)

Universal doctrine (FIRST, Given-When-Then, coverage thresholds, never weaken tests) is in `testing.md`. Python additions:

- **Fixtures in `conftest.py`**, scoped tightly (`function` default; `session` scope only for expensive immutable resources like a containerized DB). Avoid fixtures that request three other fixtures that each request more — **prefer plain factory functions** for test data:

```python
def make_order(*, user_id: int = 1, status: str = "PENDING", **kw) -> Order:
    return Order(user_id=user_id, status=status, **kw)
```

- **`pytest.mark.parametrize` for boundary tables** — one parametrized test beats five copy-pasted ones:

```python
@pytest.mark.parametrize("quantity, ok", [(0, False), (1, True), (50, True), (51, False)])
def test_quantity_bounds(quantity: int, ok: bool) -> None: ...
```

- **API tests via httpx**: `TestClient(app)` for sync suites, `AsyncClient(transport=ASGITransport(app=app), base_url="http://test")` for async. Override dependencies with `app.dependency_overrides[get_db] = ...` — do not monkeypatch internals of FastAPI.
- **No real external calls** (testing.md rule, Python tooling): stub HTTP with `respx` (for httpx) or `responses` (for requests); `monkeypatch` for env vars and module attributes. A test that hits a live API is a broken test.
- **Time is injected**: freeze with `freezegun` (`@freeze_time("2026-01-01T00:00:00Z")`) or, better, inject a `now: Callable[[], datetime]` dependency. Never assert against real wall-clock time.
- **Coverage** via pytest-cov: `pytest --cov=app --cov-report=term-missing`. Thresholds per `testing.md` (80% overall, 100% for money/auth paths).
- Async tests: `pytest-asyncio` (or anyio) with the project's configured mode — check `pyproject.toml` before adding markers.

---

## §7. Security Implementation Table

Python bindings for the `security.md` doctrine. The SEC-* rule defines *what*; this table fixes *which library and how*:

| Rule | Requirement | Python implementation |
|---|---|---|
| SEC-N5 | Password hashing | `passlib[bcrypt]` (`CryptContext(schemes=["bcrypt"])`) or `argon2-cffi`. Never hashlib/md5/sha for passwords. |
| SEC-A5 | JWT validation | `PyJWT`: `jwt.decode(token, key, algorithms=["HS256"], options={"require": ["exp"]})` — algorithm list **pinned**, `exp` **required**. Never `algorithms=None` or decode without verification. |
| SEC-A7 | Rate limiting | `slowapi` limiter on login/signup/password-reset routes (e.g., `@limiter.limit("5/minute")`), keyed per IP + per account. |
| SEC-O1 | CORS | `CORSMiddleware` with an **explicit origin list** from settings. `allow_origins=["*"]` combined with `allow_credentials=True` is forbidden. |
| SEC-D2 | Dependency scanning | `pip-audit` (works on uv/poetry/pip environments) in CI; fail the build on known-vulnerable pins. |
| SEC-I* | Upload limits | `python-multipart` present for form uploads; enforce max body size at the reverse proxy **and** validate `UploadFile` size/content-type in the handler before reading. |

Also: secrets only via `Settings` (§2) — never hardcoded, never logged; Pydantic `SecretStr` for fields that must not appear in `repr()`.

---

## §8. Troubleshooting Table

| Symptom | Root cause | Fix |
|---|---|---|
| All requests slow / server "freezes" under load | Blocking call (`requests`, `time.sleep`, sync DB driver) inside `async def` | Use async libraries (httpx, asyncpg) or make the handler plain `def` so it runs in the threadpool |
| List endpoint fires hundreds of near-identical SELECTs | N+1 lazy loading | `selectinload`/`joinedload` on the query (§5); with AsyncSession the same bug appears as `MissingGreenlet` |
| Alembic migration "applied" but schema unchanged / wrong | Autogenerate missed the change (server defaults, renames, enum edits) | Always review the generated revision; write manual `op.*` calls for what autogenerate can't see |
| `TypeError: can't subtract offset-naive and offset-aware datetimes`; times shift between environments | Naive datetimes (`datetime.now()`, `datetime.utcnow()`) | Always `datetime.now(tz=timezone.utc)`; store TIMESTAMPTZ; treat any naive datetime as a bug |
| Function "remembers" data across calls | Mutable default argument | `param: list | None = None` then default inside the body (§3) |
| `ImportError: cannot import name ... (most likely due to a circular import)` | Two domain modules importing each other at module level | Restructure so dependencies point one way; move shared types to `common/`; last resort `if TYPE_CHECKING:` import for annotations only |
| Response missing fields / leaking extra fields | `response_model` absent or ORM object returned raw | Set `response_model` on every route; response schema with `model_config = ConfigDict(from_attributes=True)` |
| Tests pass alone, fail together | Shared state: session-scoped fixture holding data, module-level cache, un-rolled-back DB | Function-scoped fixtures, transaction-per-test with rollback, reset caches in fixture teardown |

---

## §9. Deprecated / Do-Not-Follow Patterns

- ❌ `session.query(...)` legacy API → §5 SQLAlchemy 2.0 `select()`
- ❌ `Optional[X]` / `List[X]` typing imports in new code → §3 PEP 604 / builtin generics
- ❌ `datetime.utcnow()` (deprecated, returns naive) → `datetime.now(tz=timezone.utc)`
- ❌ `os.path.join` chains in new code → §3 pathlib
- ❌ Pydantic v1 patterns (`class Config`, `.dict()`, `validator`) → v2 (`model_config`, `.model_dump()`, `field_validator`)
- ❌ Business logic in routers, `HTTPException` raised from services → §4.1 layering
- ❌ `allow_origins=["*"]` with credentials, unpinned JWT algorithms, default-value secrets → §7
