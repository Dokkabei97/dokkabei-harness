# Data Fetching Patterns — Next.js 15 App Router

Next.js 15 App Router에서 데이터 페칭, 캐싱, 뮤테이션의 핵심 패턴.

---

## 1. Server Component Data Fetching

### 역할
- 서버에서 직접 데이터를 가져와 클라이언트에 HTML로 전달
- API 엔드포인트 없이 데이터베이스, 외부 API에 직접 접근
- 클라이언트 번들 사이즈 제로 — fetch 로직이 서버에서만 실행

### 올바른 패턴 — Async Server Component

```tsx
// app/posts/page.tsx
// Server Component는 기본값 — 'use client' 없으면 서버에서 실행
async function PostList() {
  const posts = await fetch('https://api.example.com/posts', {
    next: { revalidate: 60, tags: ['posts'] },
  }).then((res) => res.json());

  return (
    <ul>
      {posts.map((post: Post) => (
        <li key={post.id}>{post.title}</li>
      ))}
    </ul>
  );
}

export default async function PostsPage() {
  return (
    <Suspense fallback={<PostListSkeleton />}>
      <PostList />
    </Suspense>
  );
}
```

### fetch 옵션 정리

| 옵션 | 설명 | 예시 |
|------|------|------|
| `cache: 'force-cache'` | 기본값. 응답을 Data Cache에 저장 | 정적 데이터 |
| `cache: 'no-store'` | 매 요청마다 새로 fetch | 실시간 데이터 |
| `next: { revalidate: N }` | N초마다 백그라운드에서 재검증 | 블로그 포스트 |
| `next: { tags: ['tag'] }` | 태그 기반 on-demand 재검증용 | CMS 콘텐츠 |

### 올바른 패턴 — Request Deduplication

```tsx
// React는 동일 URL + 옵션의 fetch를 자동으로 중복 제거한다.
// 별도 캐시 레이어 없이 여러 컴포넌트에서 같은 데이터를 요청해도 된다.

// app/layout.tsx
async function Layout({ children }: { children: React.ReactNode }) {
  // 이 fetch는 한 번만 실행됨
  const user = await getUser();
  return (
    <html>
      <body>
        <Navbar user={user} />
        {children}
      </body>
    </html>
  );
}

// app/page.tsx
async function Page() {
  // 같은 함수 호출이지만, React가 위의 요청과 중복 제거
  const user = await getUser();
  return <Dashboard user={user} />;
}

// lib/data.ts
async function getUser() {
  const res = await fetch('https://api.example.com/user', {
    next: { tags: ['user'] },
  });
  return res.json();
}
```

### 올바른 패턴 — Parallel Data Fetching

```tsx
// GOOD: Promise.all로 병렬 fetch — 총 시간 = 가장 느린 요청
async function Dashboard() {
  const [user, posts, analytics] = await Promise.all([
    getUser(),
    getPosts(),
    getAnalytics(),
  ]);

  return (
    <div>
      <UserProfile user={user} />
      <PostList posts={posts} />
      <AnalyticsChart data={analytics} />
    </div>
  );
}
```

### 잘못된 패턴 — Sequential Waterfall

```tsx
// BAD: 순차적 fetch — 총 시간 = 모든 요청 시간의 합
async function Dashboard() {
  // ❌ getUser() 완료 후에야 getPosts() 시작
  const user = await getUser();
  // ❌ getPosts() 완료 후에야 getAnalytics() 시작
  const posts = await getPosts();
  const analytics = await getAnalytics();

  return (
    <div>
      <UserProfile user={user} />
      <PostList posts={posts} />
      <AnalyticsChart data={analytics} />
    </div>
  );
}
```

### 왜 이 패턴인가
- Server Component에서 직접 fetch하면 클라이언트-서버 왕복이 없어 성능이 좋다
- React의 자동 중복 제거 덕분에 데이터를 props로 내려보내는 prop drilling이 불필요하다
- 독립적인 데이터는 반드시 병렬로 fetch하여 waterfall을 방지해야 한다

---

## 2. Caching 전략

### 역할
- Next.js는 4개 레이어의 캐시를 제공하며, 각각의 무효화 방법이 다르다
- 올바른 캐시 전략은 성능과 데이터 신선도 사이의 균형을 결정한다

### 캐시 레이어 개요

