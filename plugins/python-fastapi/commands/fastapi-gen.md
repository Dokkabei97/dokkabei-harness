---
name: fastapi-gen
description: |
  FastAPI CRUD 계층 생성 — 쿼리 계층(ORM/원시 SQL)·마이그레이션 도구(Alembic/dbmate)를 감지해 기존 컨벤션대로 생성.
  Generates FastAPI CRUD layers after detecting query layer and migration tool. Use when: /fastapi-gen <Domain>.
disable-model-invocation: true
---

# /fastapi-gen - Python FastAPI CRUD 코드 생성

## Triggers
- 새로운 도메인 모델의 CRUD 코드가 필요할 때
- "Order 모델 만들어줘", "Product CRUD 생성해줘"
- 기존 FastAPI 프로젝트에 새 도메인 계층을 추가할 때
- FastAPI 프로젝트에서 표준 계층 구조를 스캐폴딩할 때

## Usage
```
/fastapi-gen [도메인명] [options]

Options:
  --fields       필드 정의 (e.g., "name:str, price:Decimal, status:OrderStatus")
  --layers       생성할 계층 선택 (e.g., "model,schema,repo,service,router")
  --no-test      테스트 코드 생성 생략
  --async        비동기 스택으로 생성 (감지 결과가 없을 때만 — 기존 코드가 있으면 그 방식을 따름)
  --soft-delete  soft delete 패턴 적용 (deleted_at 필드 + 쿼리 필터)
  --audit        Auditing 필드 자동 포함 (created_at, updated_at)
```

## Behavioral Flow

### Phase 1: Discovery
프로젝트 구조와 기존 코드 컨벤션을 분석한다. **스택을 단정하지 않는다** — 감지 결과가 기본값보다 우선한다.

**Steps:**
1. **Scan**: `pyproject.toml`/lock(`uv.lock`, `poetry.lock`, `requirements*.txt`), 프로젝트 `CLAUDE.md`·`.claude/rules/`·`docs/` 의 규약 확인
2. **쿼리 계층 감지**:
   | 신호 | 판정 | 생성 대상 |
   |---|---|---|
   | `sqlalchemy`/`sqlmodel` 의존성 + `DeclarativeBase`/`Mapped[` | ORM | Model + Repository(select/session) |
   | `psycopg`(3)/`asyncpg` 직접 import, `%s`·`$1` SQL 문자열, `dict_row`/`class_row` | 원시 SQL | Repository(SQL 상수 + 바인딩), Model 클래스 없음 |
   | `psycopg2` | 원시 SQL(레거시) | 기존 스타일 유지, psycopg 3 차이(PY-PG-01)는 이전 시에만 언급 |
   | 혼용 | 경로별 | 새 도메인이 닮아야 할 기존 도메인을 사용자에게 확인 |
3. **마이그레이션 도구 감지**: `alembic.ini` → Alembic revision · `db/migrations/*.sql` + `-- migrate:up` 또는 `dbmate` 언급 → dbmate SQL 파일(`dbmate new <name>` 명명 규칙) · 그 외 기존 디렉터리 관례 · 없음 → 스키마 변경 SQL 을 제안만 하고 파일은 만들지 않음
4. **Analyze**: 기존 도메인 1개를 골라 파일 배치·Schema 명명(`OrderCreate`/`OrderResponse`)·DI(`Depends(get_conn)`, `Depends(get_db)`)·에러 처리·트랜잭션 경계(누가 commit 하는가 — yield 의존성 teardown commit 이면 FA-BG-03 확인)·sync/async 를 추출
5. **DB 확장 확인**: PostGIS 등 확장 타입이 있으면 `python-fastapi-guide` 의 `references/postgis.md` 규칙(geography/SRID, 좌표 순서)을 적용

### Phase 2: Generation
감지 결과에 맞는 계층만 bottom-up 으로 생성한다.

**Steps:**
1. **Migration** (도구가 감지된 경우): 해당 도구 문법으로 테이블/인덱스 생성. 운영 테이블 인덱스는 `CONCURRENTLY`(dbmate 는 `-- migrate:up transaction:false` 별도 파일)
2. **Model** (ORM 인 경우만): 기존 Base/Mixin 재사용
3. **Schema**: Pydantic v2 Create/Update/Response
4. **Repository**: ORM → session 쿼리 / 원시 SQL → SQL 상수 + 파라미터 바인딩(`= ANY(%s)` 등 psycopg 3 규칙), 기존 row factory 사용
5. **Service**: 비즈니스 규칙 + Repository 호출, 트랜잭션 경계는 기존 관례대로
6. **Router**: 반환 타입(`-> OrderResponse`)으로 응답 모델 지정, `response_class` 는 지정하지 않음(FA-RESP-01)
7. **Test**: Unit (mock) + Integration (httpx AsyncClient). 원시 SQL 리포지토리는 실제 PostgreSQL 대상 테스트를 우선 — SQL 은 모킹으로 검증되지 않는다

