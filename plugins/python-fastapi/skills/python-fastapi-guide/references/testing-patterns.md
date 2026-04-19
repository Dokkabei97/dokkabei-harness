# Testing Patterns — pytest, Mock, httpx, Factory

Python + FastAPI 프로젝트의 테스트 작성 패턴과 전략.

---

## 테스트 피라미드

```
        ╱ E2E ╲               ~5%  — httpx + Testcontainers (전체 스택)
       ╱ Integration ╲        ~15% — httpx + TestClient (Router + DB)
      ╱ Unit Tests    ╲       ~80% — pytest + unittest.mock
     ────────────────────
```

| 레벨 | 도구 | 용도 | 속도 |
|------|------|------|------|
| Unit | pytest + mock | Service 비즈니스 로직 | 가장 빠름 |
| Integration | httpx AsyncClient | Router HTTP 매핑, 검증 | 빠름 |
| DB Integration | pytest + 실제 DB 세션 | Repository 쿼리, 모델 매핑 | 중간 |
| E2E | httpx + Testcontainers | 전체 스택 통합 | 느림 |

---

## pytest 기본 구조

### conftest.py 계층

```
tests/
├── conftest.py              # 공통 fixture (DB 세션, 클라이언트, 팩토리)
├── unit/
│   ├── conftest.py          # 단위 테스트 전용 fixture
│   └── test_order_service.py
├── integration/
│   ├── conftest.py          # 통합 테스트 전용 fixture (DB, 클라이언트)
│   └── test_order_router.py
└── e2e/
    ├── conftest.py          # E2E 전용 fixture (Testcontainers)
    └── test_order_flow.py
```

### 공통 conftest.py

```python
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    create_async_engine,
    async_sessionmaker,
)

from app.core.database import get_db
from app.main import app
from app.models.base import Base


@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture(scope="session")
async def async_engine():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def async_session(async_engine):
    session_factory = async_sessionmaker(
        async_engine, class_=AsyncSession, expire_on_commit=False,
    )
    async with session_factory() as session:
        async with session.begin():
            yield session
            await session.rollback()


@pytest.fixture
async def async_client(async_session):
    async def override_get_db():
        yield async_session

    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        yield client

    app.dependency_overrides.clear()
```

**핵심 설계:**
- `async_session` — 각 테스트마다 트랜잭션 롤백으로 격리
- `async_client` — `dependency_overrides`로 테스트 DB 세션 주입
- `scope="session"` — 엔진은 세션 전체에서 재사용 (성능)
- `expire_on_commit=False` — 커밋 후에도 객체 접근 가능

---

## 단위 테스트 — pytest + mock

### Service 테스트

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
        # Given
        order = Order(id=1, name="테스트 주문", status=OrderStatus.CREATED)
        mock_repository.get_by_id.return_value = order

        # When
        result = await service.get_by_id(1)

        # Then
        assert result.id == 1
        assert result.name == "테스트 주문"
        mock_repository.get_by_id.assert_called_once_with(1)

    async def test_존재하지_않으면_예외_발생(self, service, mock_repository):
        # Given
        mock_repository.get_by_id.return_value = None

        # When / Then
        with pytest.raises(OrderNotFoundException):
            await service.get_by_id(999)


class TestOrderServiceCreate:
    @pytest.fixture
    def mock_repository(self):
        repo = AsyncMock()
        repo.create.side_effect = lambda order: order
        return repo

    @pytest.fixture
    def service(self, mock_repository):
        return OrderService(repository=mock_repository)

    async def test_정상_생성(self, service, mock_repository):
        # Given
        data = OrderCreate(name="새 주문", amount=Decimal("10000"))

        # When
        result = await service.create(data)

        # Then
        assert result.name == "새 주문"
        mock_repository.create.assert_called_once()

    async def test_한도_초과_시_예외(self, service):
        # Given
        data = OrderCreate(name="큰 주문", amount=Decimal("99999999"))

        # When / Then
        with pytest.raises(OrderLimitExceeded):
            await service.create(data)
