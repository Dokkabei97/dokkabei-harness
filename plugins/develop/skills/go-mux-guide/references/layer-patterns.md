# Layer Patterns — Handler / Service / Repository

Go + stdlib `net/http` mux에서 각 계층의 책임과 구현 패턴.

---

## Handler Layer

### 책임
- HTTP 요청 파싱 (path value, query param, body decoding)
- 입력값 검증 위임 (DTO Validate 메서드)
- 적절한 HTTP 상태 코드 반환
- Service 호출 위임
- JSON 직렬화/역직렬화

### 올바른 패턴

```go
package order

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
)

// Handler — HTTP 핸들러 그룹
type Handler struct {
	svc Service
}

func NewHandler(svc Service) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes — Go 1.22+ method-based routing
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/orders", h.List)
	mux.HandleFunc("GET /api/v1/orders/{id}", h.GetByID)
	mux.HandleFunc("POST /api/v1/orders", h.Create)
	mux.HandleFunc("PUT /api/v1/orders/{id}", h.Update)
	mux.HandleFunc("DELETE /api/v1/orders/{id}", h.Delete)
}

// GetByID — 단건 조회 200 OK
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

// List — 목록 조회 + 페이지네이션
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	opts := ListOptions{
		Offset: parseIntDefault(r.URL.Query().Get("offset"), 0),
		Limit:  clamp(parseIntDefault(r.URL.Query().Get("limit"), 20), 1, 100),
	}
	if s := r.URL.Query().Get("status"); s != "" {
		status := OrderStatus(s)
		opts.Status = &status
	}

	resp, err := h.svc.List(r.Context(), opts)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// Create — 생성 201 Created
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

// Update — 수정 200 OK
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

// Delete — 삭제 204 No Content
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

### HTTP 유틸리티 함수

```go
func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(data); err != nil {
		slog.Error("failed to encode response", "error", err)
	}
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]string{
		"error_code": code,
		"message":    message,
	})
}

func decodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

func parseIntDefault(s string, defaultVal int) int {
	if s == "" {
		return defaultVal
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return defaultVal
	}
	return v
}

func clamp(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
```

### 안티패턴

```go
// BAD: Handler에서 비즈니스 로직 수행
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateRequest
	json.NewDecoder(r.Body).Decode(&req) // ❌ 에러 무시

	// ❌ Handler에서 비즈니스 검증
	if req.Amount > 1000000 {
		http.Error(w, "limit exceeded", 400)
		return
	}

	// ❌ Repository 직접 호출
	order := &Order{Name: req.Name, Amount: req.Amount}
	h.repo.Create(r.Context(), order)

	// ❌ Model 직접 반환
	json.NewEncoder(w).Encode(order)
}
```

---

## Service Layer

### 책임
- 비즈니스 로직 수행
- 도메인 검증 (입력 검증과 구분)
- Repository 조합 및 호출
- 도메인 에러 반환 (HTTP 에러가 아닌)
- 트랜잭션 조율 (필요시)

### 올바른 패턴

```go
package order

import (
	"context"
	"fmt"
)

// Service — 비즈니스 로직 인터페이스
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

func (s *service) List(ctx context.Context, opts ListOptions) (*PaginatedResponse, error) {
	orders, total, err := s.repo.FindAll(ctx, opts)
	if err != nil {
		return nil, fmt.Errorf("list orders: %w", err)
	}

	items := make([]OrderResponse, len(orders))
	for i, o := range orders {
		items[i] = *toResponse(&o)
	}

	return &PaginatedResponse{
		Items:   items,
		Total:   total,
		Offset:  opts.Offset,
		Limit:   opts.Limit,
		HasNext: opts.Offset+opts.Limit < total,
	}, nil
}

func (s *service) Create(ctx context.Context, req CreateRequest) (*OrderResponse, error) {
	// DTO 검증
	if err := req.Validate(); err != nil {
		return nil, err
	}

	// 도메인 검증
	// TODO(human): 비즈니스 규칙 검증 (한도, 중복 등)

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

func (s *service) Update(ctx context.Context, id int64, req UpdateRequest) (*OrderResponse, error) {
	order, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("find order: %w", err)
	}
	if order == nil {
		return nil, &NotFoundError{Resource: "order", ID: id}
	}

	// 부분 업데이트 — nil이 아닌 필드만 적용
	if req.Name != nil {
		order.Name = *req.Name
	}
	if req.Amount != nil {
		order.Amount = *req.Amount
	}
	if req.Status != nil {
		// TODO(human): 상태 전이 검증 로직
		order.Status = OrderStatus(*req.Status)
	}

	if err := s.repo.Update(ctx, order); err != nil {
		return nil, fmt.Errorf("update order: %w", err)
	}
	return toResponse(order), nil
}

func (s *service) Delete(ctx context.Context, id int64) error {
	order, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("find order: %w", err)
	}
	if order == nil {
		return &NotFoundError{Resource: "order", ID: id}
	}

	// TODO(human): 삭제 가능 상태 검증

	if err := s.repo.Delete(ctx, id); err != nil {
		return fmt.Errorf("delete order: %w", err)
	}
	return nil
}
```

### 안티패턴

```go
// BAD: Service에서 HTTP 객체 접근
func (s *service) Create(w http.ResponseWriter, r *http.Request, req CreateRequest) {
	// ❌ http.ResponseWriter 직접 사용
	// ❌ http.Request 직접 사용
}

