# Component Patterns — Next.js 15 App Router

Next.js 15 App Router에서 Server/Client Component의 판별 기준, 구현 패턴, 조합 전략.

---

## 1. Server Component vs Client Component 판별 기준

### 판별 매트릭스

| 요구사항 | Server Component | Client Component |
|---------|:---:|:---:|
| 데이터 fetching (DB, API) | O | X |
| 백엔드 리소스 직접 접근 | O | X |
| 민감한 정보 (API key, token) | O | X |
| 큰 의존성을 서버에 유지 | O | X |
| onClick, onChange 등 이벤트 핸들러 | X | O |
| useState, useEffect 등 Hook | X | O |
| 브라우저 API (localStorage, window) | X | O |
| ref, forwardRef 사용 | X | O |
| 클래스 컴포넌트 | X | O |

### 핵심 원칙

- **기본값은 Server Component** -- App Router에서 모든 컴포넌트는 기본적으로 Server Component
- **`'use client'`는 클라이언트 경계 선언** -- 해당 파일과 그 파일이 import하는 모든 모듈이 클라이언트 번들에 포함
- **경계를 최대한 아래로 밀어내기** -- 인터랙션이 필요한 최소 단위에만 `'use client'` 적용

### `'use client'` 디렉티브 규칙

```tsx
// 파일 최상단에 반드시 위치해야 함 (import 위)
'use client'

import { useState } from 'react'
// ...
```

- 파일의 첫 번째 줄이어야 함 (주석은 허용)
- `'use client'`가 선언된 파일에서 import하는 모든 모듈은 클라이언트 번들에 포함
- Server Component에서 Client Component를 import할 수 있지만, 그 반대는 불가

### 잘못된 패턴 -- 모든 것을 Client로 만드는 실수

```tsx
// BAD: 최상위 layout에 'use client' 선언
// --> 하위 모든 컴포넌트가 클라이언트 번들에 포함
'use client'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>{children}</body>
    </html>
  )
}
```

```tsx
// BAD: 데이터 fetching만 하는 컴포넌트에 'use client'
'use client'

import { useEffect, useState } from 'react'

export default function UserList() {
  const [users, setUsers] = useState([])

  useEffect(() => {
    fetch('/api/users').then(res => res.json()).then(setUsers)
  }, [])

  return <ul>{users.map(u => <li key={u.id}>{u.name}</li>)}</ul>
}
```

```tsx
// GOOD: Server Component에서 직접 데이터 fetching
export default async function UserList() {
  const users = await db.user.findMany()

  return <ul>{users.map(u => <li key={u.id}>{u.name}</li>)}</ul>
}
```

### 왜 이 패턴인가

- Server Component는 JavaScript 번들에 포함되지 않아 초기 로드 성능이 향상됨
- 서버에서 데이터를 직접 가져오면 클라이언트-서버 간 불필요한 왕복이 제거됨
- 민감한 로직과 키가 클라이언트에 노출되지 않음

---

## 2. Server Component 패턴

### 책임

- 데이터 fetching 및 서버 사이드 로직
- SEO에 중요한 콘텐츠 렌더링
- 무거운 라이브러리 의존성을 서버에 유지
- DB, 파일시스템, 내부 API 직접 접근

### 올바른 패턴 -- Async Server Component

```tsx
// app/posts/page.tsx
// Server Component -- 'use client' 없음 (기본값)
import { db } from '@/lib/db'
import { PostCard } from '@/components/post-card'

export default async function PostsPage() {
  // 서버에서 직접 DB 조회 -- 클라이언트로 API 왕복 없음
  const posts = await db.post.findMany({
    orderBy: { createdAt: 'desc' },
    include: { author: true },
  })

  return (
    <main>
      <h1>게시글 목록</h1>
      <div className="grid grid-cols-3 gap-4">
        {posts.map(post => (
          <PostCard key={post.id} post={post} />
        ))}
      </div>
    </main>
  )
}
```

### 잘못된 패턴

