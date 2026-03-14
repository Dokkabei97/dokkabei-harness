# Plan: search-admin-ui → shopping-frontend/admin Migration

## Context

search-admin-ui는 ES 사전관리 단일 기능의 독립 Next.js 16 앱(30개 파일). 이를 shopping-frontend/admin(Next.js 15, 40+ 페이지)의 `/search-dictionary` 라우트로 feature merge한다. 핵심 변환: shadcn/ui → Ant Design, Axios → fetch wrapper, FSD 구조 적용.

## 작업 단위 (5 Units)

### Unit 1: Infrastructure + Data Layer
**목표:** 프록시 설정, 환경변수, 타입, REST 클라이언트, mapper, React Query 훅 — 전체 데이터 레이어 완성

**수정 파일:**
- `next.config.ts` — SEARCH_ADMIN_REWRITES 추가
- `.env.development` — `SEARCH_ADMIN_URL=http://localhost:8080`
- `.env.stage` — `SEARCH_ADMIN_URL=http://search-admin-api:8080`
- `.env.production` — `SEARCH_ADMIN_URL=http://search-admin-api:8080`
- `src/middleware.ts` — matcher에 `search-admin-api` 제외 추가

**생성 파일:**
- `src/views/search-dictionary/model/types.ts` — 타입 정의 (SearchDictionary* prefix)
- `src/shared/services/rest/search-admin/client.ts` — fetch wrapper (place/client.ts 패턴)
- `src/shared/services/rest/search-admin/mapper.ts` — 응답 변환
- `src/views/search-dictionary/model/useSearchDictionary.ts` — 6개 React Query 훅

**검증:** `pnpm run build` 통과

---

### Unit 2: Overview Component (shadcn → antd)
**목표:** dictionary-overview.tsx를 antd Table로 변환

**생성 파일:**
- `src/views/search-dictionary/ui/SearchDictionaryOverview.tsx`

**변환 매핑:**
| shadcn | antd |
|--------|------|
| `<Table>` + Header/Body/Row/Cell | antd `<Table columns={...} dataSource={...}>` |
| Checkbox (select-all, individual) | antd `Table.rowSelection` prop |
| `<Badge>` | `<Tag>` |
| `<Button>` | `<Button>` (antd) |
| lucide icons | `@ant-design/icons` |
| `toast.success/error` | `message.success/error` |

**주의:** Worker는 Unit 1의 파일(types, hooks)을 워크트리에 로컬 생성 후, Overview 파일만 커밋

---

### Unit 3: List Component (shadcn → antd)
**목표:** dictionary-list.tsx(540줄)를 antd로 변환, 커서 기반 pagination 보존

**생성 파일:**
- `src/views/search-dictionary/ui/SearchDictionaryList.tsx`

**핵심 변환:**
- shadcn Select → antd `<Select>`
- shadcn Input → antd `<Input.Search>`
- shadcn Checkbox → antd `<Checkbox>`
- shadcn Table → antd `<Table pagination={false}>` (커서 pagination은 커스텀)
- shadcn AlertDialog → `Modal.confirm()`
- lucide icons → `@ant-design/icons`
- `toast` → `message`

**커서 pagination:** antd Table 내장 pagination 사용하지 말 것! 커스텀 이전/다음/처음 버튼 유지
**카테고리별 동적 컬럼:** SET(단어), SYNONYM(방향+대표어+동의어), SPACE(붙여쓴말), COMPOUND(복합어+분해결과)
**Edit mode toggle:** 수정/보기 모드 전환 + 조건부 rowSelection

---

### Unit 4: Modal Components (shadcn → antd)
**목표:** dictionary-dialogs.tsx(750줄)를 antd Modal + Form으로 변환

**생성 파일:**
- `src/views/search-dictionary/ui/modal/SearchDictionaryAddModal.tsx`
- `src/views/search-dictionary/ui/modal/SearchDictionaryEditModal.tsx`

**핵심 변환:**
- shadcn Dialog → antd `<Modal>` + `confirmLoading`
- useState 폼 → antd `Form.useForm()` + `Form.Item` + `rules`
- shadcn RadioGroup → antd `<Radio.Group>`
- shadcn Label/Input → antd `<Form.Item>` + `<Input>`
- shadcn Separator → antd `<Divider>`
- shadcn Alert → antd `<Alert>`
- 검증 로직: antd Form rules + custom validator

**8종 사전별 폼 분기:**
- SET: value만 입력
- SYNONYM: 방향 선택(양방향/단방향) → 폼 필드 변경
- UNIT_SYNONYM: keyword(대상표현) + value(정규화 기호)
- SPACE: keyword(붙여쓴말, 공백불가) + value(분리결과, 2+단어)
- COMPOUND: keyword(복합어) + value(분해결과, 2+단어)