**Generation Rules:**
- Bottom-up 순서: (Migration) → (Model) → Schema → Repository → Service → Router
- 각 계층은 아래 계층만 의존 (Router → Service → Repository)
- Schema는 Model과 분리 (API 계약과 도메인 모델 독립)
- 테스트는 각 계층별로 적합한 수준으로 생성
- 비즈니스 로직이 필요한 부분은 `# TODO(human)` 마커 사용

### Phase 3: Verification
생성된 코드가 정상 동작하고 테스트가 통과하는지 검증한다.

**Steps:**
1. **Test**: `python -m pytest tests/ -x --tb=short` 실행
2. **Type Check**: `mypy` 또는 `pyright` 실행 (설정되어 있는 경우)
3. **Lint**: `ruff check` 실행 (가능한 경우)
4. **Report**: 생성 결과 요약 출력

## Tool Coordination
- **Glob**: 프로젝트 구조 파악, 기존 파일 탐색
- **Read**: 기존 코드 패턴 분석, pyproject.toml 의존성 확인
- **Grep**: 기존 컨벤션 추출 (import, class 패턴, Depends 패턴)
- **Write**: 새 파일 생성
- **Edit**: 기존 파일 수정 (필요시, e.g., `__init__.py` export 추가)
- **Bash**: 테스트 실행, 린트/타입 검사
- **Context7 MCP** (선택): 버전 민감 API는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 생성 (미설치 시 생략)

## Examples

### Basic Usage
```
/fastapi-gen Order
# Order 도메인의 전체 CRUD 계층 생성
# → Order model, OrderCreate/Update/Response schema, OrderRepository, OrderService, order router, tests
```

### With Fields
```
/fastapi-gen Product --fields "name:str, price:Decimal, category:Category, stock:int"
# 필드가 정의된 Product 도메인 전체 계층 생성
```

### Specific Layers Only
```
/fastapi-gen Payment --layers "model,schema,repo,service"
# Router 없이 Model, Schema, Repository, Service만 생성
```

### Async Stack
```
/fastapi-gen Notification --async
# 감지할 기존 코드가 없을 때 비동기 스택으로 생성 (ORM: AsyncSession / 원시 SQL: AsyncConnection)
```

### Soft Delete + Audit
```
/fastapi-gen Member --soft-delete --audit
# soft delete (deleted_at) + audit (created_at, updated_at) 패턴 적용
```

## Generated Code Patterns

> 아래 Model/Repository 예시는 **ORM(SQLAlchemy) 감지 시** 형태다. 원시 SQL 이면 아래 "Repository (Raw SQL)"·"Migration (dbmate)" 예시를 따른다. 어느 쪽이든 기존 코드 스타일이 우선한다.

### Model
```python
from datetime import datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import String, Numeric, Enum as SAEnum, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin


class OrderStatus(StrEnum):
    CREATED = "CREATED"
    CONFIRMED = "CONFIRMED"
    SHIPPED = "SHIPPED"
    DELIVERED = "DELIVERED"
    CANCELLED = "CANCELLED"


class Order(TimestampMixin, Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[OrderStatus] = mapped_column(
        SAEnum(OrderStatus, native_enum=False, length=20),
        default=OrderStatus.CREATED,
    )
```

### Schema
```python
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class OrderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    amount: Decimal = Field(..., gt=0, decimal_places=2)
    status: OrderStatus = OrderStatus.CREATED


class OrderUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    amount: Decimal | None = Field(None, gt=0, decimal_places=2)
    status: OrderStatus | None = None


class OrderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    amount: Decimal
    status: OrderStatus
    created_at: datetime
    updated_at: datetime
```

### Repository
```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.order import Order, OrderStatus
from app.repositories.base import BaseRepository


class OrderRepository(BaseRepository[Order]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, Order)

    async def get_by_status(self, status: OrderStatus) -> list[Order]:
        stmt = select(Order).where(Order.status == status)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())
```

### Repository (Raw SQL — psycopg 3, async)
```python
from psycopg import AsyncConnection
from psycopg.rows import class_row

from app.schemas.order import OrderCreate, OrderResponse

_INSERT = """
    INSERT INTO orders (name, amount, status)
    VALUES (%(name)s, %(amount)s, %(status)s)
    RETURNING id, name, amount, status, created_at, updated_at
"""
_BY_IDS = "SELECT id, name, amount, status, created_at, updated_at FROM orders WHERE id = ANY(%s)"


class OrderRepository:
    def __init__(self, conn: AsyncConnection) -> None:
        self.conn = conn

    async def create(self, data: OrderCreate) -> OrderResponse:
        async with self.conn.cursor(row_factory=class_row(OrderResponse)) as cur:
            await cur.execute(_INSERT, data.model_dump())
            row = await cur.fetchone()
        assert row is not None
        return row

    async def get_many(self, ids: list[int]) -> list[OrderResponse]:
        async with self.conn.cursor(row_factory=class_row(OrderResponse)) as cur:
            await cur.execute(_BY_IDS, (ids,))
            return await cur.fetchall()
```

