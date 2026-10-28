# 캐싱·렌더링 모델 함정 (NX-CACHE)

> 먼저 판별: `next.config` 에 `cacheComponents: true` 가 있는가? 있으면 "Cache Components 모델"(16+, 기본 동적 + `'use cache'` opt-in),
> 없으면 "이전 모델"(fetch 옵션·`unstable_cache`·route segment config). 두 모델의 규칙은 서로 섞이지 않는다.
> 확인 문서: `node_modules/next/dist/docs/01-app/01-getting-started/08-caching.md`, `02-guides/caching-without-cache-components.md`,
> `02-guides/migrating-to-cache-components.md`, `03-api-reference/01-directives/use-cache.md`.

### NX-CACHE-01 · "기본 캐시됨" 기억은 14 이하의 것 — 15 부터 fetch·GET 핸들러·동적 라우터 캐시 모두 기본 off
- 적용: Next 15+(두 모델 공통)
- 신호: "fetch 는 자동 캐시되니 괜찮다"는 가정, 페이지마다 동일 외부 API 를 매 요청 호출, 뒤로가기마다 동적 페이지 재요청
- 메커니즘: `fetch` 기본 비캐시(필요 시 `cache: 'force-cache'` 또는 `'use cache'`). 클라이언트 라우터 `staleTimes.dynamic` 기본 0s(15.0 에서 30s → 0s), `static` 5분. 같은 렌더 패스 안의 GET fetch **메모이제이션**(URL+옵션 동일)은 여전히 있지만 요청 간 캐시가 아니며 Route Handler 에는 적용되지 않음
- 처방: 캐시 의도를 코드에 명시 — 데이터 단위로 `'use cache'`+`cacheLife`(신모델) 또는 `force-cache`/`unstable_cache`(구모델)
- 반례: 사용자별·실시간 데이터는 캐시하지 않는 게 기본값의 의도
- 검증: 서버 로그/외부 API 호출 수, 응답 헤더 `x-nextjs-cache`(구모델 ISR), dev overlay
- 근거: `02-guides/caching-without-cache-components.md`, `03-api-reference/05-config/01-next-config-js/staleTimes.md`(Version history), `04-glossary.md#memoization`

### NX-CACHE-02 · DB/ORM 직접 호출은 fetch 메모이제이션 대상이 아니다
- 적용: 서버 컴포넌트에서 DB 클라이언트·SDK·gRPC 를 직접 호출(fetch 아님)
- 신호: layout·page·`generateMetadata` 가 같은 `getUser()` 를 각각 호출 → 한 요청에 쿼리 N회
- 메커니즘: 자동 메모이제이션은 `fetch` GET 에만 적용. 그 외 함수는 렌더 패스 안에서도 매번 실행
- 처방: DAL 함수를 `React.cache(fn)` 으로 감싸 요청 스코프 중복 제거. 요청 간 캐시는 별도(`'use cache'`/`unstable_cache`)
- 반례: Cache Components 에서 `'use cache'` 함수들끼리는 React.cache 결과를 공유하지 않는다(NX-CACHE-07)
- 검증: 쿼리 로그 카운트(요청당), OpenTelemetry span 수
- 근거: `04-glossary.md#memoization`, `02-guides/data-security.md#data-access-layer`

### NX-CACHE-03 · 'use cache' 안에서 cookies/headers 접근은 build 는 통과하고 next start 에서 실패할 수 있다
- 적용: Cache Components 모델
- 신호: 캐시 함수가 호출하는 헬퍼(깊은 콜스택 포함)가 `cookies()`/`headers()`/`searchParams` 를 읽음; 운영에서만 `next-request-in-use-cache` 에러
- 메커니즘: 금지 규칙이 콜스택 전체로 전파된다. 동적 렌더 라우트에서는 요청 시점에야 드러나 빌드를 통과한다
- 처방: 런타임 값은 캐시 스코프 밖에서 읽어 **인자로** 넘긴다(인자 = 캐시 키). 리팩터링 불가·컴플라이언스 사유면 `'use cache: private'`
- 반례: `draftMode().isEnabled` 는 캐시 스코프 안에서 읽기 허용
- 검증: `next build && next start` 후 동적 라우트를 실제 요청(쿠키 포함)하는 스모크 테스트 — dev/build 만으로 끝내지 말 것
- 근거: `03-api-reference/01-directives/use-cache.md#runtime-apis`(본문 "restriction follows the call stack")

### NX-CACHE-04 · 'use cache' 캐시 키 = 빌드 ID + 함수 ID + 직렬화 인자 + **클로저 캡처 변수**
- 적용: Cache Components 모델
- 신호: 캐시 함수가 바깥 스코프의 큰 객체·요청별 값(타임스탬프, 전체 user 객체)을 참조; 히트율이 0 에 가까움
- 메커니즘: 외부 변수는 자동으로 인자로 바인딩되어 키에 들어간다 → 요청마다 다른 값을 캡처하면 매번 미스 + 메모리만 증가. 인자는 RSC 직렬화(클래스 인스턴스 불가), 반환값은 클라이언트 직렬화(JSX 가능) 규칙 — 서로 다름. 직렬화 불가 값(children, Server Action)은 **열어보지 않으면** pass-through 가능
- 처방: 키에 필요한 최소 원시값(id 등)만 인자로. 큰 객체 대신 id 를 넘기고 내부에서 조회
- 반례: 사용자별 캐시가 의도라면 userId 를 키에 넣는 것이 맞다
- 검증: 동일 입력 반복 요청 시 원본 호출 수 감소 확인(DB 로그)
- 근거: `use-cache.md#cache-keys`, `#serialization`, `#pass-through-non-serializable-arguments`

