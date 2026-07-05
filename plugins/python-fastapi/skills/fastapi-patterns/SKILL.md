---
name: fastapi-patterns
description: |
  FastAPI (Python) 프레임워크 관용 패턴 레퍼런스 — DI, Pydantic v2, async SQLAlchemy, Alembic, 미들웨어, Strawberry GraphQL
  Idiomatic pattern reference for the FastAPI (Python) framework — DI, Pydantic v2, async SQLAlchemy, Alembic, middleware, and Strawberry GraphQL. Use when: writing FastAPI code and needing concrete idioms for Depends injection, Pydantic v2 models, async SQLAlchemy sessions, Alembic migrations, or GraphQL resolvers.
---

# FastAPI (Python) 관용 패턴 레퍼런스

## 1. Depends DI 체인

### 기본 의존성 주입

```python
from fastapi import Depends, FastAPI
from sqlalchemy.ext.asyncio import AsyncSession

app = FastAPI()

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """yield 의존성: 요청 종료 시 자동 정리"""
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """중첩 Depends: get_db를 재사용"""
    user = await user_repository.find_by_token(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="인증 실패")
    return user

async def get_admin_user(
    user: User = Depends(get_current_user),
) -> User:
    """체이닝: get_current_user를 기반으로 권한 확인"""
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="관리자 권한 필요")
    return user
```

### 캐시되는 의존성 vs 매번 생성

```python
# 같은 요청 내에서 Depends(get_db)가 여러 곳에 선언되어도
# FastAPI는 동일한 인스턴스를 캐시하여 재사용한다.

# 매번 새 인스턴스가 필요한 경우: use_cache=False
async def get_request_id() -> str:
    return str(uuid.uuid4())

@app.get("/test")
async def test(
    id1: str = Depends(get_request_id),              # 캐시됨
    id2: str = Depends(get_request_id, use_cache=False),  # 매번 생성
):
    # id1 == id1 (캐시), id2는 별도 값
    pass
```

### 클래스 기반 의존성

```python
class Pagination:
    def __init__(self, page: int = 1, size: int = 20):
        self.offset = (page - 1) * size
        self.limit = min(size, 100)  # 최대 100개 제한

@app.get("/products")
async def list_products(
    pagination: Pagination = Depends(),
    db: AsyncSession = Depends(get_db),
):
    return await product_service.list(db, pagination.offset, pagination.limit)
```

---

## 2. Pydantic v2 모델

### model_validator (before/after)

```python
from pydantic import BaseModel, model_validator, field_validator

class DateRangeRequest(BaseModel):
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def validate_date_range(self) -> "DateRangeRequest":
        if self.start_date > self.end_date:
            raise ValueError("start_date는 end_date보다 이전이어야 합니다")
        return self

class RawImportData(BaseModel):
    model_config = ConfigDict(strict=False)

    @model_validator(mode="before")
    @classmethod
    def normalize_keys(cls, data: dict) -> dict:
        """외부 API의 snake_case 변환 전처리"""
        return {k.lower().replace("-", "_"): v for k, v in data.items()}
```

### field_validator & computed fields

```python
from pydantic import BaseModel, field_validator, computed_field

class ProductCreate(BaseModel):
    name: str
    price: int
    discount_rate: float = 0.0

    @field_validator("price")
    @classmethod
    def price_must_be_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("가격은 양수여야 합니다")
        return v

    @field_validator("discount_rate")
    @classmethod
    def validate_discount(cls, v: float) -> float:
        if not 0 <= v <= 1:
            raise ValueError("할인율은 0~1 사이여야 합니다")
        return v

    @computed_field
    @property
    def final_price(self) -> int:
        return int(self.price * (1 - self.discount_rate))
```

### Generic 모델 & from_attributes

```python
from pydantic import BaseModel, ConfigDict
from typing import Generic, TypeVar

T = TypeVar("T")

class PageResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    size: int
    has_next: bool

class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)  # ORM 모드

    id: int
    name: str
    price: int

# 사용
async def list_products() -> PageResponse[ProductResponse]:
    ...
```