### Migration (dbmate)
```sql
-- migrate:up
CREATE TABLE orders (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        varchar(100) NOT NULL,
  amount      numeric(12, 2) NOT NULL CHECK (amount > 0),
  status      varchar(20) NOT NULL DEFAULT 'CREATED',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- migrate:down
DROP TABLE orders;
```

### Service
```python
from decimal import Decimal

from app.models.order import Order, OrderStatus
from app.schemas.order import OrderCreate, OrderUpdate, OrderResponse
from app.repositories.order import OrderRepository
from app.exceptions import OrderNotFoundException

MAX_ORDER_AMOUNT = Decimal("10000000")


class OrderService:
    def __init__(self, repository: OrderRepository) -> None:
        self.repository = repository

    async def get_by_id(self, order_id: int) -> OrderResponse:
        order = await self.repository.get_by_id(order_id)
        if order is None:
            raise OrderNotFoundException(order_id)
        return OrderResponse.model_validate(order)

    async def create(self, data: OrderCreate) -> OrderResponse:
        order = Order(
            name=data.name,
            amount=data.amount,
            status=data.status,
        )
        created = await self.repository.create(order)
        return OrderResponse.model_validate(created)

    async def update(self, order_id: int, data: OrderUpdate) -> OrderResponse:
        order = await self.repository.get_by_id(order_id)
        if order is None:
            raise OrderNotFoundException(order_id)

        update_data = data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(order, field, value)

        await self.repository.session.flush()
        await self.repository.session.refresh(order)
        return OrderResponse.model_validate(order)

    async def delete(self, order_id: int) -> None:
        order = await self.repository.get_by_id(order_id)
        if order is None:
            raise OrderNotFoundException(order_id)
        await self.repository.delete(order)
```

### Router
```python
from fastapi import APIRouter, Depends, status

from app.schemas.order import OrderCreate, OrderUpdate, OrderResponse
from app.services.order import OrderService
from app.dependencies import get_order_service

router = APIRouter(prefix="/api/v1/orders", tags=["orders"])


@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: int,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.get_by_id(order_id)


@router.get("", response_model=list[OrderResponse])
async def list_orders(
    skip: int = 0,
    limit: int = 20,
    service: OrderService = Depends(get_order_service),
) -> list[OrderResponse]:
    return await service.get_all(skip=skip, limit=limit)


@router.post("", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(
    data: OrderCreate,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.create(data)


@router.put("/{order_id}", response_model=OrderResponse)
async def update_order(
    order_id: int,
    data: OrderUpdate,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.update(order_id, data)


@router.delete("/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_order(
    order_id: int,
    service: OrderService = Depends(get_order_service),
) -> None:
    await service.delete(order_id)
```

### Unit Test (pytest + mock)
```python
import pytest
from unittest.mock import AsyncMock
from decimal import Decimal

from app.models.order import Order, OrderStatus
from app.schemas.order import OrderCreate
from app.services.order import OrderService
from app.exceptions import OrderNotFoundException


class TestOrderServiceGetById:
    @pytest.fixture
    def mock_repository(self):
        return AsyncMock()

    @pytest.fixture
    def service(self, mock_repository):
        return OrderService(repository=mock_repository)

    async def test_존재하는_주문_반환(self, service, mock_repository):
        order = Order(id=1, name="테스트 주문", status=OrderStatus.CREATED)
        mock_repository.get_by_id.return_value = order

        result = await service.get_by_id(1)

        assert result.id == 1
        assert result.name == "테스트 주문"
        mock_repository.get_by_id.assert_called_once_with(1)

    async def test_존재하지_않으면_예외(self, service, mock_repository):
        mock_repository.get_by_id.return_value = None

        with pytest.raises(OrderNotFoundException):
            await service.get_by_id(999)
```

### Integration Test (httpx)
```python
import pytest
from httpx import AsyncClient


@pytest.mark.anyio
class TestOrderRouter:
    async def test_주문_생성_201(self, async_client: AsyncClient):
        response = await async_client.post(
            "/api/v1/orders",
            json={"name": "새 주문", "amount": "10000"},
        )
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "새 주문"
        assert data["status"] == "CREATED"

    async def test_존재하지_않는_주문_404(self, async_client: AsyncClient):
        response = await async_client.get("/api/v1/orders/99999")
        assert response.status_code == 404
```

## Boundaries

**Will:**
- 프로젝트 기존 컨벤션을 분석하고 정확히 따름
- 전체 CRUD 계층을 일관된 패턴으로 생성
- Pydantic V2 Field 검증 포함
- 적절한 테스트 코드 생성 (단위 + 통합)
- Audit 필드 자동 포함 (프로젝트 패턴에 따라)
- 커스텀 Exception 클래스 생성

**Will Not:**
- 기존 파일을 무단 수정
- 비즈니스 로직을 임의로 구현 (`# TODO(human)` 마커 사용)
- 프로젝트에 없는 의존성을 요구하는 코드 생성
- Non-Pythonic 패턴 생성 (Optional[], type() 비교 등)
- 불필요한 주석이나 docstring 생성
- pyproject.toml 의존성 추가 (별도 확인 필요)
