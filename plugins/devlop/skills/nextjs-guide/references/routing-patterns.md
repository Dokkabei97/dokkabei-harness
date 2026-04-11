# Routing Patterns — Next.js 15 App Router

Next.js 15 App Router에서 라우팅 구조, 레이아웃, 로딩, 에러 처리, 동적 라우트, 미들웨어 패턴.

---

## App Router 파일 컨벤션

### 역할

App Router는 파일 시스템 기반 라우팅을 사용한다. `app/` 디렉토리 내의 특수 파일명이 각각의 역할을 수행한다.

| 파일 | 역할 |
|------|------|
| `page.tsx` | 해당 경로의 UI를 정의하고 공개적으로 접근 가능하게 만든다 |
| `layout.tsx` | 하위 경로에 공유되는 UI. 리렌더링 없이 상태가 유지된다 |
| `loading.tsx` | Suspense 기반 즉시 로딩 UI |
| `error.tsx` | React Error Boundary 기반 에러 UI |
| `not-found.tsx` | 404 상태를 위한 UI |
| `template.tsx` | layout과 유사하나 네비게이션마다 새 인스턴스가 생성된다 |
| `default.tsx` | Parallel route의 폴백 UI |

### 올바른 패턴 — 기본 디렉토리 구조

```
app/
├── layout.tsx          # Root Layout (필수)
├── page.tsx            # / 경로
├── loading.tsx         # / 경로 로딩 UI
├── error.tsx           # / 경로 에러 UI
├── not-found.tsx       # 전역 404 UI
├── global-error.tsx    # Root Error Boundary
├── dashboard/
│   ├── layout.tsx      # 대시보드 공유 레이아웃
│   ├── page.tsx        # /dashboard
│   ├── loading.tsx     # 대시보드 로딩 UI
│   └── settings/
│       └── page.tsx    # /dashboard/settings
└── blog/
    ├── page.tsx        # /blog
    └── [slug]/
        └── page.tsx    # /blog/:slug
```

### Route Groups — 괄호를 이용한 논리적 그룹화

```
app/
├── (marketing)/
│   ├── layout.tsx      # 마케팅 전용 레이아웃
│   ├── about/
│   │   └── page.tsx    # /about
│   └── contact/
│       └── page.tsx    # /contact
├── (shop)/
│   ├── layout.tsx      # 쇼핑 전용 레이아웃
│   ├── products/
│   │   └── page.tsx    # /products
│   └── cart/
│       └── page.tsx    # /cart
└── layout.tsx          # Root Layout
```

> Route Group `(name)`은 URL에 반영되지 않는다. 레이아웃 분리 또는 코드 조직화에 사용한다.

### Parallel Routes — `@` 슬롯

```
app/
├── layout.tsx
├── page.tsx
├── @analytics/
│   ├── page.tsx        # 동시에 렌더링되는 analytics 슬롯
│   └── default.tsx     # 폴백 UI
└── @team/
    ├── page.tsx        # 동시에 렌더링되는 team 슬롯
    └── default.tsx
```

```tsx
// app/layout.tsx — Parallel Route 사용
export default function Layout({
  children,
  analytics,
  team,
}: {
  children: React.ReactNode;
  analytics: React.ReactNode;
  team: React.ReactNode;
}) {
  return (
    <div>
      {children}
      <div className="grid grid-cols-2 gap-4">
        {analytics}
        {team}
      </div>
    </div>
  );
}
```

### Intercepting Routes — 모달 패턴

```
app/
├── feed/
│   └── page.tsx            # /feed
├── photo/
│   └── [id]/
│       └── page.tsx        # /photo/:id (직접 접근 시 전체 페이지)
└── @modal/
    └── (.)photo/
        └── [id]/
            └── page.tsx    # /photo/:id (feed에서 이동 시 모달)
```

| 인터셉트 표기 | 의미 |
|--------------|------|
| `(.)` | 같은 레벨 |
| `(..)` | 한 레벨 위 |
| `(..)(..)` | 두 레벨 위 |
| `(...)` | app 루트부터 |

### Route Segment Config