```

### Mock 패턴 요약

```python
from unittest.mock import AsyncMock, MagicMock, patch

# AsyncMock — 비동기 메서드 모킹
mock_repo = AsyncMock()
mock_repo.get_by_id.return_value = Order(id=1, name="test")

# side_effect — 호출 시 동작 정의
mock_repo.create.side_effect = lambda order: order
mock_repo.get_by_id.side_effect = Exception("DB error")

# 호출 검증
mock_repo.get_by_id.assert_called_once_with(1)
mock_repo.create.assert_not_called()
mock_repo.delete.assert_called()

# patch — 모듈 레벨 의존성 교체
with patch("app.services.order.send_notification") as mock_notify:
    await service.create(data)
    mock_notify.assert_called_once()
```

---

## 통합 테스트 — httpx AsyncClient

### Router 테스트

```python
import pytest
from httpx import AsyncClient


@pytest.mark.anyio
class TestOrderRouter:
    async def test_주문_생성_201(self, async_client: AsyncClient):
        # When
        response = await async_client.post(
            "/api/v1/orders",
            json={"name": "새 주문", "amount": "10000"},
        )

        # Then
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "새 주문"
        assert data["status"] == "CREATED"
        assert "id" in data

    async def test_주문_조회_200(self, async_client: AsyncClient):
        # Given — 먼저 생성
        create_response = await async_client.post(
            "/api/v1/orders",
            json={"name": "조회 테스트", "amount": "5000"},
        )
        order_id = create_response.json()["id"]

        # When
        response = await async_client.get(f"/api/v1/orders/{order_id}")

        # Then
        assert response.status_code == 200
        assert response.json()["name"] == "조회 테스트"

    async def test_존재하지_않는_주문_404(self, async_client: AsyncClient):
        response = await async_client.get("/api/v1/orders/99999")
        assert response.status_code == 404
        assert response.json()["error_code"] == "ORDER_NOT_FOUND"

    async def test_주문_수정_200(self, async_client: AsyncClient):
        # Given
        create_response = await async_client.post(
            "/api/v1/orders",
            json={"name": "수정 전", "amount": "1000"},
        )
        order_id = create_response.json()["id"]

        # When
        response = await async_client.put(
            f"/api/v1/orders/{order_id}",
            json={"name": "수정 후"},
        )

        # Then
        assert response.status_code == 200
        assert response.json()["name"] == "수정 후"

    async def test_주문_삭제_204(self, async_client: AsyncClient):
        # Given
        create_response = await async_client.post(
            "/api/v1/orders",
            json={"name": "삭제 대상", "amount": "1000"},
        )
        order_id = create_response.json()["id"]

        # When
        response = await async_client.delete(f"/api/v1/orders/{order_id}")

        # Then
        assert response.status_code == 204


@pytest.mark.anyio
class TestOrderValidation:
    async def test_이름_빈값_422(self, async_client: AsyncClient):
        response = await async_client.post(
            "/api/v1/orders",
            json={"name": "", "amount": "1000"},
        )
        assert response.status_code == 422

    async def test_금액_음수_422(self, async_client: AsyncClient):
        response = await async_client.post(
            "/api/v1/orders",
            json={"name": "테스트", "amount": "-1000"},
        )
        assert response.status_code == 422
```

---

## pytest-mock (mocker fixture)

```python
async def test_알림_발송_호출(mocker):
    mock_notify = mocker.patch(
        "app.services.order.send_notification",
        new_callable=AsyncMock,
    )
    mock_repo = AsyncMock()
    mock_repo.create.side_effect = lambda order: order
    service = OrderService(repository=mock_repo)

    await service.create(OrderCreate(name="알림 테스트", amount=Decimal("1000")))

    mock_notify.assert_called_once()
