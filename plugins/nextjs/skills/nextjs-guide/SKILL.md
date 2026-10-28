---
name: nextjs-guide
description: |
  Next.js 스페셜리스트 트리아지 — 하이드레이션 불일치, 'use client' 번들 비대, RSC 직렬화 노출, Server Action 인증, 'use cache' 캐싱, proxy.ts(middleware), 워터폴, 이미지·폰트 CLS. 버전은 package.json·동봉 문서로 확인.
  Next.js specialist triage: hydration, client bundle, RSC serialization, Server Action security, caching, proxy.ts, waterfalls, CLS, self-hosting.
  Use when: reviewing or debugging Next.js App Router code or upgrading to Next 16.
---

# Next.js 스페셜리스트 트리아지

강한 시니어도 놓치기 쉬운 Next.js(App Router) 함정을 **증상 → 레퍼런스 항목**으로 찾는 인덱스다.
일반 튜토리얼(라우팅 파일 규칙, 컴포넌트 작성법)은 담지 않는다 — 그건 모델과 공식 문서가 이미 안다.

## 0. 먼저 버전과 동봉 문서를 확인한다 (단정 금지)

Next.js 는 메이저마다 규칙이 바뀌고(15: async request API, 16: proxy.ts·Cache Components·Turbopack 기본),
학습 데이터와 어긋나기 쉽다. 코드를 쓰거나 판정하기 전에:

1. **버전**: 앱의 `package.json` 의 `next`/`react` 버전(모노레포면 `apps/*/package.json`). 실제 설치본은 `node_modules/next/package.json`.
   그 버전이 보안 공지의 패치 하한 이상인지도 확인한다(GitHub Security Advisories·`npm audit` — RSC-ACT-10).
2. **에이전트 규칙 파일**: 앱 디렉터리의 `AGENTS.md`/`CLAUDE.md` 에 `nextjs-agent-rules` 블록이 있으면 그 지시를 따른다(`next dev` 가 생성·재생성).
3. **동봉 문서(16.2+)**: `node_modules/next/dist/docs/` — `01-app/02-guides/upgrading/version-16.md`, `01-app/03-api-reference/…`.
   이 문서가 본 스킬의 레퍼런스보다 우선한다. 없으면(16.1 이하) https://nextjs.org/docs 의 해당 버전 문서, 또는 Context7(설치 시 `backend-shared:context7-docs-guide` 규약).
4. **모델 판별**: `next.config.*` 의 `cacheComponents: true` 여부(캐싱 규칙이 완전히 다름), 요청 가로채기 파일이 `proxy.ts` 인지 `middleware.ts` 인지, `--webpack` 사용 여부.
5. **배포 형태**: Vercel 인지 셀프호스팅(Docker/k8s, 레플리카 수, 앞단 nginx/Ingress)인지 — 운영 함정(NX-OPS, RSC-ACT-07/08) 적용 여부가 갈린다.
6. **프로젝트 컨벤션**: 기존 코드의 데이터 접근 계층(DAL), 상태·폼 라이브러리, 테스트 러너는 그대로 따른다. 이 스킬은 라이브러리를 추천하지 않는다.

레퍼런스 항목의 "적용" 줄이 현재 버전·모델과 맞지 않으면 그 항목은 건너뛴다.

## 1. 증상 → 레퍼런스

