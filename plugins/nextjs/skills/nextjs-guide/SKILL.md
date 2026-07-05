---
name: nextjs-guide
description: |
  Next.js App Router 개발 종합 가이드. Server/Client Component 판별, 라우팅 패턴, 데이터 페칭, 테스트 전략을 제공한다.
  코드 작성 시 자동으로 참조하여 Next.js 15 모범 사례를 적용한다.
  Comprehensive Next.js App Router development guide — covers Server/Client Component decisions, routing patterns, data fetching, and testing strategy, applying Next.js 15 best practices automatically during code writing. Use when: writing Next.js components or pages, choosing Server vs Client Components, deciding data fetching or caching strategy, writing frontend tests.
---

# Next.js App Router Development Guide

Next.js 15 App Router 프로젝트에서 관용적이고 성능 최적화된 프론트엔드 코드를 작성하기 위한 종합 가이드.

## When to Apply

Reference these guidelines when:
- Next.js App Router 프로젝트에서 새 컴포넌트나 페이지를 작성할 때
- Server Component와 Client Component 선택이 필요할 때
- 데이터 페칭 전략이나 캐싱 정책을 결정할 때
- 프론트엔드 테스트 코드를 작성할 때
- 버전 민감 API(App Router async params, 캐싱 기본값 등)는 backend-shared 플러그인의 Context7 최신 문서 조회 공통 규약(`context7-docs-guide`) 참조 (미설치 시 생략)

**인접 도구와의 역할 경계** — 텍스트 와이어프레임·유저플로우·`[story: S-xx]` 스토리 매핑은 mvp 플러그인의 `ux-designer`(Stage 2) 소관이고,
고충실도 시각 구현·스타일링('AI 티 나는 밋밋한 UI' 방지)은 공식 `frontend-design` 스킬(`/plugin install frontend-design@claude-plugins-official`, 미설치 시 본 가이드만으로 진행) 소관이며,
코드 구조(Server/Client 경계·라우팅·데이터 페칭·테스트)는 본 nextjs 플러그인이 담당한다.

## Quick Reference

| Priority | Category | Impact | Reference |
|----------|----------|--------|-----------|
| 1 | Component Patterns | 렌더링 성능과 번들 크기 | `references/component-patterns.md` |
| 2 | Routing Patterns | 페이지 구조와 UX | `references/routing-patterns.md` |
| 3 | Data Fetching Patterns | 데이터 로딩 전략과 캐싱 | `references/data-fetching-patterns.md` |
| 4 | Testing Patterns | 테스트 품질과 신뢰성 | `references/testing-patterns.md` |

## Core Principles

### 1. Server First — 클라이언트는 필요할 때만

| 필요 | Component | Why |
|------|-----------|-----|
| 데이터 표시만 | Server Component | 번들 크기 0, 직접 DB/API 접근 |
| onClick, onChange | Client Component | 이벤트 핸들러는 브라우저에서만 |
| useState, useEffect | Client Component | React hooks는 클라이언트 전용 |
| 정적 UI, 마크다운 | Server Component | JS 불필요 |
| 폼 제출 (mutation) | Server Action | 서버에서 실행, 점진적 향상 |
| 실시간 UI 갱신 | Client Component | WebSocket, polling 등 |

### 2. Composition Over Prop Drilling

```tsx
// GOOD: Server Component가 Client Component를 children으로 감싸기
// → 서버에서 데이터 fetch, 클라이언트에서 인터랙션
export default async function ProductPage() {
  const product = await getProduct()           // Server: 데이터 로딩
  return (
    <ProductLayout product={product}>
      <AddToCartButton productId={product.id} /> {/* Client: 인터랙션 */}
    </ProductLayout>
  )
}

// BAD: 전체 페이지를 'use client'로 만들기
```

### 3. Colocation — 관련 파일은 가까이

```
app/
  products/
    page.tsx          # 페이지 (Server Component)
    loading.tsx       # 로딩 UI (Suspense fallback)
    error.tsx         # 에러 UI (Error Boundary)
    not-found.tsx     # 404 UI
    _components/      # 이 라우트 전용 컴포넌트
      product-card.tsx
      product-filter.tsx
    _actions/         # Server Actions
      create-product.ts
    _lib/             # 이 라우트 전용 유틸리티
      validators.ts
```

### 4. Type Safety First

```tsx
// Zod 스키마로 런타임 + 타입 안전성 동시 확보
const ProductSchema = z.object({
  name: z.string().min(1),
  price: z.number().positive(),
})
type Product = z.infer<typeof ProductSchema>
```

## Decision Quick Reference

### State Management

| 상황 | 권장 | 이유 |
|------|-----|------|
| 서버 데이터 캐시/동기화 | TanStack Query | 캐시 무효화, 낙관적 업데이트 |
| 전역 클라이언트 상태 | Zustand | 최소 보일러플레이트, 번들 작음 |
| 컴포넌트 로컬 상태 | useState / useReducer | React 내장, 추가 의존성 없음 |
| URL 기반 상태 | nuqs (useQueryState) | URL 동기화, SSR 호환 |
| 서버 mutation | Server Actions | 점진적 향상, 자동 revalidation |

### Styling

| 상황 | 권장 | 이유 |
|------|-----|------|
| 유틸리티 우선 | Tailwind CSS | Next.js 기본 지원, JIT |
| 컴포넌트 라이브러리 | shadcn/ui | 복사 기반, 커스터마이징 자유 |
| 스코프 CSS 필요 | CSS Modules | Next.js 네이티브 지원 |
| 동적 스타일 | Tailwind + clsx/cn | 조건부 클래스 조합 |

### Form Handling

| 상황 | 권장 | 이유 |
|------|-----|------|
| 복잡한 클라이언트 폼 | React Hook Form + Zod | 성능, 타입 안전, 유효성 검증 |
| 단순 서버 mutation | Server Action + useActionState | 점진적 향상, JS 없이 동작 |
| 낙관적 업데이트 | useOptimistic + Server Action | 즉각적 UI 반영 |

## How to Use

Read individual reference files for detailed patterns and examples:

```
references/component-patterns.md     — Server/Client Component 판별, Composition, Compound
references/routing-patterns.md       — App Router, Layout, Loading, Error, Middleware
references/data-fetching-patterns.md — RSC fetch, cache, revalidation, Server Actions
references/testing-patterns.md       — Vitest, React Testing Library, Playwright
```

Each reference file contains:
- Pattern description and rationale
- Bad/Good code examples with explanations
- Common pitfalls and solutions
- Decision guidance for choosing between approaches