```

**pytest-mock vs unittest.mock:**

| 기준 | pytest-mock (mocker) | unittest.mock (patch) |
|------|---------------------|----------------------|
| 문법 | `mocker.patch(...)` | `with patch(...):` |
| 정리 | 자동 (fixture 범위) | 수동 (context manager) |
| fixture 통합 | 네이티브 | 별도 관리 |
| 권장 | pytest 프로젝트 | 기존 코드 호환 |

---

## Factory Boy + Faker

### 팩토리 정의

```python
import factory
from factory.alchemy import SQLAlchemyModelFactory
from faker import Faker

from app.models.order import Order, OrderStatus

fake = Faker("ko_KR")


class OrderFactory(SQLAlchemyModelFactory):
    class Meta:
        model = Order
        sqlalchemy_session_persistence = "flush"

    name = factory.LazyFunction(lambda: fake.company())
    amount = factory.LazyFunction(
        lambda: fake.pydecimal(left_digits=5, right_digits=2, positive=True)
    )
    status = OrderStatus.CREATED


class OrderItemFactory(SQLAlchemyModelFactory):
    class Meta:
        model = OrderItem
        sqlalchemy_session_persistence = "flush"

    order = factory.SubFactory(OrderFactory)
    product_name = factory.LazyFunction(lambda: fake.catch_phrase())
    quantity = factory.LazyFunction(lambda: fake.random_int(min=1, max=10))
    price = factory.LazyFunction(
        lambda: fake.pydecimal(left_digits=4, right_digits=2, positive=True)
    )
```

### 팩토리 사용

```python
# 단건 생성
order = OrderFactory(session=async_session)

# 배치 생성
orders = OrderFactory.create_batch(5, session=async_session)

# 특정 필드 오버라이드
cancelled_order = OrderFactory(
    session=async_session,
    status=OrderStatus.CANCELLED,
    name="취소된 주문",
)

# 연관 객체 포함
order_with_items = OrderFactory(session=async_session)
items = OrderItemFactory.create_batch(3, session=async_session, order=order_with_items)
```

---

## parametrize — 데이터 기반 테스트

```python
@pytest.mark.parametrize(
    "name, amount, expected_status",
    [
        ("정상 주문", "10000", 201),
        ("", "10000", 422),           # 이름 빈값
        ("x" * 101, "10000", 422),    # 이름 초과
        ("주문", "-1000", 422),        # 음수 금액
        ("주문", "0", 422),            # 0원
    ],
)
@pytest.mark.anyio
async def test_주문_생성_검증(
    async_client: AsyncClient,
    name: str,
    amount: str,
    expected_status: int,
):
    response = await async_client.post(
        "/api/v1/orders",
        json={"name": name, "amount": amount},
    )
    assert response.status_code == expected_status


@pytest.mark.parametrize(
    "current_status, target_status, should_succeed",
    [
        (OrderStatus.CREATED, OrderStatus.CONFIRMED, True),
        (OrderStatus.CREATED, OrderStatus.CANCELLED, True),
        (OrderStatus.CREATED, OrderStatus.DELIVERED, False),
        (OrderStatus.CONFIRMED, OrderStatus.SHIPPED, True),
        (OrderStatus.SHIPPED, OrderStatus.CANCELLED, False),
    ],
)
async def test_상태_전이_검증(current_status, target_status, should_succeed):
    order = Order(id=1, name="test", status=current_status)
    if should_succeed:
        order.validate_status_transition(target_status)
    else:
        with pytest.raises(ValueError):
            order.validate_status_transition(target_status)
```

---

## 테스트 격리 전략

### 트랜잭션 롤백 (권장)

```python
@pytest.fixture
async def async_session(async_engine):
    async with AsyncSession(async_engine) as session:
        async with session.begin():
            yield session
            await session.rollback()  # 매 테스트 후 롤백
```

**장점:** 빠름, 깨끗한 격리.  
**주의:** 실제 커밋이 필요한 테스트에서는 사용 불가 (e.g., unique 제약조건 테스트).

### 테이블 Truncate (대안)

```python
@pytest.fixture(autouse=True)
async def clean_db(async_session):
    yield
    for table in reversed(Base.metadata.sorted_tables):
        await async_session.execute(table.delete())
    await async_session.commit()