| 증상 / 키워드 | 먼저 볼 항목 | 파일 |
|---|---|---|
| Hydration failed, 날짜·시간 깜빡임, 운영에서만 불일치 | WEB-HYD-01, 03 | `references/web-vitals.md` |
| 번들 비대, "이 라이브러리가 왜 클라이언트에?", `'use client'` 가 페이지 상단, `ssr: false` | RSC-BND-01, 06 / WEB-BUN-01 | `references/rsc-boundary.md`, `references/web-vitals.md` |
| HTML/페이로드가 큼, `__next_f` 스크립트 과대, 민감 필드가 DevTools 에 보임 | RSC-BND-02, 04 | `references/rsc-boundary.md` |
| 브라우저에서만 API 키가 빈 값, 서버 모듈이 클라이언트에 import | RSC-BND-03 | `references/rsc-boundary.md` |
| Date 가 문자열로 옴, "cannot be passed to Client Components" | RSC-BND-05 | `references/rsc-boundary.md` |
| Server Action 권한·IDOR, 페이지 인증만 있음, hidden input/bind 로 id 전달 | RSC-ACT-01, 02, 03 | `references/server-actions-security.md` |
| next/react 보안 패치 수준, CVE·advisory, React2Shell | RSC-ACT-10 | `references/server-actions-security.md` |
| 액션 병렬 호출이 느림, redirect 가 안 됨, 업로드 실패, 운영에서만 액션 거부 | RSC-ACT-04~07 | `references/server-actions-security.md` |
| "Failed to find Server Action", 배포 직후 ChunkLoadError | RSC-ACT-08 / NX-OPS-03 | `references/server-actions-security.md`, `references/self-hosting-ops.md` |
| 저장했는데 옛 값, 캐시가 안 맞음, 파드마다 다른 데이터 | NX-CACHE-05/06 / NX-V16-04 / NX-OPS-02 | `references/caching-rendering.md`, `references/version-16-changes.md`, `references/self-hosting-ops.md` |
| `'use cache'` 에러(`next-request-in-use-cache`), 히트율 0, Date.now build 에러 | NX-CACHE-03, 04, 08 | `references/caching-rendering.md` |
| cacheComponents 전환 후 빌드 에러 폭증, 뒤로가기 시 UI 상태가 남음 | NX-CACHE-09, 11 | `references/caching-rendering.md` |
| 같은 쿼리가 요청당 여러 번, fetch 가 캐시될 거라 가정 | NX-CACHE-01, 02 | `references/caching-rendering.md` |
| TTFB 가 가장 느린 쿼리에 묶임, 링크 클릭 후 무반응 | NX-DATA-02, 03 / NX-CACHE-10, 12 | `references/data-waterfall.md`, `references/caching-rendering.md` |
| 운영에서 스트리밍 안 됨(로컬은 됨) | NX-DATA-04 | `references/data-waterfall.md` |
| 페이지 대부분이 SSR HTML 에 없음, `missing-suspense-with-csr-bailout`, `blocking-prerender-client-hook` | NX-DATA-05 | `references/data-waterfall.md` |
| middleware.ts, proxy 에서 DB 인증, 15→16 업그레이드 | NX-V16-01~12 | `references/version-16-changes.md` |
| 이미지 과대 다운로드, LCP 이미지 늦음, CLS | WEB-IMG-01~03 | `references/web-vitals.md` |
| 한글 웹폰트 CLS·LCP 지연, 폰트 중복 다운로드 | WEB-FONT-01~03 | `references/web-vitals.md` |
| 이미지 최적화로 파드 메모리↑, 환경별 NEXT_PUBLIC 값 오염, 종료 시 유실 | NX-OPS-01, 04 / WEB-IMG-04 | `references/self-hosting-ops.md`, `references/web-vitals.md` |

## 2. 항목 인덱스 (ID · 한 줄)

각 항목은 `적용 / 신호 / 메커니즘 / 처방 / 반례 / 검증 / 근거` 형식이다. 프로젝트 규칙(workflow:project-rules 등)으로
선별할 때는 "적용" 조건이 프로젝트 버전·배포 형태와 맞는 ID 만 고른다. ID 는 안정 식별자라 항목을 병합·삭제해도 재번호하지 않는다(빈 번호 = 다른 항목에 흡수).

**version-16-changes.md** — NX-V16-01 proxy.ts 개명·Node 런타임 고정 · 02 proxy 는 낙관적 체크만 · 03 동기 Request API 제거 ·
04 revalidateTag 2인자/updateTag/refresh · 05 Turbopack 기본과 webpack 설정 충돌 · 06 next lint 제거 · 07 next/image 기본값 4종 ·
08 parallel route default.js 필수 · 09 runtime config 제거 · 10 scroll-behavior 미덮어쓰기 · 11 First Load JS 지표 제거 · 12 dev config 1회 로드