---

## 3. async SQLAlchemy

### 엔진 & 세션 설정

```python
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

engine = create_async_engine(
    "postgresql+asyncpg://user:pass@localhost:5432/mydb",
    echo=False,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)
```

### select() 쿼리 패턴

```python
from sqlalchemy import select, func
from sqlalchemy.orm import joinedload, selectinload

class ProductRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def find_by_id(self, product_id: int) -> Product | None:
        result = await self.session.execute(
            select(Product).where(Product.id == product_id)
        )
        return result.scalar_one_or_none()

    async def search(
        self, keyword: str | None, category_id: int | None, limit: int = 20
    ) -> list[Product]:
        stmt = select(Product)
        if keyword:
            stmt = stmt.where(Product.name.ilike(f"%{keyword}%"))
        if category_id:
            stmt = stmt.where(Product.category_id == category_id)
        stmt = stmt.order_by(Product.created_at.desc()).limit(limit)

        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def count_by_category(self) -> list[tuple[int, int]]:
        stmt = (
            select(Product.category_id, func.count())
            .group_by(Product.category_id)
        )
        result = await self.session.execute(stmt)
        return list(result.all())
```

### relationship lazy loading 주의사항 & eager loading

```python
# Bad: async 환경에서 lazy loading은 동작하지 않는다
product = await session.get(Product, 1)
# product.reviews  # MissingGreenlet 에러!

# Good: joinedload — 1:1 또는 N:1에 적합 (JOIN으로 한 번에)
stmt = (
    select(Product)
    .options(joinedload(Product.category))
    .where(Product.id == product_id)
)

# Good: selectinload — 1:N에 적합 (SELECT IN 으로 별도 쿼리)
stmt = (
    select(Order)
    .options(selectinload(Order.items).selectinload(OrderItem.product))
    .where(Order.user_id == user_id)
)
```

---

## 4. Alembic 마이그레이션

### async 엔진 설정 (env.py)

```python
# alembic/env.py
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine

def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()

async def run_async_migrations():
    connectable = create_async_engine(get_database_url())
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()

def run_migrations_online():
    asyncio.run(run_async_migrations())
```

### auto-generate 주의점

```bash
# auto-generate는 편리하지만 아래 항목은 감지하지 못한다:
# - 테이블/컬럼 이름 변경 (DROP + CREATE로 인식)
# - CHECK 제약조건 변경
# - 기존 데이터 마이그레이션 (DML)
# - 인덱스 이름 변경

# 생성 후 반드시 수동 검토 필수
alembic revision --autogenerate -m "add_product_sku_column"
```

### 수동 revision 패턴

```python
"""add product sku column

Revision ID: a1b2c3d4
"""
from alembic import op
import sqlalchemy as sa

def upgrade() -> None:
    # 1단계: nullable 컬럼 추가
    op.add_column("products", sa.Column("sku", sa.String(50), nullable=True))
    # 2단계: 기존 데이터 백필
    op.execute("UPDATE products SET sku = 'SKU-' || id WHERE sku IS NULL")
    # 3단계: NOT NULL 적용
    op.alter_column("products", "sku", nullable=False)
    # 4단계: 유니크 인덱스
    op.create_index("ix_products_sku", "products", ["sku"], unique=True)

def downgrade() -> None:
    op.drop_index("ix_products_sku", table_name="products")
    op.drop_column("products", "sku")
```

---

## 5. 미들웨어 패턴

### CORS 설정

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### Request-ID 주입 & 실행 시간 로깅

```python
import time
import uuid
from starlette.middleware.base import BaseHTTPMiddleware

class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        start_time = time.perf_counter()

        # contextvars로 request_id 전파 (로깅에 활용)
        request_id_var.set(request_id)

        response = await call_next(request)

        elapsed = time.perf_counter() - start_time
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Process-Time"] = f"{elapsed:.4f}"

        logger.info(
            "request completed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "elapsed_ms": round(elapsed * 1000, 2),
            },
        )
        return response
```