```

### dependency_overrides 정리

```python
@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()  # 반드시 정리!
```

**정리하지 않으면:** 이전 테스트의 override가 다음 테스트에 영향을 줌.

---

## 비동기 테스트 설정

### pytest-anyio (권장)

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"  # pytest-asyncio 사용 시
# 또는
[tool.pytest.ini_options]
# pytest-anyio는 @pytest.mark.anyio 마커 사용
```

```python
# pytest-anyio
@pytest.mark.anyio
async def test_async_operation():
    result = await some_async_function()
    assert result is not None

# pytest-asyncio
@pytest.mark.asyncio
async def test_async_operation():
    result = await some_async_function()
    assert result is not None
```

**pytest-anyio vs pytest-asyncio:**

| 기준 | pytest-anyio | pytest-asyncio |
|------|-------------|----------------|
| 백엔드 | asyncio + trio | asyncio only |
| 설정 | `anyio_backend` fixture | `asyncio_mode` 설정 |
| 마커 | `@pytest.mark.anyio` | `@pytest.mark.asyncio` |
| FastAPI 호환 | AnyIO 기반이므로 자연스러움 | 별도 설정 필요 |
| 권장 | FastAPI 프로젝트 | 기존 asyncio 프로젝트 |

---

## 흔한 실수와 해결

### 1. 불필요한 전체 앱 로드

```python
# BAD: Service 단위 테스트에서 전체 앱 로드
from app.main import app  # FastAPI 앱 전체 초기화

# GOOD: 필요한 모듈만 임포트
from app.services.order import OrderService
from app.repositories.order import OrderRepository
```

### 2. 테스트 간 상태 공유

```python
# BAD: 모듈 레벨 변수로 상태 공유
test_order_id = None  # 테스트 간 의존

def test_create():
    global test_order_id
    test_order_id = create_order()

def test_get():
    get_order(test_order_id)  # test_create가 먼저 실행되어야 함

# GOOD: fixture로 독립적 테스트
@pytest.fixture
async def created_order(async_client):
    response = await async_client.post(
        "/api/v1/orders",
        json={"name": "fixture 주문", "amount": "1000"},
    )
    return response.json()

async def test_get(async_client, created_order):
    response = await async_client.get(f"/api/v1/orders/{created_order['id']}")
    assert response.status_code == 200
```

### 3. Assertion 메시지 부재

```python
# BAD: 실패 시 원인 불명확
assert response.status_code == 201

# GOOD: 실패 시 디버깅 용이
assert response.status_code == 201, f"Expected 201, got {response.status_code}: {response.json()}"
```

### 4. Fixture Scope 오용

```python
# BAD: function scope에서 무거운 리소스 생성 (매 테스트마다 DB 엔진 생성)
@pytest.fixture  # 기본: scope="function"
async def engine():
    engine = create_async_engine("...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()

# GOOD: session scope으로 한 번만 생성
@pytest.fixture(scope="session")
async def engine():
    engine = create_async_engine("...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()
```

| Scope | 용도 | 예시 |
|-------|------|------|
| `session` | 전체 테스트에서 한 번 | DB 엔진, 테이블 생성 |
| `module` | 파일당 한 번 | 모듈별 공유 데이터 |
| `function` (기본) | 매 테스트마다 | DB 세션, 클라이언트 |

---

## Testcontainers (실제 DB 테스트)

```python
import pytest
from testcontainers.postgres import PostgresContainer
from sqlalchemy.ext.asyncio import create_async_engine


@pytest.fixture(scope="session")
async def postgres_engine():
    with PostgresContainer("postgres:16-alpine") as postgres:
        url = postgres.get_connection_url().replace(
            "psycopg2", "asyncpg",
        )
        engine = create_async_engine(url)
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        yield engine
        await engine.dispose()
```

**Testcontainers 사용 시기:**
- PostgreSQL 고유 기능 테스트 (JSONB, 배열, CTE)
- 마이그레이션 스크립트 검증
- SQLite로 대체 불가능한 쿼리 테스트
- CI/CD 파이프라인에서 안정적인 DB 테스트
