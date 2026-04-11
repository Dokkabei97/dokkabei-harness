# Layer Patterns — Router / Service / Repository

Python + FastAPI에서 각 계층의 책임과 구현 패턴.

---

## Router Layer

### 책임
- HTTP 요청/응답 변환 (직렬화/역직렬화)
- 입력값 검증 위임 (Pydantic + Path/Query/Body)
- 적절한 HTTP 상태 코드 반환
- Service 호출 위임

### 올바른 패턴

```python
from fastapi import APIRouter, Depends, Path, Query, status

from app.schemas.order import OrderCreate, OrderUpdate, OrderResponse
from app.services.order import OrderService
from app.dependencies import get_order_service

router = APIRouter(prefix="/api/v1/orders", tags=["orders"])


# 단건 조회 — 200 OK
@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: int = Path(..., gt=0),
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.get_by_id(order_id)


# 목록 조회 — 페이지네이션
@router.get("", response_model=PaginatedResponse[OrderResponse])
async def list_orders(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    status_filter: OrderStatus | None = Query(None, alias="status"),
    service: OrderService = Depends(get_order_service),
) -> PaginatedResponse[OrderResponse]:
    return await service.get_all(skip=skip, limit=limit, status=status_filter)


# 생성 — 201 Created
@router.post("", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(
    data: OrderCreate,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.create(data)


# 수정 — 200 OK
@router.put("/{order_id}", response_model=OrderResponse)
async def update_order(
    order_id: int,
    data: OrderUpdate,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.update(order_id, data)


# 삭제 — 204 No Content
@router.delete("/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_order(
    order_id: int,
    service: OrderService = Depends(get_order_service),
) -> None:
    await service.delete(order_id)
```

### 안티패턴

```python
# BAD: Router에서 비즈니스 로직 수행
@router.post("")
async def create_order(
    data: OrderCreate,
    db: AsyncSession = Depends(get_db),
):
    # 비즈니스 로직이 Router에 있음
    if data.amount > Decimal("1000000"):
        raise HTTPException(status_code=400, detail="한도 초과")

    # Repository를 건너뛰고 직접 DB 조작
    order = Order(**data.model_dump())
    db.add(order)
    await db.commit()

    # ORM 모델을 직접 반환 (API 계약 불안정)
    return order
```

**위반 사항:**
- 비즈니스 로직(한도 검증)이 Router에 위치
- Repository 계층을 건너뛰고 직접 session 조작
- SQLAlchemy 모델을 직접 반환 (Pydantic Schema 미사용)

---

## Service Layer

### 책임
- 비즈니스 로직 수행
- 도메인 검증 (입력 검증과 구분)
- 트랜잭션 경계 관리
- Repository 조합 및 호출
- Domain Exception 발생

### 올바른 패턴

```python
from app.models.order import Order, OrderStatus
from app.schemas.order import OrderCreate, OrderUpdate, OrderResponse
from app.repositories.order import OrderRepository
from app.exceptions import OrderNotFoundException, OrderLimitExceeded

MAX_ORDER_AMOUNT = Decimal("10000000")


class OrderService:
    def __init__(self, repository: OrderRepository) -> None:
        self.repository = repository

    async def get_by_id(self, order_id: int) -> OrderResponse:
        order = await self.repository.get_by_id(order_id)
        if order is None:
            raise OrderNotFoundException(order_id)
        return OrderResponse.model_validate(order)

    async def get_all(
        self,
        *,
        skip: int = 0,
        limit: int = 20,
        status: OrderStatus | None = None,
    ) -> PaginatedResponse[OrderResponse]:
        orders, total = await self.repository.get_all(
            skip=skip, limit=limit, status=status,
        )
        items = [OrderResponse.model_validate(o) for o in orders]
        return PaginatedResponse(
            items=items,
            total=total,
            skip=skip,
            limit=limit,
            has_next=(skip + limit) < total,
        )

    async def create(self, data: OrderCreate) -> OrderResponse:
        # 도메인 검증 — Router의 입력 검증과 구분
        if data.amount > MAX_ORDER_AMOUNT:
            raise OrderLimitExceeded(data.amount)

        order = Order(
            name=data.name,
            amount=data.amount,
            status=OrderStatus.CREATED,
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

### 안티패턴

```python
# BAD: Service에서 HTTP 객체 접근
class OrderService:
    async def create(self, request: Request, data: OrderCreate):
        # Request 객체에 직접 접근 — 웹 계층 의존
        user_ip = request.client.host
        # ...

# BAD: Service에서 HTTPException 발생
class OrderService:
    async def get_by_id(self, order_id: int):
        order = await self.repository.get_by_id(order_id)
        if order is None:
            # HTTPException은 웹 계층 — 도메인 예외 사용해야 함
            raise HTTPException(status_code=404, detail="Not found")