```tsx
// BAD: Server Component에서 클라이언트 Hook 사용 시도
import { useState } from 'react' // 런타임 에러 발생

export default async function PostsPage() {
  const [filter, setFilter] = useState('') // Server Component에서 useState 사용 불가
  const posts = await db.post.findMany()
  return <div>...</div>
}
```

### 올바른 패턴 -- Streaming with Suspense

```tsx
// app/dashboard/page.tsx
import { Suspense } from 'react'
import { RevenueChart } from '@/components/revenue-chart'
import { LatestOrders } from '@/components/latest-orders'
import { CardsSkeleton, ChartSkeleton, OrdersSkeleton } from '@/components/skeletons'

export default function DashboardPage() {
  return (
    <main>
      <h1>대시보드</h1>

      {/* 각 섹션을 독립적으로 스트리밍 -- 느린 데이터가 전체 페이지를 블로킹하지 않음 */}
      <Suspense fallback={<ChartSkeleton />}>
        <RevenueChart />
      </Suspense>

      <Suspense fallback={<OrdersSkeleton />}>
        <LatestOrders />
      </Suspense>
    </main>
  )
}
```

```tsx
// components/revenue-chart.tsx -- 느린 데이터 독립 로딩
import { db } from '@/lib/db'

export async function RevenueChart() {
  // 이 쿼리가 2초 걸려도 다른 Suspense 영역은 먼저 표시됨
  const revenue = await db.revenue.findMany({
    orderBy: { month: 'asc' },
  })

  return (
    <div className="chart-container">
      {/* 차트 렌더링 */}
    </div>
  )
}
```

### 잘못된 패턴 -- Suspense 없이 순차 로딩

```tsx
// BAD: 모든 데이터를 순차적으로 기다림 -- 가장 느린 쿼리가 전체 페이지를 블로킹
export default async function DashboardPage() {
  const revenue = await db.revenue.findMany()    // 2초
  const orders = await db.order.findMany()        // 1초
  const users = await db.user.count()             // 0.5초
  // 총 3.5초 후에야 페이지 렌더링 시작

  return (
    <main>
      <RevenueChart data={revenue} />
      <LatestOrders data={orders} />
      <UserCount count={users} />
    </main>
  )
}
```

### 올바른 패턴 -- Server Component를 Client Component의 children으로 전달

```tsx
// components/client-tabs.tsx
'use client'

import { useState } from 'react'

export function ClientTabs({ children }: { children: React.ReactNode }) {
  const [activeTab, setActiveTab] = useState(0)

  return (
    <div>
      <div className="tab-buttons">
        <button onClick={() => setActiveTab(0)}>탭 1</button>
        <button onClick={() => setActiveTab(1)}>탭 2</button>
      </div>
      {/* children은 Server Component의 렌더 결과 -- 클라이언트 번들에 포함되지 않음 */}
      <div>{children}</div>
    </div>
  )
}
```

```tsx
// app/page.tsx -- Server Component
import { ClientTabs } from '@/components/client-tabs'
import { ServerContent } from '@/components/server-content'

export default function Page() {
  return (
    <ClientTabs>
      {/* Server Component를 children으로 전달 -- 서버에서 렌더된 결과만 전달 */}
      <ServerContent />
    </ClientTabs>
  )
}
```

### 왜 이 패턴인가

- `Suspense`를 사용하면 독립적인 데이터 영역을 병렬로 스트리밍하여 TTFB(Time To First Byte)가 개선됨
- Server Component를 children으로 전달하면 클라이언트 경계 안에서도 서버 렌더링의 이점을 유지할 수 있음
- async/await로 데이터를 직접 가져오면 `useEffect` + `useState` 보일러플레이트가 제거됨

---

## 3. Client Component 패턴

### 책임

- 사용자 인터랙션 처리 (클릭, 입력, 드래그 등)
- React Hook을 통한 상태 관리
- 브라우저 API 접근
- 실시간 UI 업데이트

### 올바른 패턴 -- 클라이언트 경계 최소화

