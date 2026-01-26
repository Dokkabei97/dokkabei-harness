---
name: python-backend-patterns
description: FastAPI backend patterns with Pydantic v2, SQLAlchemy 2.0, async-first architecture, and production-ready Python best practices.
---

# Python Backend Development Patterns

Modern backend patterns for FastAPI with Pydantic v2, SQLAlchemy 2.0, and async-first architecture. Covers type hints, dependency injection, and production-ready patterns.

## Technology Stack

- **Framework**: FastAPI 0.115+
- **Validation**: Pydantic v2
- **ORM**: SQLAlchemy 2.0 (async)
- **Migrations**: Alembic
- **Testing**: pytest + pytest-asyncio
- **Python**: 3.12+

## Project Structure

```
src/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI application
│   ├── config.py               # Settings & configuration
│   ├── dependencies.py         # Dependency injection
│   ├── models/                 # SQLAlchemy models
│   │   ├── __init__.py
│   │   ├── base.py
│   │   └── user.py
│   ├── schemas/                # Pydantic schemas
│   │   ├── __init__.py
│   │   └── user.py
│   ├── repositories/           # Data access layer
│   │   ├── __init__.py
│   │   └── user.py
│   ├── services/               # Business logic
│   │   ├── __init__.py
│   │   └── user.py
│   ├── routers/                # API routes
│   │   ├── __init__.py
│   │   └── users.py
│   └── core/                   # Core utilities
│       ├── __init__.py
│       ├── database.py
│       ├── security.py
│       └── exceptions.py
├── migrations/                 # Alembic migrations
│   ├── versions/
│   └── env.py
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── unit/
│   └── integration/
├── pyproject.toml
└── alembic.ini
```

## Project Configuration (pyproject.toml)

```toml
[project]
name = "my-api"
version = "0.1.0"
description = "FastAPI Backend Service"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.32.0",
    "pydantic>=2.10.0",
    "pydantic-settings>=2.6.0",
    "sqlalchemy[asyncio]>=2.0.36",
    "asyncpg>=0.30.0",
    "alembic>=1.14.0",
    "python-jose[cryptography]>=3.3.0",
    "passlib[bcrypt]>=1.7.4",
    "httpx>=0.28.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.0",
    "pytest-asyncio>=0.24.0",
    "pytest-cov>=6.0.0",
    "ruff>=0.8.0",
    "mypy>=1.13.0",
    "testcontainers>=4.8.0",
]

[tool.ruff]
target-version = "py312"
line-length = 88

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W", "UP", "B", "C4", "SIM"]
ignore = ["E501"]

[tool.ruff.lint.isort]
known-first-party = ["app"]

[tool.mypy]
python_version = "3.12"
strict = true
plugins = ["pydantic.mypy"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
```

## Configuration (config.py)

```python
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Application
    app_name: str = "My API"
    debug: bool = False
    environment: str = "development"

    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/mydb"
    database_pool_size: int = 10
    database_max_overflow: int = 20

    # Security
    secret_key: str = "change-me-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    # CORS
    cors_origins: list[str] = ["http://localhost:3000"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

## Database Setup (core/database.py)

```python
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from app.config import get_settings

settings = get_settings()

engine = create_async_engine(
    settings.database_url,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
    echo=settings.debug,
)

async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

## SQLAlchemy Models (models/user.py)

```python
from datetime import datetime
from enum import Enum
from uuid import UUID, uuid4

from sqlalchemy import String, Enum as SQLEnum, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class UserStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"


class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(
        primary_key=True,
        default=uuid4,
    )
    email: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
    )
    hashed_password: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )
    status: Mapped[UserStatus] = mapped_column(
        SQLEnum(UserStatus),
        default=UserStatus.ACTIVE,
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    def __repr__(self) -> str:
        return f"<User {self.email}>"
```

### Base Model (models/base.py)

```python
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
```

## Pydantic Schemas (schemas/user.py)

