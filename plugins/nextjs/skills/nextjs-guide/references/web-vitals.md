# 이미지·폰트 CLS/LCP, 하이드레이션 불일치, 번들 분석 (WEB)

> 확인 문서: `node_modules/next/dist/docs/01-app/03-api-reference/02-components/image.md`, `.../font.md`,
> `02-guides/preventing-flash-before-hydration.md`, `02-guides/package-bundling.md`.
> 측정 원칙: lab(Lighthouse) 은 회귀 탐지, field(CrUX/RUM `useReportWebVitals`) 는 판정. 개발 서버 수치로 판단하지 말 것(`next build && next start`).

## 이미지 (WEB-IMG)

### WEB-IMG-01 · fill/반응형 이미지에 sizes 누락 → 브라우저가 100vw 로 가정해 과대 다운로드
- 적용: `next/image` 의 `fill` 또는 CSS 로 폭이 뷰포트보다 작은 이미지(카드 그리드, 썸네일)
- 신호: 3열 그리드 썸네일인데 Network 에서 `w=1920`/`w=3840` 요청, LCP 이미지 바이트 과다
- 메커니즘: `sizes` 가 없으면 브라우저는 이미지가 뷰포트 전체 폭이라고 가정. 또 `sizes` 유무로 srcset 생성 방식이 달라진다 — 없으면 1x/2x 제한 srcset, 있으면 640w/750w… 전체 폭 기반 srcset
- 처방: 실제 레이아웃 폭을 `sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"` 처럼 명시
- 반례: 고정 크기(아이콘·아바타 48px)는 width/height 만으로 충분 — sizes 를 붙이면 오히려 큰 srcset 이 생성
- 검증: DevTools Network 의 `w=` 파라미터와 렌더 크기 × DPR 비교, Lighthouse "Properly size images"
- 근거: `image.md#sizes`

### WEB-IMG-02 · LCP 이미지 우선 로딩 — 16 에서 priority 는 deprecated, fetchPriority="high" 만으로는 lazy 가 풀리지 않는다
- 적용: 히어로/첫 화면 최대 이미지. Next 16+ (15 이하는 `priority`)
- 신호: LCP 요소가 이미지인데 기본 `loading="lazy"`; 반대로 여러 이미지에 우선순위를 남발
- 메커니즘: 기본 lazy 는 LCP 를 늦춘다. `preload` 는 `<head>` 에 `<link rel=preload>` 삽입 — 뷰포트에 따라 LCP 후보가 여럿이면 둘 다 받아 낭비. `loading`/`fetchPriority` 와 함께 쓰지 않는다. 문서는 대부분 경우 `loading="eager"` 또는 `fetchPriority="high"` 를 권장하지만, 소스상 lazy 해제 조건은 `!priority && !preload && loading 미지정|lazy` 뿐이라 `fetchPriority` 단독이면 `loading="lazy"` 가 그대로 남는다(레이아웃 후에야 요청 시작 → 프리로드 스캐너가 조기 발견 못 함)
- 처방: 단일 히어로 → `loading="eager" fetchPriority="high"`(또는 `preload` 단독); 반응형(art direction)으로 서로 다른 이미지가 LCP 가 되는 경우만 → `preload`/eager 금지, lazy 유지 + `fetchPriority="high"`(문서가 의도한 유일한 단독 사용처)
- 반례: `fetchPriority="high"` 단독은 lazy 를 유지해 조기 페치되지 않는다 — 단일 히어로에 단독으로 쓰면 효과가 거의 없다. below-the-fold 이미지에 eager 를 주면 대역폭 경쟁으로 LCP 가 더 나빠진다
- 검증: Lighthouse "LCP request discovery", Performance 패널의 LCP 리소스 시작 시각
- 근거: `image.md#preload`, `#priority`(art direction Good to know), version-16.md, `node_modules/next/dist/shared/lib/get-img-props.js`(`isLazy` 계산, 16.2.1·16.3.7 확인)