```tsx
// app/blog/[slug]/page.tsx
export const dynamic = "force-dynamic";       // 항상 동적 렌더링
export const revalidate = 3600;               // ISR: 1시간마다 재검증
export const runtime = "edge";                // Edge Runtime 사용
export const preferredRegion = "icn1";        // 선호 리전
export const fetchCache = "default-no-store"; // fetch 캐시 기본값

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  // ...
}
```

| 옵션 | 값 | 설명 |
|------|-----|------|
| `dynamic` | `"auto"` `"force-dynamic"` `"error"` `"force-static"` | 렌더링 전략 |
| `revalidate` | `false` `0` `number` | ISR 재검증 주기(초) |
| `runtime` | `"nodejs"` `"edge"` | 실행 런타임 |

---

## Layout 패턴

### 역할

Layout은 여러 페이지 간에 공유되는 UI를 정의한다. 네비게이션 시 상태가 보존되고 리렌더링되지 않는다.

### 올바른 패턴 — Root Layout

```tsx
// app/layout.tsx — 필수. <html>과 <body> 태그를 포함해야 한다.
import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: {
    template: "%s | My App",
    default: "My App",
  },
  description: "Next.js application",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ko">
      <body className={inter.className}>
        <header>
          <nav>{/* 전역 네비게이션 */}</nav>
        </header>
        <main>{children}</main>
        <footer>{/* 전역 푸터 */}</footer>
      </body>
    </html>
  );
}
```

### 올바른 패턴 — Nested Layout

```tsx
// app/dashboard/layout.tsx — 대시보드 하위에만 적용
import { SideNav } from "@/components/side-nav";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex">
      <SideNav />
      <section className="flex-1 p-6">{children}</section>
    </div>
  );
}
```

### 올바른 패턴 — Layout 간 데이터 공유

```tsx
// Layout에서 fetch한 데이터를 children과 공유할 때는
// React cache()를 사용하여 중복 요청을 방지한다.

// lib/data.ts
import { cache } from "react";

export const getUser = cache(async (userId: string) => {
  const res = await fetch(`https://api.example.com/users/${userId}`);
  return res.json();
});

// app/dashboard/layout.tsx
import { getUser } from "@/lib/data";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const user = await getUser("current");

  return (
    <div>
      <nav>
        <span>{user.name}</span>
      </nav>
      {children}
    </div>
  );
}

// app/dashboard/page.tsx — 같은 getUser 호출이지만 캐시로 중복 요청 없음
import { getUser } from "@/lib/data";

export default async function DashboardPage() {
  const user = await getUser("current");

  return <h1>{user.name}의 대시보드</h1>;
}
```

### 잘못된 패턴

```tsx
// BAD: Layout에서 props로 데이터를 children에 전달하려는 시도
export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const user = await getUser("current");

  // children은 React.ReactNode이므로 props를 전달할 수 없다
  return (
    <div>
      {React.cloneElement(children, { user })} {/* 동작하지 않음 */}
    </div>
  );
}

// BAD: Layout에서 pathname 기반 조건부 렌더링
// Layout은 현재 경로를 알 수 없다 (Server Component에서 usePathname 사용 불가)
export default function Layout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname(); // Server Component에서 사용 불가
  return pathname === "/dashboard" ? <SpecialNav /> : <DefaultNav />;
}
```

### template.tsx vs layout.tsx

| 특성 | `layout.tsx` | `template.tsx` |
|------|-------------|----------------|
| 상태 유지 | 네비게이션 시 상태 보존 | 네비게이션마다 새 인스턴스 |
| 리렌더링 | 하지 않음 | 매번 수행 |
| useEffect | 네비게이션 시 재실행 안 됨 | 매번 재실행 |
| 용도 | 사이드바, 네비게이션 등 | 진입 애니메이션, 페이지뷰 로깅 |

```tsx
// app/dashboard/template.tsx — 페이지 전환마다 애니메이션 실행
"use client";

import { motion } from "framer-motion";