**caching-rendering.md** — NX-CACHE-01 15+ 기본 비캐시 · 02 DB 호출은 메모이제이션 없음 → React.cache · 03 캐시 스코프 runtime API 가 start 에서만 실패 ·
04 캐시 키에 클로저 캡처 포함 · 05 인스턴스별 in-memory LRU 50MB · 06 cacheLife 기본 프로필·클라 최소 30s · 07 캐시 함수별 React.cache 격리 ·
08 프리렌더 동기 IO build 에러 · 09 cacheComponents 전환 시 에러 목록 · 10 Suspense 는 동적화가 아님 · 11 Activity 상태 보존 ·
12 동적 페이지 prefetch 조건 · 13 after() 는 동적화 안 함

**data-waterfall.md** — NX-DATA-02 트리 깊이 워터폴과 preload(01 흡수) · 03 런타임 데이터 layout 의 블로킹 · 04 앞단 버퍼링 · 05 useSearchParams CSR 강등

**rsc-boundary.md** — RSC-BND-01 모듈 그래프 경계 · 02 props 이중 전송 · 03 env 오염(빈 문자열) · 04 DB 행 통째 전달 노출 ·
05 직렬화 비대칭 · 06 배럴 파일 · 08 use(promise) 생성 위치 (07 ssr:false 는 01 에 흡수)

**server-actions-security.md** — RSC-ACT-01 export = 공개 엔드포인트 · 02 왕복 값 불신 · 03 반환값 노출 · 04 순차 디스패치 ·
05 redirect throw · 06 1MB 상한 · 07 Origin/Host 검사 · 08 암호화 키·액션 ID 스큐 · 09 렌더 중 변이 금지 · 10 RSC 보안 패치 하한

**web-vitals.md** — WEB-IMG-01 sizes 누락 · 02 LCP 우선순위(fetchPriority 단독은 lazy 유지) · 03 fill 부모 크기 · 04 셀프호스팅 최적화 부하 ·
WEB-FONT-01 swap·폴백 보정과 CJK · 02 폰트 인스턴스 중복 · 03 CJK preload — local 은 경쟁, google 은 한글 미preload ·
WEB-HYD-01 로캘·TZ · 03 typeof window/localStorage(02 HTML 중첩 흡수) · WEB-BUN-01 번들 분석 도구 · 02 React Compiler

**self-hosting-ops.md** — NX-OPS-01 NEXT_PUBLIC 빌드 동결 · 02 다중 인스턴스 태그 무효화 · 03 버전 스큐 · 04 SIGTERM 드레인

## 3. 리뷰 시 최소 점검 순서

1. 0절로 버전·모델·배포 형태 확정 → 해당 없는 항목 제외
2. `grep -rn "'use server'"` → 모든 export 에 인증·인가 재검증이 있는가(RSC-ACT-01)
3. `grep -rn "'use client'"` → 경계가 leaf 에 있는가, 서버 데이터가 통째로 넘어가는가(RSC-BND-01/02/04)
4. 캐시 의도가 코드에 명시돼 있는가(`'use cache'`+`cacheLife` 또는 fetch 옵션) / 변경 경로의 무효화 API 가 맞는가(NX-V16-04)
5. 성능 주장에는 측정 근거(`next build && next start` 기준 Lighthouse·analyze 산출물·서버 span)를 붙인다 — dev 서버 수치 금지

## 4. 인접 도구와의 경계

- 시각 디자인·스타일링 품질은 공식 `frontend-design` 스킬 소관(설치 시 조합, 미설치 시 생략).
- 코드 생성 절차는 `/nextjs-gen`·`/nextjs-page-design` 커맨드와 `nextjs-developer` 에이전트가 담당하고, 이 스킬은 판정 근거를 제공한다.
- 백엔드 API·DB 설계는 백엔드 스택 플러그인 소관.