### NX-CACHE-05 · 'use cache' 런타임 저장소는 인스턴스별 in-memory LRU(기본 50MB) — 다중 인스턴스·서버리스에서 일관성 없음
- 적용: Cache Components 모델, 셀프호스팅 다중 레플리카(k8s 등) 또는 서버리스
- 신호: 파드마다 다른 데이터, 무효화(`revalidateTag`)가 한 파드에만 반영된 듯한 현상, 서버리스에서 히트율 ~0
- 메커니즘: 기본 핸들러는 프로세스 메모리. `cacheMaxMemorySize` 기본 50MB. 서버리스는 요청 간 유지되지 않음. 새 배포는 키(빌드 ID/`deploymentId`)가 바뀌어 전부 무효
- 처방: 공유가 필요하면 `'use cache: remote'` + `cacheHandlers`(Redis/KV 등) — 네트워크 왕복 비용 감수. 다중 인스턴스 무효화 조율은 self-hosting 가이드의 Multi-Instance Cache Coordination 참고
- 반례: 단일 인스턴스·짧은 TTL·정합성 완화 허용이면 기본 in-memory 가 가장 싸다
- 검증: 레플리카 2개에서 같은 키를 무효화 후 양쪽 응답 비교
- 근거: `use-cache.md#runtime-caching-considerations`, `03-api-reference/05-config/01-next-config-js/cacheMaxMemorySize.md`, `02-guides/self-hosting.md#shared-cache`

### NX-CACHE-06 · cacheLife 생략 시 default 프로필(stale 5분 / revalidate 15분 / expire 없음) + 클라이언트 최소 stale 30초
- 적용: Cache Components 모델
- 신호: `'use cache'` 만 있고 `cacheLife(...)` 없음; "방금 바꿨는데 최대 몇 분 옛값"
- 메커니즘: 생략 시 암묵 `default` 프로필. 클라이언트 라우터는 설정과 무관하게 **최소 30초** stale 을 강제. 중첩 캐시는 안쪽 수명이 바깥 엔트리에 영향
- 처방: 모든 캐시 스코프에 `cacheLife` 명시 + 변경 경로엔 `cacheTag` → `updateTag`/`revalidateTag`
- 반례: 진짜 실시간 값은 캐시하지 말고 Suspense 로 스트리밍
- 검증: 응답 헤더 `x-nextjs-stale-time`
- 근거: `use-cache.md#revalidation`, `#use-cache-at-runtime`, `03-api-reference/04-functions/cacheLife.md`

### NX-CACHE-07 · 각 'use cache' 함수는 독립된 React.cache 스코프
- 적용: Cache Components 모델에서 `React.cache` 로 프리로드/공유하던 코드
- 신호: 한 캐시 함수가 프리로드한 결과를 다른 캐시 함수가 재사용한다고 가정 → 중복 쿼리
- 메커니즘: 캐시 함수 간 React.cache 결과 비공유. React.cache 로 캐시 스코프에 데이터를 "주입"하는 것도 불가
- 처방: 인자로 전달. 요청 데이터를 캐시 스코프 간 공유해야 하면 `'use cache: private'`(+요청 스코프 중복 제거만 필요하면 `cacheLife({ stale: Infinity })`)
- 반례: 일반 렌더 트리 안의 React.cache 는 그대로 동작
- 검증: 쿼리 로그 카운트
- 근거: `02-guides/migrating-to-cache-components.md#reactcache`, `use-cache.md`

### NX-CACHE-08 · 프리렌더 중 동기 IO(Date.now / Math.random / crypto.randomUUID)는 build 에러 — instant=false 로도 안 풀림
- 적용: Cache Components 모델
- 신호: `new Date()` 를 렌더에서 호출하는 "오늘 날짜" 배지, 랜덤 추천, `randomUUID()` key
- 메커니즘: 정적 셸 프리렌더 중 비결정 값은 셸을 오염시키므로 차단. `instant = false` 는 "블로킹 허용" 표시일 뿐 동기 IO 에러를 지우지 않음
- 처방: 해당 부분을 `<Suspense>` 로 감싸고 그 안에서 `await connection()` 후 호출, 또는 Client Component 로 이동(이때 하이드레이션 불일치 주의 — WEB-HYD-01)
- 반례: 빌드 시각을 의도적으로 박는 값이면 `'use cache'` 안에서 계산
- 검증: `next build`
- 근거: `migrating-to-cache-components.md#adopting-incrementally`, `03-api-reference/04-functions/connection.md`

