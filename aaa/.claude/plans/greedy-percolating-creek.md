# Plan: search-dictionary → search/dictionary 리팩토링

## Context
검색 관련 뷰를 `search/` 디렉토리에 통합하여 향후 검색 기능(랭킹, 분석 등) 추가 시 확장 가능한 구조로 변경한다. 현재는 dictionary만 존재하며, 뷰 디렉토리와 라우트 경로 모두 변경한다.

## 변경 요약

| 변경 | Before | After |
|------|--------|-------|
| Views | `views/search-dictionary/` | `views/search/dictionary/` |
| Route | `app/(Layout)/search-dictionary/` | `app/(Layout)/search/dictionary/` |
| URL | `/search-dictionary` | `/search/dictionary` |

## 수정 대상 파일 (3개 — import 경로 변경)

1. **`admin/src/views/search-dictionary/index.ts`** → `admin/src/views/search/dictionary/index.ts`로 이동
   - `@/views/search-dictionary/ui/Page` → `@/views/search/dictionary/ui/Page`

2. **`admin/src/app/(Layout)/search-dictionary/page.tsx`** → `admin/src/app/(Layout)/search/dictionary/page.tsx`로 이동
   - `@/views/search-dictionary` → `@/views/search/dictionary`

3. **`admin/src/shared/services/rest/search-admin/mapper.ts`** (이동 없이 import만 수정)
   - `@/views/search-dictionary/model/types` → `@/views/search/dictionary/model/types`

## 이동만 하면 되는 파일 (내부 import 모두 relative path — 수정 불필요)

- `model/types.ts`
- `model/useSearchDictionary.ts`
- `ui/Page.tsx`
- `ui/SearchDictionaryOverview.tsx`
- `ui/SearchDictionaryList.tsx`
- `ui/modal/SearchDictionaryAddModal.tsx`
- `ui/modal/SearchDictionaryEditModal.tsx`

## 변경 불필요 (확인 완료)

- `admin/src/middleware.ts` — `search-admin-api` (API 프록시 경로, 페이지 라우트 아님)
- `admin/next.config.ts` — API rewrite 설정, 페이지 경로와 무관
- `admin/src/shared/services/rest/search-admin/client.ts` — `search-dictionary` 참조 없음

## 실행 순서

### Step 1: 디렉토리 생성
```bash
mkdir -p admin/src/views/search/dictionary/model
mkdir -p admin/src/views/search/dictionary/ui/modal
mkdir -p admin/src/app/(Layout)/search/dictionary
```

### Step 2: 파일 이동
```bash
# Views — git mv로 이력 보존
git mv admin/src/views/search-dictionary/model/types.ts admin/src/views/search/dictionary/model/
git mv admin/src/views/search-dictionary/model/useSearchDictionary.ts admin/src/views/search/dictionary/model/
git mv admin/src/views/search-dictionary/ui/Page.tsx admin/src/views/search/dictionary/ui/
git mv admin/src/views/search-dictionary/ui/SearchDictionaryOverview.tsx admin/src/views/search/dictionary/ui/
git mv admin/src/views/search-dictionary/ui/SearchDictionaryList.tsx admin/src/views/search/dictionary/ui/
git mv admin/src/views/search-dictionary/ui/modal/SearchDictionaryAddModal.tsx admin/src/views/search/dictionary/ui/modal/
git mv admin/src/views/search-dictionary/ui/modal/SearchDictionaryEditModal.tsx admin/src/views/search/dictionary/ui/modal/
git mv admin/src/views/search-dictionary/index.ts admin/src/views/search/dictionary/

# Route
git mv admin/src/app/(Layout)/search-dictionary/page.tsx admin/src/app/(Layout)/search/dictionary/
```

### Step 3: Import 경로 수정 (3개 파일)
위 "수정 대상 파일" 섹션 참고

### Step 4: 빈 디렉토리 정리
```bash
rm -rf admin/src/views/search-dictionary
rm -rf admin/src/app/(Layout)/search-dictionary
```

### Step 5: 잔여 참조 확인
```bash
grep -r "search-dictionary" admin/src/
```
→ 0건이어야 함

## 검증

1. `cd admin && pnpm run build` — 빌드 성공 확인
2. `pnpm run dev` → `/search/dictionary` 접속하여 페이지 정상 렌더링 확인
3. 사전 CRUD 동작 테스트 (목록 조회, 추가, 수정, 삭제)

## 참고 사항

- **메뉴 설정**: 백엔드 Auth 서비스에서 관리하는 메뉴 URL이 `/search-dictionary`로 되어 있다면 별도 업데이트 필요
- **git mv** 사용으로 파일 이력 보존