export default function Template({ children }: { children: React.ReactNode }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
    >
      {children}
    </motion.div>
  );
}
```

> **왜 이 패턴인가:** Layout은 네비게이션 간 상태를 유지하므로 사이드바, 네비게이션 등 지속적 UI에 적합하다. 반면 template은 매번 새로 마운트되므로 진입 애니메이션이나 페이지별 추적이 필요할 때 사용한다. 대부분의 경우 layout이 올바른 선택이다.

---

## Loading UI 패턴

### 역할

`loading.tsx`는 React Suspense를 기반으로 라우트 세그먼트의 콘텐츠가 로드되는 동안 즉시 표시되는 로딩 UI를 정의한다. 서버에서 새 콘텐츠가 준비되면 자동으로 교체된다.

### 올바른 패턴 — loading.tsx

```tsx
// app/dashboard/loading.tsx
export default function DashboardLoading() {
  return (
    <div className="animate-pulse space-y-4">
      <div className="h-8 w-48 rounded bg-gray-200" />
      <div className="grid grid-cols-3 gap-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="h-32 rounded bg-gray-200" />
        ))}
      </div>
      <div className="h-64 rounded bg-gray-200" />
    </div>
  );
}
```

### 올바른 패턴 — Suspense를 이용한 세밀한 스트리밍

```tsx
// app/dashboard/page.tsx — 페이지 내 개별 영역에 Suspense 적용
import { Suspense } from "react";
import { RevenueChart } from "@/components/revenue-chart";
import { LatestOrders } from "@/components/latest-orders";
import { StatCards } from "@/components/stat-cards";
import { StatCardsSkeleton, RevenueChartSkeleton, OrdersSkeleton } from "@/components/skeletons";

export default function DashboardPage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">대시보드</h1>

      {/* 각 영역이 독립적으로 스트리밍된다 */}
      <Suspense fallback={<StatCardsSkeleton />}>
        <StatCards />
      </Suspense>

      <div className="grid grid-cols-2 gap-6">
        <Suspense fallback={<RevenueChartSkeleton />}>
          <RevenueChart />
        </Suspense>

        <Suspense fallback={<OrdersSkeleton />}>
          <LatestOrders />
        </Suspense>
      </div>
    </div>
  );
}
```

### 올바른 패턴 — Skeleton 컴포넌트

```tsx
// components/skeletons.tsx
function Skeleton({ className }: { className?: string }) {
  return <div className={`animate-pulse rounded bg-gray-200 ${className ?? ""}`} />;
}

export function StatCardsSkeleton() {
  return (
    <div className="grid grid-cols-3 gap-4">
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="rounded-lg border p-4 space-y-2">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-8 w-32" />
        </div>
      ))}
    </div>
  );
}

export function RevenueChartSkeleton() {
  return (
    <div className="rounded-lg border p-4 space-y-4">
      <Skeleton className="h-4 w-32" />
      <Skeleton className="h-48 w-full" />
    </div>
  );
}

export function OrdersSkeleton() {
  return (
    <div className="rounded-lg border p-4 space-y-3">
      <Skeleton className="h-4 w-28" />
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="flex items-center gap-3">
          <Skeleton className="h-10 w-10 rounded-full" />
          <div className="flex-1 space-y-1">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-3 w-2/3" />
          </div>
        </div>
      ))}
    </div>
  );
}
```

### 잘못된 패턴

```tsx
// BAD: 페이지 전체를 하나의 loading.tsx로만 처리
// 모든 데이터가 준비될 때까지 전체 페이지가 로딩 상태로 표시된다
// → 빠르게 로드되는 영역도 불필요하게 대기하게 됨

// BAD: Client Component에서 useEffect + useState로 로딩 상태 관리
"use client";

import { useState, useEffect } from "react";