// BAD: Service에서 HTTP 에러 반환
func (s *service) GetByID(ctx context.Context, id int64) (*Order, error) {
	order, err := s.repo.FindByID(ctx, id)
	if order == nil {
		// ❌ HTTP 상태 코드를 Service에서 결정
		return nil, fmt.Errorf("404: order not found")
	}
}

// BAD: 에러 wrapping 없이 반환
func (s *service) Create(ctx context.Context, req CreateRequest) error {
	return s.repo.Create(ctx, order) // ❌ context 없는 에러 메시지
}
```

**규칙:** Service는 `net/http` 패키지를 절대 import하지 않는다.

---

## Repository Layer

### 책임
- 데이터 접근 추상화
- SQL 쿼리 실행
- 스캔 (row → struct 변환)
- 에러 wrapping

### 올바른 패턴

```go
package order

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Repository — 데이터 접근 인터페이스
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
		return nil, nil // not found → nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("query order by id %d: %w", id, err)
	}
	return &o, nil
}

func (r *repository) FindAll(ctx context.Context, opts ListOptions) ([]Order, int, error) {
	// Count query
	countQuery := `SELECT COUNT(*) FROM orders`
	args := []any{}
	whereClause := ""

	if opts.Status != nil {
		whereClause = ` WHERE status = $1`
		args = append(args, *opts.Status)
	}

	var total int
	err := r.db.QueryRowContext(ctx, countQuery+whereClause, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count orders: %w", err)
	}

	// Data query
	dataQuery := `SELECT id, name, amount, status, created_at, updated_at FROM orders`
	dataQuery += whereClause
	dataQuery += ` ORDER BY created_at DESC OFFSET $%d LIMIT $%d`

	paramIdx := len(args) + 1
	dataQuery = fmt.Sprintf(
		`SELECT id, name, amount, status, created_at, updated_at FROM orders`+
			whereClause+
			` ORDER BY created_at DESC OFFSET $%d LIMIT $%d`,
		paramIdx, paramIdx+1,
	)
	args = append(args, opts.Offset, opts.Limit)

	rows, err := r.db.QueryContext(ctx, dataQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("query orders: %w", err)
	}
	defer rows.Close()

	var orders []Order
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.Name, &o.Amount, &o.Status, &o.CreatedAt, &o.UpdatedAt); err != nil {
			return nil, 0, fmt.Errorf("scan order: %w", err)
		}
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate orders: %w", err)
	}

	return orders, total, nil
}

func (r *repository) Create(ctx context.Context, order *Order) error {
	err := r.db.QueryRowContext(ctx,
		`INSERT INTO orders (name, amount, status, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id`,
		order.Name, order.Amount, order.Status, time.Now(), time.Now(),
	).Scan(&order.ID)
	if err != nil {
		return fmt.Errorf("insert order: %w", err)
	}
	order.CreatedAt = time.Now()
	order.UpdatedAt = time.Now()
	return nil
}