```tsx
// GOOD: 인터랙션이 필요한 최소 단위만 Client Component로 분리

// components/search-bar.tsx -- 'use client'는 이 작은 컴포넌트에만 적용
'use client'

import { useRouter, useSearchParams } from 'next/navigation'
import { useTransition } from 'react'

export function SearchBar() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [isPending, startTransition] = useTransition()

  function handleSearch(term: string) {
    const params = new URLSearchParams(searchParams.toString())
    if (term) {
      params.set('q', term)
    } else {
      params.delete('q')
    }
    startTransition(() => {
      router.replace(`/search?${params.toString()}`)
    })
  }

  return (
    <input
      type="search"
      placeholder="검색..."
      defaultValue={searchParams.get('q') ?? ''}
      onChange={e => handleSearch(e.target.value)}
      className={isPending ? 'opacity-50' : ''}
    />
  )
}
```

```tsx
// app/search/page.tsx -- Server Component (페이지 자체는 서버)
import { SearchBar } from '@/components/search-bar'
import { SearchResults } from '@/components/search-results'

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>
}) {
  const { q } = await searchParams

  return (
    <main>
      {/* Client Component -- 인터랙션 담당 */}
      <SearchBar />
      {/* Server Component -- 데이터 fetching 담당 */}
      <SearchResults query={q} />
    </main>
  )
}
```

### 잘못된 패턴 -- 페이지 전체를 Client Component로 만들기

```tsx
// BAD: 검색 기능 때문에 페이지 전체를 'use client'로 선언
'use client'

import { useState, useEffect } from 'react'

export default function SearchPage() {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState([])

  useEffect(() => {
    // 클라이언트에서 API 호출 -- 불필요한 왕복
    fetch(`/api/search?q=${query}`).then(r => r.json()).then(setResults)
  }, [query])

  return (
    <main>
      <input value={query} onChange={e => setQuery(e.target.value)} />
      {/* 검색 결과 렌더링도 클라이언트 -- 번들 크기 증가 */}
      <ul>{results.map(r => <li key={r.id}>{r.title}</li>)}</ul>
    </main>
  )
}
```

### 올바른 패턴 -- Lazy Loading with next/dynamic

```tsx
// components/heavy-editor.tsx
'use client'

import dynamic from 'next/dynamic'

// 무거운 에디터 라이브러리를 lazy load
const RichTextEditor = dynamic(() => import('@/components/rich-text-editor'), {
  loading: () => <div className="h-64 animate-pulse bg-gray-200 rounded" />,
  ssr: false, // 브라우저 API에 의존하는 컴포넌트는 SSR 비활성화
})

export function HeavyEditor({ initialContent }: { initialContent: string }) {
  return <RichTextEditor content={initialContent} />
}
```

```tsx
// app/editor/page.tsx -- Server Component
import { db } from '@/lib/db'
import { HeavyEditor } from '@/components/heavy-editor'

export default async function EditorPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const doc = await db.document.findUnique({ where: { id } })

  return (
    <main>
      <h1>{doc?.title}</h1>
      {/* 에디터는 필요할 때만 로드 */}
      <HeavyEditor initialContent={doc?.content ?? ''} />
    </main>
  )
}
```

### 잘못된 패턴 -- 불필요한 SSR false

```tsx
// BAD: 브라우저 API를 사용하지 않는데 ssr: false 적용
const SimpleList = dynamic(() => import('@/components/simple-list'), {
  ssr: false, // 이 컴포넌트는 서버에서 렌더링 가능 -- SSR 이점을 불필요하게 포기
})
```

### 왜 이 패턴인가

- `'use client'` 경계를 최소 단위로 밀어내면 대부분의 컴포넌트가 서버에서 렌더링되어 번들 크기가 감소함
- `next/dynamic`으로 무거운 컴포넌트를 lazy load하면 초기 페이지 로드가 빨라짐
- `ssr: false`는 `window`, `document` 등 브라우저 API에 의존하는 컴포넌트에만 사용해야 함

---

## 4. Composition 패턴

### 책임

- Server Component와 Client Component를 효과적으로 조합
- 렌더링 경계를 명확하게 설계
- 서버 렌더링 이점을 최대한 유지하면서 인터랙티브 UI 구현

