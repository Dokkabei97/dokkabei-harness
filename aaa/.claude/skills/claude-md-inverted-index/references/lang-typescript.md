# Node.js / TypeScript Ecosystem -- Inverted Index Guide

Covers Next.js App Router, NestJS, Turborepo/Nx monorepos, and pnpm workspaces.
TypeScript projects hide code behind barrel exports and path aliases -- the index must cut through both.

## Next.js App Router Patterns

Next.js App Router splits code across three separate trees that the agent must navigate.

```markdown
## Tech -> Location Map

### Next.js Routing
- pages (app router): src/app/
- route groups: src/app/(auth)/, src/app/(dashboard)/
- layouts: src/app/**/layout.tsx
- loading UI: src/app/**/loading.tsx
- error boundary: src/app/**/error.tsx
- not-found: src/app/**/not-found.tsx

### Server Actions
- actions: src/app/_actions/ or co-located src/app/**/actions.ts
- server-only: files with "use server" directive

### API Routes
- route handlers: src/app/api/**/route.ts
- middleware: src/middleware.ts (root level, singular)

### Client Components
- components: src/components/ (shared UI)
- feature components: src/app/(feature)/_components/
- hooks: src/hooks/ or src/lib/hooks/
- providers: src/providers/

### Data Layer
- server queries: src/lib/queries/ or src/server/
- database: src/lib/db/ (Prisma client, Drizzle schema)
- auth: src/lib/auth/ or src/auth/ (NextAuth/Lucia)
- cache/revalidation: co-located with data fetching functions
```

### 3-Way Split Pattern

Next.js forces a 3-way code split. Document this explicitly:

```markdown
## Next.js 3-Way Split
| Concern          | Location                        | Runtime     |
|------------------|---------------------------------|-------------|
| Route/Page UI    | src/app/**/page.tsx             | Server(RSC) |
| Business logic   | src/lib/**                      | Server      |
| Interactive UI   | src/components/**               | Client      |
```

## NestJS Patterns

```markdown
## Tech -> Location Map

### NestJS Core
- modules: src/modules/{feature}/{feature}.module.ts
- controllers: src/modules/{feature}/{feature}.controller.ts
- services: src/modules/{feature}/{feature}.service.ts
- DTOs: src/modules/{feature}/dto/

### NestJS Infrastructure
- guards: src/common/guards/
- interceptors: src/common/interceptors/
- pipes: src/common/pipes/
- filters: src/common/filters/
- decorators: src/common/decorators/

### Queue Processing
- processors: src/modules/{feature}/processors/
- bull config: src/config/queue.config.ts

### Database (TypeORM/Prisma)
- entities: src/modules/{feature}/entities/
- repositories: src/modules/{feature}/repositories/
- migrations: src/database/migrations/
```

## Turborepo / Nx Monorepo Structure

```
project-root/
  turbo.json                    # Pipeline definitions
  pnpm-workspace.yaml           # Workspace members
  apps/
    web/                        # Next.js frontend
    admin/                      # Admin dashboard
    api/                        # NestJS/Express backend
    worker/                     # Background job processor
  packages/
    ui/                         # Shared UI component library
    db/                         # Database schema + client (Prisma/Drizzle)
    auth/                       # Shared authentication logic
    config-eslint/              # Shared ESLint config
    config-typescript/          # Shared tsconfig
    email/                      # Email templates + sending
    types/                      # Shared TypeScript types
```

```markdown
## Tech -> Location Map

### Shared Packages (used across apps)
- UI components: packages/ui/src/
- DB schema: packages/db/src/schema.ts
- DB client: packages/db/src/client.ts
- Auth logic: packages/auth/src/
- Shared types: packages/types/src/

### Frontend (apps/web)
- pages: apps/web/src/app/
- API calls: apps/web/src/lib/api/
- state: apps/web/src/store/

### Backend (apps/api)
- routes: apps/api/src/routes/
- services: apps/api/src/services/
- middleware: apps/api/src/middleware/

### Impact Scope Warnings
- packages/db/ changes affect: apps/web, apps/api, apps/admin, apps/worker
- packages/types/ changes affect: ALL apps
- packages/ui/ changes affect: apps/web, apps/admin
- packages/auth/ changes affect: apps/web, apps/api, apps/admin
```

## Barrel Export (index.ts) Warnings

Barrel exports are the biggest trap for AI agents in TypeScript projects.
`index.ts` files re-export from actual source files, making Grep results misleading.

```markdown
## Barrel Export Warnings
Do NOT edit index.ts barrel files directly. Find the real source:

| Barrel File               | Re-exports From                        |
|---------------------------|----------------------------------------|
| packages/ui/src/index.ts  | packages/ui/src/components/*.tsx        |
| packages/db/src/index.ts  | packages/db/src/schema.ts, client.ts   |
| packages/types/src/index.ts| packages/types/src/*.ts                |
| src/lib/index.ts          | src/lib/utils.ts, src/lib/constants.ts |

Rule: When you find a symbol in index.ts, trace the import to the actual file.
```

## Generated Files -- DO NOT MODIFY

```markdown
## Generated Files (DO NOT MODIFY)
- node_modules/              # dependency artifacts
- .next/                     # Next.js build output
- packages/db/src/generated/ # Prisma client (prisma generate)
- src/lib/api/generated/     # OpenAPI codegen output
- src/__generated__/         # GraphQL codegen (graphql-codegen)
- src/trpc/                  # tRPC router types (auto-inferred, but check)
```

