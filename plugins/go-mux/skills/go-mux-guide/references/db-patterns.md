# DB Patterns — database/sql, Connection Pool, Transaction

Go + `database/sql` 패키지를 사용한 데이터 접근 패턴과 모범 사례.

---

## database/sql 기본 구조

### 커넥션 풀 설정

```go
package database

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib" // pgx를 database/sql 드라이버로 등록
)

type Config struct {
	Host            string
	Port            int
	User            string
	Password        string
	DBName          string
	SSLMode         string
	MaxOpenConns    int
	MaxIdleConns    int
	ConnMaxLifetime time.Duration
	ConnMaxIdleTime time.Duration
}

func Open(cfg Config) (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName, cfg.SSLMode,
	)

	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}

	// 커넥션 풀 설정
	db.SetMaxOpenConns(cfg.MaxOpenConns)       // 최대 열린 커넥션 (기본: 무제한 → 반드시 설정)
	db.SetMaxIdleConns(cfg.MaxIdleConns)       // 최대 유휴 커넥션
	db.SetConnMaxLifetime(cfg.ConnMaxLifetime) // 커넥션 최대 수명
	db.SetConnMaxIdleTime(cfg.ConnMaxIdleTime) // 유휴 커넥션 최대 대기 시간

	// 연결 확인
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping db: %w", err)
	}

	return db, nil
}
```

### 커넥션 풀 설정 가이드

| 설정 | 권장값 | 이유 |
|------|--------|------|
| `MaxOpenConns` | 25~50 | DB 서버 `max_connections`의 일부 (다른 서비스 고려) |
| `MaxIdleConns` | `MaxOpenConns`과 동일 | idle에서 open으로 승격 비용 절감 |
| `ConnMaxLifetime` | 5분~30분 | 로드밸런서/DNS 변경 반영, 리소스 회수 |
| `ConnMaxIdleTime` | 5분 | 장기 유휴 커넥션 정리 |

```go
// 일반적인 웹 서비스 기본값
db.SetMaxOpenConns(25)
db.SetMaxIdleConns(25)
db.SetConnMaxLifetime(5 * time.Minute)
db.SetConnMaxIdleTime(5 * time.Minute)
```

### 안티패턴

```go
// ❌ BAD: 커넥션 풀 설정 미설정 → 기본값 무제한
db, _ := sql.Open("pgx", dsn)
// MaxOpenConns = 0 (무제한) → DB 커넥션 고갈 가능

// ❌ BAD: MaxIdleConns < MaxOpenConns → 커넥션 재생성 빈번
db.SetMaxOpenConns(50)
db.SetMaxIdleConns(5) // 유휴 커넥션이 부족해서 매번 새로 생성
```

---

## CRUD 쿼리 패턴

### QueryRowContext — 단건 조회

```go
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
		return nil, fmt.Errorf("find order %d: %w", id, err)
	}
	return &o, nil
}
```

### QueryContext — 복수 조회

```go
func (r *repository) FindByStatus(ctx context.Context, status OrderStatus) ([]Order, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT id, name, amount, status, created_at, updated_at
		 FROM orders WHERE status = $1 ORDER BY created_at DESC`, status,
	)
	if err != nil {
		return nil, fmt.Errorf("query orders by status: %w", err)
	}
	defer rows.Close()

	var orders []Order
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.Name, &o.Amount, &o.Status, &o.CreatedAt, &o.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan order: %w", err)
		}
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate orders: %w", err)
	}

	return orders, nil
}
```

### ExecContext — INSERT / UPDATE / DELETE

```go
// INSERT with RETURNING (PostgreSQL)
func (r *repository) Create(ctx context.Context, order *Order) error {
	now := time.Now()
	err := r.db.QueryRowContext(ctx,
		`INSERT INTO orders (name, amount, status, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id`,
		order.Name, order.Amount, order.Status, now, now,
	).Scan(&order.ID)
	if err != nil {
		return fmt.Errorf("insert order: %w", err)
	}
	order.CreatedAt = now
	order.UpdatedAt = now
	return nil
}

// UPDATE with RowsAffected check
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
	affected, _ := result.RowsAffected()
	if affected == 0 {
		return fmt.Errorf("update order %d: not found", order.ID)
	}
	return nil
}

