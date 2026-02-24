---
name: turborepo
target-stack: TypeScript Turborepo/Nx/pnpm Workspace
placeholders: ["{scope}", "{app}"]
---

# Turborepo -- Inverted Index Template

## Part 1: PROJECT_ROOT/CLAUDE.md

(Copy this section to your project root's `CLAUDE.md`. Not `~/.claude/CLAUDE.md`.)

```markdown
## Workspace Map

### Apps
| App               | Path          | Framework     | Port  |
|-------------------|---------------|---------------|-------|
| {scope}/web       | apps/web/     | Next.js       | 3000  |
| {scope}/api       | apps/api/     | Express/Hono  | 4000  |
| {scope}/admin     | apps/admin/   | Next.js       | 3001  |

### Shared Packages
| Package              | Path                  | Purpose                             |
|----------------------|-----------------------|-------------------------------------|
| {scope}/ui           | packages/ui/          | Shared React component library      |
| {scope}/auth         | packages/auth/        | Auth helpers, session types          |
| {scope}/db           | packages/db/          | Prisma client & schema              |
| {scope}/types        | packages/types/       | Shared TypeScript types/zod schemas |
| {scope}/config       | packages/config/      | Shared ESLint, TS, Tailwind configs |

## Path Aliases
| Alias            | Resolves To                  | Used By     |
|------------------|------------------------------|-------------|
| {scope}/ui       | packages/ui/src/index.ts     | web, admin  |
| {scope}/db       | packages/db/src/index.ts     | api, web    |
| {scope}/types    | packages/types/src/index.ts  | all apps    |
| {scope}/auth     | packages/auth/src/index.ts   | web, admin, api |
| ~/ or @/         | apps/{app}/src/              | per-app     |

## Cross-App Impact Scope
| File / Path                        | Impact                                 |
|------------------------------------|----------------------------------------|
| packages/db/prisma/schema.prisma   | ALL apps using DB (migration required) |
| packages/types/src/index.ts        | ALL consumers of shared types          |
| packages/ui/src/components/        | web + admin (visual regression risk)   |
| packages/auth/src/session.ts       | web + admin + api (auth flow)          |
| turbo.json                         | Build pipeline for entire monorepo     |
| .env (root)                        | All apps inherit root env vars         |
Before modifying any file above, verify downstream impact with `turbo run build --dry-run`.

## Barrel Export Warnings
| Barrel File                        | Guidance                                   |
|------------------------------------|--------------------------------------------|
| packages/ui/src/index.ts           | Import specific component files instead    |
| packages/types/src/index.ts        | Import from sub-path if tree-shakeable     |
Prefer direct imports: `from '{scope}/ui/src/components/Button'`
over barrel: `from '{scope}/ui'`

## Entry Points
| App           | Dev Command            | Build Output     |
|---------------|------------------------|------------------|
| web           | `turbo dev --filter=web` | apps/web/.next/  |
| api           | `turbo dev --filter=api` | apps/api/dist/   |
| admin         | `turbo dev --filter=admin` | apps/admin/.next/ |

## Generated Files (DO NOT MODIFY)
- packages/db/src/generated/         (Prisma client output)
- apps/*/src/generated/              (tRPC / OpenAPI codegen)
- **/node_modules/
- **/.next/
- **/.turbo/
- **/dist/

## Build & Config
- turbo.json                         -- Pipeline definition (build/test/lint ordering)
- pnpm-workspace.yaml                -- Workspace member globs
- .npmrc                             -- Registry & hoist settings
- tsconfig.base.json                 -- Shared TS config extended by all packages

See .claude/rules/ for tech-specific guides (Next.js, Prisma, tRPC, Tailwind).
```

## Part 2: PROJECT_ROOT/.claude/rules/ Files

### File: nextjs.md

```yaml
---
description: "Next.js pages, server actions, API routes, and middleware"
paths: ["apps/web/**", "apps/admin/**", "**/next.config.*"]
---
```

```markdown
## Next.js (web + admin)

### Location Index
- pages/app-router: apps/{app}/src/app/
- layouts: apps/{app}/src/app/**/layout.tsx
- server-actions: apps/{app}/src/app/**/actions.ts
- API routes: apps/{app}/src/app/api/
- middleware: apps/{app}/src/middleware.ts
- config: apps/{app}/next.config.ts

### Conventions
- Use App Router (src/app/) for all new routes
- Server Components by default; add 'use client' only when needed
- Server Actions go in co-located actions.ts files
- Middleware runs on Edge Runtime -- keep deps minimal
- Shared UI comes from {scope}/ui, not local components/
```

### File: prisma.md

```yaml
---
description: "Prisma schema, migrations, and database client"
paths: ["**/prisma/**", "packages/db/**"]
---
```

```markdown
## Prisma (packages/db)

### Location Index
- schema: packages/db/prisma/schema.prisma
- migrations: packages/db/prisma/migrations/
- seed: packages/db/prisma/seed.ts
- client: packages/db/src/client.ts
- generated: packages/db/src/generated/ (DO NOT MODIFY)

### Conventions
- After schema changes: `pnpm --filter {scope}/db db:generate && db:migrate`
- Always create a migration for schema changes (never push directly)
- Seed data lives in seed.ts -- run with `pnpm --filter {scope}/db db:seed`
- Import PrismaClient from {scope}/db, never from @prisma/client directly
```

### File: trpc.md

```yaml
---
description: "tRPC/API router definitions and procedures"
paths: ["apps/api/**", "**/router/**", "**/routes/**"]
---
```

```markdown
## tRPC / API Layer

### Location Index
- router-root: apps/api/src/router/index.ts
- procedures: apps/api/src/router/{domain}/
- context: apps/api/src/context.ts
- client-hook: packages/types/src/trpc.ts

### Conventions
- Group procedures by domain (e.g., router/order/, router/user/)
- Use superjson for serialization
- Input validation via zod schemas from {scope}/types
- If using REST instead of tRPC, replace with OpenAPI paths
```

### File: tailwind.md

```yaml
---
description: "Tailwind configuration, design tokens, and shared styling"
paths: ["**/tailwind.config.*", "packages/ui/**", "**/tokens/**"]
---
```

```markdown
## Tailwind / Styling

### Location Index
- base-config: packages/config/tailwind/
- app-overrides: apps/{app}/tailwind.config.ts
- design-tokens: packages/ui/src/tokens/
- shared-components: packages/ui/src/components/

### Conventions
- Extend base config from packages/config/tailwind, don't duplicate
- Design tokens defined in packages/ui/src/tokens/ -- import, don't hardcode values
- Component styling lives with component in packages/ui
- App-specific overrides only in apps/{app}/tailwind.config.ts
```

### File: monorepo-rules.md

```yaml
---
description: "Cross-package dependency rules and workspace conventions"
paths: ["turbo.json", "pnpm-workspace.yaml", "tsconfig.base.json", "packages/config/**"]
---
```

```markdown
## Monorepo Rules

### Dependency Direction
- Shared packages MUST NOT import from apps
- All cross-package type changes require updating packages/types first
- Prisma migrations must be reviewed by a human before merge

### Build Pipeline
- turbo.json defines build/test/lint task ordering and caching
- Remote cache: configured via TURBO_TOKEN + TURBO_TEAM env vars
- Run `turbo run build --dry-run` to preview task graph before changes

### Package Management
- Use `pnpm --filter {scope}/{pkg}` to scope commands
- Workspace dependencies use `workspace:*` protocol
- Hoist settings in .npmrc -- check before adding new root dependencies
```
