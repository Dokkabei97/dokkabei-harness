# Testing Patterns — Next.js 15 App Router

Next.js 15 App Router 프로젝트의 테스트 작성 패턴과 전략.

---

## 테스트 피라미드

```
        ╱ E2E ╲               ~5%  — Playwright (브라우저 전체 흐름)
       ╱ Integration ╲        ~15% — Server Actions, Page 컴포넌트, API
      ╱ Component Tests ╲     ~30% — @testing-library/react + MSW
     ╱ Unit Tests        ╲    ~50% — Vitest / Jest (순수 함수, hooks)
    ────────────────────────
```

| 레벨 | 도구 | 용도 | 속도 |
|------|------|------|------|
| Unit | Vitest + @testing-library/react | 유틸 함수, Custom Hooks | 가장 빠름 |
| Component | @testing-library/react + MSW | Client/Server 컴포넌트 렌더링 | 빠름 |
| Integration | @testing-library/react + Server Actions | 페이지 단위, 폼 제출, 네비게이션 | 중간 |
| E2E | Playwright | 전체 사용자 시나리오 | 느림 |

---

## 1. 테스트 프레임워크 선택

### Decision Matrix: Vitest vs Jest

| 기준 | Vitest | Jest |
|------|--------|------|
| 속도 | 빠름 (Vite 기반 HMR, 병렬 실행) | 보통 (transform 오버헤드) |
| ESM 지원 | 네이티브 ESM | 설정 필요 (--experimental-vm-modules) |
| Next.js 공식 지원 | 커뮤니티 (next.js 문서에 포함) | 공식 (`next/jest`) |
| 설정 복잡도 | 중간 (vitest.config.ts) | 낮음 (next/jest가 대부분 처리) |
| Watch 모드 | 빠르고 스마트한 re-run | 안정적이나 느림 |
| 호환성 | Jest API 호환 (expect, describe, it) | 생태계 최대 |
| UI 모드 | `vitest --ui` (브라우저 기반) | 없음 (별도 도구 필요) |

### 선택 가이드

| 상황 | 추천 | 이유 |
|------|------|------|
| 새 프로젝트, 빠른 피드백 원함 | **Vitest** | ESM 네이티브, 빠른 실행 |
| 기존 Jest 기반 프로젝트 | **Jest** | 마이그레이션 비용 불필요 |
| Turbopack 사용 | **Vitest** | Vite 기반으로 호환성 좋음 |
| 안정성 최우선 | **Jest** | Next.js 공식 지원, 검증된 생태계 |

### Vitest 설정

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    include: ['**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        '.next/',
        '**/*.d.ts',
        '**/*.config.*',
        '**/types/**',
      ],
    },
    // CSS 모듈 처리
    css: {
      modules: {
        classNameStrategy: 'non-scoped',
      },
    },
  },
});
```

```typescript
// vitest.setup.ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

### Jest 설정 (next/jest)

```typescript
// jest.config.ts
import type { Config } from 'jest';
import nextJest from 'next/jest';

const createJestConfig = nextJest({
  dir: './', // next.config.js와 .env 파일 위치
});

const config: Config = {
  testEnvironment: 'jsdom',
  setupFilesAfterSetup: ['<rootDir>/jest.setup.ts'],
  moduleNameMapper: {
    // next/image 등 모듈 매핑은 next/jest가 자동 처리
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  testPathIgnorePatterns: ['<rootDir>/e2e/'], // E2E는 Playwright로
};

export default createJestConfig(config);
```

```typescript
// jest.setup.ts
import '@testing-library/jest-dom';
```

---

## 2. Unit Test 패턴

### 유틸리티 함수 테스트

순수 함수는 가장 단순한 테스트 대상. 의존성 없이 입력/출력만 검증.

```typescript
// lib/utils/format.ts
export function formatCurrency(amount: number, locale = 'ko-KR'): string {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: 'KRW',
  }).format(amount);
}

export function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .replace(/\s+/g, '-')
    .trim();
}
```

```typescript
// lib/utils/__tests__/format.test.ts
import { describe, it, expect } from 'vitest';
import { formatCurrency, slugify } from '../format';

describe('formatCurrency', () => {
  it('한국 원화 형식으로 변환한다', () => {
    expect(formatCurrency(10000)).toBe('₩10,000');
  });

  it('0원을 올바르게 표시한다', () => {
    expect(formatCurrency(0)).toBe('₩0');
  });

  it('음수 금액을 처리한다', () => {
    expect(formatCurrency(-5000)).toBe('-₩5,000');
  });
});

describe('slugify', () => {
  it('공백을 하이픈으로 변환한다', () => {
    expect(slugify('Hello World')).toBe('hello-world');
  });

  it('특수문자를 제거한다', () => {
    expect(slugify('Hello! @World#')).toBe('hello-world');
  });
});
```

### Custom Hook 테스트 — renderHook

```typescript
// hooks/use-debounce.ts
import { useState, useEffect } from 'react';

export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}
```

```typescript
// hooks/__tests__/use-debounce.test.ts
import { renderHook, act } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { useDebounce } from '../use-debounce';

describe('useDebounce', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('delay 후 값을 업데이트한다', () => {
    const { result, rerender } = renderHook(
      ({ value, delay }) => useDebounce(value, delay),
      { initialProps: { value: 'hello', delay: 500 } }
    );

    // 초기값
    expect(result.current).toBe('hello');

    // 값 변경
    rerender({ value: 'world', delay: 500 });

    // delay 전에는 이전 값 유지
    expect(result.current).toBe('hello');

    // delay 후 업데이트
    act(() => {
      vi.advanceTimersByTime(500);
    });

    expect(result.current).toBe('world');
  });
});
```

