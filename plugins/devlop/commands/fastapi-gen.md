---
name: fastapi-gen
description: "Python FastAPI CRUD 계층 코드 생성. 도메인명을 입력하면 SQLAlchemy Model, Pydantic Schema, Repository, Service, Router, Test를 프로젝트 컨벤션에 맞춰 자동 생성한다."
category: development
complexity: advanced
mcp-servers: []
personas: []
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
  --async        비동기 스택으로 생성 (AsyncSession + async def)
  --soft-delete  soft delete 패턴 적용 (deleted_at 필드 + 쿼리 필터)
  --audit        Auditing 필드 자동 포함 (created_at, updated_at)
```

## Behavioral Flow

### Phase 1: Discovery
프로젝트 구조와 기존 코드 컨벤션을 분석한다.

**Steps:**
1. **Scan**: `pyproject.toml`, `requirements.txt`, `alembic.ini` 스캔하여 의존성과 설정 파악
2. **Analyze**: 기존 Model, Router, Service 파일을 읽어 패턴 추출
   - 모듈 구조 (`app/models/order.py` vs `app/domain/order/model.py`)
   - Schema 패턴 (`OrderCreate` / `OrderUpdate` / `OrderResponse`)
   - DI 패턴 (`Depends(get_db)`, class-based `Depends`)
   - 에러 핸들링 패턴 (custom exception handler, HTTPException)
   - Audit 패턴 (TimestampMixin, created_at/updated_at)
3. **Classify**: 프로젝트 타입 결정
   - Sync vs Async (Session vs AsyncSession)
   - SQLAlchemy 1.x vs 2.0
   - Flat structure vs Domain-driven structure

### Phase 2: Generation
도메인 모델 정의를 기반으로 전체 계층 코드를 생성한다.

**Steps:**
1. **Model**: SQLAlchemy Model with audit fields, validation, relationships
2. **Schema**: Pydantic V2 Create/Update/Response with Field validation
3. **Repository**: BaseRepository 상속 + 도메인 특화 쿼리
4. **Service**: 비즈니스 로직 + 도메인 검증 + Repository 호출
5. **Router**: REST endpoints with Depends, response_model, status_code
6. **Test**: Unit (mock) + Integration (httpx AsyncClient) tests

**Generation Rules:**
- Bottom-up 순서: Model → Schema → Repository → Service → Router
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
# 비동기 스택으로 코드 생성 (AsyncSession + async def)
```

### Soft Delete + Audit
```
/fastapi-gen Member --soft-delete --audit
# soft delete (deleted_at) + audit (created_at, updated_at) 패턴 적용
```

## Generated Code Patterns

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