func (r *repository) Update(ctx context.Context, order *Order) error {
	order.UpdatedAt = time.Now()
	result, err := r.db.ExecContext(ctx,
		`UPDATE orders SET name = $1, amount = $2, status = $3, updated_at = $4
		 WHERE id = $5`,
		order.Name, order.Amount, order.Status, order.UpdatedAt, order.ID,
	)
	if err != nil {
		return fmt.Errorf("update order %d: %w", order.ID, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("update order %d: no rows affected", order.ID)
	}
	return nil
}

func (r *repository) Delete(ctx context.Context, id int64) error {
	result, err := r.db.ExecContext(ctx, `DELETE FROM orders WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete order %d: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("delete order %d: no rows affected", id)
	}
	return nil
}
```

### Not Found 처리 규칙

```go
// Repository → nil, nil (not found는 에러가 아님)
func (r *repository) FindByID(ctx context.Context, id int64) (*Order, error) {
	// ...
	if err == sql.ErrNoRows {
		return nil, nil  // ✅ not found → nil 반환
	}
}

// Service → 도메인 에러 변환
func (s *service) GetByID(ctx context.Context, id int64) (*OrderResponse, error) {
	order, err := s.repo.FindByID(ctx, id)
	if order == nil {
		return nil, &NotFoundError{Resource: "order", ID: id}  // ✅ 도메인 에러
	}
}

// Handler → HTTP 상태 코드 매핑
func handleServiceError(w http.ResponseWriter, err error) {
	var notFound *NotFoundError
	if errors.As(err, &notFound) {
		writeError(w, http.StatusNotFound, notFound.Code(), notFound.Error())  // ✅ 404
		return
	}
}
```

### rows.Close()와 rows.Err() 패턴

```go
// ✅ GOOD: defer Close + Err 확인
rows, err := r.db.QueryContext(ctx, query, args...)
if err != nil {
	return nil, err
}
defer rows.Close()  // 반드시 defer close

for rows.Next() {
	// scan...
}
if err := rows.Err(); err != nil {  // iteration 중 에러 확인
	return nil, err
}

// ❌ BAD: Close 누락 → 커넥션 누수
rows, _ := r.db.QueryContext(ctx, query)
for rows.Next() {
	// scan...
}
// rows.Close() 빠짐 → connection leak
```

---

## DTO Patterns

### Request/Response 분리

```go
// Create Request — 필수 필드 + 검증
type CreateRequest struct {
	Name   string  `json:"name"`
	Amount float64 `json:"amount"`
}

func (r CreateRequest) Validate() error {
	var errs []string
	if r.Name == "" {
		errs = append(errs, "name is required")
	}
	if len(r.Name) > 100 {
		errs = append(errs, "name must be 100 characters or less")
	}
	if r.Amount <= 0 {
		errs = append(errs, "amount must be positive")
	}
	if len(errs) > 0 {
		return &ValidationError{Errors: errs}
	}
	return nil
}

// Update Request — 모든 필드 포인터 (부분 업데이트)
type UpdateRequest struct {
	Name   *string  `json:"name,omitempty"`
	Amount *float64 `json:"amount,omitempty"`
	Status *string  `json:"status,omitempty"`
}

// Response — Model에서 변환
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
```

### 부분 업데이트 패턴 — 포인터 사용 이유

```go
// *string → JSON "name": null과 field 미전송을 구분
type UpdateRequest struct {
	Name *string `json:"name,omitempty"`
}

// json.Unmarshal 결과:
// {"name": "new"} → Name = &"new"   (업데이트)
// {"name": null}  → Name = nil      (업데이트하지 않음)
// {}              → Name = nil      (업데이트하지 않음)

func (s *service) Update(ctx context.Context, id int64, req UpdateRequest) {
	if req.Name != nil {
		order.Name = *req.Name  // nil이 아닐 때만 업데이트
	}
}
```

---

## Error Handling

### 커스텀 Error 타입

```go
// NotFoundError — 리소스를 찾을 수 없음
type NotFoundError struct {
	Resource string
	ID       int64
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("%s not found: %d", e.Resource, e.ID)
}

func (e *NotFoundError) Code() string {
	return strings.ToUpper(e.Resource) + "_NOT_FOUND"
}

// ValidationError — 입력 검증 실패
type ValidationError struct {
	Errors []string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("validation failed: %s", strings.Join(e.Errors, "; "))
}

// BusinessError — 비즈니스 규칙 위반
type BusinessError struct {
	ErrCode string
	Message string
}

func (e *BusinessError) Error() string { return e.Message }
func (e *BusinessError) Code() string  { return e.ErrCode }
```

### Service → Handler 에러 매핑

```go
func handleServiceError(w http.ResponseWriter, err error) {
	var notFound *NotFoundError
	var validation *ValidationError
	var business *BusinessError

	switch {
	case errors.As(err, &notFound):
		writeError(w, http.StatusNotFound, notFound.Code(), notFound.Error())
	case errors.As(err, &validation):
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", validation.Error())
	case errors.As(err, &business):
		writeError(w, http.StatusUnprocessableEntity, business.Code(), business.Error())
	default:
		slog.Error("unexpected error", "error", err)
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
```

---

## Middleware Pattern

### 미들웨어 시그니처

```go
// 표준 미들웨어 타입
type Middleware func(http.Handler) http.Handler

// 체이닝
func Chain(h http.Handler, mws ...Middleware) http.Handler {
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}

// 사용
mux := http.NewServeMux()
orderHandler.RegisterRoutes(mux)

wrapped := Chain(mux,
	middleware.Recovery,
	middleware.Logging,
	middleware.CORS([]string{"*"}),
)

http.ListenAndServe(":8080", wrapped)
```

### statusWriter — 응답 상태 캡처

```go
type statusWriter struct {
	http.ResponseWriter
	status int
	written bool
}

func (w *statusWriter) WriteHeader(status int) {
	if !w.written {
		w.status = status
		w.written = true
	}
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if !w.written {
		w.status = http.StatusOK
		w.written = true
	}
	return w.ResponseWriter.Write(b)
}
```

---

## Dependency Injection — 생성자 주입

### main.go 와이어링

```go
func main() {
	// Config
	cfg := config.Load()

	// DB
	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Layers — bottom-up
	orderRepo := order.NewRepository(db)
	orderSvc := order.NewService(orderRepo)
	orderHandler := order.NewHandler(orderSvc)

	// Router
	mux := http.NewServeMux()
	orderHandler.RegisterRoutes(mux)

	// Middleware
	handler := middleware.Chain(mux,
		middleware.Recovery,
		middleware.Logging,
	)

	// Server
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      handler,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	slog.Info("server starting", "addr", srv.Addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
```

**DI 규칙:**
- `main.go`에서 모든 의존성을 명시적으로 와이어링
- `New*()` 생성자를 통한 의존성 주입
- 인터페이스를 통해 계층 간 결합
- 글로벌 변수나 `init()` 사용하지 않음