### next/navigation Mock 패턴

App Router에서 `useRouter`, `usePathname`, `useSearchParams`를 mock하는 패턴.

```typescript
// __tests__/helpers/next-navigation.ts
import { vi } from 'vitest';

// ✅ GOOD: 재사용 가능한 mock 헬퍼
export function mockNextNavigation(overrides: {
  pathname?: string;
  searchParams?: Record<string, string>;
  push?: ReturnType<typeof vi.fn>;
  replace?: ReturnType<typeof vi.fn>;
  back?: ReturnType<typeof vi.fn>;
} = {}) {
  const push = overrides.push ?? vi.fn();
  const replace = overrides.replace ?? vi.fn();
  const back = overrides.back ?? vi.fn();
  const pathname = overrides.pathname ?? '/';
  const searchParams = new URLSearchParams(overrides.searchParams);

  vi.mock('next/navigation', () => ({
    useRouter: () => ({ push, replace, back, refresh: vi.fn(), prefetch: vi.fn() }),
    usePathname: () => pathname,
    useSearchParams: () => searchParams,
    useParams: () => ({}),
    redirect: vi.fn(),
    notFound: vi.fn(),
  }));

  return { push, replace, back };
}
```

```typescript
// components/__tests__/search-bar.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { vi, describe, it, expect, beforeEach } from 'vitest';
import { SearchBar } from '../search-bar';

// 모듈 레벨에서 mock 선언
const pushMock = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: pushMock, replace: vi.fn(), back: vi.fn() }),
  usePathname: () => '/search',
  useSearchParams: () => new URLSearchParams(),
}));

describe('SearchBar', () => {
  beforeEach(() => {
    pushMock.mockClear();
  });

  it('검색어 입력 후 Enter로 검색 페이지로 이동한다', async () => {
    const user = userEvent.setup();

    render(<SearchBar />);

    const input = screen.getByRole('searchbox');
    await user.type(input, 'nextjs testing{Enter}');

    expect(pushMock).toHaveBeenCalledWith('/search?q=nextjs+testing');
  });
});
```

```typescript
// ❌ BAD: 테스트마다 mock을 인라인으로 반복 선언
describe('SearchBar', () => {
  it('검색한다', async () => {
    // 매 테스트마다 중복 mock — 유지보수 어려움
    vi.mock('next/navigation', () => ({
      useRouter: () => ({ push: vi.fn(), replace: vi.fn(), back: vi.fn() }),
      usePathname: () => '/search',
      useSearchParams: () => new URLSearchParams(),
    }));
    // ...
  });
});
```

**왜 이 패턴인지:** `vi.mock`은 모듈 레벨에서 hoisting되므로, 테스트 함수 내부에서 선언하면 예상치 못한 동작이 발생한다. 모듈 최상단에 한 번 선언하고, `beforeEach`에서 mock 함수를 초기화하는 것이 올바른 패턴.

### next/headers Mock 패턴

```typescript
// ✅ GOOD: cookies(), headers() mock
vi.mock('next/headers', () => ({
  cookies: () => ({
    get: (name: string) => {
      const cookieStore: Record<string, { name: string; value: string }> = {
        'session-token': { name: 'session-token', value: 'mock-token-123' },
        theme: { name: 'theme', value: 'dark' },
      };
      return cookieStore[name] ?? undefined;
    },
    getAll: () => [
      { name: 'session-token', value: 'mock-token-123' },
      { name: 'theme', value: 'dark' },
    ],
    has: (name: string) => ['session-token', 'theme'].includes(name),
    set: vi.fn(),
    delete: vi.fn(),
  }),
  headers: () =>
    new Headers({
      'content-type': 'application/json',
      authorization: 'Bearer mock-token',
      'x-forwarded-for': '127.0.0.1',
    }),
}));
```

```typescript
// lib/__tests__/auth.test.ts
import { describe, it, expect, vi } from 'vitest';
import { getCurrentUser } from '../auth';

vi.mock('next/headers', () => ({
  cookies: () => ({
    get: (name: string) =>
      name === 'session-token'
        ? { name: 'session-token', value: 'valid-token' }
        : undefined,
  }),
}));

describe('getCurrentUser', () => {
  it('세션 토큰이 있으면 사용자를 반환한다', async () => {
    const user = await getCurrentUser();
    expect(user).toBeDefined();
    expect(user?.id).toBe('user-1');
  });
});
```

---

## 3. Component Test 패턴

### Server Component 테스트 (async 컴포넌트)

Next.js 15의 Server Component는 async 함수. 테스트 시 await로 렌더링해야 한다.

```typescript
// app/posts/page.tsx (Server Component)
import { getPosts } from '@/lib/api/posts';

export default async function PostsPage() {
  const posts = await getPosts();

  return (
    <main>
      <h1>게시글 목록</h1>
      <ul>
        {posts.map((post) => (
          <li key={post.id}>
            <a href={`/posts/${post.id}`}>{post.title}</a>
          </li>
        ))}
      </ul>
    </main>
  );
}
```

```typescript
// app/posts/__tests__/page.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import PostsPage from '../page';

// ✅ GOOD: 데이터 페칭 함수를 mock
vi.mock('@/lib/api/posts', () => ({
  getPosts: vi.fn().mockResolvedValue([
    { id: 1, title: '첫 번째 게시글' },
    { id: 2, title: '두 번째 게시글' },
  ]),
}));

describe('PostsPage', () => {
  it('게시글 목록을 렌더링한다', async () => {
    // Server Component는 await로 실행 후 결과를 render
    const Component = await PostsPage();
    render(Component);

    expect(screen.getByText('게시글 목록')).toBeInTheDocument();
    expect(screen.getByText('첫 번째 게시글')).toBeInTheDocument();
    expect(screen.getByText('두 번째 게시글')).toBeInTheDocument();
  });

  it('게시글 링크가 올바른 경로를 가리킨다', async () => {
    const Component = await PostsPage();
    render(Component);

    const link = screen.getByText('첫 번째 게시글');
    expect(link.closest('a')).toHaveAttribute('href', '/posts/1');
  });
});
```

