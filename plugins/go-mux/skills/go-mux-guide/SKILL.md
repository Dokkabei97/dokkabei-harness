---
name: go-mux-guide
description: |
  Go + stdlib net/http mux 개발 종합 가이드. 계층별 구현 패턴, database/sql 모범 사례, 테스트 전략을 제공한다.
  코드 작성 시 자동으로 참조하여 관용적 Go와 stdlib mux 모범 사례를 적용한다.
---

# Go + stdlib net/http mux Development Guide

Go + stdlib `net/http` 프로젝트에서 관용적이고 유지보수 가능한 코드를 작성하기 위한 종합 가이드.

## When to Apply

Reference these guidelines when:
- Go + stdlib mux 프로젝트에서 새 코드를 작성할 때
- 기존 Go HTTP 코드를 리뷰하거나 리팩토링할 때
- database/sql 쿼리 설계나 커넥션 풀 최적화가 필요할 때
- 테스트 코드를 작성하거나 테스트 전략을 결정할 때
- 버전 민감 API(Go 1.22+ ServeMux 패턴 매칭 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 생성 (미설치 시 생략)

## Quick Reference

| Priority | Category | Impact | Reference |
|----------|----------|--------|-----------|
| 1 | Layer Patterns | 코드 구조와 의존성 방향 | `references/layer-patterns.md` |
| 2 | DB Patterns | 데이터 접근 성능과 정합성 | `references/db-patterns.md` |
| 3 | Testing Patterns | 테스트 품질과 신뢰성 | `references/testing-patterns.md` |

## Core Principles

### 1. Idiomatic Go — 비관용적 패턴 제거

| Non-Idiomatic (Avoid) | Idiomatic (Use) | Why |
|----|----|----|
| `panic()` for errors | `return ..., err` | 복구 가능한 에러에 panic 금지 |
| `_ = doSomething()` | `if err := doSomething(); err != nil` | 에러 무시 금지 |
| `GetName()` getter | `Name()` | Go는 Get 접두사 불필요 |
| `order.OrderService` | `order.Service` | stuttering 이름 금지 |
| `interface{}` / `any` | 구체적 타입 | 가능하면 specific type 사용 |
| `init()` complex setup | explicit `New()` | 테스트 어려움, 숨겨진 부작용 |
| global mutable state | constructor injection | 테스트 가능, 명시적 의존성 |
| `new(T)` for structs | `&T{}` or `T{}` | 필드 초기화가 명확 |
| bare `return` (named) | explicit `return val, err` | 가독성, 특히 긴 함수에서 |
| channel for mutex job | `sync.Mutex` | 단순 보호는 mutex가 적합 |

### 2. Layer Discipline — 의존 방향은 항상 위→아래

```
Handler (HTTP 계약)
    ↓ DTO (Request/Response)
Service (비즈니스 로직)
    ↓ Model
Repository (데이터 접근)
    ↓
Database
```

**절대 규칙:**
- Handler는 Model을 직접 반환하지 않는다 (Response struct 사용)
- Repository는 Service 없이 Handler에서 직접 호출하지 않는다
- Service는 `http.Request`, `http.ResponseWriter` 등 웹 계층 객체에 접근하지 않는다
- 각 계층은 인터페이스를 통해 아래 계층에 의존한다

### 3. Accept Interfaces, Return Structs

```go
// GOOD: 인터페이스를 받아 구체 타입 반환
type Service interface {
    GetByID(ctx context.Context, id int64) (*OrderResponse, error)
}

type service struct {
    repo Repository  // 인터페이스 의존
}

func NewService(repo Repository) Service {
    return &service{repo: repo}
}

// BAD: 구체 타입을 매개변수로 직접 사용
type service struct {
    repo *PostgresRepository  // 구체 타입 의존 → 테스트 어려움
}
```

### 4. Error Handling — Wrap and Propagate

```go
// 1st defense: DTO validation at Handler layer
func (r CreateRequest) Validate() error {
    if r.Name == "" {
        return &ValidationError{Field: "name", Message: "is required"}
    }
    return nil
}

// 2nd defense: Domain validation at Service layer
func (s *service) Create(ctx context.Context, req CreateRequest) (*OrderResponse, error) {
    if req.Amount > maxOrderAmount {
        return nil, &BusinessError{Code: "ORDER_LIMIT_EXCEEDED", Message: "order limit exceeded"}
    }
    // ...
}

// 3rd defense: DB constraint as last safety net
// UNIQUE constraint, NOT NULL, CHECK constraint
```

### 5. Context Propagation

```go
// GOOD: context를 첫 번째 매개변수로 전달
func (s *service) GetByID(ctx context.Context, id int64) (*OrderResponse, error) {
    order, err := s.repo.FindByID(ctx, id)
    // ...
}

// BAD: context 생략
func (s *service) GetByID(id int64) (*OrderResponse, error) {
    order, err := s.repo.FindByID(context.Background(), id) // anti-pattern
    // ...
}
```

## How to Use

Read individual reference files for detailed patterns and examples:

```
references/layer-patterns.md   — Handler, Service, Repository 계층별 패턴
references/db-patterns.md      — database/sql, 커넥션 풀, 트랜잭션, 마이그레이션
references/testing-patterns.md — testing, httptest, table-driven, mock 패턴
```

Each reference file contains:
- Pattern description and rationale
- Bad/Good code examples with explanations
- Common pitfalls and solutions
- Decision guidance for choosing between approaches

## Decision Quick Reference

### Architecture Style

| 상황 | 권장 | 이유 |
|------|-----|------|
| CRUD 중심 서비스 | Flat / Layered | 패키지 최소화, Go 관용적 |
| 복잡한 도메인 로직 | Hexagonal (ports/adapters) | 도메인 보호, 테스트 용이 |
| MSA 이벤트 기반 | CQRS + Event | 읽기/쓰기 분리, 스케일링 |

### Project Layout

| 상황 | 권장 | 이유 |
|------|-----|------|
| 단일 서비스 | `internal/` layout | 캡슐화, 표준 |
| 다중 바이너리 | `cmd/` + `internal/` | Go 표준 레이아웃 |
| 라이브러리 | `pkg/` export | 외부 공개 API |
| 소규모 프로젝트 | flat (root package) | 오버엔지니어링 방지 |

### DB Driver Selection

| 상황 | 권장 | 이유 |
|------|-----|------|
| 표준, 드라이버 교체 가능 | `database/sql` | 표준 인터페이스, 이식성 |
| PostgreSQL 고급 기능 | `pgx` native | LISTEN/NOTIFY, COPY, 성능 |
| 편의 기능 필요 | `sqlx` | StructScan, NamedQuery |
| ORM 필요 | `GORM` / `ent` | 빠른 개발, 마이그레이션 |

### Test Framework

| 상황 | 권장 | 이유 |
|------|-----|------|
| 기본 단위 테스트 | stdlib `testing` | 외부 의존성 없음, Go 관용적 |
| assertion 편의성 | `testify/assert` | 읽기 쉬운 assertion |
| HTTP 통합 테스트 | `httptest` | stdlib, 빠름, mock server |
| DB 통합 테스트 | `testcontainers-go` | 실제 DB, 격리된 환경 |
| Mock 생성 | interface + 수동 mock | Go 인터페이스가 간결, mockgen은 선택 |