```

**규칙:** Service는 `Request`, `Response`, `HTTPException` 등 FastAPI/웹 프레임워크 객체를 절대 import하지 않는다.

---

## Repository Layer

### 책임
- 데이터 접근 추상화
- 쿼리 빌딩
- 세션/트랜잭션 관리 위임
- CRUD 기본 연산 제공

### Generic BaseRepository

```python
from typing import Generic, TypeVar

from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.base import Base

ModelT = TypeVar("ModelT", bound=Base)


class BaseRepository(Generic[ModelT]):
    def __init__(self, session: AsyncSession, model_class: type[ModelT]) -> None:
        self.session = session
        self.model_class = model_class

    async def get_by_id(self, id: int) -> ModelT | None:
        return await self.session.get(self.model_class, id)

    async def get_all(
        self,
        *,
        skip: int = 0,
        limit: int = 20,
    ) -> tuple[list[ModelT], int]:
        # 데이터 조회
        stmt = (
            select(self.model_class)
            .offset(skip)
            .limit(limit)
            .order_by(self.model_class.id.desc())
        )
        result = await self.session.execute(stmt)
        items = list(result.scalars().all())

        # 전체 개수
        count_stmt = select(func.count()).select_from(self.model_class)
        total = (await self.session.execute(count_stmt)).scalar() or 0

        return items, total

    async def create(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        await self.session.flush()
        await self.session.refresh(entity)
        return entity

    async def update(self, entity: ModelT) -> ModelT:
        await self.session.flush()
        await self.session.refresh(entity)
        return entity

    async def delete(self, entity: ModelT) -> None:
        await self.session.delete(entity)
        await self.session.flush()
```

### 도메인 특화 Repository

```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.models.order import Order, OrderStatus


class OrderRepository(BaseRepository[Order]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, Order)

    async def get_all(
        self,
        *,
        skip: int = 0,
        limit: int = 20,
        status: OrderStatus | None = None,
    ) -> tuple[list[Order], int]:
        stmt = select(Order)
        count_stmt = select(func.count()).select_from(Order)

        if status is not None:
            stmt = stmt.where(Order.status == status)
            count_stmt = count_stmt.where(Order.status == status)

        stmt = stmt.offset(skip).limit(limit).order_by(Order.created_at.desc())

        result = await self.session.execute(stmt)
        items = list(result.scalars().all())
        total = (await self.session.execute(count_stmt)).scalar() or 0

        return items, total

    async def get_with_items(self, order_id: int) -> Order | None:
        stmt = (
            select(Order)
            .options(selectinload(Order.items))
            .where(Order.id == order_id)
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def exists_by_name(self, name: str) -> bool:
        from sqlalchemy import exists as sa_exists
        stmt = select(sa_exists().where(Order.name == name))
        return (await self.session.execute(stmt)).scalar() or False
```

---

## Dependency Injection — FastAPI Depends

### 기본 DI 체인

```python
from collections.abc import AsyncGenerator

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session_factory
from app.repositories.order import OrderRepository
from app.services.order import OrderService


# 1단계: DB 세션
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        async with session.begin():
            yield session


# 2단계: Repository
def get_order_repository(
    session: AsyncSession = Depends(get_db),
) -> OrderRepository:
    return OrderRepository(session)


# 3단계: Service
def get_order_service(
    repository: OrderRepository = Depends(get_order_repository),
) -> OrderService:
    return OrderService(repository)
```

**DI 체인 규칙:**
- `get_db` → `get_repository` → `get_service` 순서
- Router에서는 `Depends(get_service)`만 사용
- Repository나 Session을 Router에서 직접 주입하지 않음

### Class-based Dependency (대안)

```python
class OrderServiceDep:
    def __init__(self, session: AsyncSession = Depends(get_db)) -> None:
        self.repository = OrderRepository(session)
        self.service = OrderService(self.repository)

    def __call__(self) -> OrderService:
        return self.service
```

**함수형 DI vs Class-based DI:**

| 기준 | 함수형 Depends | Class-based |
|------|---------------|-------------|
| 간결성 | 단순, 직관적 | 복잡한 의존성에 유리 |
| 테스트 | `app.dependency_overrides` | 동일 |
| 재사용 | 함수 조합 | 클래스 상속 |
| 권장 | 기본 선택 | 의존성 3개 이상일 때 |

---

## Exception Handling

### 커스텀 Exception 계층

```python
class DomainException(Exception):
    """모든 도메인 예외의 기본 클래스."""

    def __init__(
        self,
        message: str,
        error_code: str,
        status_code: int = 400,
    ) -> None:
        self.message = message
        self.error_code = error_code
        self.status_code = status_code
        super().__init__(message)


class NotFoundException(DomainException):
    """리소스를 찾을 수 없을 때."""

    def __init__(self, resource: str, resource_id: int | str) -> None:
        super().__init__(
            message=f"{resource}을(를) 찾을 수 없습니다: {resource_id}",
            error_code=f"{resource.upper()}_NOT_FOUND",
            status_code=404,
        )


class OrderNotFoundException(NotFoundException):
    def __init__(self, order_id: int) -> None:
        super().__init__("주문", order_id)


class DuplicateException(DomainException):
    def __init__(self, resource: str, field: str, value: str) -> None:
        super().__init__(
            message=f"이미 존재하는 {resource}입니다: {field}={value}",
            error_code=f"{resource.upper()}_DUPLICATE",
            status_code=409,
        )


class BusinessRuleException(DomainException):
    """비즈니스 규칙 위반."""
    pass


class OrderLimitExceeded(BusinessRuleException):
    def __init__(self, amount: Decimal) -> None:
        super().__init__(
            message=f"주문 한도를 초과했습니다: {amount}",
            error_code="ORDER_LIMIT_EXCEEDED",
            status_code=422,
        )


class InvalidStatusTransition(BusinessRuleException):
    def __init__(self, current: str, target: str) -> None:
        super().__init__(
            message=f"잘못된 상태 전이입니다: {current} → {target}",
            error_code="INVALID_STATUS_TRANSITION",
            status_code=422,
        )
```

### Global Exception Handler

```python
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainException)
    async def domain_exception_handler(
        request: Request, exc: DomainException,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error_code": exc.error_code,
                "message": exc.message,
                "detail": None,
            },
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={
                "error_code": "VALIDATION_ERROR",
                "message": "입력값 검증에 실패했습니다",
                "detail": exc.errors(),
            },
        )

    @app.exception_handler(Exception)
    async def unexpected_exception_handler(
        request: Request, exc: Exception,
    ) -> JSONResponse:
        import logging
        logging.exception("Unexpected error")
        return JSONResponse(
            status_code=500,
            content={
                "error_code": "INTERNAL_ERROR",
                "message": "서버 내부 오류가 발생했습니다",
                "detail": None,
            },
        )
