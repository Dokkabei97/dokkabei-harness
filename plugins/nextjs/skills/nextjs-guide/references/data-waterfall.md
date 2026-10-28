# 데이터 페칭 워터폴·스트리밍 함정 (NX-DATA)

> 확인 문서: `node_modules/next/dist/docs/01-app/01-getting-started/06-fetching-data.md`(Sequential/Parallel/Preloading),
> `02-guides/streaming.md`. 공개본: https://nextjs.org/docs/app/getting-started/fetching-data

### NX-DATA-02 · 트리 깊이 워터폴 — 부모 await 뒤에 렌더되는 자식의 요청은 늦게 시작한다
- 적용: async 부모 → async 자식 구조(부모 데이터에 의존하지 않는 자식 포함)
- 신호: 자식이 부모 결과와 무관한 데이터를 가져오는데 타임라인상 부모 완료 후 시작
- 메커니즘: 자식 컴포넌트 함수는 부모가 반환한 뒤에야 호출된다. 같은 라우트의 layout 과 page 는 이미 병렬 렌더되므로, 워터폴은 주로 한 컴포넌트 안의 연속 await 와 부모→자식 깊이에서 생긴다
- 처방: preload 패턴 — 부모의 블로킹 작업 전에 `void getItem(id)` 로 요청 시작, 자식은 같은 함수를 호출해 재사용. 함수는 반드시 중복 제거(React.cache 또는 신모델의 private cache function)되어야 함. preload 함수는 소비 컴포넌트 옆에 둔다
- 반례: 자식이 부모 데이터(id 등)에 진짜 의존하면 순차가 정답 — Suspense 로 부모 부분을 먼저 보여준다
- 검증: span 시작 시각 비교
- 근거: `06-fetching-data.md#preloading-data`, `#sequential-data-fetching`, `#parallel-data-fetching`

### NX-DATA-03 · 런타임 데이터를 읽는 layout 은 같은 세그먼트의 loading.js 로 폴백하지 않는다 — 내비게이션 전체 블로킹
- 적용: 이전 모델(신모델은 build 에러로 강제)
- 신호: `layout.tsx` 에서 `cookies()`/`headers()`/비캐시 fetch, 링크 클릭 후 아무 반응 없이 대기
- 메커니즘: `loading.js` 는 layout **안쪽**에서 page 를 감싸는 Suspense 다. layout 자체의 대기는 그 경계 밖이라 폴백이 없다
- 처방: 런타임 데이터 읽기를 layout 에서 빼서 하위 컴포넌트 + 개별 `<Suspense>` 로 이동, 또는 상위 세그먼트에 loading 경계
- 반례: 상위 layout 이 가볍고 캐시된 데이터만 읽으면 무관
- 검증: 느린 네트워크 스로틀로 클릭 반응 확인
- 근거: `06-fetching-data.md`(loading.js 와 layout 블로킹 설명)

### NX-DATA-04 · 스트리밍은 앞단 버퍼링 하나로 무력화된다
- 적용: 셀프호스팅(nginx, Ingress, ALB 등) 뒤의 App Router
- 신호: 로컬 `next start` 에선 스켈레톤→콘텐츠 순차 표시, 운영에선 전체가 한 번에 늦게 도착; TTFB ≈ 전체 렌더 시간
- 메커니즘: 프록시/로드밸런서가 chunked 응답을 버퍼링하면 셸과 동적 부분이 렌더 완료 후 함께 전달. PPR(정적 셸)의 TTFB 이점도 사라진다
- 처방: nginx 는 `X-Accel-Buffering: no` 헤더(Next `headers()` 로 부여) 또는 `proxy_buffering off`; 경로상 모든 프록시·LB 가 청크 전송을 패스스루하도록 점검. 압축 계층의 버퍼링도 확인
- 반례: 봇/크롤러에는 Next 가 의도적으로 완성 페이지를 보낸다 — 크롤러 UA 로 테스트하면 버퍼링처럼 보인다
- 검증: `curl -N --raw` 로 청크 도착 시각 관찰(브라우저 UA)
- 근거: `02-guides/self-hosting.md#streaming-and-suspense`, `06-fetching-data.md`(Bots and crawlers)

### NX-DATA-05 · useSearchParams 를 Suspense 없이 쓰면 가장 가까운 경계까지 클라이언트 렌더로 강등
- 적용: 프리렌더되는 라우트의 Client Component. 신호가 모델별로 다르다(0절 4: `cacheComponents` 여부)
- 신호: 필터/페이지네이션 컴포넌트가 `useSearchParams()` 를 쓰고 Suspense 경계 없음. **이전 모델**: 정적 페이지면 `next build` 가 실패(`missing-suspense-with-csr-bailout`, 경고 아님) — 상위에 넓은 Suspense/`loading.js` 가 있으면 빌드는 통과하지만 그 경계 전체가 SSR HTML 에서 빠짐(빈 셸). `next dev` 는 온디맨드 렌더라 재현 안 됨. **Cache Components(16.3+)**: instant-navigation 검증 에러 `blocking-prerender-client-hook`(`usePathname`/`useParams` 등도 동적 params 라우트에서 해당)
- 메커니즘: 검색 파라미터는 프리렌더 시점에 알 수 없어, 그 컴포넌트에서 가장 가까운 Suspense 경계까지의 클라이언트 트리를 CSR 로 넘긴다. 경계가 없으면 범위가 커진다
- 처방: `useSearchParams` 를 쓰는 leaf 를 `<Suspense fallback>` 으로 감싸 나머지를 프리렌더 유지. 서버에서 필요하면 page 의 `searchParams` prop 사용(라우트는 동적이 됨)
- 반례: 이미 동적 렌더 라우트면 영향 작음. 페이지 본문 전체를 감싸는 Suspense 는 빌드·검증은 통과시키지만 빈 셸이 되어 목적을 잃는다. Cache Components 의 `export const instant = false` 는 검증만 끄는 탈출구 — 클라이언트 훅 에러에는 대개 부적절
- 검증: `next build`(dev 아님) 결과, JS 비활성화 상태로 페이지 HTML 확인. 신모델은 `next build --debug-prerender` 로 실패 컴포넌트 추적
- 근거: `03-api-reference/04-functions/use-search-params.md#prerendering`(Good to know: 프로덕션 빌드 실패), https://nextjs.org/docs/messages/missing-suspense-with-csr-bailout , https://nextjs.org/docs/messages/blocking-prerender-client-hook
