# SQLAlchemy Patterns — 모델 설계, N+1, 연관 관계, 마이그레이션

Python + FastAPI + SQLAlchemy 2.0에서 성능과 정합성을 위한 모범 사례.

---

## 모델 설계

### 기본 Model 구조

```python
from datetime import datetime
from enum import StrEnum

from sqlalchemy import String, Numeric, Enum as SAEnum, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class OrderStatus(StrEnum):
    CREATED = "CREATED"
    CONFIRMED = "CONFIRMED"
    SHIPPED = "SHIPPED"
    DELIVERED = "DELIVERED"
    CANCELLED = "CANCELLED"


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[OrderStatus] = mapped_column(
        SAEnum(OrderStatus, native_enum=False, length=20),
        default=OrderStatus.CREATED,
    )
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), onupdate=func.now(),
    )

    def validate_status_transition(self, target: OrderStatus) -> None:
        allowed = self._VALID_TRANSITIONS.get(self.status)
        if allowed is None:
            raise ValueError(f"현재 상태에서 전이 불가: {self.status}")
        if target not in allowed:
            raise ValueError(f"{self.status} → {target} 전이는 허용되지 않습니다")

    _VALID_TRANSITIONS: dict[OrderStatus, set[OrderStatus]] = {
        OrderStatus.CREATED: {OrderStatus.CONFIRMED, OrderStatus.CANCELLED},
        OrderStatus.CONFIRMED: {OrderStatus.SHIPPED, OrderStatus.CANCELLED},
        OrderStatus.SHIPPED: {OrderStatus.DELIVERED},
    }
```

### SQLAlchemy 1.x vs 2.0 스타일

```python
# BAD: 1.x 스타일 — Column, declarative_base()
from sqlalchemy import Column, Integer, String
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class Order(Base):
    __tablename__ = "orders"
    id = Column(Integer, primary_key=True)
    name = Column(String(100))


# GOOD: 2.0 스타일 — Mapped, mapped_column, DeclarativeBase
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

class Base(DeclarativeBase):
    pass

class Order(Base):
    __tablename__ = "orders"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
```

**왜 2.0 스타일인가?**
- 타입 힌트 통합 — `Mapped[str]`이 Python 타입 시스템과 일치
- IDE 자동완성 — mypy, pyright 완전 지원
- 명시적 nullable — `Mapped[str]`은 NOT NULL, `Mapped[str | None]`은 nullable
- SQLAlchemy 1.x는 2.0에서 deprecated

### TimestampMixin — 공통 Audit 필드

```python
from datetime import datetime
from sqlalchemy import func
from sqlalchemy.orm import Mapped, mapped_column


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), onupdate=func.now(),
    )


class Order(TimestampMixin, Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100))
```

**주의:** Mixin은 Base보다 먼저 상속해야 한다 (`class Order(TimestampMixin, Base)`).

### Soft Delete 패턴

```python
from datetime import datetime
from sqlalchemy import event
from sqlalchemy.orm import Mapped, mapped_column


class SoftDeleteMixin:
    deleted_at: Mapped[datetime | None] = mapped_column(default=None)

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None

    def soft_delete(self) -> None:
        from datetime import datetime as dt
        self.deleted_at = dt.now()
```

Soft Delete 적용 시 Repository에서 기본 필터를 추가해야 한다:

```python
async def get_all(self, *, include_deleted: bool = False) -> list[Order]:
    stmt = select(Order)
    if not include_deleted:
        stmt = stmt.where(Order.deleted_at.is_(None))
    result = await self.session.execute(stmt)
    return list(result.scalars().all())
```

### Enum 매핑

```python
from enum import StrEnum
from sqlalchemy import Enum as SAEnum

class OrderStatus(StrEnum):
    CREATED = "CREATED"
    CONFIRMED = "CONFIRMED"

# native_enum=False → VARCHAR로 저장 (DB 독립적, 마이그레이션 안전)
status: Mapped[OrderStatus] = mapped_column(
    SAEnum(OrderStatus, native_enum=False, length=20),
    default=OrderStatus.CREATED,
)
```

**`native_enum=False` 권장 이유:**
- DB 마이그레이션 시 enum 값 추가/삭제가 ALTER TYPE 없이 가능
- 테스트 환경에서 SQLite와 호환
- 단점: DB 레벨 제약조건 없음 (애플리케이션 레벨에서 검증)

