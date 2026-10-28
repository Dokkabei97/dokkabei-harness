# RSC 직렬화 경계·클라이언트 번들 유입 (RSC-BND)

> 확인 문서: `node_modules/next/dist/docs/01-app/01-getting-started/05-server-and-client-components.md`,
> `02-guides/data-security.md`, React 공식 직렬화 표 https://react.dev/reference/rsc/use-client#serializable-types

### RSC-BND-01 · 'use client' 는 컴포넌트 표시가 아니라 "모듈 그래프 경계" — import 하는 모든 것이 클라이언트 번들로
- 적용: App Router 전 버전
- 신호: 페이지·레이아웃 상단의 `'use client'`, 큰 컴포넌트 파일 하나에 상호작용 한 줄 때문에 붙은 지시어, 클라이언트 파일이 마크다운 파서·날짜 라이브러리·스키마 전체를 import
- 메커니즘: 지시어가 붙은 파일이 import 하는 모듈과 **직접 렌더하는** 컴포넌트가 모두 클라이언트 그래프로 편입된다(하위 파일에 지시어가 없어도). 예외는 서버에서 `children`/props 로 넘겨받은 렌더 결과뿐
- 처방: 상호작용 leaf 만 분리해 `'use client'`. 서버 콘텐츠는 `children`/slot props 로 클라이언트 래퍼에 주입(Context Provider 도 같은 방식). `next/dynamic` 의 `ssr: false` 는 클라이언트 래퍼 안에서만 가능하고 그 콘텐츠를 SSR HTML 에서 빼므로(LCP·SEO 손해) `window` 접근 회피 목적이면 effect 내부 접근으로 충분한지 먼저 본다
- 반례: 거의 전부가 상호작용인 에디터/캔버스 화면은 경계를 쪼갤수록 props 직렬화 비용만 는다 — 한 덩어리 클라이언트가 맞다
- 검증: `next experimental-analyze`(16.1+, Turbopack) 의 import chain 뷰로 "이 모듈이 왜 클라이언트에 있나" 추적, Webpack 이면 `@next/bundle-analyzer`
- 근거: `05-server-and-client-components.md#use-client`(module graph 설명), `02-guides/package-bundling.md`, `02-guides/lazy-loading.md`

### RSC-BND-02 · 서버→클라이언트 props 는 HTML 과 RSC 페이로드에 이중으로 실린다
- 적용: 서버 컴포넌트가 큰 배열/객체를 Client Component prop 으로 전달
- 신호: 클라이언트 테이블에 수천 행 전달, view-source 의 `self.__next_f.push(...)` 스크립트가 HTML 본문보다 큼, 문서 크기 대비 TTFB/파싱 시간 과다
- 메커니즘: SSR HTML(렌더 결과) + 하이드레이션용 RSC 페이로드(직렬화된 props)가 같은 응답에 인라인된다. 클라이언트 경계로 넘긴 데이터는 사용하지 않는 필드까지 그대로 직렬화
- 처방: 경계에서 필요한 필드만 매핑(DTO), 서버에서 페이지네이션/가상화, 표시만 하는 부분은 서버 컴포넌트로 남겨 렌더 결과만 전송
- 반례: 클라이언트에서 정렬·필터를 즉시 해야 하는 소량 데이터는 넘기는 것이 왕복보다 싸다
- 검증: 응답 HTML 크기와 `__next_f` 청크 합계 비교(`curl -s URL | wc -c`), Lighthouse "Reduce JavaScript execution"/총 바이트
- 근거: `05-server-and-client-components.md`(RSC Payload 에 "Client Component 로 전달된 props" 포함)

