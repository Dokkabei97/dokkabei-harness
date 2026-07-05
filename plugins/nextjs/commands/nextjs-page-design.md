---
name: nextjs-page-design
description: |
  Next.js 페이지/기능 UI 설계 및 컴포넌트 분해. 요구사항을 분석하여 컴포넌트 트리, Server/Client 경계, 데이터 흐름, 라우트 구조를 설계하고 스캐폴딩한다.
  Designs Next.js page/feature UI and decomposes it into components — analyzes requirements to design the component tree, Server/Client Component boundaries, data flow, and route structure, then scaffolds them. Use when: designing the UI structure of a new page or feature, breaking a complex feature into components, restructuring an existing Next.js page.
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /nextjs-page-design - Next.js 페이지 UI 설계

## Triggers
- 새로운 기능이나 페이지의 전체 UI 구조를 설계할 때
- "대시보드 페이지 설계해줘", "상품 검색 기능 구조 잡아줘"
- 복잡한 기능의 컴포넌트 분해가 필요할 때
- 기존 페이지를 리팩토링할 때 구조를 재설계할 때

## Usage
```
/nextjs-page-design [기능명] [options]

Options:
  --responsive     반응형 브레이크포인트 전략 포함 (sm/md/lg/xl)
  --skeleton       로딩 스켈레톤 UI 설계 포함
  --error-boundary 에러 바운더리 전략 포함
  --route          라우트 경로 지정 (e.g., "dashboard", "products/[id]/edit")
  --data           데이터 소스 명시 (e.g., "REST /api/products", "Server Action")
```

## Behavioral Flow

### Phase 1: Requirements Analysis
요구사항을 분석하여 기능 범위를 정의한다.

**Steps:**
1. **Parse**: 사용자 요구사항에서 핵심 기능과 UI 요소 추출
2. **Scan**: 기존 프로젝트의 유사 페이지/컴포넌트 탐색
   - `app/` 디렉토리 구조 파악
   - 기존 컴포넌트 라이브러리 확인 (`components/ui/`, shadcn/ui)
   - 기존 데이터 페칭 패턴 확인
   - 기존 레이아웃 구조 확인
3. **Identify**: 재사용 가능한 기존 컴포넌트 목록화

### Phase 2: Component Decomposition
기능을 컴포넌트 트리로 분해한다.

**Steps:**
1. **Component Tree**: 페이지를 컴포넌트 트리로 분해
   - 각 컴포넌트의 책임 정의
   - Server/Client Component 경계 결정
   - Props interface 설계
2. **Data Flow**: 데이터 흐름 설계
   - 어떤 컴포넌트가 데이터를 fetch하는가
   - Props vs Context vs URL State vs Global State
   - Server Action mutation 흐름
3. **Route Structure**: 라우트 파일 구조 설계
   - page.tsx, layout.tsx, loading.tsx, error.tsx 배치
   - Route groups, parallel routes 필요 여부
   - _components/, _actions/, _lib/ colocation

### Phase 3: Design Output
설계 결과를 구조화된 포맷으로 출력한다.

**Output Sections:**
1. **Component Tree Diagram**: ASCII 트리 + Server/Client 표기
2. **File Structure**: 생성될 파일 목록과 위치
3. **Component Specs**: 각 컴포넌트의 props, 책임, 타입
4. **Data Flow Diagram**: 데이터 소스 → 컴포넌트 흐름
5. **State Management Plan**: 상태 관리 전략
6. **Responsive Strategy**: 반응형 브레이크포인트 (--responsive)
7. **Loading Strategy**: 스켈레톤 UI 계획 (--skeleton)
8. **Error Strategy**: 에러 처리 계획 (--error-boundary)

### Phase 4: Scaffolding
설계를 기반으로 파일 구조와 인터페이스를 스캐폴딩한다.

**Steps:**
1. 디렉토리 구조 생성
2. 각 컴포넌트의 파일 생성 (인터페이스 + TODO 마커)
3. TypeScript 타입/인터페이스 정의
4. page.tsx, layout.tsx, loading.tsx, error.tsx 생성
5. 타입 체크 실행 (`npx tsc --noEmit`)

공식 `frontend-design` 스킬(anthropics/skills — 'AI 티 나는 밋밋한 UI' 방지)이 설치되어 있으면 스캐폴딩된 컴포넌트의 시각 스타일링 단계에서 스킬 가이드를 조합 적용한다. 미설치 시 기존 동작을 유지한다(graceful degrade).

## Tool Coordination
- **Glob**: 기존 프로젝트 구조, 재사용 가능 컴포넌트 탐색
- **Read**: 기존 컴포넌트/페이지 패턴 분석, 기존 타입 확인
- **Grep**: UI 라이브러리, 상태 관리, 데이터 페칭 패턴 확인
- **Write**: 새 파일 생성 (컴포넌트, 타입, 페이지)
- **Edit**: 기존 파일 수정 (필요시)
- **Bash**: TypeScript 타입 체크, 린트
- **frontend-design 스킬** (선택): 시각 스타일링 단계에서 조합 활용 — 설치: `/plugin install frontend-design@claude-plugins-official` (미설치 시 생략)