export default function Dashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/dashboard")
      .then((res) => res.json())
      .then((data) => {
        setData(data);
        setLoading(false);
      });
  }, []);

  if (loading) return <div>Loading...</div>;  // Suspense를 사용하지 않아 스트리밍 불가

  return <div>{/* ... */}</div>;
}
```

> **왜 이 패턴인가:** `loading.tsx`와 Suspense를 조합하면 서버에서 HTML을 점진적으로 스트리밍한다. 빠르게 준비되는 영역부터 사용자에게 보여줄 수 있어 체감 성능이 크게 향상된다. `useEffect` + `useState` 패턴은 클라이언트에서 추가 요청을 발생시키며 스트리밍의 이점을 잃는다.

---

## Error Handling 패턴

### 역할

`error.tsx`는 React Error Boundary를 자동으로 감싸 해당 라우트 세그먼트에서 발생하는 런타임 에러를 포착한다. `global-error.tsx`는 Root Layout의 에러를 포착하는 최상위 에러 경계이다.

### 올바른 패턴 — error.tsx

```tsx
// app/dashboard/error.tsx — 반드시 Client Component
"use client";

import { useEffect } from "react";

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // 에러 리포팅 서비스에 전송
    console.error(error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center gap-4 p-8">
      <h2 className="text-xl font-semibold">문제가 발생했습니다</h2>
      <p className="text-gray-600">
        {error.message || "알 수 없는 오류가 발생했습니다."}
      </p>
      <button
        onClick={() => reset()}
        className="rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600"
      >
        다시 시도
      </button>
    </div>
  );
}
```

### 올바른 패턴 — global-error.tsx

```tsx
// app/global-error.tsx — Root Layout 에러 포착. 자체 <html>/<body> 필요
"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="ko">
      <body>
        <div className="flex min-h-screen items-center justify-center">
          <div className="text-center space-y-4">
            <h1 className="text-2xl font-bold">심각한 오류가 발생했습니다</h1>
            <p>{error.message}</p>
            <button
              onClick={() => reset()}
              className="rounded bg-blue-500 px-4 py-2 text-white"
            >
              다시 시도
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
```

### 올바른 패턴 — not-found.tsx와 notFound()

```tsx
// app/not-found.tsx — 전역 404 페이지
import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4">
      <h2 className="text-2xl font-bold">페이지를 찾을 수 없습니다</h2>
      <p className="text-gray-600">요청하신 페이지가 존재하지 않습니다.</p>
      <Link
        href="/"
        className="rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600"
      >
        홈으로 돌아가기
      </Link>
    </div>
  );
}
```

```tsx
// app/blog/[slug]/page.tsx — notFound() 함수로 프로그래밍적 404 트리거
import { notFound } from "next/navigation";
import { getPost } from "@/lib/posts";

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await getPost(slug);

  if (!post) {
    notFound(); // 가장 가까운 not-found.tsx를 렌더링
  }

  return (
    <article>
      <h1>{post.title}</h1>
      <div dangerouslySetInnerHTML={{ __html: post.content }} />
    </article>
  );
}
```

```tsx
// app/blog/[slug]/not-found.tsx — 블로그 전용 404
import Link from "next/link";

export default function BlogNotFound() {
  return (
    <div className="space-y-4 p-8">
      <h2 className="text-xl font-bold">게시글을 찾을 수 없습니다</h2>
      <p>요청하신 블로그 게시글이 존재하지 않거나 삭제되었습니다.</p>
      <Link href="/blog" className="text-blue-500 underline">
        블로그 목록으로 돌아가기
      </Link>
    </div>
  );
}
```

### 잘못된 패턴

```tsx
// BAD: error.tsx를 Server Component로 작성
// error.tsx는 반드시 "use client" 디렉티브가 필요하다
export default function Error({ error, reset }) {
  // Error Boundary는 Client Component에서만 동작한다
  return <div>{error.message}</div>;
}

// BAD: try-catch로 모든 에러를 페이지 레벨에서 처리
export default async function Page() {
  try {
    const data = await fetchData();
    return <div>{data.title}</div>;
  } catch (e) {
    // 에러 UI가 page 내부에 하드코딩되어 일관성 없음
    // error.tsx를 사용하면 자동으로 Error Boundary가 적용된다
    return <div>에러 발생</div>;
  }
}