---

## N+1 문제

### 문제 상황

```python
# BAD: N+1 쿼리 발생
orders = (await session.execute(select(Order))).scalars().all()
for order in orders:
    # 각 order마다 추가 쿼리 발생!
    print(f"주문 {order.id}: {len(order.items)}개 상품")
```

### 해결 전략

#### 1. joinedload — 단건 조회 + 연관 필요

```python
from sqlalchemy.orm import joinedload

stmt = select(Order).options(joinedload(Order.items)).where(Order.id == order_id)
result = await session.execute(stmt)
order = result.unique().scalar_one_or_none()
```

**특징:** 단일 JOIN 쿼리, 결과가 많으면 카테시안 곱으로 데이터 증폭.

#### 2. selectinload — 목록 조회 + 컬렉션 (권장)

```python
from sqlalchemy.orm import selectinload

stmt = select(Order).options(selectinload(Order.items))
result = await session.execute(stmt)
orders = result.scalars().all()
```

**특징:** `SELECT ... WHERE id IN (...)` 별도 쿼리. 카테시안 곱 없음, 페이지네이션 호환.

#### 3. subqueryload — 대량 데이터

```python
from sqlalchemy.orm import subqueryload

stmt = select(Order).options(subqueryload(Order.items))
result = await session.execute(stmt)
orders = result.scalars().all()
```

**특징:** 서브쿼리로 연관 데이터 로드. `selectinload`보다 IN 절이 너무 클 때 유용.

#### 4. 컬럼 직접 조회 — 읽기 전용 + 일부 필드

```python
stmt = (
    select(Order.id, Order.name, func.count(OrderItem.id).label("item_count"))
    .outerjoin(OrderItem)
    .group_by(Order.id, Order.name)
)
result = await session.execute(stmt)
rows = result.all()  # list[Row(id, name, item_count)]
```

### N+1 해결 전략 선택 가이드

| 상황 | 전략 | 이유 |
|------|------|------|
| 단건 조회 + 연관 1개 | `joinedload` | 쿼리 1번으로 해결 |
| 목록 조회 + 컬렉션 | `selectinload` | 카테시안 곱 방지 |
| 대량 IN 절 우려 | `subqueryload` | IN 절 대신 서브쿼리 |
| 읽기 전용 + 일부 필드 | 컬럼 직접 조회 | 최고 성능 |
| 중첩 관계 (A→B→C) | `selectinload` 체인 | `selectinload(A.b).selectinload(B.c)` |

---

## 연관 관계

### OneToMany / ManyToOne

```python
from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id"))
    order: Mapped["Order"] = relationship(back_populates="items")
    product_name: Mapped[str] = mapped_column(String(200))
    quantity: Mapped[int]
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
```

**핵심 규칙:**
- `back_populates` 양쪽에 명시 — 일관성과 IDE 지원
- `cascade="all, delete-orphan"` — 부모 삭제 시 자식도 삭제
- `lazy="selectin"` — 기본 로딩 전략 지정 (쿼리 시 override 가능)
- ForeignKey는 "자식" 쪽에 선언

### ManyToMany

```python
from sqlalchemy import Table, Column, ForeignKey

order_tag_table = Table(
    "order_tags",
    Base.metadata,
    Column("order_id", ForeignKey("orders.id"), primary_key=True),
    Column("tag_id", ForeignKey("tags.id"), primary_key=True),
)


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    tags: Mapped[list["Tag"]] = relationship(
        secondary=order_tag_table, back_populates="orders",
    )


class Tag(Base):
    __tablename__ = "tags"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(50), unique=True)
    orders: Mapped[list["Order"]] = relationship(
        secondary=order_tag_table, back_populates="tags",
    )
```

### 안티패턴: 과도한 양방향 관계

```python
# BAD: 모든 관계를 양방향으로 만들면 순환 의존 + 직렬화 문제
class User(Base):
    orders: Mapped[list["Order"]] = relationship(back_populates="user")
    reviews: Mapped[list["Review"]] = relationship(back_populates="user")
    payments: Mapped[list["Payment"]] = relationship(back_populates="user")
    # ... 10개 이상의 관계

# GOOD: 필요한 방향만 관계 설정
class User(Base):
    orders: Mapped[list["Order"]] = relationship(back_populates="user")

class Order(Base):
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    user: Mapped["User"] = relationship(back_populates="orders")

# Review는 user_id FK만 있고, relationship 없음 (필요할 때 직접 쿼리)
class Review(Base):
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
```

