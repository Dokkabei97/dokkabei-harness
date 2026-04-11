---
name: go-gen
description: "Go stdlib mux CRUD 계층 코드 생성. 도메인명을 입력하면 Model, Repository, Service, Handler, DTO, Test를 프로젝트 컨벤션에 맞춰 자동 생성한다."
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /go-gen - Go stdlib mux CRUD 코드 생성

## Triggers
- 새로운 도메인 모델의 CRUD 코드가 필요할 때
- "Order 핸들러 만들어줘", "Product CRUD 생성해줘"
- 기존 Go 프로젝트에 새 도메인 계층을 추가할 때
- Go stdlib mux 프로젝트에서 표준 계층 구조를 스캐폴딩할 때

## Usage
```
/go-gen [도메인명] [options]

Options:
  --fields       필드 정의 (e.g., "Name:string, Price:float64, Status:OrderStatus")
  --layers       생성할 계층 선택 (e.g., "model,repo,service,handler")
  --no-test      테스트 코드 생성 생략
  --db           DB 드라이버 (pgx, sqlx, database-sql) (기본: 프로젝트 감지)
  --soft-delete  soft delete 패턴 적용 (DeletedAt 필드 + WHERE)
  --audit        Audit 필드 자동 포함 (CreatedAt, UpdatedAt)
```

## Behavioral Flow

### Phase 1: Discovery
프로젝트 구조와 기존 코드 컨벤션을 분석한다.

**Steps:**
1. **Scan**: `go.mod`, `main.go`, 프로젝트 디렉토리 구조 스캔
2. **Analyze**: 기존 Handler, Service, Repository 파일을 읽어 패턴 추출
   - 패키지 구조 (`internal/order/` vs `pkg/handler/`)
   - Handler 패턴 (함수 기반 vs 구조체 메서드)
   - DB 드라이버 (database/sql, pgx, sqlx)
   - 에러 핸들링 패턴 (custom error types, error wrapping)
   - 테스트 프레임워크 (stdlib only vs testify)
   - DI 패턴 (constructor injection, wire, manual)
3. **Classify**: 프로젝트 타입 결정
   - stdlib mux vs chi vs gin
   - database/sql vs pgx vs sqlx
   - flat structure vs standard layout (`internal/`, `cmd/`)

### Phase 2: Generation
도메인 모델 정의를 기반으로 전체 계층 코드를 생성한다.

**Steps:**
1. **Model**: Go struct with DB tags, JSON tags
2. **Repository**: Interface + implementation with SQL queries
3. **Service**: Interface + implementation with business logic placeholders
4. **DTO**: Request/Response structs with JSON tags, validation methods
5. **Handler**: HTTP handler functions/methods with routing setup
6. **Test**: Unit (mock interface) + Integration (httptest) tests

**Generation Rules:**
- Bottom-up 순서: Model → Repository → Service → Handler
- 각 계층은 인터페이스를 통해 아래 계층에만 의존
- DTO는 Model과 분리 (API 계약과 도메인 모델 독립)
- 테스트는 각 계층별로 적합한 수준으로 생성
- 비즈니스 로직이 필요한 부분은 `// TODO(human)` 마커 사용

### Phase 3: Verification
생성된 코드가 컴파일되고 테스트가 통과하는지 검증한다.

**Steps:**
1. **Build**: `go build ./...` 실행
2. **Vet**: `go vet ./...` 실행
3. **Test**: 생성된 테스트 실행 `go test ./internal/order/... -v`
4. **Report**: 생성 결과 요약 출력

## Tool Coordination
- **Glob**: 프로젝트 구조 파악, 기존 파일 탐색
- **Read**: 기존 코드 패턴 분석, go.mod 의존성 확인
- **Grep**: 기존 컨벤션 추출 (import, package, handler 패턴)
- **Write**: 새 파일 생성
- **Edit**: 기존 파일 수정 (라우팅 등록 등)
- **Bash**: 빌드, 테스트 실행, 린트 검사

## Examples

### Basic Usage
```
/go-gen Order
# Order 도메인의 전체 CRUD 계층 생성
# → model.go, repository.go, service.go, handler.go, dto.go, *_test.go
```

### With Fields
```
/go-gen Product --fields "Name:string, Price:float64, Category:string, Stock:int"
# 필드가 정의된 Product 도메인 전체 계층 생성
```