| 캐시 | 위치 | 대상 | 무효화 방법 |
|------|------|------|-------------|
| Request Memoization | 서버 (요청 단위) | 동일 fetch 중복 제거 | 요청 종료 시 자동 |
| Data Cache | 서버 (영구) | fetch 응답 | `revalidateTag`, `revalidatePath`, `revalidate: N` |
| Full Route Cache | 서버 (영구) | 렌더링된 HTML + RSC Payload | 재배포 또는 revalidation |
| Router Cache | 클라이언트 (세션) | RSC Payload (방문한 라우트) | `router.refresh()`, revalidation, 쿠키 변경 |

### 올바른 패턴 — Static vs Dynamic Rendering 제어

```tsx
// 정적 렌더링 (기본값) — 빌드 타임에 렌더링, Full Route Cache 적용
// 동적 함수(cookies(), headers(), searchParams)를 사용하지 않으면 정적
export default async function StaticPage() {
  // force-cache가 기본값 — Data Cache에 저장
  const data = await fetch('https://api.example.com/static-data');
  return <div>{/* ... */}</div>;
}

// 동적 렌더링 — 매 요청마다 렌더링
export default async function DynamicPage() {
  // cookies() 사용 → 자동으로 동적 렌더링 전환
  const session = await cookies();
  const token = session.get('token');

  const data = await fetch('https://api.example.com/user-data', {
    headers: { Authorization: `Bearer ${token?.value}` },
    cache: 'no-store',
  });
  return <div>{/* ... */}</div>;
}
```

### 올바른 패턴 — unstable_cache (Data Cache 직접 제어)

```tsx
import { unstable_cache } from 'next/cache';
import { db } from '@/lib/db';

// fetch를 사용하지 않는 데이터 소스(ORM, DB 직접 쿼리)에 캐싱 적용
const getCachedPosts = unstable_cache(
  async (authorId: string) => {
    return db.post.findMany({
      where: { authorId },
      orderBy: { createdAt: 'desc' },
    });
  },
  // 캐시 키 접두사
  ['posts-by-author'],
  {
    tags: ['posts'],
    revalidate: 60,
  }
);

export default async function AuthorPosts({ authorId }: { authorId: string }) {
  const posts = await getCachedPosts(authorId);
  return <PostList posts={posts} />;
}
```

### 잘못된 패턴 — 캐시 무효화 누락

```tsx
// BAD: 캐시를 사용하면서 무효화 전략이 없음
export default async function ProductPage({ params }: { params: { id: string } }) {
  // ❌ force-cache(기본값)인데 상품 가격이 변경되면 반영 안 됨
  const product = await fetch(`https://api.example.com/products/${params.id}`);

  // ❌ revalidate도, tags도 없어서 재배포 전까지 오래된 데이터 표시
  return <ProductDetail product={await product.json()} />;
}
```

### 올바른 패턴 — 캐싱 비활성화 (실시간 데이터)

```tsx
// 방법 1: fetch 단위 — 특정 요청만 캐시 비활성화
const data = await fetch('https://api.example.com/realtime', {
  cache: 'no-store',
});

// 방법 2: 라우트 세그먼트 단위 — 전체 페이지 동적 렌더링
// app/dashboard/layout.tsx
export const dynamic = 'force-dynamic';
// 또는
export const revalidate = 0;
```

### 왜 이 패턴인가
- Next.js의 캐시는 기본적으로 "가능한 한 많이 캐싱"하는 방향이다
- 각 캐시 레이어를 이해하지 못하면 오래된 데이터가 표시되는 버그가 발생한다
- `unstable_cache`는 ORM/DB 쿼리처럼 `fetch`를 사용하지 않는 데이터 소스에 필수적이다

---

## 3. Revalidation 패턴

### 역할
- 캐시된 데이터를 적절한 시점에 갱신하여 데이터 신선도를 보장
- Time-based와 On-demand 두 가지 접근 방식을 상황에 맞게 선택

### 올바른 패턴 — Time-based Revalidation

```tsx
// 60초마다 백그라운드에서 재검증 (stale-while-revalidate 방식)
// 유저는 항상 캐시된 데이터를 즉시 받고, 백그라운드에서 갱신
const posts = await fetch('https://api.example.com/posts', {
  next: { revalidate: 60 },
});

