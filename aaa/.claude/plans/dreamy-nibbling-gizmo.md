# Stitch 디자인 기반 search-admin 페이지 구현 계획

## Context
Stitch MCP의 "search-admin" 프로젝트(ID: `11345063675917554464`)에 있는 6개 visible 스크린을 기반으로, 기존 Next.js 16.1 프로젝트의 페이지를 교체하고 신규 페이지를 추가합니다. 현재 프로젝트는 React 19.2 + Tailwind CSS 4 + TypeScript를 사용하며, App Router 기반입니다.

## Stitch 스크린 → 라우트 매핑

| Stitch Screen | Screen ID | 라우트 | 유형 |
|---|---|---|---|
| 형태소 분석 대시보드 | `b0e36f4` | `/dashboard` | 교체 |
| Commerce 검색엔진 대시보드 | `bf71345` | `/engine-dashboard` | 교체 |
| AI 사전 관리 (배치 테이블) | `5e52c35` | `/ai-dict/review` | 신규 |
| AI 사전 Focused Reviewer | `fc0c8ba` | `/ai-dict/focused` | 교체 |
| AI 사전 Triage (3-column) | `86392e0` | `/ai-dict/triage` | 교체 |
| 시스템 사전 관리 | `91dc5b3` | `/system-dict` | 교체 |

## 구현 순서

### Step 1: Stitch HTML 다운로드 및 분석
각 스크린의 HTML을 WebFetch로 다운로드하여 구조 파악. Stitch HTML은 순수 HTML/CSS이므로 React JSX + Tailwind로 변환 필요.

### Step 2: 공통 컴포넌트 업데이트
Stitch 디자인의 네비게이션 구조에 맞춰 공통 컴포넌트를 업데이트합니다.

**수정 파일:**
- `src/components/Header.tsx` - 탑 네비게이션 (검색엔진 관리 / 형태소 분석 탭)에 실제 라우팅 추가
- `src/components/Sidebar.tsx` - 확장 가능한 메뉴 구조로 변경
  - 형태소 분석 탭: 사전 > 시스템 사전, 사용자 사전, 동의어 사전, 단위명 사전, 복합명사 사전, AI 사전 / 형태소 분석기
  - 검색엔진 관리 탭: 대시보드, 검색 클러스터, 인덱스 관리, 로그 분석
- `src/app/globals.css` - Stitch 디자인 테마에 맞는 추가 스타일 (다크 모드 테마 변수 등)

### Step 3: 기존 페이지 교체 (5개)

각 페이지에서 Stitch HTML을 React 컴포넌트로 변환합니다. 주요 변환 작업:
- HTML → JSX 변환 (className, self-closing tags 등)
- 인라인 스타일 → Tailwind 유틸리티 클래스
- 정적 데이터 → TypeScript 상수/타입 정의
- Header/Sidebar는 layout.tsx에서 제공되므로 메인 콘텐츠 영역만 구현

**수정 파일:**
1. `src/app/dashboard/page.tsx` - 형태소 분석 대시보드
2. `src/app/engine-dashboard/page.tsx` - Commerce 검색엔진 대시보드
3. `src/app/ai-dict/focused/page.tsx` - AI 사전 Focused Reviewer
4. `src/app/ai-dict/triage/page.tsx` - AI 사전 Triage (3-column kanban)
5. `src/app/system-dict/page.tsx` - 시스템 사전 관리

### Step 4: 신규 페이지 추가 (1개)

**생성 파일:**
- `src/app/ai-dict/review/page.tsx` - AI 사전 배치 리뷰 (테이블 기반 일괄 검토)

### Step 5: 홈 페이지 리다이렉트 확인
- `src/app/page.tsx` - 기존 `/dashboard` 리다이렉트 유지

## 변환 원칙
1. Stitch HTML의 레이아웃과 스타일을 **최대한 충실히** 반영
2. Stitch에서 사이드바/헤더는 제거하고 `<main>` 콘텐츠 영역만 페이지에 포함
3. 정적 mock 데이터는 컴포넌트 상단에 TypeScript 상수로 정의
4. 기존 프로젝트의 패턴 유지: `<main className="flex-1 overflow-y-auto bg-[#f5f6f8] p-8">` 래퍼
5. Material Symbols 아이콘 시스템 유지
6. 모든 텍스트는 한국어 유지

## 검증 방법
1. `npm run build` - TypeScript 컴파일 및 빌드 성공 확인
2. `npm run dev` - 개발 서버에서 각 라우트 접근하여 렌더링 확인
3. 각 페이지의 레이아웃이 Stitch 스크린샷과 일치하는지 시각적 비교
4. Sidebar/Header 네비게이션의 라우팅이 정상 동작하는지 확인