### 예외 미들웨어

```python
from fastapi import Request
from fastapi.responses import JSONResponse

@app.exception_handler(BusinessError)
async def business_error_handler(request: Request, exc: BusinessError):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "type": "about:blank",
            "title": exc.error_code,
            "status": exc.status_code,
            "detail": exc.message,
            "instance": str(request.url),
        },
    )

@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error", exc_info=exc)
    return JSONResponse(
        status_code=500,
        content={"title": "INTERNAL_ERROR", "detail": "서버 내부 오류"},
    )
```

---

## 6. Strawberry GraphQL

### Type 정의

```python
import strawberry
from datetime import datetime

@strawberry.type
class Product:
    id: strawberry.ID
    name: str
    price: int
    created_at: datetime

@strawberry.input
class CreateProductInput:
    name: str
    price: int
    category_id: int
```

### Resolver 작성

```python
from strawberry.types import Info

@strawberry.type
class Query:
    @strawberry.field(description="상품 목록 조회")
    async def products(
        self,
        info: Info,
        category: str | None = None,
        first: int = 20,
        after: str | None = None,
    ) -> ProductConnection:
        db = info.context["db"]
        return await product_service.find_products(db, category, first, after)

@strawberry.type
class Mutation:
    @strawberry.mutation(description="상품 생성")
    async def create_product(
        self, info: Info, input: CreateProductInput
    ) -> Product:
        db = info.context["db"]
        user = info.context["current_user"]
        return await product_service.create(db, user, input)
```

### DataLoader 패턴 (N+1 방지)

```python
from strawberry.dataloader import DataLoader

async def load_reviews_by_product_ids(
    product_ids: list[int],
) -> list[list[Review]]:
    """배치 함수: product_id 목록으로 리뷰를 한 번에 조회"""
    async with async_session_maker() as session:
        stmt = select(ReviewModel).where(
            ReviewModel.product_id.in_(product_ids)
        )
        result = await session.execute(stmt)
        reviews = result.scalars().all()

    review_map: dict[int, list[Review]] = {pid: [] for pid in product_ids}
    for r in reviews:
        review_map[r.product_id].append(Review.from_orm(r))

    return [review_map[pid] for pid in product_ids]

# context에 DataLoader 등록
async def get_context(request: Request, db: AsyncSession = Depends(get_db)):
    return {
        "db": db,
        "review_loader": DataLoader(load_fn=load_reviews_by_product_ids),
    }

# 사용
@strawberry.type
class Product:
    id: strawberry.ID
    name: str

    @strawberry.field
    async def reviews(self, info: Info) -> list[Review]:
        loader = info.context["review_loader"]
        return await loader.load(int(self.id))
```

### Subscription (WebSocket)

```python
import asyncio
from typing import AsyncGenerator

@strawberry.type
class Subscription:
    @strawberry.subscription(description="실시간 주문 상태 변경 알림")
    async def order_status_changed(
        self, info: Info, order_id: int
    ) -> AsyncGenerator[OrderStatus, None]:
        pubsub = info.context["pubsub"]
        async for message in pubsub.subscribe(f"order:{order_id}"):
            yield OrderStatus(
                order_id=order_id,
                status=message["status"],
                updated_at=message["updated_at"],
            )
```

### FastAPI 마운트 & 인증 연동

```python
from strawberry.fastapi import GraphQLRouter

schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    subscription=Subscription,
)

graphql_router = GraphQLRouter(
    schema,
    context_getter=get_context,
)

app.include_router(graphql_router, prefix="/graphql")
```

---

## 7. Lifespan 이벤트