### WEB-IMG-03 · fill 이미지의 부모 크기 미정 → CLS 또는 0 높이
- 적용: `fill` 사용(원본 크기를 모르는 CMS 이미지)
- 신호: 이미지 로드 시 아래 콘텐츠가 밀림, 이미지가 안 보임(부모 높이 0)
- 메커니즘: `fill` 은 부모를 채우는 절대 배치라 공간 예약은 부모 책임. width/height 를 주는 경우에만 브라우저가 aspect-ratio 로 공간을 예약
- 처방: 부모에 `position: relative` + 명시 크기 또는 `aspect-ratio`. 크기를 아는 이미지는 `fill` 대신 width/height
- 반례: 없음
- 검증: Lighthouse CLS "Layout shift culprits", Performance 패널 Layout Shift 트랙
- 근거: `image.md#width-and-height`, `#fill`

### WEB-IMG-04 · 셀프호스팅 이미지 최적화는 앱 파드의 CPU·메모리를 쓴다
- 적용: k8s/VM 에 `next start` 로 배포, `next/image` 기본 로더
- 신호: 이미지 많은 페이지 트래픽에 파드 메모리 상승·OOM, p99 렌더 지연이 이미지 요청과 상관
- 메커니즘: `/_next/image` 변환이 같은 Node 프로세스에서 sharp 로 수행. glibc 리눅스에서는 메모리 할당자 설정이 필요할 수 있다(문서 경고). 16 의 `minimumCacheTTL` 4시간 기본은 재변환을 줄이지만 캐시는 인스턴스 로컬 디스크
- 처방: CDN 캐시 앞단 배치, 또는 외부 이미지 서비스용 `loader`/`loaderFile`. sharp 메모리 문서(링크) 적용 검토. `images.qualities`·`deviceSizes` 를 줄여 변형 수 제한
- 반례: 트래픽이 작으면 기본 로더가 가장 단순
- 검증: 파드 메모리/CPU 와 `/_next/image` 요청률 상관 분석
- 근거: `02-guides/self-hosting.md#image-optimization`(sharp 링크), `03-api-reference/05-config/01-next-config-js/images.md`

## 폰트 (WEB-FONT)

### WEB-FONT-01 · next/font 기본은 display: swap + 자동 폴백 메트릭 보정 — 한글(CJK)에는 보정 효과가 제한될 수 있다
- 적용: `next/font/google`/`next/font/local` 로 한글 웹폰트(Pretendard, Noto Sans KR 등)
- 신호: 폰트 교체 시 문단 줄바꿈이 바뀌어 CLS, 라틴 텍스트는 안정적인데 한글 본문만 흔들림
- 메커니즘: `display` 기본 `'swap'`. `adjustFontFallback` 기본 — google: `true`, local: `'Arial'` — 은 폴백 폰트에 size-adjust 등 메트릭 보정을 건다. Arial 에는 한글 글리프가 없어 한글은 시스템 한글 폰트로 다시 폴백되므로 보정이 한글 폭에 맞지 않을 수 있다(측정으로 확인할 것)
- 처방: CLS 가 측정되면 `display: 'optional'`(첫 방문은 폴백 유지) 검토, 또는 `fallback` 에 시스템 한글 폰트 지정(예: `['Apple SD Gothic Neo', 'Malgun Gothic', 'sans-serif']`) 후 체감 비교
- 반례: 브랜드상 웹폰트가 반드시 첫 페인트에 보여야 하면 `optional` 부적합
- 검증: Performance 패널 Layout Shift 의 원인 노드가 텍스트 블록인지, 느린 3G 스로틀로 재현
- 근거: `font.md#display`, `#adjustfontfallback`, `#fallback`

