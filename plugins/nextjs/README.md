> **English** · [한국어](README_KO.md)

# nextjs

> A specialized plugin that designs, scaffolds, and generates Next.js App Router frontend code in line with project conventions.

## Overview

`nextjs` is a toolset for producing idiomatic, performance-optimized frontend code in Next.js App Router projects, without assuming a Next.js version: it first checks the project's `next` version and the docs bundled in `node_modules/next/dist/docs/` (16.2+). Its guiding principle is to always first analyze the target project's structure and conventions (directory layout, import alias, styling approach, UI/form/state-management libraries, test runner) before writing any code, and then, on top of that, to generate code with the Server/Client Component boundary drawn correctly.

The responsibilities split into three stages. `/nextjs-page-design` designs requirements into a component tree, data flow, and route structure; `/nextjs-gen` automatically generates Page, Layout, Loading, Error, Component, Form, Hook, and Test from just a name and a type; and the `nextjs-developer` agent, to which these two commands delegate the actual code generation. When a judgment call is needed, the `nextjs-guide` skill supplies specialist pitfalls that strong generalists still miss (RSC serialization, Server Action security, caching models, hydration, CLS/LCP, self-hosting), each with an ID.

Design and generation consistently follow "Server First" (Server Component by default, `'use client'` only when interaction is needed), colocation, and type safety (Zod + `z.infer`). This plugin handles **code structure** (Server/Client boundary, routing, data fetching, testing), while high-fidelity visual styling (preventing "flat, obviously-AI UI") falls to the official `frontend-design` skill — the boundaries are drawn there.

## Components

### Commands

- `/nextjs-page-design` — Analyzes requirements to design a component tree, Server/Client boundary, data flow, and route structure, and scaffolds interface stubs. The `--responsive`, `--skeleton`, `--error-boundary`, `--route`, and `--data` options specify responsive/loading/error strategy and the route/data source.
- `/nextjs-gen` — Given a name and a type, generates Page/Layout/Loading/Error/Component/Form/Hook/Test in line with project conventions. Supports the `--type`, `--client`, `--server-action`, `--style`, `--test`, and `--route` options.

### Agents

- `nextjs-developer` — An agent specialized in Next.js App Router code generation. It produces production-grade code through a five-stage workflow: version and bundled-docs discovery → convention extraction → boundary, data and Server Action decisions → code generation → verification (tsc/lint/test/build). It is the actual generation engine behind both commands and loads the `nextjs-guide` skill.

### Skills

- `nextjs-guide` — A version-neutral Next.js specialist triage: a version/docs check procedure, a symptom → item table, and 61 items in `ID · applies / signal / mechanism / fix / counter-case / verify / source` form (preloaded by `nextjs-developer`).
  - `references/version-16-changes.md` — NX-V16: proxy.ts rename, removed sync request APIs, revalidateTag/updateTag, Turbopack, next/image defaults.
  - `references/caching-rendering.md` — NX-CACHE: Cache Components vs. the previous model, `'use cache'` keys and runtime storage, Suspense and prefetch.
  - `references/data-waterfall.md` — NX-DATA: waterfalls, preload, blocking layouts, proxy buffering, `useSearchParams`.
  - `references/rsc-boundary.md` — RSC-BND: client module graph, props duplication and exposure, env poisoning, serialization.
  - `references/server-actions-security.md` — RSC-ACT: public endpoints, round-tripped values, sequential dispatch, origin checks, key/ID skew.
  - `references/web-vitals.md` — WEB: image/font CLS and LCP, hydration mismatch causes, bundle analysis.
  - `references/self-hosting-ops.md` — NX-OPS: build-time `NEXT_PUBLIC_`, multi-instance invalidation, version skew, shutdown drain.
  - The previous tutorial-style references were moved to `archive/components/nextjs/`.

## Usage

The commands are invoked directly as `/nextjs-page-design` and `/nextjs-gen`. For complex features that need design first, the natural flow is to lay out the structure with `/nextjs-page-design` and then fill it in with `/nextjs-gen`.

```
# Design the full structure of a dashboard page (including responsive/skeleton/error strategy)
/nextjs-page-design Dashboard --responsive --skeleton --error-boundary

# Design a product search feature (specifying route/data source)
/nextjs-page-design ProductSearch --route "products" --data "REST /api/products"

# Generate a full product list page (page/loading/error/_components)
/nextjs-gen Products

# Generate a dynamic route page
/nextjs-gen ProductDetail --route "products/[id]"

# Generate a form + Zod schema + Server Action + test
/nextjs-gen CreateProduct --type form --server-action --test

# Generate a custom hook + test
/nextjs-gen useDebounce --type hook --test
```

The commands are user-invoked only (`disable-model-invocation`). The `nextjs-guide` skill can be picked up when reviewing or debugging Next.js code and is preloaded into `nextjs-developer`. After generation, verify with `npx tsc --noEmit`, the project's lint script (`next lint` was removed in Next 16), the tests, and `next build` when routing or caching changed.

## Notes

- **App Router focused.** New code targets the App Router; existing Pages Router areas are left as they are unless migration is requested.
- **What it does not build directly:** API routes/backend logic, arbitrary business logic (a `TODO(human)` marker is inserted instead), and code that requires dependencies not present in the project. It does not modify existing files without an explicit request, and it does not attach unnecessary `'use client'`.
- **Optional integrations (only when installed; graceful degrade when not installed):** For visual styling, combine with the official `frontend-design` skill (`/plugin install frontend-design@claude-plugins-official`); for version-sensitive APIs (App Router async params, caching defaults, etc.), follow the backend-shared plugin's Context7 latest-docs lookup convention (`context7-docs-guide`).
- **Good to use together:** Divide roles by using the `backend-*` plugins for backend API/DB.