// 라우트 세그먼트 단위로 설정도 가능
// app/blog/layout.tsx
export const revalidate = 60; // 이 레이아웃 하위 모든 fetch에 적용
```

### 올바른 패턴 — On-demand Revalidation

```tsx
// app/actions.ts
'use server';

import { revalidateTag, revalidatePath } from 'next/cache';

// 태그 기반 — 특정 데이터 그룹만 정밀하게 무효화
export async function publishPost(formData: FormData) {
  const title = formData.get('title') as string;
  const content = formData.get('content') as string;

  await db.post.create({ data: { title, content } });

  // 'posts' 태그가 붙은 모든 fetch 캐시 무효화
  revalidateTag('posts');
}

// 경로 기반 — 특정 페이지 전체 재렌더링
export async function updateProfile(formData: FormData) {
  await db.user.update({ /* ... */ });

  // /profile 페이지의 모든 캐시 무효화
  revalidatePath('/profile');

  // 레이아웃 단위 무효화
  revalidatePath('/dashboard', 'layout');
}
```

### 잘못된 패턴 — 과도한 revalidatePath

```tsx
// BAD: 모든 변경에 revalidatePath('/') 사용
export async function updatePost() {
  await db.post.update({ /* ... */ });

  // ❌ 전체 사이트 캐시 무효화 — 불필요한 재렌더링 유발
  revalidatePath('/');
}

// BAD: 태그를 사용할 수 있는 상황에서 path 사용
export async function deleteComment(commentId: string) {
  await db.comment.delete({ where: { id: commentId } });

  // ❌ 어떤 포스트에 달린 댓글인지 모르면 관련 없는 페이지도 무효화됨
  revalidatePath('/posts');
}
```

### 언제 어떤 방식을 사용하는가

| 시나리오 | 권장 방식 | 이유 |
|---------|----------|------|
| 블로그 포스트 목록 | `revalidate: 60` | 약간의 지연 허용, 자동 갱신 |
| CMS 콘텐츠 발행 | `revalidateTag('content')` | 발행 시점에 즉시 반영 필요 |
| 유저 프로필 수정 | `revalidatePath('/profile')` | 수정 직후 반영 필요 |
| 주식 가격, 실시간 채팅 | `cache: 'no-store'` | 캐싱 자체가 부적합 |
| 정적 마케팅 페이지 | 기본값 (빌드 타임) | 변경 빈도 극히 낮음 |

### 왜 이 패턴인가
- `revalidateTag`는 가장 정밀한 무효화 도구다 — 관련 데이터만 갱신한다
- `revalidatePath('/')`는 사실상 캐시를 포기하는 것과 같으므로 피해야 한다
- Time-based는 "적당히 신선한" 데이터에, On-demand는 "즉시 반영"이 필요한 뮤테이션에 사용한다

---

## 4. Server Actions

### 역할
- 서버에서 실행되는 비동기 함수를 클라이언트에서 직접 호출
- Form 제출, 데이터 뮤테이션의 표준 패턴
- API Route 없이 서버 로직 실행 가능

### 올바른 패턴 — 기본 Server Action + Form

```tsx
// app/actions.ts
'use server';

import { revalidateTag } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';

const CreatePostSchema = z.object({
  title: z.string().min(1, '제목은 필수입니다').max(200),
  content: z.string().min(1, '내용은 필수입니다'),
});

export type ActionState = {
  errors?: {
    title?: string[];
    content?: string[];
    _form?: string[];
  };
  message?: string;
};

export async function createPost(
  prevState: ActionState,
  formData: FormData,
): Promise<ActionState> {
  // 1. 입력값 검증
  const parsed = CreatePostSchema.safeParse({
    title: formData.get('title'),
    content: formData.get('content'),
  });

  if (!parsed.success) {
    return {
      errors: parsed.error.flatten().fieldErrors,
    };
  }

  // 2. 데이터 변경
  try {
    await db.post.create({
      data: parsed.data,
    });
  } catch (error) {
    return {
      errors: { _form: ['포스트 생성에 실패했습니다. 다시 시도해주세요.'] },
    };
  }

  // 3. 캐시 무효화 + 리다이렉트
  revalidateTag('posts');
  redirect('/posts');
}
```

### 올바른 패턴 — useActionState로 Form 상태 관리

```tsx
// app/posts/new/page.tsx
'use client';

import { useActionState } from 'react';
import { createPost, type ActionState } from '@/app/actions';

