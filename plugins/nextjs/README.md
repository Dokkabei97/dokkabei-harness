> **English** · [한국어](README_KO.md)

# nextjs

> A specialized plugin that designs, scaffolds, and generates Next.js App Router frontend code in line with project conventions.

## Overview

`nextjs` is a toolset for producing idiomatic, performance-optimized frontend code in Next.js 15 App Router projects. Its guiding principle is to always first analyze the target project's structure and conventions (directory layout, import alias, styling approach, UI/form/state-management libraries, test runner) before writing any code, and then, on top of that, to generate code with the Server/Client Component boundary drawn correctly.

The responsibilities split into three stages. `/nextjs-page-design` designs requirements into a component tree, data flow, and route structure; `/nextjs-gen` automatically generates Page, Layout, Loading, Error, Component, Form, Hook, and Test from just a name and a type; and the `nextjs-developer` agent, to which these two commands delegate the actual code generation. When a judgment call is needed, the `nextjs-guide` skill automatically attaches Server First, routing, data fetching, and testing best practices.

Design and generation consistently follow "Server First" (Server Component by default, `'use client'` only when interaction is needed), colocation, and type safety (Zod + `z.infer`). This plugin handles **code structure** (Server/Client boundary, routing, data fetching, testing), while text wireframes and user-flow design fall to the mvp plugin's `ux-designer`, and high-fidelity visual styling (preventing "flat, obviously-AI UI") falls to the official `frontend-design` skill — the boundaries are drawn there.

## Components

### Commands

- `/nextjs-page-design` — Analyzes requirements to design a component tree, Server/Client boundary, data flow, and route structure, and scaffolds interface stubs. The `--responsive`, `--skeleton`, `--error-boundary`, `--route`, and `--data` options specify responsive/loading/error strategy and the route/data source.
- `/nextjs-gen` — Given a name and a type, generates Page/Layout/Loading/Error/Component/Form/Hook/Test in line with project conventions. Supports the `--type`, `--client`, `--server-action`, `--style`, `--test`, and `--route` options.

### Agents

- `nextjs-developer` — An agent specialized in Next.js App Router code generation. It produces production-grade code through a five-stage workflow: project convention analysis → convention extraction → Server/Client boundary decision → code generation → verification (tsc/lint/test). It is the actual generation engine behind both commands and loads the `nextjs-guide` skill.

### Skills

- `nextjs-guide` — A comprehensive App Router development guide (quick reference + 4 detailed references). It is automatically referenced in code-writing contexts to apply Next.js 15 best practices.
  - `references/component-patterns.md` — Server/Client Component discrimination, Composition, Compound patterns.
  - `references/routing-patterns.md` — App Router, Layout, Loading, Error, Middleware.
  - `references/data-fetching-patterns.md` — RSC fetch, cache, revalidation, Server Actions.
  - `references/testing-patterns.md` — Vitest, React Testing Library, Playwright.

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

The `nextjs-guide` skill is loaded automatically — without a separate invocation — in the context of Next.js component/page/data-fetching/testing work to reinforce the judgment criteria. After generation, verify with `npx tsc --noEmit`, `npx next lint` (or `eslint`), and by running the tests.

## Notes

- **App Router only.** Legacy patterns such as Pages Router and `getServerSideProps` are not generated, and when detected, App Router migration is recommended.
- **What it does not build directly:** API routes/backend logic, arbitrary business logic (a `TODO(human)` marker is inserted instead), and code that requires dependencies not present in the project. It does not modify existing files without an explicit request, and it does not attach unnecessary `'use client'`.
- **Optional integrations (only when installed; graceful degrade when not installed):** For visual styling, combine with the official `frontend-design` skill (`/plugin install frontend-design@claude-plugins-official`); for version-sensitive APIs (App Router async params, caching defaults, etc.), follow the backend-shared plugin's Context7 latest-docs lookup convention (`context7-docs-guide`).
- **Good to use together:** Divide roles by using the mvp plugin's `ux-designer` for feature planning/wireframes and the `backend-*` plugins for backend API/DB.