**Preview 컴포넌트:** SynonymPreview, MapPreview를 antd Tag로 변환

---

### Unit 5: Page Assembly + Route Registration
**목표:** 메인 페이지 쉘(사이드바+콘텐츠) + 라우트 등록

**생성 파일:**
- `src/views/search-dictionary/ui/Page.tsx` — 사이드바 네비게이션 + 콘텐츠 영역
- `src/views/search-dictionary/index.ts` — barrel export
- `src/app/(Layout)/search-dictionary/page.tsx` — 라우트 진입점

**Page.tsx 설계:**
- 왼쪽 사이드바: antd `<Menu mode="inline">` (9개 메뉴: 개요 + 8사전)
- 오른쪽 콘텐츠: Overview or List 컴포넌트 조건부 렌더링
- 아이콘: @ant-design/icons 사용
- Layout: `flex h-full gap-4 p-4` (기존 admin 레이아웃 내부)

---

## 공통 코드 컨벤션

```
- Arrow function components (no React.FC, no function keyword)
- No semicolons, single quotes (Prettier)
- interface > type
- @ant-design/icons 사용 (lucide-react 미설치)
- message.success/error (antd, sonner 아님)
- 타입명 SearchDictionary* prefix (기존 dictionary-manage 충돌 방지)
- Query key prefix: 'searchDictionary'
```

## 타입명 매핑

| Source | Target |
|--------|--------|
| DictionaryType | SearchDictionaryType |
| Dictionary | SearchDictionaryEntry |
| DictionaryOverviewItem | SearchDictionaryOverviewItem |
| BackendDictionary | SearchDictionaryBackendDTO |
| BackendCursorResponse | SearchDictionaryCursorResponse |
| CompileResult | SearchDictionaryCompileResult |
| CursorPaginatedResponse | SearchDictionaryCursorPage |
| MenuSection | SearchDictionaryMenuSection |

## REST Client 패턴 (place/client.ts 참조)

```typescript
const SEARCH_ADMIN_BASE_PATH = '/search-admin-api/api'
// searchAdminApi.get/post/put/delete — fetch 기반
// API paths: /v1/dictionary/{type}, /v1/dictionary/compile 등
```

## 파일 트리 (최종)

```
src/
├── app/(Layout)/search-dictionary/page.tsx          [Unit 5]
├── shared/services/rest/search-admin/
│   ├── client.ts                                     [Unit 1]
│   └── mapper.ts                                     [Unit 1]
└── views/search-dictionary/
    ├── index.ts                                      [Unit 5]
    ├── model/
    │   ├── types.ts                                  [Unit 1]
    │   └── useSearchDictionary.ts                    [Unit 1]
    └── ui/
        ├── Page.tsx                                  [Unit 5]
        ├── SearchDictionaryOverview.tsx              [Unit 2]
        ├── SearchDictionaryList.tsx                  [Unit 3]
        └── modal/
            ├── SearchDictionaryAddModal.tsx          [Unit 4]
            └── SearchDictionaryEditModal.tsx         [Unit 4]
```

## 핵심 참조 파일

- `shopping-frontend/admin/src/shared/services/rest/place/client.ts` — REST 클라이언트 패턴
- `shopping-frontend/admin/src/shared/services/rest/billing/client.ts` — REST 클라이언트 패턴
- `shopping-frontend/admin/src/views/dictionary-manage/ui/Page.tsx` — antd 페이지 패턴
- `shopping-frontend/admin/src/views/dictionary-manage/ui/DictionaryManageTable.tsx` — antd Table 패턴
- `search-admin-ui/src/hooks/use-dictionary.ts` — 변환 대상 훅 (6개)
- `search-admin-ui/src/components/dictionary/dictionary-dialogs.tsx` — 변환 대상 모달 (750줄)
- `search-admin-ui/src/components/dictionary/dictionary-list.tsx` — 변환 대상 리스트 (540줄)
- `search-admin-ui/src/components/dictionary/dictionary-overview.tsx` — 변환 대상 개요 (200줄)

## E2E 검증

개별 유닛은 e2e 스킵. 전체 머지 후:
1. `pnpm run build` 통과
2. `pnpm run dev` 후 `/search-dictionary` 접속
3. 개요 테이블 8개 사전 표시 + compile 동작
4. 각 사전 타입별 CRUD + cursor pagination
5. 기존 `/dictionary` 라우트 영향 없음 확인

## Merge 전략

- Unit 1 먼저 머지 (data layer)
- Units 2, 3, 4 병렬 머지 가능 (UI 컴포넌트, 서로 다른 파일)
- Unit 5 마지막 머지 (Page가 다른 컴포넌트 import)
- 모든 머지 후 `pnpm run build` 확인