### Specific Layers Only
```
/go-gen Payment --layers "model,repo,service"
# Handler 없이 Model, Repository, Service만 생성
```

### Soft Delete + Audit
```
/go-gen Member --soft-delete --audit
# soft delete (DeletedAt) + audit (CreatedAt, UpdatedAt) 패턴 적용
```

## Generated Code Patterns

### Model
```go
package order

import "time"

type Order struct {
	ID        int64       `json:"id" db:"id"`
	Name      string      `json:"name" db:"name"`
	Amount    float64     `json:"amount" db:"amount"`
	Status    OrderStatus `json:"status" db:"status"`
	CreatedAt time.Time   `json:"created_at" db:"created_at"`
	UpdatedAt time.Time   `json:"updated_at" db:"updated_at"`
}

type OrderStatus string

const (
	OrderStatusCreated   OrderStatus = "CREATED"
	OrderStatusConfirmed OrderStatus = "CONFIRMED"
	OrderStatusShipped   OrderStatus = "SHIPPED"
	OrderStatusDelivered OrderStatus = "DELIVERED"
	OrderStatusCancelled OrderStatus = "CANCELLED"
)
```

### Repository
```go
package order

import (
	"context"
	"database/sql"
	"fmt"
)

type Repository interface {
	FindByID(ctx context.Context, id int64) (*Order, error)
	FindAll(ctx context.Context, opts ListOptions) ([]Order, int, error)
	Create(ctx context.Context, order *Order) error
	Update(ctx context.Context, order *Order) error
	Delete(ctx context.Context, id int64) error
}

type repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) Repository {
	return &repository{db: db}
}

func (r *repository) FindByID(ctx context.Context, id int64) (*Order, error) {
	var o Order
	err := r.db.QueryRowContext(ctx,
		`SELECT id, name, amount, status, created_at, updated_at
		 FROM orders WHERE id = $1`, id,
	).Scan(&o.ID, &o.Name, &o.Amount, &o.Status, &o.CreatedAt, &o.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("find order by id: %w", err)
	}
	return &o, nil
}

func (r *repository) Create(ctx context.Context, order *Order) error {
	err := r.db.QueryRowContext(ctx,
		`INSERT INTO orders (name, amount, status, created_at, updated_at)
		 VALUES ($1, $2, $3, NOW(), NOW())
		 RETURNING id, created_at, updated_at`,
		order.Name, order.Amount, order.Status,
	).Scan(&order.ID, &order.CreatedAt, &order.UpdatedAt)
	if err != nil {
		return fmt.Errorf("create order: %w", err)
	}
	return nil
}
```

### Service
```go
package order

import (
	"context"
	"fmt"
)

type Service interface {
	GetByID(ctx context.Context, id int64) (*OrderResponse, error)
	List(ctx context.Context, opts ListOptions) (*PaginatedResponse, error)
	Create(ctx context.Context, req CreateRequest) (*OrderResponse, error)
	Update(ctx context.Context, id int64, req UpdateRequest) (*OrderResponse, error)
	Delete(ctx context.Context, id int64) error
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) GetByID(ctx context.Context, id int64) (*OrderResponse, error) {
	order, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get order: %w", err)
	}
	if order == nil {
		return nil, &NotFoundError{Resource: "order", ID: id}
	}
	return toResponse(order), nil
}

func (s *service) Create(ctx context.Context, req CreateRequest) (*OrderResponse, error) {
	if err := req.Validate(); err != nil {
		return nil, fmt.Errorf("validate: %w", err)
	}
	order := &Order{
		Name:   req.Name,
		Amount: req.Amount,
		Status: OrderStatusCreated,
	}
	if err := s.repo.Create(ctx, order); err != nil {
		return nil, fmt.Errorf("create order: %w", err)
	}
	return toResponse(order), nil
}
```