// DELETE
func (r *repository) Delete(ctx context.Context, id int64) error {
	result, err := r.db.ExecContext(ctx, `DELETE FROM orders WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete order %d: %w", id, err)
	}
	affected, _ := result.RowsAffected()
	if affected == 0 {
		return fmt.Errorf("delete order %d: not found", id)
	}
	return nil
}
```

---

## 트랜잭션 패턴

### 기본 트랜잭션

```go
func (r *repository) CreateWithItems(ctx context.Context, order *Order, items []OrderItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() // 커밋 후에도 안전 (no-op)

	// Order 생성
	err = tx.QueryRowContext(ctx,
		`INSERT INTO orders (name, amount, status) VALUES ($1, $2, $3) RETURNING id`,
		order.Name, order.Amount, order.Status,
	).Scan(&order.ID)
	if err != nil {
		return fmt.Errorf("insert order: %w", err)
	}

	// Items 생성
	for _, item := range items {
		_, err := tx.ExecContext(ctx,
			`INSERT INTO order_items (order_id, product_name, quantity, price)
			 VALUES ($1, $2, $3, $4)`,
			order.ID, item.ProductName, item.Quantity, item.Price,
		)
		if err != nil {
			return fmt.Errorf("insert order item: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}
```

### 재사용 가능한 트랜잭션 헬퍼

```go
// WithTx — 트랜잭션 헬퍼 (rollback/commit 자동 관리)
func WithTx(ctx context.Context, db *sql.DB, fn func(tx *sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	if err := fn(tx); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// 사용
func (s *service) CreateOrder(ctx context.Context, req CreateOrderRequest) error {
	return WithTx(ctx, s.db, func(tx *sql.Tx) error {
		// tx를 사용하여 여러 쿼리 실행
		_, err := tx.ExecContext(ctx, `INSERT INTO orders ...`)
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO order_items ...`)
		return err
	})
}
```

### DBTX 인터페이스 — Repository에서 tx/db 투명 처리

```go
// DBTX — *sql.DB와 *sql.Tx 공통 인터페이스
type DBTX interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

type repository struct {
	db DBTX // *sql.DB 또는 *sql.Tx
}

func NewRepository(db DBTX) Repository {
	return &repository{db: db}
}

// 트랜잭션 없이 사용
orderRepo := order.NewRepository(db)

// 트랜잭션 내에서 사용
tx, _ := db.BeginTx(ctx, nil)
orderRepo := order.NewRepository(tx)
```

---

## Prepared Statement

### 언제 사용하나?

| 상황 | 권장 | 이유 |
|------|-----|------|
| 반복 실행 쿼리 | Prepared Statement | 파싱 비용 절감 |
| 일회성 쿼리 | 직접 실행 | 오버헤드 불필요 |
| 커넥션 풀 환경 | 주의 필요 | stmt가 특정 커넥션에 바인딩 |

```go
// Prepared statement — 반복 쿼리에 유용
stmt, err := db.PrepareContext(ctx,
	`SELECT id, name FROM orders WHERE status = $1`,
)
if err != nil {
	return err
}
defer stmt.Close()

for _, status := range statuses {
	rows, err := stmt.QueryContext(ctx, status)
	// ...
}
```

**주의:** `database/sql`은 prepared statement를 커넥션 풀에서 투명하게 관리하지만, 커넥션마다 다시 prepare할 수 있어 성능 이점이 제한적. 대부분의 경우 직접 쿼리 실행으로 충분.

---

## Null 처리

### sql.Null* 타입

```go
import "database/sql"

type Order struct {
	ID          int64
	Name        string
	Description sql.NullString // nullable column
	DeletedAt   sql.NullTime   // soft delete
}

// Scan
var o Order
err := row.Scan(&o.ID, &o.Name, &o.Description, &o.DeletedAt)

// 값 접근
if o.Description.Valid {
	fmt.Println(o.Description.String)
}

// 값 설정
o.Description = sql.NullString{String: "설명", Valid: true}
o.Description = sql.NullString{Valid: false} // NULL
```

### 포인터 대안 (JSON 친화적)

```go
type Order struct {
	ID          int64      `json:"id"`
	Name        string     `json:"name"`
	Description *string    `json:"description"` // nullable → 포인터
	DeletedAt   *time.Time `json:"deleted_at"`  // nullable → 포인터
}