```

### 에러 응답 형식

```json
{
    "error_code": "ORDER_NOT_FOUND",
    "message": "주문을 찾을 수 없습니다: 123",
    "detail": null
}
```

**Validation 에러 응답:**
```json
{
    "error_code": "VALIDATION_ERROR",
    "message": "입력값 검증에 실패했습니다",
    "detail": [
        {
            "loc": ["body", "name"],
            "msg": "String should have at least 1 character",
            "type": "string_too_short"
        }
    ]
}
```

---

## Pydantic V2 Schema 패턴

### Create / Update / Response 분리

```python
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class OrderCreate(BaseModel):
    """주문 생성 요청."""
    name: str = Field(..., min_length=1, max_length=100)
    amount: Decimal = Field(..., gt=0, decimal_places=2)
    status: OrderStatus = OrderStatus.CREATED


class OrderUpdate(BaseModel):
    """주문 수정 요청 — 모든 필드 선택적."""
    name: str | None = Field(None, min_length=1, max_length=100)
    amount: Decimal | None = Field(None, gt=0, decimal_places=2)
    status: OrderStatus | None = None


class OrderResponse(BaseModel):
    """주문 응답."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    amount: Decimal
    status: OrderStatus
    created_at: datetime
    updated_at: datetime
```

**핵심 규칙:**
- `model_config = ConfigDict(from_attributes=True)` — SQLAlchemy 모델에서 직접 변환
- Create에는 필수 필드, Update에는 모든 필드 Optional
- Response에는 id, timestamps 포함
- `Field(...)`로 검증 규칙 선언

### field_validator — 커스텀 검증

```python
from pydantic import field_validator

class OrderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)

    @field_validator("name")
    @classmethod
    def name_must_not_be_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("이름은 공백만으로 구성될 수 없습니다")
        return v.strip()
```

### model_validator — 필드 간 검증

```python
from pydantic import model_validator

class DateRangeFilter(BaseModel):
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def validate_date_range(self) -> "DateRangeFilter":
        if self.start_date > self.end_date:
            raise ValueError("시작일은 종료일보다 앞서야 합니다")
        return self
```

### Generic Pagination Response

```python
from typing import Generic, TypeVar
from pydantic import BaseModel

T = TypeVar("T")


class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    skip: int
    limit: int
    has_next: bool
```

### Cursor Pagination Response

```python
class CursorPage(BaseModel, Generic[T]):
    items: list[T]
    next_cursor: str | None
    has_next: bool
```

### Pydantic V1 → V2 마이그레이션 체크

| V1 (Avoid) | V2 (Use) | 비고 |
|------------|----------|------|
| `class Config:` | `model_config = ConfigDict(...)` | 클래스 변수 |
| `orm_mode = True` | `from_attributes=True` | ConfigDict 내부 |
| `.dict()` | `.model_dump()` | 메서드 이름 변경 |
| `.json()` | `.model_dump_json()` | 메서드 이름 변경 |
| `@validator` | `@field_validator` | 데코레이터 변경 |
| `@root_validator` | `@model_validator` | 데코레이터 변경 |
| `Optional[str]` | `str \| None` | Python 3.10+ |
| `from_orm(obj)` | `model_validate(obj)` | 팩토리 메서드 |