```typescript
// ❌ BAD: Server Component를 await 없이 렌더링
describe('PostsPage', () => {
  it('게시글을 보여준다', () => {
    // Promise가 반환되어 실제 컴포넌트가 렌더링되지 않음
    render(<PostsPage />);
  });
});
```

**왜 이 패턴인지:** Server Component는 async 함수이므로 JSX를 직접 렌더링할 수 없다. 함수를 await로 실행하여 반환된 JSX를 render에 전달해야 한다.

### Client Component 테스트 (user events, state)

```typescript
// components/counter.tsx
'use client';

import { useState } from 'react';

export function Counter({ initialCount = 0 }: { initialCount?: number }) {
  const [count, setCount] = useState(initialCount);

  return (
    <div>
      <p role="status">현재 카운트: {count}</p>
      <button onClick={() => setCount((c) => c + 1)}>증가</button>
      <button onClick={() => setCount((c) => c - 1)}>감소</button>
      <button onClick={() => setCount(0)}>초기화</button>
    </div>
  );
}
```

```typescript
// components/__tests__/counter.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect } from 'vitest';
import { Counter } from '../counter';

describe('Counter', () => {
  it('초기값을 표시한다', () => {
    render(<Counter initialCount={5} />);
    expect(screen.getByRole('status')).toHaveTextContent('현재 카운트: 5');
  });

  it('증가 버튼 클릭 시 카운트가 올라간다', async () => {
    const user = userEvent.setup();
    render(<Counter />);

    await user.click(screen.getByText('증가'));
    await user.click(screen.getByText('증가'));

    expect(screen.getByRole('status')).toHaveTextContent('현재 카운트: 2');
  });

  it('초기화 버튼으로 0으로 돌아간다', async () => {
    const user = userEvent.setup();
    render(<Counter initialCount={10} />);

    await user.click(screen.getByText('초기화'));

    expect(screen.getByRole('status')).toHaveTextContent('현재 카운트: 0');
  });
});
```

```typescript
// ❌ BAD: fireEvent 사용 — 실제 사용자 동작과 다름
import { fireEvent } from '@testing-library/react';

it('증가한다', () => {
  render(<Counter />);
  // fireEvent는 이벤트를 동기적으로 디스패치 — 실제 브라우저와 다름
  fireEvent.click(screen.getByText('증가'));
});

// ✅ GOOD: userEvent 사용 — 실제 사용자 상호작용 시뮬레이션
import userEvent from '@testing-library/user-event';

it('증가한다', async () => {
  const user = userEvent.setup();
  render(<Counter />);
  // 실제 사용자처럼 click 이벤트 전체 시퀀스 실행
  await user.click(screen.getByText('증가'));
});
```

**왜 이 패턴인지:** `userEvent`는 `pointerdown` -> `pointerup` -> `click` 등 실제 브라우저 이벤트 시퀀스를 시뮬레이션한다. `fireEvent`는 단일 이벤트만 디스패치하여 실제 사용자 행동을 정확히 재현하지 못한다.

### MSW (Mock Service Worker)를 이용한 API Mocking

```typescript
// __tests__/mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  http.get('/api/posts', () => {
    return HttpResponse.json([
      { id: 1, title: '첫 번째 게시글', content: '내용 1' },
      { id: 2, title: '두 번째 게시글', content: '내용 2' },
    ]);
  }),

  http.post('/api/posts', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json(
      { id: 3, ...body },
      { status: 201 }
    );
  }),

  http.get('/api/posts/:id', ({ params }) => {
    const { id } = params;
    if (id === '999') {
      return HttpResponse.json(
        { message: '게시글을 찾을 수 없습니다' },
        { status: 404 }
      );
    }
    return HttpResponse.json({ id: Number(id), title: `게시글 ${id}` });
  }),
];
```

```typescript
// __tests__/mocks/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

```typescript
// vitest.setup.ts (MSW 통합)
import { beforeAll, afterAll, afterEach } from 'vitest';
import { server } from './__tests__/mocks/server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

```typescript
// components/__tests__/post-list.test.tsx
import { render, screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { server } from '../../__tests__/mocks/server';
import { PostList } from '../post-list';

describe('PostList', () => {
  it('게시글 목록을 가져와서 렌더링한다', async () => {
    render(<PostList />);

    // 비동기 로딩 후 데이터가 표시될 때까지 대기
    await waitFor(() => {
      expect(screen.getByText('첫 번째 게시글')).toBeInTheDocument();
    });

    expect(screen.getByText('두 번째 게시글')).toBeInTheDocument();
  });

  it('API 에러 시 에러 메시지를 표시한다', async () => {
    // 특정 테스트에서만 핸들러 오버라이드
    server.use(
      http.get('/api/posts', () => {
        return HttpResponse.json(
          { message: '서버 에러' },
          { status: 500 }
        );
      })
    );

    render(<PostList />);

    await waitFor(() => {
      expect(screen.getByText(/에러가 발생했습니다/)).toBeInTheDocument();
    });
  });
});
```

```typescript
// ❌ BAD: fetch를 직접 mock — 구현 세부사항에 의존
vi.spyOn(global, 'fetch').mockResolvedValue(
  new Response(JSON.stringify([{ id: 1, title: 'Post' }]))
);

// ✅ GOOD: MSW로 네트워크 레벨에서 mock — 구현과 분리
server.use(
  http.get('/api/posts', () => {
    return HttpResponse.json([{ id: 1, title: 'Post' }]);
  })
);
```