### NX-CACHE-09 · Cache Components 켜면 dynamic/revalidate/fetchCache export·빈 generateStaticParams·dynamicParams 가 에러
- 적용: 기존 앱에서 `cacheComponents: true` 전환
- 신호: 전환 직후 대량 build 에러
- 메커니즘: 플래그는 이름 바꾸기가 아니라 모델 교체. route segment config 3종은 에러, `generateStaticParams` 는 최소 1개 반환 필수(`[]` 에러), `dynamicParams` export 는 build 실패. `runtime = 'edge'` 미지원(Node 필요)
- 처방: 공식 마이그레이션 가이드의 키별 치환표를 따른다. 점진 도입은 세그먼트별 `instant = false`(codemod `cache-components-instant-false`)
- 반례: `experimental.dynamicIO`/`useCache` 를 실제로 쓰지 않던 프로젝트는 플래그를 켜지 말고 제거만
- 검증: dev overlay 의 insight/에러(HTTP 200 으로 응답하므로 overlay·dev 서버 로그를 봐야 함)
- 근거: `migrating-to-cache-components.md`, version-16.md `#experimentaldynamicio-and-experimentalusecache`

### NX-CACHE-10 · Suspense 는 컴포넌트를 동적으로 만들지 않는다 / 경계 밖 비캐시 읽기는 라우트 전체를 블로킹
- 적용: 두 모델(신모델에서 특히 검출됨)
- 신호: 페이지 최상단에서 `await getData()` 후 하위에 Suspense; TTFB 가 가장 느린 쿼리에 묶임; dev overlay "blocking-route"
- 메커니즘: 동기 작업만 하는 컴포넌트는 Suspense 안에 있어도 프리렌더된다. 반대로 비캐시/런타임 데이터 읽기가 Suspense 밖에 있으면 셸 전체가 그 데이터를 기다린다. `loading.js` 는 세그먼트 전체 단위라 거칠다
- 처방: 느린 읽기를 하는 **컴포넌트 자체**를 Suspense 경계 안으로 내리고, 페이지는 동기적으로 셸을 반환
- 반례: 봇/크롤러에는 스트리밍 대신 완성 페이지가 나간다(문서 명시) — SEO 우회 목적의 스트리밍 설계는 무의미
- 검증: TTFB vs LCP 비교, dev overlay insight
- 근거: `01-getting-started/08-caching.md#streaming-uncached-data`, `01-getting-started/06-fetching-data.md#streaming`

### NX-CACHE-11 · Cache Components 내비게이션은 Activity(hidden)로 이전 라우트 상태를 보존
- 적용: Cache Components 모델
- 신호: 뒤로가기 시 드롭다운/다이얼로그가 열린 채 복귀, "언마운트 시 초기화"를 가정한 effect·테스트 실패
- 메커니즘: 이전 라우트를 언마운트하지 않고 `<Activity mode="hidden">`. effect 는 hidden 시 cleanup, visible 시 재실행되지만 state 는 유지. 최근 몇 개 라우트만 유지(휴리스틱)
- 처방: 열림 상태 등은 effect cleanup 에서 닫거나 URL 상태로 관리. 문서 "Preserving UI state" 패턴 적용
- 반례: 폼 입력 보존은 오히려 의도된 이점
- 검증: 왕복 내비게이션 e2e
- 근거: `03-api-reference/05-config/01-next-config-js/cacheComponents.md#navigation-with-activity`

### NX-CACHE-12 · 동적 페이지는 loading.js 없으면 prefetch 되지 않는다(이전 모델)
- 적용: `cacheComponents` 미사용
- 신호: 정적 링크는 즉시, 동적 링크는 클릭 후 공백 대기
- 메커니즘: 정적 라우트는 전체 prefetch(클라 TTL 5분), 동적 라우트는 `loading.js` 가 있을 때만 첫 로딩 경계까지 prefetch(클라 TTL 기본 off). prefetch 는 production 에서만 동작 — dev 에서 재현 안 됨
- 처방: 동적 세그먼트에 `loading.tsx` 추가 또는 의도적으로 `prefetch={true}`(비용 고려)
- 반례: 링크가 수백 개인 목록에서 `prefetch={true}` 남발은 요청 폭증
- 검증: `next build && next start` 후 Network 탭에서 prefetch 요청 확인
- 근거: `02-guides/prefetching.md#prefetching-static-vs-dynamic-routes`

### NX-CACHE-13 · after() 는 라우트를 동적으로 만들지 않는다 — 정적 페이지에서는 빌드/재검증 시점에 실행
- 적용: `after` 로 로깅·분석 이벤트를 보내는 코드
- 신호: 페이지뷰 로깅이 요청마다 안 찍힘(정적 페이지)
- 메커니즘: `after` 는 Request-time API 가 아니다. 실행 시간은 라우트의 maxDuration 에 묶임
- 처방: 요청 단위 로깅은 동적 경로/Route Handler/Server Action 의 `after` 에서. 페이지 내 cookies/headers 는 `after` 밖에서 읽어 전달
- 반례: 빌드 시 한 번 실행이 의도라면 무관
- 검증: 운영 로그 카운트 vs 트래픽
- 근거: `03-api-reference/04-functions/after.md`