---

## Alembic 마이그레이션

### 기본 사용법

```bash
# 초기 설정
alembic init alembic

# 마이그레이션 생성 (autogenerate)
alembic revision --autogenerate -m "add orders table"

# 마이그레이션 적용
alembic upgrade head

# 롤백
alembic downgrade -1

# 현재 리비전 확인
alembic current

# 마이그레이션 히스토리
alembic history --verbose
```

### env.py 설정 (비동기)

```python
# alembic/env.py
from app.models.base import Base
from app.core.config import settings

target_metadata = Base.metadata

# 비동기 엔진 사용 시
from sqlalchemy.ext.asyncio import create_async_engine

async def run_async_migrations():
    connectable = create_async_engine(settings.DATABASE_URL)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()
```

### 마이그레이션 리뷰 체크리스트

| 항목 | 확인 사항 |
|------|----------|
| 컬럼 추가 | nullable 여부, default 값 설정 |
| 컬럼 삭제 | 데이터 백업 필요 여부 |
| NOT NULL 추가 | 기존 데이터에 NULL 값 존재 여부 |
| 인덱스 추가 | CONCURRENTLY 옵션 (PostgreSQL, 무중단) |
| 테이블 삭제 | FK 참조 확인, CASCADE 여부 |
| Enum 변경 | `native_enum=False`면 단순 값 변경, 아니면 ALTER TYPE 필요 |

### 주의사항

```python
# BAD: downgrade에서 데이터 손실
def downgrade():
    op.drop_column("orders", "discount_rate")  # 데이터 영구 삭제

# GOOD: downgrade에서 데이터 보존 고려
def downgrade():
    # 운영 환경에서는 컬럼 삭제 대신 deprecated 마킹 고려
    op.drop_column("orders", "discount_rate")
```

---

## 쿼리 최적화

### exists vs count

```python
# BAD: 전체 COUNT (불필요한 전체 스캔)
stmt = select(func.count(Order.id)).where(Order.status == OrderStatus.CREATED)
count = (await session.execute(stmt)).scalar()
has_orders = count > 0

# GOOD: EXISTS (첫 행 발견 즉시 중단)
stmt = select(
    exists().where(Order.status == OrderStatus.CREATED)
)
has_orders = (await session.execute(stmt)).scalar()
```

### 페이지네이션

```python
# offset/limit 페이지네이션 (단순하지만 대량 데이터에서 성능 저하)
stmt = (
    select(Order)
    .order_by(Order.created_at.desc())
    .offset(skip)
    .limit(limit)
)

# cursor 기반 페이지네이션 (대량 데이터에서 일관된 성능)
stmt = (
    select(Order)
    .where(Order.created_at < cursor_datetime)
    .order_by(Order.created_at.desc())
    .limit(limit)
)
```

### 벌크 업데이트

```python
# BAD: 개별 업데이트 (N번 쿼리)
orders = (await session.execute(select(Order).where(...))).scalars().all()
for order in orders:
    order.status = OrderStatus.CANCELLED

# GOOD: 벌크 업데이트 (1번 쿼리)
from sqlalchemy import update

stmt = (
    update(Order)
    .where(Order.status == OrderStatus.CREATED)
    .where(Order.created_at < cutoff_date)
    .values(status=OrderStatus.CANCELLED)
)
await session.execute(stmt)
```

**주의:** 벌크 업데이트는 영속성 컨텍스트를 우회한다. 업데이트 후 `session.expire_all()` 호출 필요.

### 비동기 세션 관리

```python
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker

engine = create_async_engine(
    "postgresql+asyncpg://user:pass@localhost/db",
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
)

async_session_factory = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False,
)

# FastAPI 의존성
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        async with session.begin():
            yield session
```

**`expire_on_commit=False` 설정 이유:**
- commit 후에도 객체 속성에 접근 가능 (추가 쿼리 방지)
- FastAPI 응답 직렬화 시 필요한 속성에 접근 가능
- 단점: 메모리에 stale 데이터가 남을 수 있음 (요청 단위 세션이면 문제 없음)