## Path Alias Resolution

TypeScript projects use `@/` aliases that hide the real path:

```markdown
## Path Aliases (tsconfig.json paths)
| Alias            | Resolves To              |
|------------------|--------------------------|
| @/               | src/                     |
| @/components/*   | src/components/*         |
| @/lib/*          | src/lib/*                |
| @repo/ui         | packages/ui/src          |
| @repo/db         | packages/db/src          |
| @repo/auth       | packages/auth/src        |
```

## node_modules Noise Elimination

Always add to CLAUDE.md:

```markdown
## Search Exclusions
When searching, exclude: node_modules/, .next/, dist/, build/, coverage/,
*.d.ts (type declarations), *.js.map (source maps)
```

## pnpm Workspace Auto-Extraction

```bash
# Extract workspace members from pnpm-workspace.yaml
cat pnpm-workspace.yaml | grep "  - " | sed 's/  - //'

# Or from package.json workspaces field
node -e "console.log(require('./package.json').workspaces?.join('\n'))"

# List all packages with their names
find apps packages -name package.json -maxdepth 2 -exec \
  node -e "const p=require('./' + process.argv[1]); console.log(p.name + ' -> ' + process.argv[1].replace('/package.json',''))" {} \;
```

## Complete 3-Tier Example

### Part 1 -- Root CLAUDE.md

The root CLAUDE.md contains the workspace map, path aliases, barrel export warnings,
impact scope, entry points, generated file warnings, and references to `.claude/rules/` files.

```markdown
# Project: Acme SaaS Platform

## Workspace Map

### Next.js (apps/web)
- pages: apps/web/src/app/
- server actions: apps/web/src/app/_actions/
- API routes: apps/web/src/app/api/
- middleware: apps/web/src/middleware.ts
- components: apps/web/src/components/

### NestJS API (apps/api)
- modules: apps/api/src/modules/
- guards: apps/api/src/common/guards/
- interceptors: apps/api/src/common/interceptors/

### Database (packages/db)
- schema: packages/db/src/schema.ts
- client: packages/db/src/client.ts
- migrations: packages/db/migrations/

### Auth (packages/auth)
- config: packages/auth/src/config.ts
- providers: packages/auth/src/providers/

### Shared UI (packages/ui)
- components: packages/ui/src/components/

## Path Aliases (tsconfig.json paths)
| Alias       | Resolves To         |
|-------------|---------------------|
| @/          | src/                |
| @repo/ui    | packages/ui/src     |
| @repo/db    | packages/db/src     |
| @repo/auth  | packages/auth/src   |

## Barrel Exports -- trace to real source
- packages/ui/src/index.ts re-exports from components/*.tsx
- packages/db/src/index.ts re-exports from schema.ts, client.ts
- packages/auth/src/index.ts re-exports from config.ts, providers/

## Impact Scope
- packages/db/ changes -> apps/web, apps/api, apps/admin, apps/worker (ALL)
- packages/types/ changes -> ALL apps
- packages/ui/ changes -> apps/web, apps/admin
- packages/auth/ changes -> apps/web, apps/api, apps/admin

## Entry Points
- Web: apps/web/src/app/layout.tsx
- API: apps/api/src/main.ts
- Worker: apps/worker/src/index.ts

## Generated Files (DO NOT MODIFY)
- node_modules/
- .next/
- packages/db/src/generated/ (prisma generate)
- src/lib/api/generated/ (OpenAPI codegen)
- src/__generated__/ (GraphQL codegen)

## Rules
See .claude/rules/ for framework-specific conventions:
- nextjs.md -- Next.js App Router patterns and constraints
- nestjs.md -- NestJS module patterns and DI conventions
- testing.md -- test structure and mocking strategy
```

### Part 2 -- `.claude/rules/nextjs.md`

Individual rule files use `paths` frontmatter so they activate only
when the agent touches matching files.

```markdown
---
paths:
  - apps/web/**
  - packages/ui/**
---

# Next.js App Router Conventions

## Server vs Client Split
- Default to Server Components (RSC). Add "use client" only for interactivity.
- Server Actions live in `apps/web/src/app/_actions/` with "use server" directive.
- Never import server-only code from "use client" files.

## Data Fetching
- Use `fetch()` in Server Components with `next: { revalidate }` or `cache`.
- For mutations, use Server Actions -- not API route handlers.
- Database calls go through `packages/db` -- never call Prisma directly from components.

## Route Group Rules
- `(auth)` group: all pages require authentication via middleware.
- `(marketing)` group: public pages, no auth required.
- `(dashboard)` group: role-based access, check `session.user.role`.

## Component Patterns
- Shared UI primitives: import from `@repo/ui` (packages/ui).
- Feature-specific components: co-locate in `_components/` within the route folder.
- Client wrappers: suffix with `.client.tsx` if wrapping a server component for interactivity.

## Common Pitfalls
- Do NOT use `useEffect` for data fetching -- use Server Components or `use()`.
- Do NOT put `"use client"` at the top of page.tsx -- pages should be server components.
- Middleware (`apps/web/src/middleware.ts`) runs on Edge -- no Node.js APIs.
```
