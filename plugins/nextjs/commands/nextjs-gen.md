---
name: nextjs-gen
description: "Next.js App Router 컴포넌트·페이지·레이아웃 스캐폴딩. 이름과 타입을 입력하면 Page, Layout, Loading, Error, Component, Form, Hook, Test를 프로젝트 컨벤션에 맞춰 자동 생성한다."
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /nextjs-gen - Next.js App Router 코드 생성

## Triggers
- 새로운 페이지나 라우트가 필요할 때
- "상품 목록 페이지 만들어줘", "로그인 폼 컴포넌트 생성해줘"
- 기존 Next.js 프로젝트에 새 기능의 UI를 스캐폴딩할 때
- 재사용 가능한 컴포넌트나 커스텀 훅을 생성할 때

## Usage
```
/nextjs-gen [이름] [options]

Options:
  --type       생성 타입 (page | component | layout | form | hook) — 기본값: page
  --client     Client Component로 강제 ('use client' 추가)
  --server-action  Server Action 파일 함께 생성
  --style      스타일링 방식 (tailwind | css-modules) — 기본값: 프로젝트 감지
  --test       테스트 파일 함께 생성
  --route      라우트 경로 지정 (e.g., "products/[id]")
```

## Behavioral Flow

### Phase 1: Discovery
프로젝트 구조와 기존 코드 컨벤션을 분석한다.

**Steps:**
1. **Scan**: `next.config.*`, `package.json`, `tsconfig.json` 스캔하여 프레임워크 버전과 설정 파악
2. **Analyze**: 기존 Page, Component, Layout 파일을 읽어 패턴 추출
   - 디렉토리 구조 (`app/` colocation vs `components/` 분리)
   - 컴포넌트 파일 이름 규칙 (kebab-case vs PascalCase)
   - 스타일링 방식 (Tailwind, CSS Modules, styled-components)
   - UI 라이브러리 (shadcn/ui, Radix, Headless UI)
   - 폼 라이브러리 (React Hook Form + Zod, useActionState)
   - 상태 관리 (Zustand, Jotai, TanStack Query)
   - Import alias (`@/`, `~/`)
3. **Classify**: 생성 전략 결정
   - Server Component vs Client Component 판별
   - 데이터 페칭 방식 (RSC fetch, TanStack Query, SWR)
   - 테스트 프레임워크 (Vitest, Jest)

### Phase 2: Generation
타입에 따라 프로젝트 컨벤션에 맞는 코드를 생성한다.