### 올바른 패턴 -- Children Pattern으로 서버/클라이언트 혼합

```tsx
// components/modal-provider.tsx
'use client'

import { createContext, useContext, useState } from 'react'

const ModalContext = createContext<{
  isOpen: boolean
  open: () => void
  close: () => void
} | null>(null)

export function ModalProvider({ children }: { children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false)

  return (
    <ModalContext.Provider value={{
      isOpen,
      open: () => setIsOpen(true),
      close: () => setIsOpen(false),
    }}>
      {children}
    </ModalContext.Provider>
  )
}

export function useModal() {
  const context = useContext(ModalContext)
  if (!context) throw new Error('useModal must be used within ModalProvider')
  return context
}
```

```tsx
// app/layout.tsx -- Server Component
import { ModalProvider } from '@/components/modal-provider'
import { Sidebar } from '@/components/sidebar' // Server Component

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>
        <ModalProvider>
          {/* Sidebar는 Server Component -- ModalProvider(Client) 안에 있지만
              children으로 전달되므로 서버에서 렌더링됨 */}
          <Sidebar />
          <main>{children}</main>
        </ModalProvider>
      </body>
    </html>
  )
}
```

### 잘못된 패턴 -- Client Component 안에서 Server Component를 import

```tsx
// BAD: Client Component에서 Server Component를 직접 import
'use client'

import { ServerSidebar } from '@/components/server-sidebar' // 서버 전용 코드 포함

export function Layout() {
  const [isOpen, setIsOpen] = useState(true)

  return (
    <div>
      {/* ServerSidebar가 클라이언트 번들에 포함됨 -- 서버 전용 코드(DB 접근 등)가 있으면 에러 */}
      {isOpen && <ServerSidebar />}
    </div>
  )
}
```

```tsx
// GOOD: children 또는 props로 Server Component를 전달
'use client'

export function Layout({
  sidebar,
  children,
}: {
  sidebar: React.ReactNode  // Server Component의 렌더 결과를 받음
  children: React.ReactNode
}) {
  const [isOpen, setIsOpen] = useState(true)

  return (
    <div>
      {isOpen && <aside>{sidebar}</aside>}
      <main>{children}</main>
    </div>
  )
}
```

```tsx
// app/page.tsx -- Server Component에서 조합
import { Layout } from '@/components/layout'
import { ServerSidebar } from '@/components/server-sidebar'

export default function Page() {
  return (
    <Layout sidebar={<ServerSidebar />}>
      <h1>메인 콘텐츠</h1>
    </Layout>
  )
}
```

### 올바른 패턴 -- Slot Pattern

```tsx
// components/dashboard-shell.tsx
'use client'

import { useState } from 'react'

interface DashboardShellProps {
  header: React.ReactNode    // slot
  sidebar: React.ReactNode   // slot
  content: React.ReactNode   // slot
  footer: React.ReactNode    // slot
}

export function DashboardShell({ header, sidebar, content, footer }: DashboardShellProps) {
  const [isSidebarOpen, setIsSidebarOpen] = useState(true)

  return (
    <div className="dashboard">
      <header>{header}</header>
      <div className="flex">
        {isSidebarOpen && <aside className="w-64">{sidebar}</aside>}
        <main className="flex-1">
          <button onClick={() => setIsSidebarOpen(!isSidebarOpen)}>
            사이드바 토글
          </button>
          {content}
        </main>
      </div>
      <footer>{footer}</footer>
    </div>
  )
}
```

```tsx
// app/dashboard/layout.tsx -- Server Component
import { DashboardShell } from '@/components/dashboard-shell'
import { DashboardHeader } from '@/components/dashboard-header'   // Server
import { DashboardSidebar } from '@/components/dashboard-sidebar' // Server
import { DashboardFooter } from '@/components/dashboard-footer'   // Server

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <DashboardShell
      header={<DashboardHeader />}
      sidebar={<DashboardSidebar />}
      content={children}
      footer={<DashboardFooter />}
    />
  )
}
```