```python
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models.user import UserStatus


# Request Schemas
class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=100)
    password: str = Field(min_length=8, max_length=128)


class UserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=100)
    status: UserStatus | None = None


# Response Schemas
class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    name: str
    status: UserStatus
    created_at: datetime
    updated_at: datetime


class UserListResponse(BaseModel):
    items: list[UserResponse]
    total: int
    page: int
    size: int


# Internal Schemas
class UserInDB(UserResponse):
    hashed_password: str
```

## Repository Layer (repositories/user.py)

```python
from uuid import UUID

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User, UserStatus


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, user_id: UUID) -> User | None:
        result = await self.session.execute(
            select(User).where(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def get_by_email(self, email: str) -> User | None:
        result = await self.session.execute(
            select(User).where(User.email == email)
        )
        return result.scalar_one_or_none()

    async def exists_by_email(self, email: str) -> bool:
        result = await self.session.execute(
            select(func.count()).select_from(User).where(User.email == email)
        )
        return result.scalar_one() > 0

    async def get_all(
        self,
        *,
        status: UserStatus | None = None,
        offset: int = 0,
        limit: int = 100,
    ) -> tuple[list[User], int]:
        query = select(User)
        count_query = select(func.count()).select_from(User)

        if status:
            query = query.where(User.status == status)
            count_query = count_query.where(User.status == status)

        query = query.offset(offset).limit(limit).order_by(User.created_at.desc())

        result = await self.session.execute(query)
        count_result = await self.session.execute(count_query)

        return list(result.scalars().all()), count_result.scalar_one()

    async def create(self, user: User) -> User:
        self.session.add(user)
        await self.session.flush()
        await self.session.refresh(user)
        return user

    async def update(self, user: User) -> User:
        await self.session.flush()
        await self.session.refresh(user)
        return user

    async def delete(self, user: User) -> None:
        await self.session.delete(user)
        await self.session.flush()
```

## Service Layer (services/user.py)

```python
from uuid import UUID

from app.core.security import get_password_hash, verify_password
from app.core.exceptions import (
    ConflictError,
    NotFoundError,
    UnauthorizedError,
)
from app.models.user import User
from app.repositories.user import UserRepository
from app.schemas.user import UserCreate, UserUpdate


class UserService:
    def __init__(self, repository: UserRepository) -> None:
        self.repository = repository

    async def get_by_id(self, user_id: UUID) -> User:
        user = await self.repository.get_by_id(user_id)
        if not user:
            raise NotFoundError(f"User not found: {user_id}")
        return user

    async def get_by_email(self, email: str) -> User:
        user = await self.repository.get_by_email(email)
        if not user:
            raise NotFoundError(f"User not found: {email}")
        return user

    async def create(self, data: UserCreate) -> User:
        if await self.repository.exists_by_email(data.email):
            raise ConflictError(f"Email already registered: {data.email}")

        user = User(
            email=data.email,
            name=data.name,
            hashed_password=get_password_hash(data.password),
        )

        return await self.repository.create(user)

    async def update(self, user_id: UUID, data: UserUpdate) -> User:
        user = await self.get_by_id(user_id)

        if data.name is not None:
            user.name = data.name
        if data.status is not None:
            user.status = data.status

        return await self.repository.update(user)

    async def delete(self, user_id: UUID) -> None:
        user = await self.get_by_id(user_id)
        await self.repository.delete(user)

    async def authenticate(self, email: str, password: str) -> User:
        user = await self.repository.get_by_email(email)
        if not user or not verify_password(password, user.hashed_password):
            raise UnauthorizedError("Invalid email or password")
        return user
```

## Custom Exceptions (core/exceptions.py)

```python
from fastapi import HTTPException, status


class AppError(HTTPException):
    def __init__(
        self,
        status_code: int,
        detail: str,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(status_code=status_code, detail=detail, headers=headers)


class NotFoundError(AppError):
    def __init__(self, detail: str = "Resource not found") -> None:
        super().__init__(status_code=status.HTTP_404_NOT_FOUND, detail=detail)


class ConflictError(AppError):
    def __init__(self, detail: str = "Resource already exists") -> None:
        super().__init__(status_code=status.HTTP_409_CONFLICT, detail=detail)


class UnauthorizedError(AppError):
    def __init__(self, detail: str = "Unauthorized") -> None:
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=detail,
            headers={"WWW-Authenticate": "Bearer"},
        )


class ForbiddenError(AppError):
    def __init__(self, detail: str = "Forbidden") -> None:
        super().__init__(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


class ValidationError(AppError):
    def __init__(self, detail: str = "Validation error") -> None:
        super().__init__(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=detail)
```