### lifespan 컨텍스트 매니저

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    """애플리케이션 시작/종료 리소스 관리"""
    # Startup: 리소스 초기화
    app.state.db_engine = create_async_engine(settings.DATABASE_URL)
    app.state.redis = await aioredis.from_url(settings.REDIS_URL)
    app.state.kafka_producer = AIOKafkaProducer(
        bootstrap_servers=settings.KAFKA_BOOTSTRAP_SERVERS,
    )
    await app.state.kafka_producer.start()

    yield  # 애플리케이션 실행

    # Shutdown: 리소스 정리
    await app.state.kafka_producer.stop()
    await app.state.redis.close()
    await app.state.db_engine.dispose()

app = FastAPI(lifespan=lifespan)
```

### on_event (deprecated) → lifespan 마이그레이션

```python
# Bad: deprecated 방식
@app.on_event("startup")
async def startup():
    app.state.redis = await aioredis.from_url(REDIS_URL)

@app.on_event("shutdown")
async def shutdown():
    await app.state.redis.close()

# Good: lifespan으로 통합 (리소스 누수 방지)
@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.redis = await aioredis.from_url(REDIS_URL)
    yield
    await app.state.redis.close()
```

---

## 8. httpx 클라이언트 패턴

### 공유 클라이언트 (lifespan + Depends)

```python
import httpx
from fastapi import Depends, Request

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(connect=5.0, read=30.0, write=10.0, pool=10.0),
        limits=httpx.Limits(max_connections=100, max_keepalive_connections=20),
        headers={"User-Agent": "my-service/1.0"},
    )
    yield
    await app.state.http_client.aclose()

def get_http_client(request: Request) -> httpx.AsyncClient:
    return request.app.state.http_client
```

### httpx + tenacity 재시도

```python
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

class PaymentClient:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=0.5, min=0.5, max=5),
        retry=retry_if_exception_type((httpx.TimeoutException, httpx.HTTPStatusError)),
    )
    async def request_payment(self, request: PaymentRequest) -> PaymentResponse:
        response = await self.client.post(
            "https://api.payment.example.com/v1/payments",
            json=request.model_dump(),
        )
        response.raise_for_status()
        return PaymentResponse.model_validate(response.json())
```

### 구조적 로깅 event hook

```python
async def log_request(request: httpx.Request):
    logger.info("outbound_request", method=request.method, url=str(request.url))

async def log_response(response: httpx.Response):
    logger.info(
        "outbound_response",
        status=response.status_code,
        url=str(response.url),
        elapsed_ms=response.elapsed.total_seconds() * 1000,
    )

client = httpx.AsyncClient(
    event_hooks={"request": [log_request], "response": [log_response]},
)
```

---

## 9. Settings (BaseSettings)

### pydantic-settings 기반 설정

```python
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_nested_delimiter="__",  # DB__HOST → db.host
    )

    # 서버 설정
    app_name: str = "my-service"
    debug: bool = False

    # DB 설정
    database_url: str
    db_pool_size: int = 20
    db_max_overflow: int = 10

    # Redis 설정
    redis_url: str = "redis://localhost:6379/0"

    # Kafka 설정
    kafka_bootstrap_servers: str = "localhost:9092"

    # JWT 설정
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 30

    @field_validator("database_url")
    @classmethod
    def validate_database_url(cls, v: str) -> str:
        if not v.startswith(("postgresql", "sqlite")):
            raise ValueError("지원하지 않는 DB URL 형식")
        return v
```

### Settings를 Depends로 주입

```python
from functools import lru_cache

@lru_cache
def get_settings() -> Settings:
    return Settings()

@app.get("/info")
async def info(settings: Settings = Depends(get_settings)):
    return {"app_name": settings.app_name, "debug": settings.debug}
```

### 환경변수 우선순위

| 우선순위 | 소스 | 예시 |
|---|---|---|
| 1 (최고) | 환경변수 | `export DATABASE_URL=postgresql://...` |
| 2 | `.env` 파일 | `DATABASE_URL=postgresql://...` |
| 3 (최저) | 기본값 | `db_pool_size: int = 20` |