**왜 이 패턴인지:** MSW는 네트워크 레벨에서 요청을 가로채므로 `fetch`, `axios` 등 HTTP 클라이언트 구현에 무관하다. `global.fetch`를 직접 mock하면 라이브러리 변경 시 테스트가 깨진다.

### Snapshot 테스트

```typescript
// ✅ GOOD: 의미있는 단위의 스냅샷 — 구조 변경 감지용
describe('Badge', () => {
  it('각 variant 별 렌더링이 올바르다', () => {
    const variants = ['default', 'success', 'warning', 'error'] as const;

    variants.forEach((variant) => {
      const { container } = render(
        <Badge variant={variant}>테스트</Badge>
      );
      expect(container.firstChild).toMatchSnapshot();
    });
  });
});
```

```typescript
// ❌ BAD: 페이지 전체를 스냅샷 — 작은 변경에도 계속 깨짐
describe('HomePage', () => {
  it('전체 페이지 스냅샷', () => {
    const { container } = render(<HomePage />);
    // 거대한 스냅샷 → 리뷰 불가능, 의미 없는 업데이트 반복
    expect(container).toMatchSnapshot();
  });
});
```

**왜 이 패턴인지:** 스냅샷 테스트는 작고 안정적인 UI 단위(Badge, Button, Icon 등)에만 사용한다. 큰 컴포넌트의 스냅샷은 변경이 잦아 "update snapshot" 습관으로 이어져 테스트의 의미가 사라진다.

### 접근성 테스트 (axe-core)

```typescript
// 설치: npm install -D @axe-core/react vitest-axe
// vitest.setup.ts에 추가
import 'vitest-axe/extend-expect';
```

```typescript
// components/__tests__/login-form.test.tsx
import { render } from '@testing-library/react';
import { axe } from 'vitest-axe';
import { describe, it, expect } from 'vitest';
import { LoginForm } from '../login-form';

describe('LoginForm 접근성', () => {
  it('접근성 위반이 없다', async () => {
    const { container } = render(<LoginForm />);
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });
});
```

```typescript
// ✅ GOOD: 접근 가능한 폼 컴포넌트
export function LoginForm() {
  return (
    <form aria-label="로그인 폼">
      <label htmlFor="email">이메일</label>
      <input id="email" type="email" required aria-describedby="email-help" />
      <span id="email-help">회사 이메일을 입력하세요</span>

      <label htmlFor="password">비밀번호</label>
      <input id="password" type="password" required />

      <button type="submit">로그인</button>
    </form>
  );
}
```

```typescript
// ❌ BAD: 접근성이 나쁜 폼
export function LoginForm() {
  return (
    <form>
      {/* label 없음, role 없음 */}
      <input placeholder="이메일" />
      <input placeholder="비밀번호" type="password" />
      <div onClick={handleSubmit}>로그인</div> {/* div를 버튼으로 사용 */}
    </form>
  );
}
```

---

## 4. Integration Test 패턴

### 페이지 레벨 컴포넌트 테스트 (with data)

```typescript
// app/dashboard/__tests__/page.test.tsx
import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import DashboardPage from '../page';

// 여러 데이터 소스를 mock
vi.mock('@/lib/api/analytics', () => ({
  getAnalytics: vi.fn().mockResolvedValue({
    totalUsers: 1500,
    activeUsers: 320,
    revenue: 5000000,
  }),
}));

vi.mock('@/lib/api/notifications', () => ({
  getNotifications: vi.fn().mockResolvedValue([
    { id: 1, message: '새 주문이 들어왔습니다', read: false },
  ]),
}));

describe('DashboardPage', () => {
  it('분석 데이터와 알림을 함께 렌더링한다', async () => {
    const Component = await DashboardPage();
    render(Component);

    expect(screen.getByText('1,500')).toBeInTheDocument(); // totalUsers
    expect(screen.getByText('320')).toBeInTheDocument();    // activeUsers
    expect(screen.getByText('새 주문이 들어왔습니다')).toBeInTheDocument();
  });
});
```

### Server Action 테스트

Next.js 15의 Server Action은 서버에서 실행되는 비동기 함수. 직접 호출하여 테스트.

```typescript
// app/actions/create-post.ts
'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { db } from '@/lib/db';

const CreatePostSchema = z.object({
  title: z.string().min(1, '제목은 필수입니다').max(100),
  content: z.string().min(10, '내용은 최소 10자 이상이어야 합니다'),
});

export async function createPost(formData: FormData) {
  const rawData = {
    title: formData.get('title'),
    content: formData.get('content'),
  };

  const validated = CreatePostSchema.safeParse(rawData);
  if (!validated.success) {
    return { errors: validated.error.flatten().fieldErrors };
  }

  const post = await db.post.create({
    data: validated.data,
  });

  revalidatePath('/posts');
  redirect(`/posts/${post.id}`);
}
```

