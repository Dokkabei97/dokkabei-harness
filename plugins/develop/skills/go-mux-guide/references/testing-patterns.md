# Testing Patterns — testing, httptest, Table-Driven, Mock

Go + stdlib `net/http` 프로젝트의 테스트 작성 패턴과 전략.

---

## 테스트 피라미드

```
        ╱ E2E ╲               ~5%  — httptest + testcontainers
       ╱ Integration ╲        ~15% — httptest (Handler + Service + DB)
      ╱ Unit Tests    ╲       ~80% — interface mock + table-driven
     ────────────────────
```

| 레벨 | 도구 | 용도 | 속도 |
|------|------|------|------|
| Unit | `testing` + interface mock | Service 비즈니스 로직 | 가장 빠름 |
| Integration | `httptest` | Handler HTTP 매핑, 검증 | 빠름 |
| DB Integration | `testing` + 실제 DB | Repository 쿼리, 스캔 매핑 | 중간 |
| E2E | `httptest` + testcontainers | 전체 스택 통합 | 느림 |

---

## Table-Driven Tests (테이블 기반 테스트)

### 기본 패턴

```go
func TestService_GetByID(t *testing.T) {
	tests := []struct {
		name    string
		id      int64
		mockFn  func(ctx context.Context, id int64) (*Order, error)
		want    *OrderResponse
		wantErr bool
	}{
		{
			name: "존재하는 주문 반환",
			id:   1,
			mockFn: func(_ context.Context, _ int64) (*Order, error) {
				return &Order{ID: 1, Name: "테스트", Status: OrderStatusCreated}, nil
			},
			want:    &OrderResponse{ID: 1, Name: "테스트", Status: OrderStatusCreated},
			wantErr: false,
		},
		{
			name: "존재하지 않으면 NotFoundError",
			id:   999,
			mockFn: func(_ context.Context, _ int64) (*Order, error) {
				return nil, nil
			},
			want:    nil,
			wantErr: true,
		},
		{
			name: "DB 에러 전파",
			id:   1,
			mockFn: func(_ context.Context, _ int64) (*Order, error) {
				return nil, fmt.Errorf("connection refused")
			},
			want:    nil,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &mockRepository{findByIDFn: tt.mockFn}
			svc := NewService(repo)

			got, err := svc.GetByID(context.Background(), tt.id)

			if (err != nil) != tt.wantErr {
				t.Errorf("GetByID() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if tt.want != nil && got.ID != tt.want.ID {
				t.Errorf("GetByID() ID = %d, want %d", got.ID, tt.want.ID)
			}
		})
	}
}
```

### Subtest 이름 규칙

```go
// ✅ GOOD: 한글로 시나리오 설명 (팀 컨벤션에 따라)
{name: "존재하는 주문 반환"}
{name: "존재하지 않으면 NotFoundError"}
{name: "금액이 음수면 ValidationError"}

// ✅ GOOD: 영문으로 시나리오 설명
{name: "returns order when exists"}
{name: "returns NotFoundError when missing"}

// ❌ BAD: 테스트 이름 없음
{name: "test1"}
{name: "case2"}
```

---

## Interface Mock 패턴

### 수동 Mock (권장)

```go
// Repository 인터페이스
type Repository interface {
	FindByID(ctx context.Context, id int64) (*Order, error)
	FindAll(ctx context.Context, opts ListOptions) ([]Order, int, error)
	Create(ctx context.Context, order *Order) error
	Update(ctx context.Context, order *Order) error
	Delete(ctx context.Context, id int64) error
}

// Mock 구현 — 필요한 메서드만 함수 필드로 구현
type mockRepository struct {
	findByIDFn func(ctx context.Context, id int64) (*Order, error)
	findAllFn  func(ctx context.Context, opts ListOptions) ([]Order, int, error)
	createFn   func(ctx context.Context, order *Order) error
	updateFn   func(ctx context.Context, order *Order) error
	deleteFn   func(ctx context.Context, id int64) error
}

func (m *mockRepository) FindByID(ctx context.Context, id int64) (*Order, error) {
	if m.findByIDFn != nil {
		return m.findByIDFn(ctx, id)
	}
	return nil, nil
}

func (m *mockRepository) FindAll(ctx context.Context, opts ListOptions) ([]Order, int, error) {
	if m.findAllFn != nil {
		return m.findAllFn(ctx, opts)
	}
	return nil, 0, nil
}

func (m *mockRepository) Create(ctx context.Context, order *Order) error {
	if m.createFn != nil {
		return m.createFn(ctx, order)
	}
	return nil
}

func (m *mockRepository) Update(ctx context.Context, order *Order) error {
	if m.updateFn != nil {
		return m.updateFn(ctx, order)
	}
	return nil
}

func (m *mockRepository) Delete(ctx context.Context, id int64) error {
	if m.deleteFn != nil {
		return m.deleteFn(ctx, id)
	}
	return nil
}
```