### 잘못된 패턴 -- 모든 슬롯을 하나의 Client Component에 구현

```tsx
// BAD: 레이아웃 전체를 하나의 Client Component로 구현
'use client'

import { db } from '@/lib/db' // 클라이언트에서 DB 접근 불가 -- 에러

export function Dashboard() {
  const [isSidebarOpen, setIsSidebarOpen] = useState(true)
  const users = await db.user.findMany() // Client Component에서 async 사용 불가

  return (
    <div>
      <header><UserNav users={users} /></header>
      <aside>{isSidebarOpen && <Navigation />}</aside>
      <main><Content /></main>
    </div>
  )
}
```

### 왜 이 패턴인가

- Children/Slot 패턴을 사용하면 Client Component가 "구멍(hole)"만 제공하고, Server Component가 그 구멍을 채움
- 서버에서 렌더링된 HTML이 Client Component의 props로 직렬화되어 전달되므로 서버 전용 코드가 클라이언트에 노출되지 않음
- 레이아웃의 인터랙티브 부분(토글, 탭 등)만 클라이언트에서 처리하고, 콘텐츠는 서버에서 렌더링하여 최적의 성능을 달성

---

## 5. Compound Component 패턴

### 책임

- 관련된 컴포넌트 그룹을 하나의 논리적 단위로 관리
- 부모-자식 간 암묵적 상태 공유
- 유연한 API 설계 (사용자가 구조를 제어)

### 올바른 패턴 -- Context 기반 Compound Component

```tsx
// components/accordion.tsx
'use client'

import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from 'react'

// --- 내부 Context ---
interface AccordionContextType {
  openItems: Set<string>
  toggle: (id: string) => void
}

const AccordionContext = createContext<AccordionContextType | null>(null)

function useAccordion() {
  const context = useContext(AccordionContext)
  if (!context) {
    throw new Error('Accordion 하위 컴포넌트는 Accordion.Root 안에서 사용해야 합니다')
  }
  return context
}

// --- Root ---
function AccordionRoot({
  children,
  multiple = false,
}: {
  children: ReactNode
  multiple?: boolean
}) {
  const [openItems, setOpenItems] = useState<Set<string>>(new Set())

  const toggle = useCallback((id: string) => {
    setOpenItems(prev => {
      const next = new Set(multiple ? prev : [])
      if (prev.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }, [multiple])

  return (
    <AccordionContext.Provider value={{ openItems, toggle }}>
      <div className="divide-y">{children}</div>
    </AccordionContext.Provider>
  )
}

// --- Item ---
function AccordionItem({ id, children }: { id: string; children: ReactNode }) {
  return <div data-accordion-item={id}>{children}</div>
}

// --- Trigger ---
function AccordionTrigger({ id, children }: { id: string; children: ReactNode }) {
  const { openItems, toggle } = useAccordion()
  const isOpen = openItems.has(id)

  return (
    <button
      onClick={() => toggle(id)}
      aria-expanded={isOpen}
      className="w-full text-left p-4 font-medium"
    >
      {children}
      <span className={`transform transition ${isOpen ? 'rotate-180' : ''}`}>
        &#9660;
      </span>
    </button>
  )
}

// --- Content ---
function AccordionContent({ id, children }: { id: string; children: ReactNode }) {
  const { openItems } = useAccordion()
  const isOpen = openItems.has(id)

  if (!isOpen) return null

  return (
    <div className="p-4" role="region">
      {children}
    </div>
  )
}

// --- 네임스페이스 export ---
export const Accordion = {
  Root: AccordionRoot,
  Item: AccordionItem,
  Trigger: AccordionTrigger,
  Content: AccordionContent,
}
```