const initialState: ActionState = {};

export default function NewPostForm() {
  const [state, formAction, isPending] = useActionState(createPost, initialState);

  return (
    <form action={formAction}>
      <div>
        <label htmlFor="title">제목</label>
        <input id="title" name="title" disabled={isPending} />
        {state.errors?.title && (
          <p className="text-red-500">{state.errors.title[0]}</p>
        )}
      </div>

      <div>
        <label htmlFor="content">내용</label>
        <textarea id="content" name="content" disabled={isPending} />
        {state.errors?.content && (
          <p className="text-red-500">{state.errors.content[0]}</p>
        )}
      </div>

      {state.errors?._form && (
        <p className="text-red-500">{state.errors._form[0]}</p>
      )}

      <button type="submit" disabled={isPending}>
        {isPending ? '저장 중...' : '포스트 작성'}
      </button>
    </form>
  );
}
```

### 올바른 패턴 — useOptimistic으로 낙관적 업데이트

```tsx
'use client';

import { useOptimistic } from 'react';
import { toggleLike } from '@/app/actions';

interface Post {
  id: string;
  title: string;
  liked: boolean;
  likeCount: number;
}

export function PostCard({ post }: { post: Post }) {
  const [optimisticPost, setOptimisticPost] = useOptimistic(
    post,
    (currentPost, newLiked: boolean) => ({
      ...currentPost,
      liked: newLiked,
      likeCount: currentPost.likeCount + (newLiked ? 1 : -1),
    }),
  );

  async function handleToggleLike() {
    const newLiked = !optimisticPost.liked;
    // 즉시 UI 반영
    setOptimisticPost(newLiked);
    // 서버 요청 — 실패 시 자동 롤백
    await toggleLike(post.id, newLiked);
  }

  return (
    <div>
      <h2>{optimisticPost.title}</h2>
      <button onClick={handleToggleLike}>
        {optimisticPost.liked ? '♥' : '♡'} {optimisticPost.likeCount}
      </button>
    </div>
  );
}
```

### 잘못된 패턴

```tsx
// BAD: Server Action 안에서 try-catch 없이 직접 throw
'use server';

export async function deletePost(id: string) {
  // ❌ 에러가 클라이언트에 직접 전파 — 유저에게 의미 없는 에러 메시지 노출
  const post = await db.post.delete({ where: { id } });

  // ❌ revalidation 누락 — 삭제 후에도 목록에 남아있음
  return post;
}

// BAD: Server Action에서 민감한 정보 반환
'use server';

export async function getSecretData() {
  // ❌ Server Action의 반환값은 클라이언트로 직렬화됨
  const config = await db.config.findFirst();
  return config; // DB 비밀번호, API 키 등이 포함될 수 있음
}
```

### 왜 이 패턴인가
- Server Action + `useActionState`는 Progressive Enhancement를 지원한다 (JS 비활성화 시에도 동작)
- Zod 검증을 서버에서 수행하면 클라이언트 검증 우회를 방지한다
- `useOptimistic`은 서버 응답을 기다리지 않아 체감 성능이 향상된다
- 에러 핸들링과 revalidation을 반드시 포함해야 데이터 일관성이 유지된다

---

## 5. Client-side Data Fetching

### 역할
- 실시간 데이터, 유저별 인터랙션, 폴링이 필요한 경우에 사용
- Server Component로 해결할 수 없는 클라이언트 전용 시나리오를 처리

### 언제 클라이언트 페칭을 사용하는가

| 시나리오 | Server Component | Client Fetching |
|---------|-----------------|-----------------|
| 초기 페이지 로드 데이터 | O | X |
| SEO가 필요한 콘텐츠 | O | X |
| 실시간 알림/채팅 | X | O |
| 무한 스크롤 | X | O |
| 유저 인터랙션 기반 데이터 | X | O |
| 인터벌 폴링 | X | O |

### 올바른 패턴 — TanStack Query + Server Component Hydration

```tsx
// providers/query-provider.tsx
'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState } from 'react';

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000, // 1분간 fresh
            gcTime: 5 * 60 * 1000, // 5분간 캐시 유지
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}
```

```tsx
// app/dashboard/page.tsx — Server Component에서 초기 데이터 주입
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query';
import { getNotifications } from '@/lib/api';
import { NotificationList } from './notification-list';