## Examples

### Dashboard Page
```
/nextjs-page-design Dashboard --responsive --skeleton --error-boundary
# 대시보드 페이지 전체 설계
# → 컴포넌트 트리, 파일 구조, 데이터 흐름, 반응형 전략 출력
# → app/dashboard/ 하위 파일 스캐폴딩
```

### Product Search Feature
```
/nextjs-page-design ProductSearch --route "products" --data "REST /api/products"
# 상품 검색/필터/목록 기능 설계
# → SearchBar(Client), FilterPanel(Client), ProductGrid(Server), Pagination(Client)
```

### Multi-step Form
```
/nextjs-page-design OrderCheckout --route "checkout" --error-boundary
# 주문 체크아웃 다단계 폼 설계
# → StepIndicator, ShippingForm, PaymentForm, OrderSummary, ConfirmDialog
```

## Design Output Format

```markdown
# Page Design: [기능명]

## Component Tree
​```
Page (Server) ─── app/[route]/page.tsx
├── Header (Server)
│   ├── Title
│   └── ActionButtons (Client) ─── onClick handlers
├── Suspense [fallback=<ContentSkeleton />]
│   └── Content (Server) ─── async data fetch
│       ├── FilterBar (Client) ─── useState, onChange
│       ├── ItemGrid (Server) ─── props from parent
│       │   └── ItemCard (Server) ─── display only
│       └── Pagination (Client) ─── useSearchParams
└── Sidebar (Server)
    └── QuickActions (Client) ─── onClick handlers
​```

## File Structure
​```
app/[route]/
├── page.tsx              # Server — 메인 페이지
├── layout.tsx            # Server — 공유 레이아웃
├── loading.tsx           # Server — 로딩 스켈레톤
├── error.tsx             # Client — 에러 바운더리
├── _components/
│   ├── content.tsx       # Server — 데이터 페칭 + 렌더
│   ├── filter-bar.tsx    # Client — 필터 상태 관리
│   ├── item-grid.tsx     # Server — 아이템 그리드
│   ├── item-card.tsx     # Server — 아이템 카드
│   ├── pagination.tsx    # Client — 페이지네이션
│   └── content-skeleton.tsx  # Server — 스켈레톤 UI
├── _actions/
│   └── update-item.ts    # Server Action
└── _lib/
    └── types.ts          # 공유 타입 정의
​```

## Component Specs

| Component | Type | Props | Responsibility |
|-----------|------|-------|----------------|
| Content | Server (async) | — | 데이터 fetch + 자식에 전달 |
| FilterBar | Client | onFilter: (filters) => void | 필터 상태 관리 + URL 동기화 |
| ItemGrid | Server | items: Item[] | 아이템 그리드 렌더링 |
| Pagination | Client | totalPages: number | 페이지 전환 + URL 동기화 |

## Data Flow
​```
[Database/API]
    ↓ fetch (Server Component)
Content (Server)
    ↓ props
ItemGrid (Server) → ItemCard (Server)
    
FilterBar (Client) → useSearchParams → URL → page.tsx re-render
Pagination (Client) → useSearchParams → URL → page.tsx re-render
​```

## State Management
| State | Type | Location | Reason |
|-------|------|----------|--------|
| Filter values | URL | useSearchParams | 공유 가능, 새로고침 유지 |
| Current page | URL | useSearchParams | 북마크 가능 |
| Sort order | URL | useSearchParams | SSR 호환 |
| Selected items | Client | useState | 임시, 공유 불필요 |

## Responsive Strategy (--responsive)
| Breakpoint | Layout | Notes |
|------------|--------|-------|
| sm (640px) | 1 column, stacked | 모바일 우선 |
| md (768px) | 2 columns grid | 태블릿 |
| lg (1024px) | 3 columns + sidebar | 데스크톱 |
| xl (1280px) | 4 columns + sidebar | 와이드 |

## Loading Strategy (--skeleton)
| Component | Skeleton | Priority |
|-----------|----------|----------|
| Content | ContentSkeleton (grid placeholder) | High — loading.tsx |
| FilterBar | 3 skeleton rectangles | Medium — inline |
| ItemCard | Image + 2 text lines placeholder | High — grid child |
```

## Boundaries

**Will:**
- 요구사항을 분석하여 컴포넌트 트리로 분해
- Server/Client Component 경계를 명확히 설계
- 데이터 흐름과 상태 관리 전략 제시
- 재사용 가능한 기존 컴포넌트 활용 제안
- 파일 구조와 인터페이스 스캐폴딩 (stub 코드)
- 반응형, 로딩, 에러 전략 설계 (옵션 시)
- 타입/인터페이스 정의 생성

**Will Not:**
- 전체 비즈니스 로직 구현 (TODO(human) 마커 사용)
- API 라우트나 백엔드 로직 설계
- 기존 파일을 무단 수정
- 디자인 시스템이나 브랜드 가이드라인 생성
- 구체적인 픽셀 단위 레이아웃 명세 (CSS framework에 위임)
- 프로젝트에 없는 의존성 추가