```typescript
// app/actions/__tests__/create-post.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createPost } from '../create-post';

// Server-only 모듈 mock
vi.mock('next/cache', () => ({
  revalidatePath: vi.fn(),
}));

vi.mock('next/navigation', () => ({
  redirect: vi.fn(),
}));

vi.mock('@/lib/db', () => ({
  db: {
    post: {
      create: vi.fn(),
    },
  },
}));

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { db } from '@/lib/db';

describe('createPost', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('유효한 데이터로 게시글을 생성한다', async () => {
    vi.mocked(db.post.create).mockResolvedValue({
      id: 1,
      title: '테스트 제목',
      content: '테스트 내용입니다 10자 이상',
    });

    const formData = new FormData();
    formData.set('title', '테스트 제목');
    formData.set('content', '테스트 내용입니다 10자 이상');

    await createPost(formData);

    expect(db.post.create).toHaveBeenCalledWith({
      data: { title: '테스트 제목', content: '테스트 내용입니다 10자 이상' },
    });
    expect(revalidatePath).toHaveBeenCalledWith('/posts');
    expect(redirect).toHaveBeenCalledWith('/posts/1');
  });

  it('빈 제목이면 유효성 검사 에러를 반환한다', async () => {
    const formData = new FormData();
    formData.set('title', '');
    formData.set('content', '테스트 내용입니다 10자 이상');

    const result = await createPost(formData);

    expect(result?.errors?.title).toContain('제목은 필수입니다');
    expect(db.post.create).not.toHaveBeenCalled();
    expect(redirect).not.toHaveBeenCalled();
  });

  it('내용이 10자 미만이면 에러를 반환한다', async () => {
    const formData = new FormData();
    formData.set('title', '제목');
    formData.set('content', '짧은 글');

    const result = await createPost(formData);

    expect(result?.errors?.content).toBeDefined();
  });
});
```

### 폼 제출 테스트

```typescript
// components/post-form.tsx
'use client';

import { useActionState } from 'react';
import { createPost } from '@/app/actions/create-post';

export function PostForm() {
  const [state, formAction, isPending] = useActionState(createPost, null);

  return (
    <form action={formAction}>
      <div>
        <label htmlFor="title">제목</label>
        <input id="title" name="title" required />
        {state?.errors?.title && (
          <p role="alert" className="error">{state.errors.title[0]}</p>
        )}
      </div>

      <div>
        <label htmlFor="content">내용</label>
        <textarea id="content" name="content" required />
        {state?.errors?.content && (
          <p role="alert" className="error">{state.errors.content[0]}</p>
        )}
      </div>

      <button type="submit" disabled={isPending}>
        {isPending ? '저장 중...' : '게시글 작성'}
      </button>
    </form>
  );
}
```

```typescript
// components/__tests__/post-form.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { PostForm } from '../post-form';

// useActionState mock
vi.mock('react', async () => {
  const actual = await vi.importActual('react');
  return {
    ...actual,
    useActionState: vi.fn(),
  };
});

import { useActionState } from 'react';

describe('PostForm', () => {
  it('초기 상태에서 폼을 렌더링한다', () => {
    vi.mocked(useActionState).mockReturnValue([null, vi.fn(), false]);

    render(<PostForm />);

    expect(screen.getByLabelText('제목')).toBeInTheDocument();
    expect(screen.getByLabelText('내용')).toBeInTheDocument();
    expect(screen.getByText('게시글 작성')).toBeEnabled();
  });

  it('pending 상태에서 버튼이 비활성화된다', () => {
    vi.mocked(useActionState).mockReturnValue([null, vi.fn(), true]);

    render(<PostForm />);

    expect(screen.getByText('저장 중...')).toBeDisabled();
  });

  it('유효성 검사 에러를 표시한다', () => {
    vi.mocked(useActionState).mockReturnValue([
      { errors: { title: ['제목은 필수입니다'] } },
      vi.fn(),
      false,
    ]);

    render(<PostForm />);

    expect(screen.getByRole('alert')).toHaveTextContent('제목은 필수입니다');
  });
});
```

### 네비게이션 흐름 테스트

```typescript
// components/__tests__/navigation-flow.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { AppNav } from '../app-nav';

const pushMock = vi.fn();
let currentPathname = '/';

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: pushMock }),
  usePathname: () => currentPathname,
  useSearchParams: () => new URLSearchParams(),
}));

describe('AppNav', () => {
  beforeEach(() => {
    pushMock.mockClear();
    currentPathname = '/';
  });

  it('현재 경로에 해당하는 메뉴가 활성화된다', () => {
    currentPathname = '/dashboard';

    render(<AppNav />);

    const dashboardLink = screen.getByText('대시보드');
    expect(dashboardLink).toHaveAttribute('aria-current', 'page');
  });

  it('메뉴 클릭 시 해당 경로로 이동한다', async () => {
    const user = userEvent.setup();

    render(<AppNav />);

    await user.click(screen.getByText('설정'));

    expect(pushMock).toHaveBeenCalledWith('/settings');
  });

  it('인증되지 않은 사용자는 로그인 링크를 본다', () => {
    render(<AppNav isAuthenticated={false} />);

    expect(screen.getByText('로그인')).toBeInTheDocument();
    expect(screen.queryByText('대시보드')).not.toBeInTheDocument();
  });
});
```

---

## 5. E2E Test 패턴

### Playwright 설정

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html'],
    ['json', { outputFile: 'test-results/results.json' }],
  ],
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
    },
  ],

  // Next.js dev server 자동 시작
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
});
```

### Page Object Model 패턴

```typescript
// e2e/pages/login.page.ts
import { type Page, type Locator, expect } from '@playwright/test';

export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.getByLabel('이메일');
    this.passwordInput = page.getByLabel('비밀번호');
    this.submitButton = page.getByRole('button', { name: '로그인' });
    this.errorMessage = page.getByRole('alert');
  }

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }

  async expectError(message: string) {
    await expect(this.errorMessage).toContainText(message);
  }

  async expectRedirectToDashboard() {
    await expect(this.page).toHaveURL('/dashboard');
  }
}
```

```typescript
// e2e/pages/dashboard.page.ts
import { type Page, type Locator, expect } from '@playwright/test';