export default async function DashboardPage() {
  const queryClient = new QueryClient();

  // 서버에서 prefetch — SSR 시점에 데이터 준비
  await queryClient.prefetchQuery({
    queryKey: ['notifications'],
    queryFn: getNotifications,
  });

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      {/* 클라이언트에서 hydration 후 실시간 갱신 */}
      <NotificationList />
    </HydrationBoundary>
  );
}
```

```tsx
// app/dashboard/notification-list.tsx
'use client';

import { useQuery } from '@tanstack/react-query';
import { getNotifications } from '@/lib/api';

export function NotificationList() {
  const { data: notifications, isLoading, error } = useQuery({
    queryKey: ['notifications'],
    queryFn: getNotifications,
    refetchInterval: 10_000, // 10초마다 폴링
  });

  if (isLoading) return <NotificationSkeleton />;
  if (error) return <ErrorMessage error={error} />;

  return (
    <ul>
      {notifications?.map((n) => (
        <li key={n.id}>{n.message}</li>
      ))}
    </ul>
  );
}
```

### 올바른 패턴 — SWR 대안

```tsx
'use client';

import useSWR from 'swr';

const fetcher = (url: string) => fetch(url).then((res) => res.json());

export function SearchResults({ query }: { query: string }) {
  const { data, error, isLoading } = useSWR(
    query ? `/api/search?q=${encodeURIComponent(query)}` : null,
    fetcher,
    {
      dedupingInterval: 2000,
      revalidateOnFocus: false,
    },
  );

  if (!query) return null;
  if (isLoading) return <SearchSkeleton />;
  if (error) return <p>검색 중 오류가 발생했습니다.</p>;

  return (
    <ul>
      {data?.results.map((item: SearchResult) => (
        <li key={item.id}>{item.title}</li>
      ))}
    </ul>
  );
}
```

### 잘못된 패턴

```tsx
// BAD: Server Component에서 할 수 있는 일을 Client에서 fetch
'use client';

import { useEffect, useState } from 'react';

export default function PostList() {
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);

  // ❌ 초기 로드 데이터를 useEffect로 fetch — 워터폴 + 레이아웃 시프트
  useEffect(() => {
    fetch('/api/posts')
      .then((res) => res.json())
      .then((data) => {
        setPosts(data);
        setLoading(false);
      });
  }, []);

  // ❌ SEO 불가 — 검색엔진이 빈 HTML을 수집
  if (loading) return <div>Loading...</div>;
  return <ul>{posts.map(/* ... */)}</ul>;
}
```

### 왜 이 패턴인가
- 초기 데이터는 Server Component에서, 실시간 갱신은 TanStack Query에서 맡기는 것이 최적이다
- `HydrationBoundary`로 서버 데이터를 클라이언트 캐시에 주입하면 이중 fetch가 없다
- `useEffect` + `useState` 패턴은 waterfall, 깜빡임, SEO 문제를 모두 유발한다

---

## 6. API Layer 패턴

### 역할
- 데이터 접근 로직을 한 곳에 집중하여 중복 제거 및 타입 안전성 확보
- fetch 래퍼로 에러 핸들링, 인증 토큰 관리를 통일
- Server Component와 Client Component 모두에서 재사용 가능한 API 클라이언트 구축

### 올바른 패턴 — Data Access Layer (DAL) 분리

```tsx
// lib/dal.ts — 서버 전용 데이터 접근 레이어
import 'server-only'; // 클라이언트 번들에 포함되면 빌드 에러

import { cookies } from 'next/headers';
import { cache } from 'react';
import { db } from '@/lib/db';
import { verifyToken } from '@/lib/auth';

// React cache로 요청 단위 메모이제이션 (fetch가 아닌 함수에 사용)
export const getCurrentUser = cache(async () => {
  const cookieStore = await cookies();
  const token = cookieStore.get('session')?.value;

  if (!token) return null;

  try {
    const payload = await verifyToken(token);
    const user = await db.user.findUnique({
      where: { id: payload.userId },
      select: { id: true, name: true, email: true, role: true },
    });
    return user;
  } catch {
    return null;
  }
});

export async function getPostsByAuthor(authorId: string) {
  const user = await getCurrentUser();
  if (!user) throw new Error('Unauthorized');

  return db.post.findMany({
    where: { authorId },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      title: true,
      summary: true,
      createdAt: true,
      // ❌ content 같은 큰 필드는 목록 조회에서 제외
    },
  });
}
```

### 올바른 패턴 — Type-safe Fetch Wrapper

```tsx
// lib/api-client.ts