### RSC-BND-03 · NEXT_PUBLIC_ 없는 env 는 클라이언트에서 "에러 없이 빈 문자열" — 환경 오염은 조용히 실패한다
- 적용: 서버/클라이언트 양쪽에서 import 가능한 유틸(lib/*.ts)
- 신호: `process.env.API_KEY` 를 쓰는 함수를 Client Component 에서 import; 브라우저에서만 401/빈 헤더
- 메커니즘: 비공개 env 는 클라이언트 번들에서 빈 문자열로 치환되어 런타임 에러 없이 오동작. 반대로 `NEXT_PUBLIC_` 를 붙이면 빌드 시 값이 번들에 하드코딩(동적 키 조회 `process.env[name]` 은 인라인 안 됨)
- 처방: 서버 전용 모듈 첫 줄 `import 'server-only'`(클라이언트 import 시 빌드 에러로 승격), 브라우저 전용은 `client-only`. `process.env` 접근은 DAL 로 한정
- 반례: 진짜 공개 값(공개 분석 ID 등)은 `NEXT_PUBLIC_` 이 맞다 — 단 빌드 시 고정(NX-OPS-01)
- 검증: `grep -r "API_KEY\|secret" .next/static` 로 산출물 검사, `server-only` 위반 시 build 에러 확인
- 근거: `05-server-and-client-components.md#preventing-environment-poisoning`, `02-guides/environment-variables.md`

### RSC-BND-04 · 서버 컴포넌트가 DB 행 전체를 클라이언트 prop 으로 넘기면 비밀 필드가 페이로드에 노출
- 적용: ORM/SQL 결과 객체를 그대로 `<ClientX user={row} />`
- 신호: `select *`/엔티티 객체 전달, 화면엔 이름만 쓰지만 prop 타입이 DB 타입
- 메커니즘: 직렬화는 필드 단위 필터가 없다 — `password_hash`, 내부 플래그, 타 사용자 PII 가 RSC 페이로드에 평문으로 실린다(DevTools 에서 보임)
- 처방: DAL 이 화면용 DTO 만 반환. 추가 방어로 `experimental.taint: true` + `experimental_taintObjectReference`/`experimental_taintUniqueValue`(실험 API — 1차 방어 아님)
- 반례: 없음 — 공개 필드만 있는 객체라도 스키마가 바뀌면 노출되므로 매핑 습관을 유지
- 검증: 페이지 HTML/RSC 응답에서 민감 컬럼명 grep
- 근거: `02-guides/data-security.md#tainting`, `#data-access-layer`

### RSC-BND-05 · 직렬화 규칙 비대칭 — RSC 는 Date/Map/Set/BigInt 를 보존하지만 JSON API 는 문자열로 바꾼다
- 적용: 같은 타입을 RSC props 와 Route Handler/외부 JSON 응답 양쪽으로 받는 코드
- 신호: 타입은 `Date` 인데 한 경로에서만 `.getTime is not a function`; 클래스 인스턴스·일반 함수 prop 전달 시 직렬화 에러
- 메커니즘: RSC 는 Date, Map, Set, BigInt, TypedArray, Promise, Server Function 등을 지원하고 클래스 인스턴스·일반 함수·null-prototype 객체·미등록 Symbol 은 거부. JSON 경로는 Date→string, Map/Set 소실
- 처방: 경계 타입은 전송 형식 기준으로 정의(예: ISO 문자열) 또는 경로별 파싱 계층(zod `z.coerce.date()`)
- 반례: RSC 전용 경로만 있다면 Date 를 그대로 쓰는 편이 단순
- 검증: 경계 타입에 대한 단위 테스트(두 경로 모두)
- 근거: https://react.dev/reference/rsc/use-client#serializable-types, `use-cache.md#serialization`(인자/반환값 직렬화 체계 차이)

### RSC-BND-06 · 배럴 파일(index.ts)은 경계를 무너뜨린다 — 라이브러리 배럴은 optimizePackageImports
- 적용: `components/index.ts` 같은 재수출 파일, 아이콘/유틸 라이브러리 named import
- 신호: 서버 컴포넌트가 `@/components` 배럴에서 1개를 import 했는데 클라이언트 컴포넌트 다수가 번들에 등장; dev 컴파일 모듈 수 수천
- 메커니즘: 배럴이 `'use client'` 모듈을 섞어 재수출하면 트리셰이킹 전 단계에서 그래프가 커지고, 배럴 상단에 `'use client'` 가 있으면 전체가 클라이언트화. 외부 패키지 배럴은 모듈 수 폭증(dev 성능)
- 처방: 앱 코드는 배럴 대신 직접 경로 import. 외부 패키지는 `experimental.optimizePackageImports`(기본 최적화 목록에 `lucide-react`, `date-fns`, `lodash-es`, `ramda`, `antd`, `react-bootstrap` 등 포함 — 버전별 목록은 문서 확인)
- 반례: 이미 기본 목록에 있는 패키지를 다시 넣을 필요 없음
- 검증: bundle analyzer 모듈 수 전후 비교, `next dev` 컴파일 로그의 모듈 수
- 근거: `03-api-reference/05-config/01-next-config-js/optimizePackageImports.md`

### RSC-BND-08 · use(promise) 의 promise 는 서버에서 만들어 내려야 한다
- 적용: 서버에서 fetch 를 시작하고 클라이언트에서 `use()` 로 소비하는 스트리밍 패턴
- 신호: Client Component 렌더 본문에서 `use(fetch(...))`/`use(getX())` → 무한 서스펜드·요청 반복
- 메커니즘: 클라이언트 렌더 중 생성한 promise 는 매 렌더 새로 만들어져 캐시되지 않는다. 서버 컴포넌트에서 await 없이 promise 를 만들어 prop 으로 넘기면 직렬화되어 스트리밍된다
- 처방: 서버: `const p = getPosts()` → `<Suspense><Posts posts={p} /></Suspense>`; 클라: `use(posts)`. 여러 소비자는 Context 로 promise 공유
- 반례: 클라이언트 주도 데이터(검색어 입력 등)는 TanStack Query/SWR 같은 캐시 레이어가 맞다
- 검증: Network 탭 요청 반복 여부
- 근거: `01-getting-started/06-fetching-data.md#streaming-data-with-the-use-api`, https://react.dev/reference/react/use