**type=page 생성 파일:**
1. **page.tsx** — Page component (Server Component by default)
2. **layout.tsx** — Layout (if new route group)
3. **loading.tsx** — Loading UI with skeleton
4. **error.tsx** — Error boundary (Client Component, required)
5. **not-found.tsx** — 404 UI (optional)
6. **_components/** — Route-specific components
7. **_actions/** — Server Actions (if --server-action)
8. **Test** — Page test file (if --test)

**type=component 생성 파일:**
1. **component.tsx** — Component file
2. **component.test.tsx** — Test file (if --test)

**type=form 생성 파일:**
1. **form.tsx** — Form component (Client Component)
2. **schema.ts** — Zod validation schema
3. **action.ts** — Server Action (if --server-action)
4. **form.test.tsx** — Test file (if --test)

**type=hook 생성 파일:**
1. **hook.ts** — Custom hook
2. **hook.test.ts** — Test file (if --test)

**type=layout 생성 파일:**
1. **layout.tsx** — Layout component (Server Component)
2. **template.tsx** — Template (if per-navigation re-render needed)

**Generation Rules:**
- Server Component가 기본값 — `'use client'`는 인터랙션이 필요한 경우에만
- `'use client'` 경계를 가능한 낮게 유지 (leaf component)
- 기존 UI 라이브러리 컴포넌트 재사용 (shadcn/ui 등)
- Tailwind CSS 사용 시 반응형 (sm/md/lg) 기본 포함
- TypeScript strict mode — `any` 사용 금지
- Zod 스키마가 있으면 `z.infer`로 타입 도출
- 비즈니스 로직이 필요한 부분은 TODO(human) 마커 사용
- 공식 `frontend-design` 스킬(anthropics/skills — 'AI 티 나는 밋밋한 UI' 방지)이 설치되어 있으면 컴포넌트·페이지의 시각 스타일링(타이포·색·간격·시각 위계)에 스킬 가이드를 조합 적용한다. 미설치 시 위 규칙만으로 기존 동작을 유지한다(graceful degrade)

### Phase 3: Verification
생성된 코드가 타입 체크를 통과하고 올바른지 검증한다.

**Steps:**
1. **TypeCheck**: `npx tsc --noEmit` 실행
2. **Lint**: `npx next lint` 또는 `npx eslint .` 실행
3. **Test**: 테스트 파일이 있으면 실행 `npx vitest run [file]` 또는 `npx jest [file]`
4. **Report**: 생성 결과 요약 출력

## Tool Coordination
- **Glob**: 프로젝트 구조 파악, 기존 파일 탐색
- **Read**: 기존 코드 패턴 분석, package.json 의존성 확인
- **Grep**: 기존 컨벤션 추출 ('use client', import 패턴, className 등)
- **Write**: 새 파일 생성
- **Edit**: 기존 파일 수정 (필요시)
- **Bash**: TypeScript 컴파일, 린트, 테스트 실행
- **Context7 MCP** (선택): 버전 민감 API는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 생성 (미설치 시 생략)
- **frontend-design 스킬** (선택): 시각 스타일링 단계에서 조합 활용 — 설치: `/plugin install frontend-design@claude-plugins-official` (미설치 시 생략)

## Examples

### Basic Page
```
/nextjs-gen Products
# Products 라우트의 전체 페이지 구조 생성
# → app/products/page.tsx, loading.tsx, error.tsx, _components/
```

### Page with Route
```
/nextjs-gen ProductDetail --route "products/[id]"
# 동적 라우트 페이지 생성
# → app/products/[id]/page.tsx, loading.tsx, error.tsx
```

### Component
```
/nextjs-gen ProductCard --type component --test
# 재사용 컴포넌트 + 테스트 생성
# → components/product-card.tsx, components/__tests__/product-card.test.tsx
```

### Client Component
```
/nextjs-gen SearchFilter --type component --client
# 인터랙티브 Client Component 생성
# → components/search-filter.tsx ('use client' 포함)
```

### Form with Server Action
```
/nextjs-gen CreateProduct --type form --server-action --test
# 폼 컴포넌트 + Zod 스키마 + Server Action + 테스트 생성
# → components/create-product-form.tsx, lib/schemas/create-product.ts,
#   app/products/_actions/create-product.ts, __tests__/create-product-form.test.tsx
```

### Custom Hook
```
/nextjs-gen useDebounce --type hook --test
# 커스텀 훅 + 테스트 생성
# → hooks/use-debounce.ts, hooks/__tests__/use-debounce.test.ts
```

## Generated Code Patterns

### Page (Server Component)
```tsx
import { Suspense } from 'react'
import { ProductList } from './_components/product-list'
import { ProductListSkeleton } from './_components/product-list-skeleton'

export const metadata = {
  title: 'Products',
  description: '상품 목록 페이지',
}

export default function ProductsPage() {
  return (
    <div className="container mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold mb-6">상품 목록</h1>
      <Suspense fallback={<ProductListSkeleton />}>
        <ProductList />
      </Suspense>
    </div>
  )
}
```

### Loading UI
```tsx
import { ProductListSkeleton } from './_components/product-list-skeleton'

export default function Loading() {
  return (
    <div className="container mx-auto px-4 py-8">
      <div className="h-8 w-48 bg-muted animate-pulse rounded mb-6" />
      <ProductListSkeleton />
    </div>
  )
}
```

### Error Boundary
```tsx
'use client'

interface ErrorProps {
  error: Error & { digest?: string }
  reset: () => void
}

export default function Error({ error, reset }: ErrorProps) {
  return (
    <div className="container mx-auto px-4 py-8 text-center">
      <h2 className="text-xl font-semibold mb-4">문제가 발생했습니다</h2>
      <p className="text-muted-foreground mb-6">{error.message}</p>
      <button
        onClick={reset}
        className="px-4 py-2 bg-primary text-primary-foreground rounded-md hover:bg-primary/90"
      >
        다시 시도
      </button>
    </div>
  )
}
```

### Form (Client Component + Zod + Server Action)
```tsx
'use client'

import { useActionState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { createProductSchema, type CreateProductInput } from '@/lib/schemas/create-product'
import { createProduct } from '../_actions/create-product'

export function CreateProductForm() {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<CreateProductInput>({
    resolver: zodResolver(createProductSchema),
  })

  const [state, formAction, isPending] = useActionState(createProduct, null)

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <label htmlFor="name" className="block text-sm font-medium mb-1">
          상품명
        </label>
        <input
          id="name"
          {...register('name')}
          className="w-full px-3 py-2 border rounded-md"
          aria-invalid={errors.name ? 'true' : undefined}
          aria-describedby={errors.name ? 'name-error' : undefined}
        />
        {errors.name && (
          <p id="name-error" className="text-sm text-destructive mt-1">
            {errors.name.message}
          </p>
        )}
      </div>
      {/* TODO(human): 추가 폼 필드 구현 */}
      <button
        type="submit"
        disabled={isPending}
        className="px-4 py-2 bg-primary text-primary-foreground rounded-md disabled:opacity-50"
      >
        {isPending ? '생성 중...' : '상품 생성'}
      </button>
      {state?.error && (
        <p className="text-sm text-destructive">{state.error}</p>
      )}
    </form>
  )
}
```

### Server Action
```tsx
'use server'

