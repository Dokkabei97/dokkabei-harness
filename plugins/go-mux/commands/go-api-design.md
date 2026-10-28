---
name: go-api-design
description: |
  Go stdlib mux REST API 설계 및 구현. 요구사항을 기반으로 API 엔드포인트를 설계하고, Handler + DTO + 에러 핸들링 + 미들웨어 코드를 생성한다.
  Designs and implements REST APIs for Go stdlib net/http mux projects: turns requirements into endpoint designs and generates Handler + DTO + error handling + middleware code. Use when: designing a new Go REST API, adding or refactoring endpoints, deciding response/error formats, or structuring middleware chains and auth in a Go stdlib mux project.
disable-model-invocation: true
---

# /go-api-design - Go REST API 설계 및 구현

## When to Use
- Go stdlib mux 프로젝트에서 새로운 API 엔드포인트를 설계해야 할 때 (`/go-api-design` 직접 호출 — 자연어 요청은 `go-mux-developer` 에이전트·`go-mux-guide` 스킬이 담당)
- 기존 Go API를 리팩토링하거나 버전업할 때
- API 응답 형식이나 에러 처리 전략을 결정해야 할 때
- 미들웨어 체인이나 인증 구조를 설계해야 할 때

## Usage
```
/go-api-design [도메인 또는 요구사항]

Options:
  --version      API 버전 (기본: v1)
  --auth         인증 방식 (jwt, api-key, session)
  --pagination   cursor | offset (기본: offset)
  --middleware    포함할 미들웨어 (logging, recovery, cors, auth)
```

## Behavioral Flow

### Phase 1: API 요구사항 분석
도메인 요구사항을 REST 리소스와 동작으로 매핑한다.

**Steps:**
1. **Resource Identification**: 핵심 리소스 식별 및 관계 매핑
   - 명사 추출 → REST 리소스 후보
   - 1:N, N:M 관계 → 중첩 리소스 여부 결정
2. **Operation Mapping**: CRUD + 커스텀 동작을 HTTP 메서드에 매핑
   - 표준 CRUD → GET, POST, PUT, PATCH, DELETE
   - 커스텀 동작 → POST `/resources/{id}/actions/{action}`
3. **Convention Check**: 기존 프로젝트 API 패턴 분석
   - URL 구조, 응답 형식, 페이지네이션, 에러 형식

### Phase 2: API 명세 설계
엔드포인트 목록, 요청/응답 스키마, 에러 코드를 정의한다.

**Steps:**
1. **Endpoint Design**: URL, HTTP Method, 상태 코드 정의
2. **Schema Design**: Request/Response struct 설계
3. **Error Design**: 에러 응답 형식 및 에러 코드 체계
4. **Middleware Design**: 미들웨어 체인 구성

**API Design Checklist:**

| 원칙 | 체크 항목 | 올바른 예시 |
|------|----------|------------|
| 리소스 명명 | 복수형 명사, kebab-case | `/api/v1/order-items` |
| HTTP 메서드 | 의미에 맞는 메서드 | GET=조회, POST=생성, PUT=전체수정, DELETE=삭제 |
| 상태 코드 | 적절한 HTTP 상태 코드 | 200, 201, 204, 400, 404, 409, 422 |
| 페이지네이션 | 일관된 페이지네이션 | `?offset=0&limit=20` |
| 필터링 | 쿼리 파라미터로 필터 | `?status=ACTIVE&category=FOOD` |
| 버전 관리 | URL path 기반 버전 | `/api/v1/...` |
| 에러 응답 | 일관된 에러 JSON | `{"error_code":"...","message":"..."}` |

### Phase 3: 코드 생성
설계를 기반으로 Handler, DTO, Error, Middleware 코드를 생성한다.

**Steps:**
1. **Handler**: HTTP handler 함수/메서드 구현
2. **DTO**: Request/Response struct + Validate() 메서드
3. **Error Handling**: Custom error types + error response helpers
4. **Middleware**: Logging, Recovery, CORS, Auth 미들웨어
5. **API Spec Summary**: 생성된 엔드포인트 명세표

## Tool Coordination
- **Glob**: 기존 Handler, DTO, Error 파일 탐색
- **Read**: 기존 API 패턴 분석 (URL 구조, 응답 형식, 에러 형식)
- **Grep**: URL 매핑 패턴, `HandleFunc`, error 패턴 검색
- **Write**: Handler, DTO, Error, Middleware 파일 생성
- **Bash**: 빌드 검증

## Examples

### Basic Usage
```
/go-api-design 주문 관리
# 주문 CRUD API 설계 및 구현
# → handler.go, dto.go, errors.go, middleware.go
```