## Dependency Injection (dependencies.py)

```python
from collections.abc import AsyncGenerator
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.repositories.user import UserRepository
from app.services.user import UserService


# Database Session
async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async for session in get_db():
        yield session


SessionDep = Annotated[AsyncSession, Depends(get_session)]


# Repository Dependencies
def get_user_repository(session: SessionDep) -> UserRepository:
    return UserRepository(session)


UserRepositoryDep = Annotated[UserRepository, Depends(get_user_repository)]


# Service Dependencies
def get_user_service(repository: UserRepositoryDep) -> UserService:
    return UserService(repository)


UserServiceDep = Annotated[UserService, Depends(get_user_service)]
```

## Router (routers/users.py)

```python
from uuid import UUID

from fastapi import APIRouter, Query, status

from app.dependencies import UserServiceDep
from app.models.user import UserStatus
from app.schemas.user import (
    UserCreate,
    UserUpdate,
    UserResponse,
    UserListResponse,
)

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=UserListResponse)
async def list_users(
    service: UserServiceDep,
    status: UserStatus | None = None,
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=100),
) -> UserListResponse:
    offset = (page - 1) * size
    users, total = await service.repository.get_all(
        status=status,
        offset=offset,
        limit=size,
    )
    return UserListResponse(
        items=[UserResponse.model_validate(u) for u in users],
        total=total,
        page=page,
        size=size,
    )


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: UUID,
    service: UserServiceDep,
) -> UserResponse:
    user = await service.get_by_id(user_id)
    return UserResponse.model_validate(user)


@router.post("", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    data: UserCreate,
    service: UserServiceDep,
) -> UserResponse:
    user = await service.create(data)
    return UserResponse.model_validate(user)


@router.patch("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: UUID,
    data: UserUpdate,
    service: UserServiceDep,
) -> UserResponse:
    user = await service.update(user_id, data)
    return UserResponse.model_validate(user)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: UUID,
    service: UserServiceDep,
) -> None:
    await service.delete(user_id)
```

## Main Application (main.py)

```python
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.routers import users

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # Startup
    yield
    # Shutdown


app = FastAPI(
    title=settings.app_name,
    debug=settings.debug,
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(users.router, prefix="/api/v1")


@app.get("/health")
async def health_check() -> dict[str, str]:
    return {"status": "healthy"}
```

## Security (core/security.py)

```python
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import get_settings
from app.core.exceptions import UnauthorizedError

settings = get_settings()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(
    data: dict,
    expires_delta: timedelta | None = None,
) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.access_token_expire_minutes)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)


def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.secret_key,
            algorithms=[settings.algorithm],
        )
        return payload
    except JWTError as e:
        raise UnauthorizedError("Invalid token") from e
```

## Testing

### Conftest (tests/conftest.py)

```python
from collections.abc import AsyncGenerator
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from testcontainers.postgres import PostgresContainer

from app.core.database import get_db
from app.main import app
from app.models.base import Base


@pytest.fixture(scope="session")
def postgres_container():
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres


@pytest.fixture(scope="session")
async def engine(postgres_container):
    url = postgres_container.get_connection_url().replace(
        "postgresql://", "postgresql+asyncpg://"
    )
    engine = create_async_engine(url, echo=True)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    yield engine

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

    await engine.dispose()


@pytest.fixture
async def session(engine) -> AsyncGenerator[AsyncSession, None]:
    session_maker = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    async with session_maker() as session:
        yield session
        await session.rollback()


@pytest.fixture
async def client(session) -> AsyncGenerator[AsyncClient, None]:
    async def override_get_db():
        yield session

    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        yield client

    app.dependency_overrides.clear()
```