class ApiError extends Error {
  constructor(
    public status: number,
    public statusText: string,
    public body: unknown,
  ) {
    super(`API Error: ${status} ${statusText}`);
    this.name = 'ApiError';
  }
}

interface RequestOptions extends Omit<RequestInit, 'method' | 'body'> {
  params?: Record<string, string>;
  next?: NextFetchRequestConfig;
}

const BASE_URL = process.env.API_BASE_URL ?? 'https://api.example.com';

async function request<T>(
  method: string,
  path: string,
  body?: unknown,
  options: RequestOptions = {},
): Promise<T> {
  const { params, next: nextConfig, ...fetchOptions } = options;

  // Query params 처리
  const url = new URL(path, BASE_URL);
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      url.searchParams.set(key, value);
    });
  }

  const res = await fetch(url.toString(), {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...fetchOptions.headers,
    },
    body: body ? JSON.stringify(body) : undefined,
    next: nextConfig,
    ...fetchOptions,
  });

  if (!res.ok) {
    const errorBody = await res.json().catch(() => null);
    throw new ApiError(res.status, res.statusText, errorBody);
  }

  // 204 No Content
  if (res.status === 204) return undefined as T;

  return res.json() as Promise<T>;
}

// 타입 안전한 API 메서드
export const api = {
  get: <T>(path: string, options?: RequestOptions) =>
    request<T>('GET', path, undefined, options),

  post: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('POST', path, body, options),

  put: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('PUT', path, body, options),

  patch: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('PATCH', path, body, options),

  delete: <T = void>(path: string, options?: RequestOptions) =>
    request<T>('DELETE', path, undefined, options),
};
```

```tsx
// 사용 예시 — Server Component
import { api } from '@/lib/api-client';

interface Post {
  id: string;
  title: string;
  content: string;
}

async function PostPage({ params }: { params: { id: string } }) {
  const post = await api.get<Post>(`/posts/${params.id}`, {
    next: { tags: [`post-${params.id}`], revalidate: 60 },
  });

  return <article>{post.title}</article>;
}
```

### 잘못된 패턴

```tsx
// BAD: 컴포넌트마다 fetch 로직 중복
async function PostList() {
  // ❌ 에러 핸들링 없음
  const res = await fetch('https://api.example.com/posts');
  const posts = await res.json();
  return <ul>{/* ... */}</ul>;
}

async function PostDetail({ id }: { id: string }) {
  // ❌ BASE_URL 하드코딩 반복
  const res = await fetch(`https://api.example.com/posts/${id}`);
  // ❌ res.ok 확인 없이 json() 호출 — 400/500 에러 시 무의미한 파싱 시도
  const post = await res.json();
  return <article>{/* ... */}</article>;
}

// BAD: 서버 전용 코드가 클라이언트에 노출
// ❌ 'server-only' import 없이 DB 직접 접근 함수를 export
// → 클라이언트 번들에 포함되면 DB 연결 정보 노출 위험
export async function getUsers() {
  return db.user.findMany();
}
```

### DAL 설계 원칙

| 원칙 | 설명 |
|------|------|
| `server-only` import 필수 | 서버 전용 코드가 클라이언트로 유출되는 것을 빌드 타임에 차단 |
| `select`로 필요한 필드만 조회 | 과도한 데이터 전송 방지, 민감 정보 노출 차단 |
| `React.cache()`로 요청 단위 메모이제이션 | fetch가 아닌 함수에 중복 제거 적용 |
| 인증/인가 검사를 DAL에서 수행 | 컴포넌트가 아닌 데이터 레이어에서 접근 제어 통일 |
| 에러를 적절한 타입으로 변환 | `ApiError` 같은 도메인 에러로 감싸서 일관된 핸들링 |

### 왜 이 패턴인가
- DAL은 "데이터 접근"이라는 관심사를 한 레이어에 집중시켜 유지보수성을 높인다
- `server-only`는 민감한 서버 코드가 클라이언트 번들에 포함되는 보안 사고를 방지한다
- Type-safe API 클라이언트는 런타임 에러 대신 컴파일 타임에 문제를 발견하게 해준다