// BAD: reset 함수를 제공하지 않아 사용자가 복구할 수 없음
"use client";
export default function Error({ error }: { error: Error }) {
  return <div>에러: {error.message}</div>;
  // reset 버튼이 없어 새로고침 외에 복구 방법이 없다
}
```

### 에러 경계의 범위

```
layout.tsx          ← global-error.tsx가 포착
  template.tsx      ← error.tsx가 포착
    error.tsx       ← 이 레벨의 Error Boundary
      loading.tsx   ← error.tsx가 포착
        page.tsx    ← error.tsx가 포착
```

> **왜 이 패턴인가:** `error.tsx`는 같은 세그먼트의 `layout.tsx` 에러를 포착하지 못한다. Layout 에러를 포착하려면 부모 세그먼트의 `error.tsx`에 의존하거나 `global-error.tsx`를 사용해야 한다. `reset()` 함수는 에러 경계를 리셋하여 전체 새로고침 없이 복구를 시도할 수 있게 한다.

---

## Dynamic Routes 패턴

### 역할

대괄호 `[]`를 사용하여 동적 세그먼트를 정의한다. URL의 일부를 매개변수로 캡처하여 페이지에서 사용할 수 있다.

### 올바른 패턴 — 기본 동적 라우트

```tsx
// app/blog/[slug]/page.tsx
// URL: /blog/hello-world → params.slug = "hello-world"

interface BlogPostPageProps {
  params: Promise<{ slug: string }>;
}

export default async function BlogPostPage({ params }: BlogPostPageProps) {
  const { slug } = await params;
  const post = await getPost(slug);

  if (!post) {
    notFound();
  }

  return (
    <article>
      <h1>{post.title}</h1>
      <time dateTime={post.date}>{post.date}</time>
      <div>{post.content}</div>
    </article>
  );
}
```

### 올바른 패턴 — Catch-all 세그먼트

```tsx
// app/docs/[...slug]/page.tsx
// URL: /docs/a       → params.slug = ["a"]
// URL: /docs/a/b     → params.slug = ["a", "b"]
// URL: /docs/a/b/c   → params.slug = ["a", "b", "c"]
// URL: /docs         → 404 (매치 안 됨)

interface DocsPageProps {
  params: Promise<{ slug: string[] }>;
}

export default async function DocsPage({ params }: DocsPageProps) {
  const { slug } = await params;
  const path = slug.join("/");
  const doc = await getDoc(path);

  return (
    <div>
      <nav>
        {/* 빵 부스러기(breadcrumb) 생성 */}
        {slug.map((segment, index) => (
          <span key={segment}>
            {index > 0 && " / "}
            <a href={`/docs/${slug.slice(0, index + 1).join("/")}`}>
              {segment}
            </a>
          </span>
        ))}
      </nav>
      <article>{doc.content}</article>
    </div>
  );
}
```

### 올바른 패턴 — Optional Catch-all 세그먼트

```tsx
// app/docs/[[...slug]]/page.tsx
// URL: /docs         → params.slug = undefined (인덱스 페이지도 매치)
// URL: /docs/a       → params.slug = ["a"]
// URL: /docs/a/b     → params.slug = ["a", "b"]

interface DocsPageProps {
  params: Promise<{ slug?: string[] }>;
}

export default async function DocsPage({ params }: DocsPageProps) {
  const { slug } = await params;

  if (!slug) {
    return <DocsIndex />;  // /docs 인덱스 페이지
  }

  const path = slug.join("/");
  const doc = await getDoc(path);
  return <article>{doc.content}</article>;
}
```

### 올바른 패턴 — generateStaticParams

```tsx
// app/blog/[slug]/page.tsx
// 빌드 시 정적 생성할 경로 목록을 반환한다

export async function generateStaticParams() {
  const posts = await getAllPosts();

  return posts.map((post) => ({
    slug: post.slug,  // 키 이름은 동적 세그먼트 이름과 일치해야 함
  }));
}

// 중첩 동적 라우트의 경우
// app/products/[category]/[id]/page.tsx
export async function generateStaticParams() {
  const products = await getAllProducts();

  return products.map((product) => ({
    category: product.category,
    id: product.id.toString(),
  }));
}
```

### 올바른 패턴 — 동적 세그먼트의 TypeScript 타입

```tsx
// 타입 안전한 동적 라우트 매개변수 정의

