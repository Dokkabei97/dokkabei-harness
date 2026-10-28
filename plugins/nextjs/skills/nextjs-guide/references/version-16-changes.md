# Next.js 16 변경점 — 학습 데이터와 어긋나는 지점 (NX-V16)

> 확인 기준: Next.js 16.3.x 동봉 문서 `node_modules/next/dist/docs/01-app/02-guides/upgrading/version-16.md`
> (공개본: https://nextjs.org/docs/app/guides/upgrading/version-16). 마이너마다 바뀌는 항목이 있으므로
> 프로젝트의 `package.json` `next` 버전과 동봉 문서를 먼저 확인하고, 아래 항목은 "어디를 볼지" 지도로만 쓴다.
> 15.x 이하 프로젝트에는 적용하지 않는다.

### NX-V16-01 · middleware.ts 는 deprecated — proxy.ts 로 개명, 런타임은 Node 고정
- 적용: Next 16+. 루트(또는 `src/`)에 `middleware.ts` 가 남아 있는 프로젝트, 새 요청 가로채기 코드를 쓸 때
- 신호: `middleware.ts`/`export function middleware`, `skipMiddlewareUrlNormalize`, proxy 파일에 `export const runtime`
- 메커니즘: 파일·함수명이 `proxy` 로 바뀌었고 `proxy` 런타임은 `nodejs` 로 고정(설정 불가 — `runtime` 지정 시 에러). edge 런타임이 필요하면 deprecated 인 `middleware` 를 유지해야 한다. 설정 플래그도 개명(`skipMiddlewareUrlNormalize` → `skipProxyUrlNormalize`)
- 처방: `mv middleware.ts proxy.ts` + `export function proxy(request)`; 또는 `npx @next/codemod@canary upgrade latest`(middleware→proxy, 플래그 개명 포함)
- 반례: edge 런타임에 의존하는 배포(엣지 지역 실행 요구)는 당장 개명하지 말 것 — 문서상 edge 후속 안내 예정
- 검증: `next build` 경고/에러, dev 서버 로그의 deprecation 메시지
- 근거: version-16.md `#middleware-to-proxy`, `03-api-reference/03-file-conventions/proxy.md#runtime`

### NX-V16-02 · Proxy 는 인증 "판정" 계층이 아니다 — 낙관적 체크만
- 적용: proxy(구 middleware)에서 세션/권한을 검사하는 모든 버전
- 신호: proxy 안에서 DB 조회, 외부 auth API 호출, 권한 판정 후 그대로 통과
- 메커니즘: proxy 는 prefetch 를 포함한 모든 매칭 요청에서 실행되므로 DB 체크는 성능 문제를 낳는다. 또한 matcher 에서 제외된 경로의 Server Function(POST) 은 proxy 를 건너뛴다 — matcher 변경이나 액션 이동만으로 보호가 조용히 사라진다
- 처방: proxy 는 쿠키 기반 낙관적 리다이렉트만. 실제 인증·인가는 DAL(`import 'server-only'`) 과 각 Server Action 내부에서 재검증
- 반례: 정적 라우트(빌드 시 공유 데이터)는 DAL 이 요청 시점에 돌지 않으므로 proxy 리다이렉트가 유일한 관문일 수 있다(문서 명시)
- 검증: matcher 를 바꾼 diff 마다 영향받는 Server Action 목록을 grep(`'use server'`)으로 대조
- 근거: `01-getting-started/16-proxy.md`, `02-guides/authentication.md#optimistic-checks-with-proxy-optional`, `proxy.md` Good to know(Server Functions). 실사례: CVE-2025-29927 — `x-middleware-subrequest` 헤더로 middleware 인가 검사를 우회(수정 15.2.3 / 14.2.25 / 13.5.9 / 12.3.5), middleware 에만 인가를 둔 앱이 그대로 뚫렸다 https://github.com/vercel/next.js/security/advisories/GHSA-f82v-jwr5-mffw

### NX-V16-03 · 동기 Request API 호환 완전 제거
- 적용: Next 16+ (15 는 경고만 내는 임시 호환기)
- 신호: `cookies().get(`, `headers().get(`, `params.slug`(await 없이), `searchParams.q` 동기 접근, OG 이미지 함수의 동기 `params`/`id`, `sitemap({ id })` 의 숫자 `id`
- 메커니즘: `cookies`/`headers`/`draftMode`/`params`/`searchParams` 는 Promise 만 반환. 16 에서 `opengraph-image`/`icon` 생성 함수의 `params`·`id`, `sitemap` 의 `id` 도 Promise 로 변경(`generateImageMetadata` 의 params 는 동기 유지)
- 처방: `npx @next/codemod@canary next-async-request-api .` (upgrade 코드모드에 포함 안 됨) + `npx next typegen` 으로 `PageProps<'/route'>`/`LayoutProps`/`RouteContext` 타입 생성
- 반례: 없음 — 16 에서는 선택지가 아님
- 검증: `tsc --noEmit`, `next build`
- 근거: version-16.md `#async-request-apis-breaking-change`, `#async-id-parameter-for-sitemap-breaking-change`

### NX-V16-04 · revalidateTag 단일 인자 deprecated — 의미가 SWR 로 바뀜
- 적용: Next 16+
- 신호: `revalidateTag('posts')`(인자 1개), 사용자 자신의 수정 직후 화면이 이전 값을 보여주는 버그
- 메커니즘: `revalidateTag(tag, profile)` 은 stale-while-revalidate — 액션 응답의 재렌더는 새 데이터를 기다리지 않는다. 즉시 만료 + read-your-writes 가 필요하면 Server Action 전용 `updateTag(tag)`. 캐시 무효화 없이 현재 라우트 RSC 페이로드만 다시 받으려면 `refresh()`
- 처방: 폼·설정 저장 → `updateTag`; 블로그·카탈로그처럼 지연 허용 → `revalidateTag(tag, 'max')`
- 반례: Route Handler 나 webhook 에서는 `updateTag` 를 쓸 수 없다(Server Actions only) — 외부 webhook 무효화는 `revalidateTag`
- 검증: 수정 직후 같은 요청의 재렌더 결과를 확인(e2e 에서 저장 → 즉시 값 assert)
- 근거: version-16.md `#caching-apis`, `02-guides/server-actions.md#choosing-a-cache-update`

### NX-V16-05 · Turbopack 기본 + 커스텀 webpack 설정 시 build 실패
- 적용: Next 16+ 에서 `next.config` 에 `webpack()` 이 있거나 플러그인이 주입하는 경우
- 신호: 직접 정의하지 않았는데 "webpack configuration was found" 로 build 실패(플러그인 — 예: 번들 분석기·sentry 등 — 가 주입)
- 메커니즘: `next dev`/`next build` 모두 Turbopack 기본. `experimental.turbopack` → 최상위 `turbopack`. Sass `~` 접두 import 미지원. 클라이언트 번들에 `fs` 등 Node 모듈이 섞이면 `resolve.fallback` 대신 `turbopack.resolveAlias` 의 `browser` 조건이 있지만, 문서는 코드 분리를 우선 권장
- 처방: 이관하거나 `next build --webpack` 으로 명시적 opt-out. `--turbopack` 플래그는 스크립트에서 제거
- 반례: resolveAlias 로 `fs` 를 빈 모듈 처리하는 것은 증상 은폐 — 서버 전용 모듈이 클라이언트 그래프에 들어온 근본 원인(RSC-BND-03)을 먼저 본다
- 검증: `next build` 로그의 번들러 표기, `.next/dev`(dev 출력이 분리됨)
- 근거: version-16.md `#turbopack-by-default`, `#resolve-alias-fallback`, `#sass-node_modules-imports`

### NX-V16-06 · next lint 제거, next build 는 더 이상 lint 하지 않음
- 적용: Next 16+
- 신호: `package.json` 의 `"lint": "next lint"`, CI 가 build 만 돌리고 lint 통과를 가정, `next.config` 의 `eslint: {}`
- 메커니즘: `next lint` 명령과 config `eslint` 옵션 삭제. `@next/eslint-plugin-next` 는 Flat Config 기본
- 처방: `npx @next/codemod@canary next-lint-to-eslint-cli .`, CI 에 `eslint .`(또는 Biome) 단계를 별도로 추가
- 반례: 없음
- 검증: CI 로그에 lint 단계가 실제로 실행되는지
- 근거: version-16.md `#next-lint-command`, `#eslint-flat-config`

### NX-V16-07 · next/image 기본값 변경 4종 — 조용한 품질·캐시 변화
- 적용: Next 16+, `next/image` 사용
- 신호: `quality={90}` 이 적용 안 되는 듯한 화질, `localhost`/사설 IP 원본 이미지 400, 쿼리스트링 붙은 로컬 이미지 실패, 원본 변경이 오래 반영 안 됨
- 메커니즘: `images.qualities` 기본 `[75]` — 목록 밖 `quality` 는 가장 가까운 값으로 강제(80→75). `minimumCacheTTL` 60s → 14400s(4h). `imageSizes` 에서 16 제거. 로컬 IP 최적화 기본 차단(`dangerouslyAllowLocalIP`), 리다이렉트 최대 3회(`maximumRedirects`), 쿼리스트링 로컬 이미지는 `localPatterns.search` 필요. `priority` prop deprecated → `preload`(WEB-IMG-02)
- 처방: 필요한 품질을 `images.qualities` 에 명시. 원본이 자주 바뀌면 원본에 `Cache-Control` 을 주거나 `minimumCacheTTL` 조정. VPC split-horizon DNS 등으로 사설 IP 를 거칠 때만 `dangerouslyAllowLocalIP`(SSRF 위험 인지 후)
- 반례: qualities 를 넓게 열면 변형 수가 늘어 캐시·CPU 비용 증가 — 실제 쓰는 값만
- 검증: 응답 이미지 URL 의 `q=` 파라미터, 응답 헤더 `Cache-Control`
- 근거: version-16.md `#nextimage-changes`

### NX-V16-08 · Parallel route 슬롯마다 default.js 필수
- 적용: Next 16+, `@slot` 디렉터리 사용
- 신호: 16 업그레이드 후 build 실패, `@modal` 등 슬롯에 `default.tsx` 없음
- 메커니즘: 이전엔 암묵 처리되던 미매칭 슬롯이 명시 파일 없이는 빌드 실패
- 처방: `default.tsx` 에서 `notFound()` 호출 또는 `return null`
- 반례: 없음
- 검증: `next build`
- 근거: version-16.md `#parallel-routes-defaultjs-requirement`

### NX-V16-09 · 제거된 런타임 설정 — serverRuntimeConfig/publicRuntimeConfig, AMP, unstable_rootParams
- 적용: Next 16+
- 신호: `getConfig()` from `next/config`, `publicRuntimeConfig`, `useAmp`, `unstable_rootParams`
- 메커니즘: 런타임 설정 API 삭제. 대체로 서버 값은 `process.env` 직접(서버 컴포넌트), 클라이언트 값은 `NEXT_PUBLIC_` — 단 이것은 **빌드 시 인라인**이라 동일 이미지를 여러 환경에 배포하면 값이 고정된다(NX-OPS-01)
- 처방: 환경별로 달라지는 공개 값은 서버 컴포넌트에서 읽어 props 로 내리거나 런타임 설정 엔드포인트 제공. `unstable_rootParams` → `next/root-params`
- 반례: 빌드를 환경별로 따로 하는 파이프라인이면 `NEXT_PUBLIC_` 으로 충분
- 검증: 스테이징 이미지를 운영으로 승격했을 때 클라이언트 번들의 값(`grep` `.next/static`)
- 근거: version-16.md `#runtime-configuration`, `02-guides/environment-variables.md`

### NX-V16-10 · scroll-behavior: smooth 를 더 이상 덮어쓰지 않음
- 적용: Next 16+, 전역 CSS 에 `html { scroll-behavior: smooth }`
- 신호: 16 이후 라우트 전환마다 맨 위로 부드럽게 스크롤되며 전환이 느려 보임
- 메커니즘: 이전엔 내비게이션 동안 `auto` 로 임시 전환했으나(비용 있음) 16 은 기본적으로 손대지 않음
- 처방: 이전 동작을 원하면 `<html data-scroll-behavior="smooth">`
- 반례: 페이지 내 앵커만 smooth 로 쓰고 라우트 전환은 신경 안 쓰는 경우 그대로 둬도 됨
- 검증: 라우트 전환 녹화로 확인
- 근거: version-16.md `#scroll-behavior-override`

### NX-V16-11 · build 출력의 size / First Load JS 지표 제거
- 적용: Next 16+
- 신호: CI 에서 `First Load JS` 를 파싱하던 번들 예산 체크가 깨짐/0 으로 통과
- 메커니즘: RSC 구조에서 부정확하다는 이유로 두 지표 삭제(Turbopack·Webpack 계산도 불일치)
- 처방: 번들 예산은 `next experimental-analyze --output`(16.1+) 산출물 비교나 Lighthouse/실사용 CWV 로 옮긴다(WEB-BUN-01)
- 반례: 없음
- 검증: CI 번들 예산 단계가 실제 숫자를 읽는지
- 근거: version-16.md `#performance-improvements`, `02-guides/package-bundling.md`

### NX-V16-12 · next dev 는 config 를 한 번만 로드 — process.argv 'dev' 판별 깨짐
- 적용: Next 16+, `next.config` 에서 부수효과(dev 서버 기동 등)를 거는 플러그인
- 신호: `process.argv.includes('dev')` 분기
- 메커니즘: dev 시 config 이중 로드를 없애면서 `argv` 에 `dev` 가 보이지 않음(`build`, `typegen` 은 보임). dev/build 출력 디렉터리 분리(`.next/dev`)와 잠금 파일로 동시 실행 가능
- 처방: `process.env.NODE_ENV === 'development'` 또는 config 의 `phase` 인자 사용
- 반례: 없음
- 검증: dev 기동 후 부수효과 실행 로그
- 근거: version-16.md `#next-dev-config-load`, `#concurrent-dev-and-build`