### Custom Operations
```
/go-api-design 결제 처리
# POST /api/v1/payments          — 결제 요청
# POST /api/v1/payments/{id}/cancel — 결제 취소
# GET  /api/v1/payments/{id}/status — 결제 상태 조회
```

### With Middleware
```
/go-api-design 사용자 관리 --middleware logging,recovery,auth
# 미들웨어 체인이 포함된 사용자 관리 API
```

## Generated Code Patterns

코드 템플릿은 중복 관리하지 않는다 — 생성 시 아래 레퍼런스를 읽고 **프로젝트 기존 컨벤션이 있으면 그쪽을 우선**한다.

| 생성물 | 기준 레퍼런스 (`go-mux:go-mux-guide`) |
|--------|----------------------------------------|
| 라우트 등록(`RegisterRoutes`, Go 1.22 패턴), CRUD 핸들러 | `references/layer-patterns.md` → Handler Layer |
| `writeJSON`/`writeError`/`decodeJSON`(바디 상한·후행 데이터 거부) | `references/layer-patterns.md` → HTTP 유틸리티 함수 |
| 커스텀 에러 타입, Service→Handler 에러 매핑 | `references/layer-patterns.md` → Error Handling |
| 미들웨어 Chain·Logging·Recovery·CORS·statusWriter, 서버 와이어링 | `references/layer-patterns.md` → Middleware Pattern, Dependency Injection |

생성 코드에 기본 반영할 스페셜리스트 항목(비용 없는 처방만): GO-HTTP-05(서버 타임아웃), GO-HTTP-06(바디 상한),
GO-HTTP-07(패턴 충돌·`{$}`·405), GO-HTTP-08(메트릭 라벨은 `r.Pattern`), GO-HTTP-11(인코딩 후 헤더 기록),
GO-CON-12(핸들러가 띄운 고루틴 recover), 쿠키 세션이면 GO-HTTP-12(`http.CrossOriginProtection`).

### 커서 기반 페이지네이션 (`--pagination cursor`)

layer-patterns 에 없는 부분만 둔다. 커서는 정렬 키(예: `created_at`, `id`)를 인코딩한 불투명 문자열이고, 조회는 keyset 조건으로 한다(OFFSET 금지).

```go
type CursorPageResponse[T any] struct {
	Items      []T    `json:"items"` // 빈 결과도 [] 로 — make([]T, 0, n) 로 초기화 (GO-SLC-09)
	NextCursor string `json:"next_cursor,omitempty"`
	HasNext    bool   `json:"has_next"`
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit := clamp(parseIntDefault(q.Get("limit"), 20), 1, 100)

	resp, err := h.svc.ListByCursor(r.Context(), q.Get("cursor"), limit)
	if err != nil {
		handleServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// Repository: limit+1 개를 읽어 HasNext 판정
// WHERE (created_at, id) < ($1, $2) ORDER BY created_at DESC, id DESC LIMIT $3
```

## Output — API Spec Summary

생성 완료 후 아래 형식의 명세표를 출력한다:

```
## API Endpoints

| Method | URL | Description | Status |
|--------|-----|-------------|--------|
| GET | /api/v1/orders | 주문 목록 조회 (페이지네이션) | 200 |
| GET | /api/v1/orders/{id} | 주문 단건 조회 | 200, 404 |
| POST | /api/v1/orders | 주문 생성 | 201, 400 |
| PUT | /api/v1/orders/{id} | 주문 수정 | 200, 404, 400 |
| DELETE | /api/v1/orders/{id} | 주문 삭제 | 204, 404 |
| POST | /api/v1/orders/{id}/confirm | 주문 확정 | 200, 404, 409 |
| POST | /api/v1/orders/{id}/cancel | 주문 취소 | 200, 404, 409 |
```

## Boundaries

**Will:**
- RESTful 원칙에 따른 API 설계
- Go stdlib `net/http` 패턴으로 일관된 핸들러 구현
- 일관된 에러 응답 형식과 커스텀 에러 타입
- 미들웨어 체인 구성 (logging, recovery, CORS, auth)
- 기존 프로젝트 API 패턴과 일관성 유지
- `context.Context` 전파 보장
- API 명세표 출력

**Will Not:**
- 비즈니스 로직 구현 (Service 계층에 위임)
- 인증/인가 로직 직접 구현 (미들웨어에 위임)
- DB 스키마 변경
- 외부 라우터 프레임워크 사용 (chi, gin, gorilla)
- OpenAPI 스펙 파일 직접 생성