### WEB-FONT-02 · 같은 폰트 함수를 여러 파일에서 호출하면 인스턴스가 여러 개 호스팅된다
- 적용: 컴포넌트마다 `const inter = Inter({...})` 를 선언하는 코드베이스
- 신호: 동일 폰트의 woff2 가 해시만 다르게 여러 번 다운로드
- 메커니즘: 폰트 로더 호출 1회 = 호스팅 인스턴스 1개
- 처방: `app/fonts.ts` 같은 정의 파일 하나에서 호출하고 객체를 import. CSS 변수(`variable`)로 노출해 Tailwind 등에서 사용
- 반례: 없음
- 검증: Network 탭 폰트 요청 수
- 근거: `font.md`(font definitions file 설명)

### WEB-FONT-03 · 대용량 CJK 폰트 preload 는 LCP 리소스와 대역폭을 경쟁한다
- 적용: 한글 웹폰트. 로더(`next/font/local` vs `next/font/google`)에 따라 함정 방향이 반대
- 신호: (local) preload 된 폰트 다운로드가 히어로 이미지보다 먼저/동시에 진행되며 LCP 지연. (google) 라틴은 즉시 렌더되는데 한글 본문만 늦게 폰트가 바뀜(swap)·텍스트 LCP 지연
- 메커니즘: next/font 는 기본 `preload: true` 이지만 무엇이 preload 되는지는 로더마다 다르다. **local**: 지정한 파일 전체를 preload — 한글 풀셋(수 MB)·다수 굵기면 LCP 리소스와 대역폭 경쟁. **google**: preload 대상은 `subsets` 로 정해지는데 한글 폰트에는 `korean` 서브셋 항목이 없다(예: Noto Sans KR = cyrillic/latin/latin-ext/vietnamese, Nanum Gothic = latin 뿐) → 한글 unicode-range 조각은 preload 되지 않고 CSS 적용 후에야 발견된다
- 처방: local → 가변 폰트 1개로 굵기 통합, 분할(unicode-range) 배포본 사용, 본문 외 폰트는 `preload: false`. google → 한글 조각이 늦게 오는 것을 전제로 `display`·`fallback` 선택(WEB-FONT-01), 텍스트가 LCP 면 가장 많이 쓰는 굵기만 local 분할 폰트로 전환 검토
- 반례: 텍스트가 LCP 요소인 페이지는 본문 폰트 preload 가 이득일 수 있다 — 측정 후 결정
- 검증: WebPageTest/Performance 패널 워터폴에서 폰트 vs LCP 리소스 순서
- 근거: `font.md#preload`, `#subsets`, `node_modules/next/dist/compiled/@next/font/dist/google/font-data.json`(폰트별 subsets 목록)

## 하이드레이션 (WEB-HYD)

### WEB-HYD-01 · 로캘·타임존 불일치 — 개발 머신과 브라우저가 같아서 로컬에선 재현 안 됨
- 적용: SSR 되는 컴포넌트에서 `toLocaleDateString()`, `Intl.DateTimeFormat`, `new Date().getHours()`
- 신호: 운영(UTC 서버)에서만 hydration error, 날짜가 깜빡이며 바뀜
- 메커니즘: 서버는 서버 로캘/TZ 로, 하이드레이션은 브라우저 로캘로 다시 렌더 → 텍스트 불일치 → React 가 가장 가까운 에러/Suspense 경계까지 클라이언트 재렌더(그 경계 안의 다른 인라인 스크립트 보정까지 유실)
- 처방: 로캘·TZ 를 명시해 서버·클라 동일 출력(`timeZone: 'Asia/Seoul'` 등)이 가능하면 그게 최선. 사용자 로캘이 필요하면 인라인 스크립트로 첫 페인트 전 DOM 보정 + 해당 요소에만 `suppressHydrationWarning`(DOM 이 이김, 한 요소 단위)
- 반례: `useEffect` 후 교체는 에러는 없지만 깜빡임 — 시각적으로 허용될 때만
- 검증: `TZ=UTC LANG=ja_JP.UTF-8 next dev` 로 일부러 불일치 환경에서 실행
- 근거: `02-guides/preventing-flash-before-hydration.md`