```tsx
// 사용 예시 -- 깔끔한 선언적 API
import { Accordion } from '@/components/accordion'

export default function FAQPage() {
  return (
    <Accordion.Root multiple>
      <Accordion.Item id="q1">
        <Accordion.Trigger id="q1">Next.js란 무엇인가요?</Accordion.Trigger>
        <Accordion.Content id="q1">
          Next.js는 React 기반의 풀스택 웹 프레임워크입니다.
        </Accordion.Content>
      </Accordion.Item>

      <Accordion.Item id="q2">
        <Accordion.Trigger id="q2">App Router란?</Accordion.Trigger>
        <Accordion.Content id="q2">
          Next.js 13에서 도입된 새로운 라우팅 시스템으로, React Server Components를 기반으로 합니다.
        </Accordion.Content>
      </Accordion.Item>
    </Accordion.Root>
  )
}
```

### 잘못된 패턴 -- 모든 것을 props로 전달

```tsx
// BAD: 데이터 배열을 props로 전달하는 경직된 API
'use client'

interface AccordionProps {
  items: Array<{ id: string; title: string; content: string }>
  multiple?: boolean
}

export function Accordion({ items, multiple }: AccordionProps) {
  const [openItems, setOpenItems] = useState<Set<string>>(new Set())

  return (
    <div>
      {items.map(item => (
        <div key={item.id}>
          <button onClick={() => toggle(item.id)}>{item.title}</button>
          {openItems.has(item.id) && <div>{item.content}</div>}
          {/* content가 string이라 React 노드를 넣을 수 없음 */}
          {/* 커스텀 렌더링, 아이콘 추가 등이 불가능 */}
        </div>
      ))}
    </div>
  )
}
```

### 올바른 패턴 -- Render Props (필요한 경우)

```tsx
// components/data-list.tsx
'use client'

import { useState } from 'react'

interface DataListProps<T> {
  items: T[]
  renderItem: (item: T, index: number) => React.ReactNode
  renderEmpty?: () => React.ReactNode
  filterFn?: (item: T, query: string) => boolean
}

export function DataList<T>({
  items,
  renderItem,
  renderEmpty,
  filterFn,
}: DataListProps<T>) {
  const [query, setQuery] = useState('')

  const filtered = filterFn
    ? items.filter(item => filterFn(item, query))
    : items

  return (
    <div>
      {filterFn && (
        <input
          type="search"
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="필터..."
          className="mb-4 p-2 border rounded"
        />
      )}

      {filtered.length === 0 && renderEmpty
        ? renderEmpty()
        : filtered.map((item, i) => renderItem(item, i))
      }
    </div>
  )
}
```

```tsx
// 사용 예시
import { DataList } from '@/components/data-list'

interface User {
  id: string
  name: string
  email: string
}

export default function UsersClient({ users }: { users: User[] }) {
  return (
    <DataList
      items={users}
      filterFn={(user, query) =>
        user.name.toLowerCase().includes(query.toLowerCase())
      }
      renderItem={(user) => (
        <div key={user.id} className="p-4 border-b">
          <h3 className="font-bold">{user.name}</h3>
          <p className="text-gray-500">{user.email}</p>
        </div>
      )}
      renderEmpty={() => (
        <p className="text-center text-gray-400 py-8">
          검색 결과가 없습니다.
        </p>
      )}
    />
  )
}
```

### 잘못된 패턴 -- Render Props 남용

```tsx
// BAD: 단순한 경우에 render props 사용 -- 불필요한 복잡성
<Button
  renderIcon={() => <Icon name="save" />}
  renderLabel={() => <span>저장</span>}
  renderTooltip={() => <Tooltip>문서를 저장합니다</Tooltip>}
/>

// GOOD: 단순한 경우는 일반 props 또는 children
<Button icon={<Icon name="save" />} tooltip="문서를 저장합니다">
  저장
</Button>
```

### 왜 이 패턴인가

- Compound Component는 컴포넌트의 **구조를 사용자가 제어**할 수 있게 하여 유연성이 극대화됨
- Context를 통한 암묵적 상태 공유로 prop drilling이 제거됨
- Render Props는 **렌더링 로직의 위임**이 필요할 때만 사용 -- 단순한 경우에는 오히려 복잡성만 증가시킴
- 네임스페이스 export(`Accordion.Root`, `Accordion.Item`)로 관련 컴포넌트를 그룹화하면 자동완성과 디스커버리가 향상됨