// Scan — 포인터로 직접 스캔 가능
err := row.Scan(&o.ID, &o.Name, &o.Description, &o.DeletedAt)

// JSON 직렬화 시 null로 자연스럽게 표현
// {"id": 1, "name": "test", "description": null}
```

**`sql.Null*` vs 포인터:**

| 기준 | `sql.Null*` | 포인터 (`*string`) |
|------|-------------|-------------------|
| JSON 직렬화 | 커스텀 MarshalJSON 필요 | 자연스러운 null |
| 가독성 | `.Valid` 체크 필요 | `!= nil` 체크 |
| 타입 안전성 | 명시적 | Go 관용적 |
| 권장 | DB 전용 내부 모델 | API 응답 DTO |

---

## 동적 쿼리 빌더

### 안전한 동적 WHERE 절

```go
func (r *repository) Search(ctx context.Context, filter SearchFilter) ([]Order, error) {
	query := `SELECT id, name, amount, status, created_at, updated_at FROM orders WHERE 1=1`
	args := []any{}
	paramIdx := 1

	if filter.Name != "" {
		query += fmt.Sprintf(` AND name ILIKE $%d`, paramIdx)
		args = append(args, "%"+filter.Name+"%")
		paramIdx++
	}
	if filter.Status != nil {
		query += fmt.Sprintf(` AND status = $%d`, paramIdx)
		args = append(args, *filter.Status)
		paramIdx++
	}
	if filter.MinAmount > 0 {
		query += fmt.Sprintf(` AND amount >= $%d`, paramIdx)
		args = append(args, filter.MinAmount)
		paramIdx++
	}

	query += fmt.Sprintf(` ORDER BY created_at DESC OFFSET $%d LIMIT $%d`, paramIdx, paramIdx+1)
	args = append(args, filter.Offset, filter.Limit)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("search orders: %w", err)
	}
	defer rows.Close()

	// scan...
}
```

### SQL 인젝션 방지 규칙

```go
// ✅ GOOD: 매개변수화된 쿼리 (placeholder 사용)
r.db.QueryContext(ctx, `SELECT * FROM orders WHERE id = $1`, id)

// ❌ BAD: 문자열 직접 삽입 → SQL 인젝션 위험
r.db.QueryContext(ctx, fmt.Sprintf(`SELECT * FROM orders WHERE id = %d`, id))

// ❌ VERY BAD: 사용자 입력 직접 삽입
r.db.QueryContext(ctx, `SELECT * FROM orders WHERE name = '`+userName+`'`)
```

---

## 마이그레이션

### golang-migrate

```bash
# 마이그레이션 파일 생성
migrate create -ext sql -dir migrations -seq create_orders

# 마이그레이션 실행
migrate -path migrations -database "postgres://..." up

# 롤백
migrate -path migrations -database "postgres://..." down 1
```

### 마이그레이션 파일 예시

```sql
-- migrations/000001_create_orders.up.sql
CREATE TABLE orders (
    id         BIGSERIAL    PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    amount     DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    status     VARCHAR(20)  NOT NULL DEFAULT 'CREATED',
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_status ON orders (status);
CREATE INDEX idx_orders_created_at ON orders (created_at DESC);

-- migrations/000001_create_orders.down.sql
DROP TABLE IF EXISTS orders;
```

### goose (대안)

```bash
goose -dir migrations postgres "postgres://..." up
goose -dir migrations postgres "postgres://..." down
goose create add_orders sql
```

**golang-migrate vs goose:**

| 기준 | golang-migrate | goose |
|------|---------------|-------|
| 파일 형식 | `{seq}_{name}.up.sql` / `.down.sql` | `{timestamp}_{name}.sql` (up/down 한 파일) |
| Go 마이그레이션 | 지원 | 지원 |
| CLI | 별도 설치 | `go install` |
| 인기도 | 더 많은 스타 | 더 활발한 유지보수 |
| 권장 | 대규모 팀, CI 연동 | 소규모 팀, 간결함 선호 |
