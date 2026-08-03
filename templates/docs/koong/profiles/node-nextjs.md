# Profile: node-nextjs

> Loaded only when stack detected as node-nextjs (package.json with next dependency; plain Node/Express projects also use this profile's Node sections).
> Universal rules live in `core-principles.md` and `security.md` (rule IDs referenced below) and `testing.md`. This profile adds only what is specific to TypeScript / Node / Next.js.

---

## §1. Tooling & Commands

- **TypeScript strict mode is mandatory.** `tsconfig.json` must have `"strict": true`. Do not weaken it per-file with `// @ts-nocheck` or per-line with `// @ts-ignore` (use `// @ts-expect-error` with a reason comment only when genuinely unavoidable).
- **`any` is forbidden.** Use `unknown` at trust boundaries and narrow before use.

```ts
// ❌ any silently disables the type system
function handle(payload: any) { return payload.user.id; }

// ✅ unknown forces narrowing at the boundary
function handle(payload: unknown) {
  const parsed = orderSchema.parse(payload); // zod narrows to a known type
  return parsed.userId;
}
```

- ESLint + Prettier are the standard lint/format pair. Never fight the formatter — run it and commit the result.
- **Respect the project's package manager.** Detect from the lockfile: `package-lock.json` → npm, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn. Never introduce a second lockfile.
- **Verification combo** (run after every implementation phase; substitute `pnpm`/`yarn` as detected):

```bash
npm run lint && npx tsc --noEmit && npm test && npm run build
```

If any step fails, fix the production code and re-run. Do not skip `tsc --noEmit` — `next build` type checking can be disabled in config, the explicit check cannot.

---

## §2. Project Structure

App Router layout (adapt `src/` prefix to what the project already uses):

```text
src/
├── app/                      # Routes only — thin files
│   ├── (marketing)/          # Route groups for layout segmentation
│   ├── api/
│   │   └── orders/route.ts   # Route handler: parse → call service → respond
│   ├── layout.tsx
│   └── page.tsx
├── lib/                      # or server/ — domain modules (service layer)
│   ├── order/
│   │   ├── service.ts        # Business logic lives HERE
│   │   ├── schema.ts         # zod schemas (single source of truth)
│   │   └── repository.ts     # DB access (Prisma calls)
│   ├── auth/
│   └── config.ts             # Validated env (see §4)
├── components/               # Shared UI; feature components colocate near usage
└── middleware.ts             # Auth gate (edge)
```

Rules:
- **Domain logic NEVER lives in route files.** `app/**/route.ts`, `page.tsx`, and server actions are I/O adapters: parse input, call a `lib/<domain>/` (or `server/<domain>/`) service, shape the response. Same principle as thin controllers everywhere else.
- Colocation: components, hooks, and tests used by exactly one route live next to that route; anything shared by two or more routes moves to `components/` or `lib/`.
- Cross-domain calls go through the other domain's service module, never its repository.
- Any module that must not reach the client bundle imports the `server-only` package at the top:

```ts
// lib/order/service.ts
import 'server-only'; // build fails if a client component imports this
```

---

## §3. TypeScript Idioms

- **`type` for unions, intersections, and utilities; `interface` is fine for plain object shapes** — follow whichever the project already uses consistently, do not mix styles in one module.
- **Discriminated unions for state** — make illegal states unrepresentable:

```ts
// ❌ Boolean soup: what does { loading: true, error: 'x', data: [...] } mean?
type State = { loading: boolean; error?: string; data?: Order[] };

// ✅ Each state is exactly one shape
type State =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'success'; data: readonly Order[] };
```

- **No `enum`.** Use const objects with `as const` (no runtime surprises, erasable, unions for free):

```ts
// ❌ enum OrderStatus { Created, Paid }
// ✅
const ORDER_STATUS = { CREATED: 'CREATED', PAID: 'PAID', SHIPPED: 'SHIPPED' } as const;
type OrderStatus = (typeof ORDER_STATUS)[keyof typeof ORDER_STATUS];
```

- **zod schemas are the single source of truth for boundary types.** Derive the TS type; never hand-write a parallel interface that can drift:

```ts
export const orderCreateSchema = z.object({
  items: z.array(z.object({ productId: z.string().uuid(), quantity: z.number().int().positive() })).min(1),
  memo: z.string().max(500).optional(),
}).strict();

export type OrderCreateInput = z.infer<typeof orderCreateSchema>;
```

- **Narrow early, return early.** Guard clauses over nested `if`/`else` pyramids.
- **No non-null assertions (`!`).** Narrow instead:

```ts
// ❌ const user = await findUser(id)!;   // runtime bomb
// ✅
const user = await findUser(id);
if (!user) throw new NotFoundError('USER_NOT_FOUND');
```

- `readonly` on array/object types that are not meant to be mutated; `Readonly<T>` for frozen config shapes.
- `async/await` over `.then()` chains. Never mix the two styles in one function.
- **Named exports over default exports** — greppable, rename-safe. Exception: Next.js conventions that require default exports (`page.tsx`, `layout.tsx`, `middleware.ts`, error/loading files).

---

## §4. Next.js Server Conventions

### 4.1 Server/Client Component Discipline

Components are **server by default**. `'use client'` goes only on interactive leaves (forms, buttons with handlers, hooks users) — never on layouts or pages wholesale. Every `'use client'` boundary drags its entire import subtree into the browser bundle.

### 4.2 Route Handlers — Thin, Validated, Enveloped

Parse with zod `.strict()` (rejects unknown keys — mass assignment defense, **SEC-A4**) → call service → return the single project envelope:

```ts
// app/api/orders/route.ts
export async function POST(req: NextRequest) {
  const principal = await requirePrincipal(req);          // 401 if absent

  const body = orderCreateSchema.safeParse(await req.json());
  if (!body.success) {
    return NextResponse.json(
      { success: false, code: 'VALIDATION_FAILED', errors: body.error.flatten().fieldErrors },
      { status: 400 },
    );
  }

  const order = await createOrder(principal.userId, body.data); // lib/order/service.ts
  return NextResponse.json({ success: true, code: 'OK', data: order }, { status: 201 });
}
```

- One error envelope shape project-wide: `{ success, code, message?, data?, errors? }`. Clients branch on `code` (enum-like string constants), never on message text.
- Domain errors are mapped to HTTP status + code in one shared helper, not ad-hoc per route.

### 4.3 Middleware Auth Gate

`middleware.ts` verifies the session/JWT before protected routes render. Use `jose` with the **algorithm pinned** (**SEC-A5**):

```ts
import { jwtVerify } from 'jose';

const { payload } = await jwtVerify(token, secret, {
  algorithms: ['HS256'],          // ❌ never omit — algorithm-confusion attacks
  issuer: 'koong',
  audience: 'koong-web',
});
```

Middleware gates coarse access; route handlers and services still enforce ownership (**SEC-A2** — never trust "middleware already checked").

### 4.4 Server Actions

Server actions are public HTTP endpoints in disguise. **Never trust `formData`** — validate with the same zod schemas and re-check authorization inside the action:

```ts
// ❌ const name = formData.get('name') as string;  await db.user.update(...)
// ✅
'use server';
export async function updateProfile(formData: FormData) {
  const principal = await requirePrincipal();
  const input = profileSchema.strict().parse(Object.fromEntries(formData));
  return updateUserProfile(principal.userId, input);
}
```

### 4.5 Environment Variables

All env access goes through one validated, server-only config module — fail fast at boot, not at first use:

```ts
// lib/config.ts
import 'server-only';
import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  NODE_ENV: z.enum(['development', 'test', 'production']),
});

export const env = envSchema.parse(process.env); // throws at startup if missing
```

- ❌ `process.env.JWT_SECRET!` scattered through the codebase.
- **NEVER put secrets in `NEXT_PUBLIC_*`** — those are inlined into the client bundle at build time and are public forever (SEC-N territory: treat it as publishing the secret).

---

## §5. Persistence (Prisma / Drizzle)

Detect the ORM from dependencies; conventions below are Prisma-first, same principles apply to Drizzle (`drizzle-kit generate`/`migrate`, schema files as source of truth).

- **`schema.prisma` is the source of truth.** Change the schema, then generate a migration — never hand-edit the DB.
- Dev: `npx prisma migrate dev --name add_order_status`. Prod/CI: `npx prisma migrate deploy`.
- **Never edit an applied migration.** Fix forward with a new migration (same iron rule as Flyway).
- Multi-step writes that must succeed or fail together use `$transaction`:

```ts
// ✅ interactive transaction for read-then-write consistency
await prisma.$transaction(async (tx) => {
  const product = await tx.product.findUniqueOrThrow({ where: { id } });
  if (product.stock < qty) throw new BusinessError('INSUFFICIENT_STOCK');
  await tx.product.update({ where: { id }, data: { stock: { decrement: qty } } });
  await tx.order.create({ data: { ... } });
});
```

- **N+1 discipline**: fetch relations with `include`/`select` in one query — never loop-and-query:

```ts
// ❌ N+1
for (const order of orders) {
  const items = await prisma.orderItem.findMany({ where: { orderId: order.id } });
}

// ✅ one query, and select only what the response needs
const orders = await prisma.order.findMany({
  where: { customerId },
  select: { id: true, status: true, items: { select: { productId: true, quantity: true } } },
});
```

- **No raw SQL built by string concatenation (SEC-N4).** If raw SQL is unavoidable, use the tagged template `prisma.$queryRaw` (parameterized) — never `$queryRawUnsafe` with interpolated input.

---

## §6. Testing (Stack Specifics)

Universal doctrine (FIRST, the Iron Rule, coverage, structure) lives in `testing.md` — this section is only the Node/Next.js toolbox. Detect the runner from the project: Vitest preferred, Jest if already in place. Do not switch runners mid-project.

- **API route handlers**: test by direct invocation (construct a `NextRequest`, call the exported `GET`/`POST`, assert on status + envelope). For Express apps, use `supertest` against the app instance — no real server port needed.

```ts
it('returns 400 with VALIDATION_FAILED when items is empty', async () => {
  const req = new NextRequest('http://test/api/orders', {
    method: 'POST', body: JSON.stringify({ items: [] }),
  });

  const res = await POST(req);
  const body = await res.json();

  expect(res.status).toBe(400);
  expect(body).toMatchObject({ success: false, code: 'VALIDATION_FAILED' });
});
```

- **External HTTP: MSW, never real calls.** `setupServer(...)` in test setup, `server.use(...)` per test for error cases. A test that hits a real payment/LLM/email API is a broken test.
- **Time**: `vi.useFakeTimers()` + `vi.setSystemTime(new Date('2026-01-15T09:00:00Z'))`; restore in `afterEach`. Never `await sleep(...)` around real timers.
- **Fixtures**: factory functions with valid-minimum defaults (see `testing.md` §7):

```ts
export const anOrder = (overrides: Partial<Order> = {}): Order =>
  ({ id: 'ord_1', status: 'CREATED', items: [anItem()], ...overrides });
```

- Services are tested with their repository/gateway dependencies injected as fakes or `vi.fn()` mocks; do not mock the service under test itself.

### 6.1 Frontend Testing (Condensed)

- **Component tests verify what the user sees**, not implementation. Query by role/label (`getByRole('button', { name: 'Sign Up' })`), simulate with `userEvent`, assert on visible output. Never assert on state variable names or internal handler calls — those break on refactor.
- **Integration tests** render the component tree with MSW serving the standard API envelope; use `findBy*` / `waitFor` for async UI — never fixed sleeps.
- **E2E via Playwright**: real user flows only (login → act → verify). No `page.waitForTimeout(...)` — use `await expect(locator).toBeVisible()`, `page.waitForResponse(...)`, and other condition-based waits. Screenshots/traces on failure.

---

## §7. Security Implementation Table

Doctrine and rule IDs live in `security.md`; this table maps them to the Node/Next.js implementation of record.

| Rule | Requirement | Node/Next.js implementation |
|---|---|---|
| SEC-N5 | Password hashing | `bcrypt` (native) with cost ≥ 12. Use `bcryptjs` only if the environment cannot build native modules — note it in the PR. Never SHA-256/MD5, never home-rolled. |
| SEC-A5 | JWT | `jose` — `jwtVerify` with `algorithms` pinned, `issuer`/`audience` checked, short-lived access tokens. Never `decode` without verify. |
| SEC-A7 | Rate limiting | `@upstash/ratelimit` (Redis) on auth and expensive endpoints; a middleware token bucket is acceptable for single-instance deployments. |
| SEC-O1 | CORS | Explicit origin allowlist in middleware/route config. `Access-Control-Allow-Origin: *` is forbidden on any authenticated route. |
| SEC-D2 | Dependency audit | `npm audit --omit=dev` (or `pnpm audit --prod`) clean of high/critical before merge. |
| SEC-I2 | File uploads | Enforce size limit before buffering, validate MIME by **magic bytes** (e.g. `file-type` package), never trust the client `Content-Type` or filename extension; store outside the web root / in object storage with a generated name. |

---

## §8. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| **Hydration mismatch** warnings | Server and client rendered different HTML: `Date`/locale formatting, `Math.random()`, or browser-only APIs during render. Move nondeterminism into `useEffect`, or format dates with a fixed locale/timezone on both sides. |
| **Server code error in browser** ("Module not found: fs", secret undefined) | A `'use client'` component imports server-only code. Add `import 'server-only'` to server modules so the build fails loudly, and pass data down as props instead of importing the module. |
| **`process.env.X` undefined** | Build vs runtime: `NEXT_PUBLIC_*` is inlined at **build** time (rebuild after changing it); server vars are read at runtime (check the deploy environment, not `.env.local`). Dynamic access `process.env[name]` is not inlined for client code at all. |
| **Prisma: "too many connections" in dev** | Hot reload creates a new `PrismaClient` per reload. Use the global singleton pattern: `globalThis.prisma ??= new PrismaClient()` in dev, plain instantiation in prod. |
| **Date becomes string across server/client boundary** | Props from server to client components are serialized; `Date` survives RSC serialization but not `JSON.stringify` in route handlers. Standardize on ISO-8601 strings in API envelopes and parse at the edge of the client. |
| **Middleware fails with Node API errors** | `middleware.ts` runs on the edge runtime: no `fs`, no native modules (no `bcrypt`, no Prisma). Keep middleware to token verification (`jose` is edge-safe) and do DB-backed checks in route handlers/services. |
