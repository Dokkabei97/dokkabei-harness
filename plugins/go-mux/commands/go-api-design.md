---
name: go-api-design
description: |
  Go stdlib mux REST API 설계 및 구현. 요구사항을 기반으로 API 엔드포인트를 설계하고, Handler + DTO + 에러 핸들링 + 미들웨어 코드를 생성한다.
  Designs and implements REST APIs for Go stdlib net/http mux projects: turns requirements into endpoint designs and generates Handler + DTO + error handling + middleware code. Use when: designing a new Go REST API, adding or refactoring endpoints, deciding response/error formats, or structuring middleware chains and auth in a Go stdlib mux project.
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /go-api-design - Go REST API 설계 및 구현

## Triggers
- Go stdlib mux 프로젝트에서 새로운 API 엔드포인트를 설계해야 할 때
- 기존 Go API를 리팩토링하거나 버전업할 때
- "주문 API 설계해줘", "결제 API 만들어줘" (Go 프로젝트 대상)
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

### Handler — 라우팅 등록
```go
package order

import "net/http"

type Handler struct {
	svc Service
}

func NewHandler(svc Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/orders", h.List)
	mux.HandleFunc("GET /api/v1/orders/{id}", h.GetByID)
	mux.HandleFunc("POST /api/v1/orders", h.Create)
	mux.HandleFunc("PUT /api/v1/orders/{id}", h.Update)
	mux.HandleFunc("DELETE /api/v1/orders/{id}", h.Delete)
}
```

### Handler — CRUD 구현
```go
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "invalid order id")
		return
	}

	resp, err := h.svc.GetByID(r.Context(), id)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	opts, err := parseListOptions(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_PARAMS", err.Error())
		return
	}

	resp, err := h.svc.List(r.Context(), opts)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_BODY", "invalid request body")
		return
	}

	resp, err := h.svc.Create(r.Context(), req)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, resp)
}

func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "invalid order id")
		return
	}

	var req UpdateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_BODY", "invalid request body")
		return
	}

	resp, err := h.svc.Update(r.Context(), id, req)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "invalid order id")
		return
	}

	if err := h.svc.Delete(r.Context(), id); err != nil {
		handleServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
```

### 에러 응답 — JSON 에러 형식
```go
package httputil

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
)

type ErrorResponse struct {
	ErrorCode string `json:"error_code"`
	Message   string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, ErrorResponse{
		ErrorCode: code,
		Message:   message,
	})
}

func decodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

func handleServiceError(w http.ResponseWriter, err error) {
	var notFound *NotFoundError
	var validation *ValidationError
	var conflict *ConflictError

	switch {
	case errors.As(err, &notFound):
		writeError(w, http.StatusNotFound, notFound.Code(), notFound.Error())
	case errors.As(err, &validation):
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", validation.Error())
	case errors.As(err, &conflict):
		writeError(w, http.StatusConflict, conflict.Code(), conflict.Error())
	default:
		slog.Error("unexpected error", "error", err)
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
```

### 커스텀 Error 타입
```go
package order

import "fmt"

type NotFoundError struct {
	Resource string
	ID       int64
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("%s not found: %d", e.Resource, e.ID)
}

func (e *NotFoundError) Code() string {
	return fmt.Sprintf("%s_NOT_FOUND", strings.ToUpper(e.Resource))
}

type ConflictError struct {
	Resource string
	Reason   string
}

func (e *ConflictError) Error() string {
	return fmt.Sprintf("%s conflict: %s", e.Resource, e.Reason)
}

func (e *ConflictError) Code() string {
	return fmt.Sprintf("%s_CONFLICT", strings.ToUpper(e.Resource))
}

type ValidationError struct {
	Field   string
	Message string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("validation failed: %s %s", e.Field, e.Message)
}
```

### 미들웨어 패턴
```go
package middleware

import (
	"log/slog"
	"net/http"
	"time"
)

type Middleware func(http.Handler) http.Handler

// Chain — 미들웨어 체이닝 (왼쪽부터 바깥 → 안쪽)
func Chain(h http.Handler, mws ...Middleware) http.Handler {
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}

// Logging — 요청/응답 로깅
func Logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"duration", time.Since(start),
		)
	})
}

// Recovery — panic 복구
func Recovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				slog.Error("panic recovered", "error", err)
				http.Error(w, "internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// CORS — Cross-Origin Resource Sharing
func CORS(allowedOrigins []string) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			for _, allowed := range allowedOrigins {
				if origin == allowed || allowed == "*" {
					w.Header().Set("Access-Control-Allow-Origin", origin)
					w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
					w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
					break
				}
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}
```

### 커서 기반 페이지네이션
```go
type CursorPageResponse[T any] struct {
	Items      []T    `json:"items"`
	NextCursor string `json:"next_cursor,omitempty"`
	HasNext    bool   `json:"has_next"`
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	cursor := r.URL.Query().Get("cursor")
	limit := parseIntDefault(r.URL.Query().Get("limit"), 20)

	resp, err := h.svc.ListByCursor(r.Context(), cursor, limit)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, resp)
}
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