### 사용

```go
func TestService_Create(t *testing.T) {
	repo := &mockRepository{
		createFn: func(_ context.Context, order *Order) error {
			order.ID = 1 // DB가 ID 할당한 것을 시뮬레이션
			return nil
		},
	}
	svc := NewService(repo)

	resp, err := svc.Create(context.Background(), CreateRequest{
		Name:   "새 주문",
		Amount: 10000,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.ID != 1 {
		t.Errorf("expected ID 1, got %d", resp.ID)
	}
}
```

### mockgen 대안 (대규모 프로젝트)

```bash
# mockgen 설치
go install go.uber.org/mock/mockgen@latest

# 인터페이스에서 mock 생성
mockgen -source=repository.go -destination=mock_repository_test.go -package=order
```

**수동 Mock vs mockgen:**

| 기준 | 수동 Mock | mockgen |
|------|----------|---------|
| 설정 비용 | 없음 | mockgen 설치, go generate |
| 유지보수 | 인터페이스 변경 시 수동 수정 | 자동 재생성 |
| 가독성 | 함수 필드로 직관적 | 생성된 코드 이해 필요 |
| 호출 검증 | 수동 카운터 추가 | `EXPECT().Times(1)` 내장 |
| 권장 | 인터페이스 3-5개 메서드 이하 | 큰 인터페이스, 복잡한 검증 |

---

## httptest — Handler 통합 테스트

### 기본 패턴

```go
package order_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func setupTestHandler(t *testing.T) *http.ServeMux {
	t.Helper()
	repo := &mockRepository{
		// setup mock functions...
	}
	svc := NewService(repo)
	handler := NewHandler(svc)

	mux := http.NewServeMux()
	handler.RegisterRoutes(mux)
	return mux
}

func TestHandler_Create_201(t *testing.T) {
	mux := setupTestHandler(t)

	body := `{"name":"새 주문","amount":10000}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp OrderResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp.Name != "새 주문" {
		t.Errorf("expected name '새 주문', got '%s'", resp.Name)
	}
}

func TestHandler_GetByID_404(t *testing.T) {
	mux := setupTestHandler(t) // mock이 nil 반환하도록 설정

	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/999", nil)
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", rec.Code)
	}
}

func TestHandler_Create_400_InvalidBody(t *testing.T) {
	mux := setupTestHandler(t)

	body := `invalid json`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rec.Code)
	}
}
```

### Table-Driven HTTP 테스트

```go
func TestHandler_Create(t *testing.T) {
	mux := setupTestHandler(t)

	tests := []struct {
		name       string
		body       string
		wantStatus int
	}{
		{
			name:       "정상 생성",
			body:       `{"name":"주문","amount":10000}`,
			wantStatus: http.StatusCreated,
		},
		{
			name:       "잘못된 JSON",
			body:       `invalid`,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "이름 누락",
			body:       `{"amount":10000}`,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "금액 음수",
			body:       `{"name":"주문","amount":-100}`,
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()

			mux.ServeHTTP(rec, req)

			if rec.Code != tt.wantStatus {
				t.Errorf("expected %d, got %d: %s", tt.wantStatus, rec.Code, rec.Body.String())
			}
		})
	}
}
```

---

## 테스트 헬퍼

### t.Helper()

```go
func assertJSON(t *testing.T, rec *httptest.ResponseRecorder, key string, want any) {
	t.Helper() // 에러 발생 시 호출자 위치 표시

	var result map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	got, ok := result[key]
	if !ok {
		t.Errorf("key %q not found in response", key)
		return
	}
	if got != want {
		t.Errorf("key %q = %v, want %v", key, got, want)
	}
}

