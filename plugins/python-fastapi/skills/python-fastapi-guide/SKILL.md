---
name: python-fastapi-guide
description: |
  Python + FastAPI 개발 원칙/의사결정 가이드. Pythonic First 철학, 레이어 규율, Fail Fast, 아키텍처·스택·테스트 프레임워크 선택 기준을 제공한다.
  구체적 구현 코드 예제(Depends DI, Pydantic v2, async SQLAlchemy, Alembic, Strawberry 관용구)는 fastapi-patterns를 참조할 것.
---

# Python + FastAPI Development Guide

Python + FastAPI 프로젝트에서 관용적이고 유지보수 가능한 코드를 작성하기 위한 종합 가이드.

## When to Apply

Reference these guidelines when:
- Python + FastAPI 프로젝트에서 새 코드를 작성할 때
- 기존 FastAPI 코드를 리뷰하거나 리팩토링할 때
- SQLAlchemy 모델 설계나 쿼리 최적화가 필요할 때
- 테스트 코드를 작성하거나 테스트 전략을 결정할 때
- 버전 민감 API(Pydantic v2 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 생성 (미설치 시 생략)

## Quick Reference

| Priority | Category | Impact | Reference |
|----------|----------|--------|-----------|
| 1 | Layer Patterns | 코드 구조와 의존성 방향 | `references/layer-patterns.md` |
| 2 | SQLAlchemy Patterns | 데이터 접근 성능과 정합성 | `references/sqlalchemy-patterns.md` |
| 3 | Testing Patterns | 테스트 품질과 신뢰성 | `references/testing-patterns.md` |

## Core Principles

### 1. Pythonic First — Non-Pythonic 관용구 제거

| Non-Pythonic (Avoid) | Pythonic (Use) | Why |
|----|----|----|
| `Optional[str]` | `str \| None` | PEP 604, Python 3.10+ 유니온 문법 |
| `dict.get(k) != None` | `k in dict` | 명확한 의도 표현 |
| `for i in range(len(lst))` | `for item in lst` / `enumerate` | iterator protocol 활용 |
| `"" + str(x)` | `f"{x}"` | f-string 가독성 |
| `try: ... except: pass` | 명시적 에러 처리 | silent failure 방지 |
| `type(x) == int` | `isinstance(x, int)` | 상속 지원 |
| `lambda x: func(x)` | `func` 직접 전달 | 불필요한 래핑 제거 |
| `def f(x=[])` | `def f(x=None)` | mutable default 버그 방지 |
| `class Foo(object)` | `class Foo` | Python 3 기본 상속 |

### 2. Layer Discipline — 의존 방향은 항상 위→아래

```
Router (API 계약)
    ↓ Schema (Pydantic)
Service (비즈니스 로직)
    ↓ Model (SQLAlchemy)
Repository (데이터 접근)
    ↓
Database
```

**절대 규칙:**
- Router는 SQLAlchemy Model을 직접 반환하지 않는다 (Pydantic Schema 사용)
- Repository는 Service 없이 Router에서 직접 호출하지 않는다
- Service는 Request, Response, HTTPException 등 웹 계층 객체에 접근하지 않는다

### 3. Fail Fast — 잘못된 입력은 빨리 거부

```python
# 1st defense: Pydantic validation at Router layer
class OrderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    amount: Decimal = Field(..., gt=0)

# 2nd defense: Domain validation at Service layer
def create(self, data: OrderCreate) -> OrderResponse:
    if data.amount > MAX_ORDER_AMOUNT:
        raise OrderLimitExceeded(data.amount)

# 3rd defense: DB constraint as last safety net
name: Mapped[str] = mapped_column(String(100), nullable=False)
```

### 4. Convention over Configuration

FastAPI의 기본값을 최대한 활용하고, 필요한 경우에만 커스터마이징한다.

```python
# GOOD: Pydantic model_config로 간결하게
class OrderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str

# BAD: 불필요한 커스텀 직렬화
class OrderResponse(BaseModel):
    id: int
    name: str

    @classmethod
    def from_entity(cls, entity: Order) -> "OrderResponse":
        return cls(id=entity.id, name=entity.name)  # model_validate로 충분
```

## How to Use

Read individual reference files for detailed patterns and examples:

```
references/layer-patterns.md       — Router, Service, Repository 계층별 패턴
references/sqlalchemy-patterns.md  — 모델 설계, N+1 방지, 연관 관계, 마이그레이션
references/testing-patterns.md     — pytest, Mock, httpx, Factory Boy
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
| CRUD 중심 서비스 | Layered Architecture | 단순하고 팀 러닝커브 낮음 |
| 복잡한 도메인 로직 | Hexagonal / Clean | 도메인 보호, 테스트 용이 |
| MSA 이벤트 기반 | CQRS + Event Sourcing | 읽기/쓰기 최적화 분리 |

### Stack Selection

| 상황 | 권장 | 이유 |
|------|-----|------|
| 표준 REST API | FastAPI + SQLAlchemy 2.0 (sync) | 단순, 디버깅 용이 |
| 고처리량 비동기 | FastAPI + SQLAlchemy 2.0 (async) | 비차단 I/O |
| 배치/데이터 처리 | Celery + SQLAlchemy | 비동기 태스크 큐 |

### Test Framework

| 상황 | 권장 | 이유 |
|------|-----|------|
| 단위 테스트 | pytest + unittest.mock | 표준, 간결 |
| API 통합 테스트 | pytest + httpx AsyncClient | async 지원, 빠름 |
| 테스트 데이터 | Factory Boy + Faker | 유연한 팩토리 패턴 |
| Mocking | pytest-mock (mocker fixture) | pytest 네이티브 통합 |