export class DashboardPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly userMenu: Locator;
  readonly logoutButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.getByRole('heading', { name: '대시보드' });
    this.userMenu = page.getByTestId('user-menu');
    this.logoutButton = page.getByRole('menuitem', { name: '로그아웃' });
  }

  async goto() {
    await this.page.goto('/dashboard');
  }

  async expectLoaded() {
    await expect(this.heading).toBeVisible();
  }

  async logout() {
    await this.userMenu.click();
    await this.logoutButton.click();
  }
}
```

```typescript
// e2e/auth.spec.ts
import { test, expect } from '@playwright/test';
import { LoginPage } from './pages/login.page';
import { DashboardPage } from './pages/dashboard.page';

test.describe('인증 흐름', () => {
  test('올바른 자격증명으로 로그인한다', async ({ page }) => {
    const loginPage = new LoginPage(page);
    const dashboardPage = new DashboardPage(page);

    await loginPage.goto();
    await loginPage.login('user@example.com', 'password123');

    await dashboardPage.expectLoaded();
    await expect(page).toHaveURL('/dashboard');
  });

  test('잘못된 비밀번호로 에러를 표시한다', async ({ page }) => {
    const loginPage = new LoginPage(page);

    await loginPage.goto();
    await loginPage.login('user@example.com', 'wrong-password');

    await loginPage.expectError('이메일 또는 비밀번호가 올바르지 않습니다');
  });

  test('로그아웃 후 로그인 페이지로 리다이렉트한다', async ({ page }) => {
    const loginPage = new LoginPage(page);
    const dashboardPage = new DashboardPage(page);

    // 로그인
    await loginPage.goto();
    await loginPage.login('user@example.com', 'password123');
    await dashboardPage.expectLoaded();

    // 로그아웃
    await dashboardPage.logout();

    await expect(page).toHaveURL('/login');
  });
});
```

```typescript
// ❌ BAD: Page Object 없이 직접 locator 사용 — 중복, 유지보수 어려움
test('로그인', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('이메일').fill('user@example.com');
  await page.getByLabel('비밀번호').fill('password123');
  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL('/dashboard');
});

test('로그인 실패', async ({ page }) => {
  await page.goto('/login');
  // 위와 동일한 locator 반복 — UI 변경 시 모든 테스트 수정 필요
  await page.getByLabel('이메일').fill('user@example.com');
  await page.getByLabel('비밀번호').fill('wrong');
  await page.getByRole('button', { name: '로그인' }).click();
});
```

**왜 이 패턴인지:** Page Object Model은 UI 요소와 상호작용을 한 곳에서 관리한다. UI가 변경되면 Page Object만 수정하면 되므로, 테스트 코드의 유지보수 비용이 크게 줄어든다.

### Visual Regression 테스트

```typescript
// e2e/visual.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Visual Regression', () => {
  test('랜딩 페이지 스냅샷', async ({ page }) => {
    await page.goto('/');
    // 동적 콘텐츠 로딩 대기
    await page.waitForLoadState('networkidle');

    // 날짜/시간 등 동적 요소 마스킹
    await page.evaluate(() => {
      document.querySelectorAll('[data-testid="timestamp"]').forEach((el) => {
        el.textContent = '2024-01-01';
      });
    });

    await expect(page).toHaveScreenshot('landing-page.png', {
      maxDiffPixelRatio: 0.01, // 1% 이하 차이 허용
      fullPage: true,
    });
  });

  test('다크 모드 전환', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: '테마 전환' }).click();

    await expect(page).toHaveScreenshot('landing-dark.png', {
      maxDiffPixelRatio: 0.01,
    });
  });

  // 컴포넌트 단위 스크린샷
  test('카드 컴포넌트 스냅샷', async ({ page }) => {
    await page.goto('/storybook/card'); // 또는 테스트 전용 페이지

    const card = page.getByTestId('product-card');
    await expect(card).toHaveScreenshot('product-card.png');
  });
});
```

### 인증 흐름 테스트 (storageState 재활용)

```typescript
// e2e/auth.setup.ts
import { test as setup, expect } from '@playwright/test';
import path from 'path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('인증 상태 저장', async ({ page }) => {
  // 로그인 수행
  await page.goto('/login');
  await page.getByLabel('이메일').fill('test@example.com');
  await page.getByLabel('비밀번호').fill('password123');
  await page.getByRole('button', { name: '로그인' }).click();

  // 로그인 성공 확인
  await expect(page).toHaveURL('/dashboard');

  // 인증 상태 저장 — 쿠키, localStorage 등
  await page.context().storageState({ path: authFile });
});
```

```typescript
// playwright.config.ts (인증 프로젝트 연결)
export default defineConfig({
  projects: [
    // 인증 setup 프로젝트
    { name: 'setup', testMatch: /.*\.setup\.ts/ },

    // 인증이 필요한 테스트들
    {
      name: 'authenticated',
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'e2e/.auth/user.json',
      },
      dependencies: ['setup'],
    },

    // 인증 없이 실행하는 테스트들
    {
      name: 'unauthenticated',
      use: { ...devices['Desktop Chrome'] },
      testMatch: /.*\.unauth\.spec\.ts/,
    },
  ],
});
```

```typescript
// e2e/dashboard.spec.ts (인증된 상태에서 실행)
import { test, expect } from '@playwright/test';

// storageState가 자동 적용됨 — 이미 로그인된 상태
test('대시보드에 사용자 이름이 표시된다', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByText('안녕하세요, Test User')).toBeVisible();
});
```

**왜 이 패턴인지:** 매 테스트마다 로그인을 반복하면 느리고 불안정하다. `storageState`로 인증 상태를 한 번 저장하고 재활용하면 테스트 속도가 크게 향상된다.

---

## 6. 테스트 유틸리티

### Custom Render with Providers

여러 Provider를 감싸야 하는 경우 커스텀 render 함수를 만든다.

```typescript
// __tests__/utils/test-utils.tsx
import { ReactElement } from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ThemeProvider } from '@/components/theme-provider';