// [id] → { id: string }
// [slug] → { slug: string }
// [...slug] → { slug: string[] }
// [[...slug]] → { slug?: string[] }
// [category]/[id] → { category: string; id: string }

// Next.js 15에서 params는 Promise로 래핑된다
interface ProductPageProps {
  params: Promise<{
    category: string;
    id: string;
  }>;
  searchParams: Promise<{
    sort?: string;
    filter?: string;
  }>;
}

export default async function ProductPage({ params, searchParams }: ProductPageProps) {
  const { category, id } = await params;
  const { sort, filter } = await searchParams;

  const product = await getProduct(category, id);

  return (
    <div>
      <h1>{product.name}</h1>
      <p>카테고리: {category}</p>
    </div>
  );
}
```

### 잘못된 패턴

```tsx
// BAD: params를 await하지 않고 직접 접근 (Next.js 15에서는 Promise)
export default function Page({ params }: { params: { slug: string } }) {
  // Next.js 15에서 params는 Promise이므로 await 필요
  return <div>{params.slug}</div>; // 동작하지 않음
}

// BAD: generateStaticParams의 반환 키가 세그먼트 이름과 불일치
// 파일: app/blog/[slug]/page.tsx
export async function generateStaticParams() {
  const posts = await getAllPosts();
  return posts.map((post) => ({
    id: post.slug, // 'slug'여야 하는데 'id'로 반환
  }));
}

// BAD: 동적 세그먼트 값을 number로 가정
export default async function Page({ params }: { params: Promise<{ id: number }> }) {
  const { id } = await params;
  // 동적 세그먼트는 항상 string이다. 필요 시 명시적 변환 필요
  const product = await getProduct(Number(id));
}
```

> **왜 이 패턴인가:** `generateStaticParams`를 사용하면 빌드 시 정적 페이지를 미리 생성하여 응답 속도를 극대화한다. Next.js 15에서 `params`와 `searchParams`가 `Promise`로 변경되었으므로 반드시 `await`해야 한다. 동적 세그먼트 값은 항상 `string` 타입이므로 숫자가 필요한 경우 명시적으로 변환해야 한다.

---

## Middleware 패턴

### 역할

Middleware는 요청이 완료되기 전에 실행되는 코드이다. 프로젝트 루트의 `middleware.ts`에 정의하며, 인증/인가, 리다이렉트, 헤더 조작 등에 사용한다. Edge Runtime에서 실행된다.

### 올바른 패턴 — 인증 체크

```tsx
// middleware.ts (프로젝트 루트 또는 src/)
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const token = request.cookies.get("session-token")?.value;
  const { pathname } = request.nextUrl;

  // 공개 경로는 통과
  const publicPaths = ["/login", "/register", "/api/auth"];
  if (publicPaths.some((path) => pathname.startsWith(path))) {
    return NextResponse.next();
  }

  // 토큰 없으면 로그인으로 리다이렉트
  if (!token) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("callbackUrl", pathname);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

// matcher로 미들웨어 실행 범위 제한
export const config = {
  matcher: [
    // 정적 파일과 API 라우트 제외
    "/((?!_next/static|_next/image|favicon.ico|public/).*)",
  ],
};
```

### 올바른 패턴 — 역할 기반 인가

```tsx
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { verifyToken } from "@/lib/auth";

const roleRoutes: Record<string, string[]> = {
  "/admin": ["admin"],
  "/dashboard": ["admin", "user"],
  "/api/admin": ["admin"],
};