func assertStatus(t *testing.T, rec *httptest.ResponseRecorder, want int) {
	t.Helper()
	if rec.Code != want {
		t.Errorf("expected status %d, got %d: %s", want, rec.Code, rec.Body.String())
	}
}
```

### 테스트 픽스처

```go
func newTestOrder(overrides ...func(*Order)) *Order {
	o := &Order{
		ID:        1,
		Name:      "테스트 주문",
		Amount:    10000,
		Status:    OrderStatusCreated,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	for _, fn := range overrides {
		fn(o)
	}
	return o
}

// 사용
order := newTestOrder()
order := newTestOrder(func(o *Order) {
	o.Status = OrderStatusCancelled
	o.Name = "취소된 주문"
})
```

---

## DB 통합 테스트

### testcontainers-go

```go
package order_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

func setupTestDB(t *testing.T) *sql.DB {
	t.Helper()
	ctx := context.Background()

	container, err := postgres.Run(ctx,
		"postgres:16-alpine",
		postgres.WithDatabase("testdb"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").WithOccurrence(2),
		),
	)
	if err != nil {
		t.Fatalf("failed to start container: %v", err)
	}
	t.Cleanup(func() { container.Terminate(ctx) })

	connStr, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("failed to get connection string: %v", err)
	}

	db, err := sql.Open("pgx", connStr)
	if err != nil {
		t.Fatalf("failed to open db: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	// 마이그레이션 실행
	if err := runMigrations(db); err != nil {
		t.Fatalf("failed to run migrations: %v", err)
	}

	return db
}

func TestRepository_Create_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	db := setupTestDB(t)
	repo := NewRepository(db)

	order := &Order{Name: "통합 테스트 주문", Amount: 10000, Status: OrderStatusCreated}
	err := repo.Create(context.Background(), order)
	if err != nil {
		t.Fatalf("Create() error: %v", err)
	}
	if order.ID == 0 {
		t.Error("expected non-zero ID after insert")
	}

	// 조회 확인
	found, err := repo.FindByID(context.Background(), order.ID)
	if err != nil {
		t.Fatalf("FindByID() error: %v", err)
	}
	if found.Name != "통합 테스트 주문" {
		t.Errorf("expected name '통합 테스트 주문', got '%s'", found.Name)
	}
}
```

### SQLite 인메모리 대안 (빠른 테스트)

```go
func setupInMemoryDB(t *testing.T) *sql.DB {
	t.Helper()

	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("failed to open sqlite: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	// 스키마 생성
	_, err = db.Exec(`
		CREATE TABLE orders (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			amount REAL NOT NULL,
			status TEXT NOT NULL DEFAULT 'CREATED',
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)
	`)
	if err != nil {
		t.Fatalf("failed to create table: %v", err)
	}

	return db
}
```

**testcontainers vs SQLite:**

| 기준 | testcontainers | SQLite 인메모리 |
|------|---------------|----------------|
| 정확성 | 실제 DB와 동일 | DB 방언 차이 가능 |
| 속도 | 느림 (컨테이너 시작) | 빠름 |
| 의존성 | Docker 필요 | 없음 |
| 권장 | CI/CD, PostgreSQL 고유 기능 | 로컬 개발, 단순 쿼리 |

---

## 테스트 격리 전략

### 트랜잭션 롤백

```go
func withTestTx(t *testing.T, db *sql.DB, fn func(tx *sql.Tx)) {
	t.Helper()
	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("begin tx: %v", err)
	}
	defer tx.Rollback() // 항상 롤백 → 테스트 격리

	fn(tx)
}

func TestRepository_CRUD(t *testing.T) {
	db := setupTestDB(t)

	withTestTx(t, db, func(tx *sql.Tx) {
		repo := NewRepository(tx) // DBTX 인터페이스 활용

		// Create
		order := &Order{Name: "테스트", Amount: 1000, Status: OrderStatusCreated}
		if err := repo.Create(context.Background(), order); err != nil {
			t.Fatalf("Create: %v", err)
		}

		// Read
		found, _ := repo.FindByID(context.Background(), order.ID)
		if found.Name != "테스트" {
			t.Errorf("name = %s, want 테스트", found.Name)
		}
	})
	// 트랜잭션 롤백 → DB 상태 원래대로
}
```

### t.Cleanup()

```go
func setupTestData(t *testing.T, db *sql.DB) {
	t.Helper()

	// 테스트 데이터 삽입
	db.Exec(`INSERT INTO orders (name, amount, status) VALUES ('test', 1000, 'CREATED')`)

	// 테스트 후 정리
	t.Cleanup(func() {
		db.Exec(`DELETE FROM orders`)
	})
}
```

---

## 벤치마크 테스트

```go
func BenchmarkService_GetByID(b *testing.B) {
	repo := &mockRepository{
		findByIDFn: func(_ context.Context, _ int64) (*Order, error) {
			return &Order{ID: 1, Name: "bench", Status: OrderStatusCreated}, nil
		},
	}
	svc := NewService(repo)
	ctx := context.Background()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		svc.GetByID(ctx, 1)
	}
}
```

---

## testify (선택적 의존성)

### assert / require

```go
import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestService_GetByID_Testify(t *testing.T) {
	// ...setup...

	resp, err := svc.GetByID(context.Background(), 1)

	// assert — 실패해도 테스트 계속 실행
	assert.NoError(t, err)
	assert.Equal(t, int64(1), resp.ID)
	assert.Equal(t, "테스트", resp.Name)

	// require — 실패 시 즉시 중단 (이후 assertion 무의미할 때)
	require.NoError(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, "테스트", resp.Name)
}
```

**stdlib vs testify:**

| 기준 | stdlib `testing` | testify |
|------|-----------------|---------|
| 의존성 | 없음 | 외부 패키지 |
| 문법 | `if got != want { t.Errorf(...) }` | `assert.Equal(t, want, got)` |
| 실패 메시지 | 수동 작성 | 자동 diff 출력 |
| Go 관용적 | 가장 관용적 | 널리 사용되지만 외부 |
| 권장 | 작은 프로젝트, stdlib 선호 | 대규모 프로젝트, 가독성 중시 |

---

## 흔한 실수와 해결

### 1. TestMain 오용

```go
// ❌ BAD: TestMain에서 무거운 리소스 초기화 (모든 테스트에 영향)
func TestMain(m *testing.M) {
	db = setupDB() // 모든 테스트가 같은 DB 공유
	os.Exit(m.Run())
}