// 테스트 전용 QueryClient — 재시도 비활성화, 에러 로그 숨김
function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        gcTime: 0,
      },
      mutations: {
        retry: false,
      },
    },
    logger: {
      log: console.log,
      warn: console.warn,
      error: () => {}, // 테스트에서 에러 로그 숨김
    },
  });
}

interface CustomRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  queryClient?: QueryClient;
  theme?: 'light' | 'dark';
}

export function renderWithProviders(
  ui: ReactElement,
  {
    queryClient = createTestQueryClient(),
    theme = 'light',
    ...renderOptions
  }: CustomRenderOptions = {}
) {
  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <ThemeProvider defaultTheme={theme}>
          {children}
        </ThemeProvider>
      </QueryClientProvider>
    );
  }

  return {
    ...render(ui, { wrapper: Wrapper, ...renderOptions }),
    queryClient,
  };
}

// re-export everything
export * from '@testing-library/react';
export { default as userEvent } from '@testing-library/user-event';
```

```typescript
// 사용법
import { renderWithProviders, screen, userEvent } from '@/__tests__/utils/test-utils';
import { UserProfile } from '../user-profile';

describe('UserProfile', () => {
  it('사용자 정보를 표시한다', async () => {
    renderWithProviders(<UserProfile userId="1" />);

    await screen.findByText('홍길동');
  });

  it('다크 모드에서 올바르게 렌더링된다', () => {
    renderWithProviders(<UserProfile userId="1" />, { theme: 'dark' });
    // ...
  });
});
```

```typescript
// ❌ BAD: 테스트마다 Provider를 직접 감싸기 — 중복, 불일치 위험
describe('UserProfile', () => {
  it('사용자 정보', () => {
    const queryClient = new QueryClient(); // 재시도 옵션 빠짐
    render(
      <QueryClientProvider client={queryClient}>
        <ThemeProvider>
          <UserProfile userId="1" />
        </ThemeProvider>
      </QueryClientProvider>
    );
  });
});
```

**왜 이 패턴인지:** Provider 구성이 테스트마다 다르면 일관성이 깨지고 디버깅이 어렵다. 커스텀 render에서 한 번 정의하고, 필요 시 옵션으로 오버라이드하는 것이 유지보수에 유리하다.

### Test Data Factory

```typescript
// __tests__/factories/user.ts
import { faker } from '@faker-js/faker/locale/ko';

interface User {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'user' | 'editor';
  createdAt: Date;
  avatar?: string;
}

export function createUser(overrides: Partial<User> = {}): User {
  return {
    id: faker.string.uuid(),
    name: faker.person.fullName(),
    email: faker.internet.email(),
    role: 'user',
    createdAt: faker.date.past(),
    avatar: faker.image.avatar(),
    ...overrides,
  };
}

export function createUsers(count: number, overrides: Partial<User> = {}): User[] {
  return Array.from({ length: count }, () => createUser(overrides));
}
```

```typescript
// __tests__/factories/post.ts
import { faker } from '@faker-js/faker/locale/ko';
import { createUser } from './user';

interface Post {
  id: number;
  title: string;
  content: string;
  author: { id: string; name: string };
  tags: string[];
  published: boolean;
  createdAt: Date;
}

export function createPost(overrides: Partial<Post> = {}): Post {
  const author = createUser();
  return {
    id: faker.number.int({ min: 1, max: 10000 }),
    title: faker.lorem.sentence(),
    content: faker.lorem.paragraphs(3),
    author: { id: author.id, name: author.name },
    tags: faker.helpers.arrayElements(['react', 'nextjs', 'typescript', 'testing'], 2),
    published: true,
    createdAt: faker.date.past(),
    ...overrides,
  };
}

// 특수 상태 factory
export function createDraftPost(overrides: Partial<Post> = {}): Post {
  return createPost({ published: false, ...overrides });
}
```

```typescript
// 사용법
import { createUser, createUsers } from '../factories/user';
import { createPost, createDraftPost } from '../factories/post';

describe('PostList', () => {
  it('게시글 목록을 렌더링한다', () => {
    const posts = [
      createPost({ title: '첫 번째 글' }),
      createPost({ title: '두 번째 글' }),
      createDraftPost(), // 비공개 글
    ];

    render(<PostList posts={posts} />);

    expect(screen.getByText('첫 번째 글')).toBeInTheDocument();
  });
});
```

```typescript
// ❌ BAD: 테스트마다 객체를 직접 구성 — 필수 필드 누락 위험, 장황
it('게시글을 보여준다', () => {
  const posts = [
    {
      id: 1,
      title: 'test',
      content: 'content',
      author: { id: 'a1', name: 'Author' },
      tags: [],
      published: true,
      createdAt: new Date(),
    },
    // 모든 필드를 반복 작성...
  ];
});
```

**왜 이 패턴인지:** Factory는 유효한 기본값을 제공하면서 필요한 부분만 오버라이드할 수 있다. 인터페이스가 변경되면 factory만 수정하면 되므로 테스트 전체의 유지보수 비용이 줄어든다.

### Common Assertions & Matchers

```typescript
// ✅ 자주 사용하는 @testing-library 쿼리 우선순위
// 1순위: 접근성 기반 (사용자가 보는 것과 동일)
screen.getByRole('button', { name: '저장' });
screen.getByLabelText('이메일');
screen.getByPlaceholderText('검색어 입력');
screen.getByText('게시글 목록');

// 2순위: 의미론적 쿼리
screen.getByAltText('프로필 사진');
screen.getByTitle('닫기');
screen.getByDisplayValue('현재 값');

