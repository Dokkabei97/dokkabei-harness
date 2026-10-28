> [English](README.md) · **한국어**

# nextjs

> Next.js App Router 프론트엔드 코드를 프로젝트 컨벤션에 맞춰 설계·스캐폴딩·생성하는 특화 플러그인.

## 개요

`nextjs`는 Next.js 버전을 단정하지 않고(프로젝트의 `next` 버전과 `node_modules/next/dist/docs/` 동봉 문서(16.2+)를 먼저 확인) App Router 프로젝트에서 관용적이고 성능 최적화된 프론트엔드 코드를 만들기 위한 도구 모음이다. 코드를 쓰기 전에 항상 대상 프로젝트의 구조와 컨벤션(디렉터리 배치, import alias, 스타일링 방식, UI/폼/상태 관리 라이브러리, 테스트 러너)을 먼저 분석하고, 그 위에서 Server/Client Component 경계를 올바르게 잡아 코드를 생성하는 것을 원칙으로 한다.

역할은 세 단계로 나뉜다. 요구사항을 컴포넌트 트리·데이터 흐름·라우트 구조로 설계하는 `/nextjs-page-design`, 이름과 타입만으로 Page·Layout·Loading·Error·Component·Form·Hook·Test를 자동 생성하는 `/nextjs-gen`, 그리고 이 두 커맨드가 실제 코드 생성을 위임하는 `nextjs-developer` 에이전트다. 판단 기준이 필요한 순간에는 `nextjs-guide` 스킬이 강한 시니어도 놓치기 쉬운 스페셜리스트 함정(RSC 직렬화, Server Action 보안, 캐싱 모델, 하이드레이션, CLS/LCP, 셀프호스팅)을 ID 와 함께 제공한다.

설계·생성은 "Server First"(기본은 Server Component, 인터랙션이 필요할 때만 `'use client'`)와 colocation, 타입 안전(Zod + `z.infer`)을 일관되게 따른다. 이 플러그인은 **코드 구조**(Server/Client 경계·라우팅·데이터 페칭·테스트)를 담당하며, 고충실도 시각 스타일링('AI 티 나는 밋밋한 UI' 방지)은 공식 `frontend-design` 스킬 소관으로 경계를 둔다.

## 구성요소

### 커맨드

- `/nextjs-page-design` — 요구사항을 분석해 컴포넌트 트리, Server/Client 경계, 데이터 흐름, 라우트 구조를 설계하고 인터페이스 스텁을 스캐폴딩한다. `--responsive`, `--skeleton`, `--error-boundary`, `--route`, `--data` 옵션으로 반응형·로딩·에러 전략과 라우트/데이터 소스를 지정한다.
- `/nextjs-gen` — 이름과 타입을 입력하면 Page/Layout/Loading/Error/Component/Form/Hook/Test를 프로젝트 컨벤션에 맞춰 생성한다. `--type`, `--client`, `--server-action`, `--style`, `--test`, `--route` 옵션을 지원한다.

### 에이전트

- `nextjs-developer` — Next.js App Router 코드 생성 전문 에이전트. 버전·동봉 문서 확인 → Convention 추출 → 경계·데이터·Server Action 결정 → 코드 생성 → 검증(tsc/lint/test/build)의 5단계 워크플로우로 프로덕션 수준 코드를 만든다. 두 커맨드의 실제 생성 엔진이며 `nextjs-guide` 스킬을 로드한다.

### 스킬

- `nextjs-guide` — 버전 중립 Next.js 스페셜리스트 트리아지. 버전·문서 확인 절차, 증상 → 항목 표, `ID · 적용/신호/메커니즘/처방/반례/검증/근거` 형식 61개 항목(`nextjs-developer` 가 사전 로드).
  - `references/version-16-changes.md` — NX-V16: proxy.ts 개명, 동기 Request API 제거, revalidateTag/updateTag, Turbopack, next/image 기본값.
  - `references/caching-rendering.md` — NX-CACHE: Cache Components vs 이전 모델, `'use cache'` 키·런타임 저장소, Suspense·prefetch.
  - `references/data-waterfall.md` — NX-DATA: 워터폴, preload, 블로킹 layout, 프록시 버퍼링, `useSearchParams`.
  - `references/rsc-boundary.md` — RSC-BND: 클라이언트 모듈 그래프, props 이중 전송·노출, env 오염, 직렬화.
  - `references/server-actions-security.md` — RSC-ACT: 공개 엔드포인트, 왕복 값 불신, 순차 디스패치, Origin 검사, 키·ID 스큐.
  - `references/web-vitals.md` — WEB: 이미지·폰트 CLS/LCP, 하이드레이션 불일치 원인, 번들 분석.
  - `references/self-hosting-ops.md` — NX-OPS: 빌드 시 동결되는 `NEXT_PUBLIC_`, 다중 인스턴스 무효화, 버전 스큐, 종료 드레인.
  - 기존 튜토리얼형 레퍼런스는 `archive/components/nextjs/` 로 이동했다.

## 사용법

커맨드는 `/nextjs-page-design`, `/nextjs-gen`으로 직접 호출한다. 설계가 먼저 필요한 복잡한 기능은 `/nextjs-page-design`으로 구조를 잡은 뒤 `/nextjs-gen`으로 채우는 흐름이 자연스럽다.

```
# 대시보드 페이지 전체 구조 설계 (반응형·스켈레톤·에러 전략 포함)
/nextjs-page-design Dashboard --responsive --skeleton --error-boundary

# 상품 검색 기능 설계 (라우트·데이터 소스 지정)
/nextjs-page-design ProductSearch --route "products" --data "REST /api/products"

# 상품 목록 페이지 전체 생성 (page/loading/error/_components)
/nextjs-gen Products

# 동적 라우트 페이지 생성
/nextjs-gen ProductDetail --route "products/[id]"

# 폼 + Zod 스키마 + Server Action + 테스트 생성
/nextjs-gen CreateProduct --type form --server-action --test

# 커스텀 훅 + 테스트 생성
/nextjs-gen useDebounce --type hook --test
```

두 커맨드는 사용자가 직접 호출할 때만 실행된다(`disable-model-invocation`). `nextjs-guide` 스킬은 Next.js 코드 리뷰·디버깅 맥락에서 쓰이고 `nextjs-developer` 에 사전 로드된다. 생성 후에는 `npx tsc --noEmit`, 프로젝트 lint 스크립트(`next lint` 는 Next 16 에서 제거), 테스트, 라우팅·캐싱 변경 시 `next build` 로 검증한다.

## 참고

- **App Router 중심.** 새 코드는 App Router 기준으로 생성하고, 기존 Pages Router 영역은 요청이 없으면 그대로 둔다.
- **직접 만들지 않는 것:** API 라우트·백엔드 로직, 임의의 비즈니스 로직(대신 `TODO(human)` 마커 삽입), 프로젝트에 없는 의존성을 요구하는 코드. 기존 파일은 명시적 요청 없이 수정하지 않고, 불필요한 `'use client'`를 붙이지 않는다.
- **선택적 연동(설치 시에만, 미설치 시 graceful degrade):** 시각 스타일링은 공식 `frontend-design` 스킬(`/plugin install frontend-design@claude-plugins-official`)과 조합하고, 버전 민감 API(App Router async params, 캐싱 기본값 등)는 backend-shared 플러그인의 Context7 최신 문서 조회 규약(`context7-docs-guide`)을 따른다.
- **함께 쓰면 좋은 것:** 백엔드 API·DB는 `backend-*` 플러그인과 역할을 나눠 쓴다.