### Unit Test (tests/unit/test_user_service.py)

```python
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError, NotFoundError
from app.models.user import User
from app.schemas.user import UserCreate
from app.services.user import UserService


@pytest.fixture
def mock_repository() -> AsyncMock:
    return AsyncMock()


@pytest.fixture
def service(mock_repository: AsyncMock) -> UserService:
    return UserService(mock_repository)


async def test_create_user_success(
    service: UserService,
    mock_repository: AsyncMock,
) -> None:
    # Arrange
    data = UserCreate(
        email="test@example.com",
        name="Test User",
        password="password123",
    )
    mock_repository.exists_by_email.return_value = False
    mock_repository.create.return_value = User(
        id=uuid4(),
        email=data.email,
        name=data.name,
        hashed_password="hashed",
    )

    # Act
    result = await service.create(data)

    # Assert
    assert result.email == data.email
    mock_repository.exists_by_email.assert_called_once_with(data.email)
    mock_repository.create.assert_called_once()


async def test_create_user_email_exists(
    service: UserService,
    mock_repository: AsyncMock,
) -> None:
    # Arrange
    data = UserCreate(
        email="existing@example.com",
        name="Test User",
        password="password123",
    )
    mock_repository.exists_by_email.return_value = True

    # Act & Assert
    with pytest.raises(ConflictError):
        await service.create(data)

    mock_repository.create.assert_not_called()


async def test_get_user_not_found(
    service: UserService,
    mock_repository: AsyncMock,
) -> None:
    # Arrange
    user_id = uuid4()
    mock_repository.get_by_id.return_value = None

    # Act & Assert
    with pytest.raises(NotFoundError):
        await service.get_by_id(user_id)
```

### Integration Test (tests/integration/test_users_api.py)

```python
import pytest
from httpx import AsyncClient


async def test_create_user(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/users",
        json={
            "email": "new@example.com",
            "name": "New User",
            "password": "password123",
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "new@example.com"
    assert data["name"] == "New User"
    assert "id" in data


async def test_create_user_invalid_email(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/users",
        json={
            "email": "invalid-email",
            "name": "Test User",
            "password": "password123",
        },
    )

    assert response.status_code == 422


async def test_get_user_not_found(client: AsyncClient) -> None:
    response = await client.get(
        "/api/v1/users/00000000-0000-0000-0000-000000000000"
    )

    assert response.status_code == 404
```

## Alembic Migrations

### Initial Migration

```python
# migrations/versions/001_create_users_table.py
"""create users table

Revision ID: 001
Revises:
Create Date: 2024-01-01 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), unique=True, nullable=False, index=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column(
            "status",
            sa.Enum("active", "inactive", "suspended", name="userstatus"),
            nullable=False,
            server_default="active",
        ),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("users")
    op.execute("DROP TYPE userstatus")
```

## Quick Reference

### Common Commands

```bash
# Development server
uvicorn app.main:app --reload --port 8000

# FastAPI dev mode (auto-reload)
fastapi dev app/main.py

# Run tests
pytest

# Run tests with coverage
pytest --cov=app --cov-report=html

# Format code
ruff format .

# Lint code
ruff check .

# Fix linting issues
ruff check --fix .

# Type checking
mypy app

# Create migration
alembic revision --autogenerate -m "description"

# Run migrations
alembic upgrade head

# Rollback migration
alembic downgrade -1
```

### Python Best Practices

1. **Type hints everywhere** - Use `mypy --strict` for validation
2. **Pydantic for validation** - Never trust external input
3. **Async by default** - Use `async def` for I/O operations
4. **Dependency injection** - Use FastAPI's `Depends()` system
5. **Repository pattern** - Separate data access from business logic
6. **Explicit > Implicit** - Clear parameter names and return types

---

**Remember**: FastAPI + Pydantic v2 provides a fast, type-safe, and well-documented API framework. Leverage async patterns, dependency injection, and automatic OpenAPI generation for a production-ready backend.