// 3순위: test ID (다른 방법이 없을 때만)
screen.getByTestId('complex-chart');
```

```typescript
// ✅ 비동기 쿼리 — 데이터 로딩 후 요소가 나타나는 경우
await screen.findByText('로딩 완료');       // getBy + waitFor
await screen.findByRole('table');           // 테이블이 렌더링될 때까지 대기

// ✅ 요소가 없음을 확인
expect(screen.queryByText('에러')).not.toBeInTheDocument();
expect(screen.queryByRole('alert')).toBeNull();

// ✅ waitFor — 상태 변경 대기
await waitFor(() => {
  expect(screen.getByText('저장 완료')).toBeInTheDocument();
});

// ✅ waitForElementToBeRemoved — 요소가 사라질 때까지 대기
await waitForElementToBeRemoved(() => screen.getByText('로딩 중...'));
```

```typescript
// ❌ BAD: 구현 세부사항에 의존하는 쿼리
screen.getByClassName('btn-primary');       // CSS 클래스에 의존
document.querySelector('#submit-btn');       // DOM 직접 접근
container.firstChild;                        // 구조에 의존

// ❌ BAD: 불필요한 waitFor 래핑
await waitFor(() => {
  // getBy는 이미 동기적으로 찾으므로 waitFor 불필요
  expect(screen.getByText('정적 텍스트')).toBeInTheDocument();
});

// ✅ GOOD: 동기적 요소는 바로 assert
expect(screen.getByText('정적 텍스트')).toBeInTheDocument();
```

### 커스텀 매처 (Vitest)

```typescript
// __tests__/utils/custom-matchers.ts
import { expect } from 'vitest';

expect.extend({
  toBeWithinRange(received: number, floor: number, ceiling: number) {
    const pass = received >= floor && received <= ceiling;
    return {
      pass,
      message: () =>
        `expected ${received} to be within range ${floor} - ${ceiling}`,
    };
  },

  toHaveBeenCalledWithMatch(received: any, ...matchers: any[]) {
    const calls = received.mock.calls;
    const pass = calls.some((call: any[]) =>
      matchers.every((matcher, i) => {
        if (typeof matcher === 'function') return matcher(call[i]);
        return JSON.stringify(call[i]) === JSON.stringify(matcher);
      })
    );
    return {
      pass,
      message: () =>
        `expected mock to have been called with matching arguments`,
    };
  },
});

// 타입 선언
declare module 'vitest' {
  interface Assertion<T = any> {
    toBeWithinRange(floor: number, ceiling: number): T;
  }
}
```

---

## 공통 실수와 해결

### 1. act() 경고 해결

```typescript
// ❌ BAD: state 업데이트가 act()로 감싸지 않음
it('카운트 업데이트', () => {
  render(<Counter />);
  // Warning: An update to Counter inside a test was not wrapped in act(...)
  fireEvent.click(screen.getByText('증가'));
});

// ✅ GOOD: userEvent는 내부적으로 act() 처리
it('카운트 업데이트', async () => {
  const user = userEvent.setup();
  render(<Counter />);
  await user.click(screen.getByText('증가'));
  // 경고 없음
});
```

### 2. 비동기 컴포넌트 테스트의 올바른 대기

```typescript
// ❌ BAD: 임의의 timeout으로 대기
it('데이터 로딩', async () => {
  render(<DataComponent />);
  await new Promise((resolve) => setTimeout(resolve, 1000)); // 불안정
  expect(screen.getByText('데이터')).toBeInTheDocument();
});

// ✅ GOOD: findBy 또는 waitFor로 대기
it('데이터 로딩', async () => {
  render(<DataComponent />);
  expect(await screen.findByText('데이터')).toBeInTheDocument();
});
```

### 3. cleanup 누락

```typescript
// ❌ BAD: Vitest에서 cleanup 미설정 — 이전 테스트 DOM이 남음
// vitest.setup.ts
import '@testing-library/jest-dom/vitest';
// cleanup 없음!

// ✅ GOOD: afterEach에서 cleanup 실행
// vitest.setup.ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

**참고:** Jest + @testing-library/react는 기본적으로 cleanup이 자동 실행된다. Vitest에서는 명시적으로 설정해야 한다.

### 4. 테스트 격리 — Mock 초기화

```typescript
// ❌ BAD: mock이 테스트 간 공유됨
const fetchMock = vi.fn();

describe('API 호출', () => {
  it('첫 번째 테스트', async () => {
    fetchMock.mockResolvedValue({ data: 'a' });
    // ...
  });

  it('두 번째 테스트', async () => {
    // fetchMock에 이전 테스트의 설정이 남아있음!
  });
});

// ✅ GOOD: beforeEach에서 초기화
describe('API 호출', () => {
  beforeEach(() => {
    vi.clearAllMocks(); // 모든 mock의 호출 기록과 구현 초기화
  });

  // 또는 특정 mock만:
  // vi.resetAllMocks(); — 구현까지 완전 초기화
  // vi.restoreAllMocks(); — 원래 구현으로 복원
});
```

### 5. 환경 변수 처리

```typescript
// ❌ BAD: process.env를 직접 조작하고 복원 안 함
it('프로덕션 모드', () => {
  process.env.NODE_ENV = 'production';
  // 테스트 후 원래 값으로 복원 안 함 — 다른 테스트에 영향
});

// ✅ GOOD: vi.stubEnv 사용 (Vitest)
it('프로덕션 모드', () => {
  vi.stubEnv('NODE_ENV', 'production');
  // afterEach에서 vi.unstubAllEnvs() 또는 자동 복원

  render(<AppBanner />);
  expect(screen.queryByText('개발 모드')).not.toBeInTheDocument();
});
```