export async function middleware(request: NextRequest) {
  const token = request.cookies.get("session-token")?.value;
  const { pathname } = request.nextUrl;

  // 역할 제한이 필요한 경로인지 확인
  const requiredRoles = Object.entries(roleRoutes).find(([path]) =>
    pathname.startsWith(path),
  );

  if (!requiredRoles) {
    return NextResponse.next();
  }

  if (!token) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  const user = await verifyToken(token);
  if (!user || !requiredRoles[1].includes(user.role)) {
    return NextResponse.redirect(new URL("/unauthorized", request.url));
  }

  // 요청 헤더에 사용자 정보 추가 (downstream에서 사용)
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-user-id", user.id);
  requestHeaders.set("x-user-role", user.role);

  return NextResponse.next({
    request: { headers: requestHeaders },
  });
}
```

### 올바른 패턴 — 리다이렉트와 리라이트

```tsx
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // 301 영구 리다이렉트 — URL이 변경됨
  if (pathname === "/old-blog") {
    return NextResponse.redirect(new URL("/blog", request.url), 301);
  }

  // 리라이트 — URL은 그대로, 내부적으로 다른 경로 처리
  if (pathname.startsWith("/api/v1")) {
    return NextResponse.rewrite(
      new URL(pathname.replace("/api/v1", "/api/v2"), request.url),
    );
  }

  // 지역 기반 리다이렉트
  const country = request.geo?.country ?? "KR";
  if (pathname === "/" && country === "US") {
    return NextResponse.rewrite(new URL("/en", request.url));
  }

  return NextResponse.next();
}
```

### 올바른 패턴 — 응답 헤더 조작

```tsx
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const response = NextResponse.next();

  // 보안 헤더 추가
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set(
    "Content-Security-Policy",
    "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';",
  );

  // CORS 헤더 (API 라우트용)
  if (request.nextUrl.pathname.startsWith("/api/")) {
    response.headers.set("Access-Control-Allow-Origin", "https://example.com");
    response.headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE");
    response.headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  }

  return response;
}
```

### 올바른 패턴 — Matcher 설정

```tsx
// matcher config 예시
export const config = {
  matcher: [
    // 단일 경로
    "/dashboard",

    // 와일드카드 — /dashboard 하위 모든 경로
    "/dashboard/:path*",

    // 정규식 — /api로 시작하지만 /api/public 제외
    "/api/((?!public).*)",

    // 여러 경로 조합 — 정적 파일 제외
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
```

### 잘못된 패턴

```tsx
// BAD: Middleware에서 무거운 작업 수행
export async function middleware(request: NextRequest) {
  // Middleware는 Edge Runtime에서 실행되므로 Node.js API 사용 불가
  const fs = require("fs"); // Edge Runtime에서 사용 불가

  // 데이터베이스 직접 연결은 피해야 함
  const db = await connectToDatabase(); // 매 요청마다 연결 → 성능 저하

  // 무거운 연산은 Middleware에서 부적절
  const result = await heavyComputation(); // 모든 요청에 지연 발생
}

// BAD: matcher 없이 모든 경로에 Middleware 적용
export function middleware(request: NextRequest) {
  // 정적 파일, 이미지 등 모든 요청에 불필요하게 실행됨
  const token = request.cookies.get("token");
  if (!token) {
    return NextResponse.redirect(new URL("/login", request.url));
  }
}
// matcher가 없으면 _next/static, favicon.ico 등에도 실행된다

// BAD: Middleware에서 응답 본문 생성
export function middleware(request: NextRequest) {
  // Middleware는 리다이렉트, 리라이트, 헤더 조작만 해야 한다
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
  }); // Route Handler나 API Route에서 처리해야 함
}
```

### Middleware 실행 순서

| 순서 | 항목 |
|------|------|
| 1 | `next.config.js`의 `headers` |
| 2 | `next.config.js`의 `redirects` |
| 3 | Middleware (`rewrites`, `redirects` 등) |
| 4 | `next.config.js`의 `beforeFiles` rewrites |
| 5 | 파일시스템 라우트 (`public/`, `_next/static/`, `pages/`, `app/`) |
| 6 | `next.config.js`의 `afterFiles` rewrites |
| 7 | `next.config.js`의 `fallback` rewrites |

> **왜 이 패턴인가:** Middleware는 모든 라우트 요청 전에 실행되므로 가볍게 유지해야 한다. Edge Runtime에서 실행되어 Node.js의 전체 API를 사용할 수 없다. `matcher`를 반드시 설정하여 정적 파일 등 불필요한 경로에서의 실행을 방지해야 한다. 무거운 인증 로직은 Server Component나 Route Handler로 위임하고, Middleware에서는 토큰 존재 여부 등 가벼운 검사만 수행한다.