### WEB-HYD-03 · 렌더 중 typeof window 분기·localStorage 읽기
- 적용: Client Component 렌더 본문
- 신호: `const isMobile = typeof window !== 'undefined' && window.innerWidth < 768`, `useState(localStorage.getItem(...))`
- 메커니즘: 서버(분기 false)와 클라 첫 렌더(true)가 다른 마크업 → 불일치. lazy initializer 도 하이드레이션 첫 렌더에서 실행된다
- 처방: 외부 저장소는 `useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot)` 로 서버 스냅샷을 명시. 반응형 분기는 CSS 미디어쿼리로. 테마처럼 첫 페인트 전 반영이 필요하면 `<head>` 인라인 스크립트 + `<html suppressHydrationWarning>`. (참고: 카드 전체 클릭 + 내부 링크는 `<a>` 중첩 대신 `::after` stretched link — 중첩 HTML 불일치는 React 19 에러 diff 로 바로 보이므로 별도 항목 없음)
- 반례: 하이드레이션 이후에만 의미 있는 값(예: 측정된 크기)은 effect 에서 설정
- 검증: 하이드레이션 에러 로그, JS 비활성화 렌더와 비교
- 근거: `preventing-flash-before-hydration.md`(themes, persisted UI state), https://react.dev/reference/react/useSyncExternalStore

## 번들 (WEB-BUN)

### WEB-BUN-01 · 16 에서 build 의 First Load JS 표시는 사라졌다 — 분석은 별도 도구로
- 적용: Next 16+(Turbopack 기본), 번들 회귀를 추적하는 팀
- 신호: "빌드 로그에 크기가 안 나온다", CI 번들 예산이 무력화
- 메커니즘: 16 이 해당 지표를 제거. Turbopack 은 `next experimental-analyze`(16.1+, 모듈 그래프 기반 import chain 추적, 서버/클라 모듈 모두), Webpack 빌드는 `@next/bundle-analyzer`
- 처방: `npx next experimental-analyze --output` → `.next/diagnostics/analyze` 를 기준선으로 복사해 PR 전후 비교. 클라이언트에 있어선 안 될 모듈(서버 SDK, 파서, 대형 아이콘 세트)을 import chain 으로 역추적(RSC-BND-01/06)
- 반례: 실험 기능이라 출력 형식이 마이너마다 바뀔 수 있다 — 동봉 문서 확인
- 검증: 분석 산출물 diff + Lighthouse 총 JS 바이트
- 근거: `02-guides/package-bundling.md`, version-16.md `#performance-improvements`

### WEB-BUN-02 · React Compiler 는 16 에서 stable 이지만 기본 off — 켜면 Babel 경유로 빌드가 약간 느려진다
- 적용: Next 16+, 수동 `useMemo`/`useCallback` 이 많은 코드베이스
- 신호: 메모이제이션 누락으로 인한 리렌더 비용, 반대로 메모 남발로 가독성 저하
- 메커니즘: `reactCompiler: true` + `babel-plugin-react-compiler` 로 자동 메모이제이션. 컴파일러가 Babel 플러그인이라 dev·build 시간이 약간 증가한다 — 단 Next 의 SWC 사전 필터가 JSX·Hook 이 있는 파일에만 적용해 영향은 작고 국소적(reactCompiler 문서). 업그레이드 가이드의 "컴파일 시간 증가" 문구만 보고 과대평가하지 말 것
- 처방: 리렌더 비용이 측정된 앱에서 켜고, 빌드 시간 증가를 CI 예산과 비교. 켠 뒤엔 수동 메모를 새로 추가하지 않는 방향
- 반례: 렌더 비용이 문제 아닌 앱은 이득 없이 빌드 시간·Babel 의존만 늘린다
- 검증: React DevTools Profiler 커밋 시간 전후, CI 빌드 시간
- 근거: version-16.md `#react-compiler-support`, `03-api-reference/05-config/01-next-config-js/reactCompiler.md`