import { revalidatePath } from 'next/cache'
import { createProductSchema } from '@/lib/schemas/create-product'

type ActionState = {
  error?: string
  success?: boolean
} | null

export async function createProduct(
  prevState: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = createProductSchema.safeParse(
    Object.fromEntries(formData),
  )

  if (!parsed.success) {
    return { error: parsed.error.issues[0].message }
  }

  try {
    // TODO(human): API 호출 또는 데이터베이스 저장 로직
    revalidatePath('/products')
    return { success: true }
  } catch {
    return { error: '상품 생성에 실패했습니다' }
  }
}
```

### Custom Hook
```tsx
import { useState, useEffect } from 'react'

export function useDebounce<T>(value: T, delay: number = 300): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value)

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay)
    return () => clearTimeout(timer)
  }, [value, delay])

  return debouncedValue
}
```

### Component Test (Vitest + RTL)
```tsx
import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import { ProductCard } from '../product-card'

describe('ProductCard', () => {
  const mockProduct = {
    id: '1',
    name: '테스트 상품',
    price: 10000,
    imageUrl: '/test.jpg',
  }

  it('상품 이름을 표시한다', () => {
    render(<ProductCard product={mockProduct} />)
    expect(screen.getByText('테스트 상품')).toBeInTheDocument()
  })

  it('가격을 포맷팅하여 표시한다', () => {
    render(<ProductCard product={mockProduct} />)
    expect(screen.getByText('₩10,000')).toBeInTheDocument()
  })

  it('이미지에 alt 텍스트가 포함된다', () => {
    render(<ProductCard product={mockProduct} />)
    expect(screen.getByAltText('테스트 상품')).toBeInTheDocument()
  })
})
```

## Boundaries

**Will:**
- 프로젝트 기존 컨벤션을 분석하고 정확히 따름
- Server/Client Component 경계를 올바르게 설정
- 로딩 UI (loading.tsx, Skeleton) 자동 생성
- 에러 바운더리 (error.tsx) 자동 생성
- Tailwind CSS 반응형 클래스 기본 포함
- 접근성 속성 (aria-*, semantic HTML) 포함
- Zod 스키마를 통한 타입 안전 폼 생성

**Will Not:**
- 기존 파일을 무단 수정
- 비즈니스 로직을 임의로 구현 (TODO(human) 마커 사용)
- API 라우트나 백엔드 로직 생성
- 프로젝트에 없는 의존성을 요구하는 코드 생성
- 불필요한 'use client' 추가
- package.json 의존성 추가 (별도 확인 필요)