// ✅ GOOD: 테스트별 독립 리소스
func TestRepository_FindByID(t *testing.T) {
	db := setupTestDB(t) // 이 테스트만의 DB
	t.Cleanup(func() { db.Close() })
	// ...
}
```

### 2. 병렬 테스트 주의

```go
// ✅ GOOD: 독립적인 테스트에 t.Parallel()
func TestService_GetByID(t *testing.T) {
	t.Parallel() // 다른 테스트와 병렬 실행

	// ...setup (공유 상태 없음)...
}

// ❌ BAD: 공유 상태가 있는 테스트에 t.Parallel()
var counter int

func TestIncrement(t *testing.T) {
	t.Parallel()
	counter++ // ❌ 데이터 레이스
}
```

### 3. 테스트 빌드 태그

```go
//go:build integration

package order_test

// 통합 테스트 — 별도 빌드 태그로 분리
// 실행: go test -tags integration ./...
func TestRepository_Integration(t *testing.T) {
	// ...
}
```

**또는 `testing.Short()` 사용:**

```go
func TestRepository_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}
	// ...
}
// 실행: go test -short ./... (통합 테스트 건너뜀)
// 실행: go test ./...       (전체 실행)
```

### 4. 테스트 파일 위치

```go
// 같은 패키지 — 비공개 함수/필드 접근 가능
// internal/order/service_test.go
package order  // ✅ 비공개 접근 가능

// 외부 패키지 — 공개 API만 테스트 (블랙박스)
// internal/order/service_integration_test.go
package order_test  // ✅ 공개 API만 테스트

// 권장:
// - Unit test (비공개 로직 접근): package order
// - Integration test (공개 API): package order_test
```