### DTO
```go
package order

import (
	"errors"
	"time"
)

type CreateRequest struct {
	Name   string  `json:"name"`
	Amount float64 `json:"amount"`
}

func (r CreateRequest) Validate() error {
	if r.Name == "" {
		return errors.New("name is required")
	}
	if r.Amount <= 0 {
		return errors.New("amount must be positive")
	}
	return nil
}

type UpdateRequest struct {
	Name   *string  `json:"name,omitempty"`
	Amount *float64 `json:"amount,omitempty"`
	Status *string  `json:"status,omitempty"`
}

type OrderResponse struct {
	ID        int64       `json:"id"`
	Name      string      `json:"name"`
	Amount    float64     `json:"amount"`
	Status    OrderStatus `json:"status"`
	CreatedAt time.Time   `json:"created_at"`
	UpdatedAt time.Time   `json:"updated_at"`
}

func toResponse(o *Order) *OrderResponse {
	return &OrderResponse{
		ID:        o.ID,
		Name:      o.Name,
		Amount:    o.Amount,
		Status:    o.Status,
		CreatedAt: o.CreatedAt,
		UpdatedAt: o.UpdatedAt,
	}
}

type ListOptions struct {
	Offset int
	Limit  int
	Status *OrderStatus
}

type PaginatedResponse struct {
	Items   []OrderResponse `json:"items"`
	Total   int             `json:"total"`
	Offset  int             `json:"offset"`
	Limit   int             `json:"limit"`
	HasNext bool            `json:"has_next"`
}
```

### Handler
```go
package order

import (
	"encoding/json"
	"net/http"
	"strconv"
)

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

func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}

	resp, err := h.svc.GetByID(r.Context(), id)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	resp, err := h.svc.Create(r.Context(), req)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, resp)
}
```

### Unit Test (table-driven)
```go
package order

import (
	"context"
	"testing"
)

type mockRepository struct {
	findByIDFn func(ctx context.Context, id int64) (*Order, error)
	createFn   func(ctx context.Context, order *Order) error
}

func (m *mockRepository) FindByID(ctx context.Context, id int64) (*Order, error) {
	return m.findByIDFn(ctx, id)
}

func (m *mockRepository) Create(ctx context.Context, order *Order) error {
	return m.createFn(ctx, order)
}

func TestService_GetByID(t *testing.T) {
	tests := []struct {
		name    string
		id      int64
		mockFn  func(ctx context.Context, id int64) (*Order, error)
		wantErr bool
	}{
		{
			name: "존재하는 주문 반환",
			id:   1,
			mockFn: func(_ context.Context, _ int64) (*Order, error) {
				return &Order{ID: 1, Name: "테스트 주문", Status: OrderStatusCreated}, nil
			},
			wantErr: false,
		},
		{
			name: "존재하지 않으면 NotFoundError",
			id:   999,
			mockFn: func(_ context.Context, _ int64) (*Order, error) {
				return nil, nil
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := NewService(&mockRepository{findByIDFn: tt.mockFn})
			resp, err := svc.GetByID(context.Background(), tt.id)
			if (err != nil) != tt.wantErr {
				t.Errorf("GetByID() error = %v, wantErr %v", err, tt.wantErr)
			}
			if !tt.wantErr && resp.ID != tt.id {
				t.Errorf("GetByID() got ID = %d, want %d", resp.ID, tt.id)
			}
		})
	}
}
```

### Integration Test (httptest)
```go
package order_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandler_Create(t *testing.T) {
	// Setup
	svc := setupTestService(t)
	handler := order.NewHandler(svc)
	mux := http.NewServeMux()
	handler.RegisterRoutes(mux)

	// Request
	body := `{"name":"새 주문","amount":10000}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	// Execute
	mux.ServeHTTP(rec, req)

	// Assert
	if rec.Code != http.StatusCreated {
		t.Errorf("expected status 201, got %d: %s", rec.Code, rec.Body.String())
	}
}
```

## Boundaries

**Will:**
- 프로젝트 기존 컨벤션을 분석하고 정확히 따름
- 전체 CRUD 계층을 일관된 패턴으로 생성
- 입력 검증 로직 포함 (Validate 메서드)
- 적절한 테스트 코드 생성 (단위 + 통합)
- Audit 필드 자동 포함 (프로젝트 패턴에 따라)
- 커스텀 Error 타입 생성
- Go 1.22+ ServeMux 라우팅 패턴 사용

**Will Not:**
- 기존 파일을 무단 수정
- 비즈니스 로직을 임의로 구현 (`// TODO(human)` 마커 사용)
- 프로젝트에 없는 의존성을 요구하는 코드 생성
- 비관용적 Go 코드 생성 (stuttering names, panic for errors 등)
- 불필요한 주석 생성 (Go는 자체 문서화 코드 선호)
- go.mod 의존성 추가 (별도 확인 필요)
