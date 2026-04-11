---
name: fastapi-api-design
description: "FastAPI REST API 설계 및 구현. 요구사항을 기반으로 API 엔드포인트를 설계하고, Router + Schema + 에러 핸들링 코드를 생성한다."
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /fastapi-api-design - FastAPI REST API 설계 및 구현

## Triggers
- 새로운 API 엔드포인트를 설계해야 할 때
- 기존 API를 리팩토링하거나 버전업할 때
- "주문 API 설계해줘", "결제 API 만들어줘"
- API 응답 형식이나 에러 처리 전략을 결정해야 할 때
- 비표준 동작(검색, 일괄 처리, 상태 전이)의 API를 설계할 때

## Usage
```
/fastapi-api-design [도메인 또는 요구사항]

Options:
  --version      API 버전 (기본: v1)
  --auth         인증 방식 (jwt, oauth2, api-key)
  --pagination   cursor | offset (기본: offset)
  --error-style  rfc7807 | custom (기본: custom)
```

## Behavioral Flow

### Phase 1: API 요구사항 분석
도메인 요구사항을 REST 리소스와 동작으로 매핑한다.

**Steps:**
1. **Resource Identification**: 핵심 리소스 식별 및 관계 매핑
   - 명사 추출 → REST 리소스 후보
   - 1:N, N:M 관계 → 중첩 리소스 여부 결정
2. **Operation Mapping**: CRUD + 커스텀 동작을 HTTP 메서드에 매핑
   - 표준 CRUD → GET, POST, PUT, PATCH, DELETE
   - 커스텀 동작 → POST `/resources/{id}/actions/{action}`
3. **Convention Check**: 기존 프로젝트 API 패턴 분석
   - URL 구조, 응답 형식, 페이지네이션, 에러 형식

### Phase 2: API 명세 설계
엔드포인트 목록, 요청/응답 스키마, 에러 코드를 정의한다.

**Steps:**
1. **Endpoint Design**: URL, HTTP Method, 상태 코드 정의
2. **Schema Design**: Request/Response Pydantic 모델 설계
3. **Error Design**: 에러 응답 코드 및 형식 정의

**Endpoint Design Checklist:**

| 항목 | 확인 사항 |
|------|----------|
| URL | 복수형 명사, kebab-case, 버전 prefix |
| Method | 리소스 CRUD에 적합한 HTTP 메서드 |
| Status | 200, 201, 204, 400, 404, 409, 422 적절히 |
| Query | 필터, 정렬, 페이지네이션 파라미터 |
| Path | 리소스 식별자 (id, slug) |
| Body | 생성/수정 요청 페이로드 |

**HTTP Status Code 가이드:**

| Code | 용도 | FastAPI 사용 |
|------|------|-------------|
| 200 | 성공 (데이터 반환) | 기본값 |
| 201 | 리소스 생성 | `status_code=status.HTTP_201_CREATED` |
| 204 | 성공 (응답 본문 없음) | `status_code=status.HTTP_204_NO_CONTENT` |
| 400 | 잘못된 요청 | `DomainException(status_code=400)` |
| 404 | 리소스 없음 | `NotFoundException` |
| 409 | 충돌 (중복) | `DuplicateException` |
| 422 | 검증 실패 | Pydantic 자동 또는 `BusinessRuleException` |

### Phase 3: 코드 생성
설계된 API 명세를 기반으로 Router + Schema + Exception 코드를 생성한다.

**Steps:**
1. **Router**: APIRouter with endpoints, Depends, response_model
2. **Schema**: Pydantic V2 Request/Response 모델
3. **Exception**: 도메인 예외 클래스 + exception_handler 등록
4. **Spec Output**: API 명세 요약표 출력

## API 설계 원칙

### URL 구조
```
# 표준 CRUD
GET    /api/v1/orders              # 목록 조회
GET    /api/v1/orders/{order_id}   # 단건 조회
POST   /api/v1/orders              # 생성
PUT    /api/v1/orders/{order_id}   # 전체 수정
PATCH  /api/v1/orders/{order_id}   # 부분 수정
DELETE /api/v1/orders/{order_id}   # 삭제

# 중첩 리소스
GET    /api/v1/orders/{order_id}/items          # 하위 리소스 목록
POST   /api/v1/orders/{order_id}/items          # 하위 리소스 생성

# 커스텀 동작 (상태 전이)
POST   /api/v1/orders/{order_id}/confirm        # 주문 확인
POST   /api/v1/orders/{order_id}/cancel         # 주문 취소

# 검색 (별도 엔드포인트)
GET    /api/v1/orders/search?q=keyword&status=CREATED
```

**규칙:**
- 복수형 명사: `orders` (✓), `order` (✗)
- kebab-case: `order-items` (✓), `orderItems` (✗)
- 동사 금지: `create-order` (✗) → POST `/orders` (✓)
- 버전 prefix: `/api/v1/` (필수)

### 페이지네이션

#### Offset 페이지네이션 (기본)

```python
from fastapi import APIRouter, Query

from app.schemas.common import PaginatedResponse
from app.schemas.order import OrderResponse


@router.get("", response_model=PaginatedResponse[OrderResponse])
async def list_orders(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    status: OrderStatus | None = Query(None),
    sort: str = Query("created_at"),
    order: str = Query("desc", pattern="^(asc|desc)$"),
    service: OrderService = Depends(get_order_service),
) -> PaginatedResponse[OrderResponse]:
    return await service.get_all(
        skip=skip, limit=limit, status=status, sort=sort, order=order,
    )
```

#### Cursor 페이지네이션 (대량 데이터)

```python
from app.schemas.common import CursorPage


@router.get("", response_model=CursorPage[OrderResponse])
async def list_orders(
    cursor: str | None = Query(None),
    size: int = Query(20, ge=1, le=100),
    service: OrderService = Depends(get_order_service),
) -> CursorPage[OrderResponse]:
    return await service.get_all(cursor=cursor, size=size)
```

### 커스텀 동작 패턴

```python
# 상태 전이 — POST /orders/{id}/confirm
@router.post("/{order_id}/confirm", response_model=OrderResponse)
async def confirm_order(
    order_id: int,
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.confirm(order_id)


# 일괄 처리 — POST /orders/batch-cancel
@router.post("/batch-cancel", response_model=BatchResult)
async def batch_cancel_orders(
    data: BatchCancelRequest,
    service: OrderService = Depends(get_order_service),
) -> BatchResult:
    return await service.batch_cancel(data.order_ids)
```

### 에러 응답 형식

**Custom 스타일 (기본):**
```python
class DomainException(Exception):
    def __init__(
        self,
        message: str,
        error_code: str,
        status_code: int = 400,
    ) -> None:
        self.message = message
        self.error_code = error_code
        self.status_code = status_code


class OrderNotFoundException(DomainException):
    def __init__(self, order_id: int) -> None:
        super().__init__(
            message=f"주문을 찾을 수 없습니다: {order_id}",
            error_code="ORDER_NOT_FOUND",
            status_code=404,
        )


# Exception Handler 등록
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
```

**RFC 7807 스타일 (--error-style rfc7807):**
```python
@app.exception_handler(DomainException)
async def domain_exception_handler(
    request: Request, exc: DomainException,
) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "type": f"https://api.example.com/errors/{exc.error_code.lower()}",
            "title": exc.error_code,
            "status": exc.status_code,
            "detail": exc.message,
            "instance": str(request.url),
        },
        media_type="application/problem+json",
    )
```

### 인증/인가

```python
from fastapi import Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> User:
    token = credentials.credentials
    payload = decode_jwt(token)
    user = await user_repository.get_by_id(payload["sub"])
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid token")
    return user


# 인증이 필요한 엔드포인트
@router.post("", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(
    data: OrderCreate,
    current_user: User = Depends(get_current_user),
    service: OrderService = Depends(get_order_service),
) -> OrderResponse:
    return await service.create(data, created_by=current_user.id)
```

## Output — API 명세 요약

```markdown
## API Specification: Order

| Method | URL | Status | Description |
|--------|-----|--------|-------------|
| GET | /api/v1/orders | 200 | 주문 목록 조회 |
| GET | /api/v1/orders/{id} | 200 | 주문 상세 조회 |
| POST | /api/v1/orders | 201 | 주문 생성 |
| PUT | /api/v1/orders/{id} | 200 | 주문 수정 |
| DELETE | /api/v1/orders/{id} | 204 | 주문 삭제 |
| POST | /api/v1/orders/{id}/confirm | 200 | 주문 확인 |
| POST | /api/v1/orders/{id}/cancel | 200 | 주문 취소 |

### Schemas
- OrderCreate: name(required), amount(required), status(optional)
- OrderUpdate: name(optional), amount(optional), status(optional)
- OrderResponse: id, name, amount, status, created_at, updated_at

### Error Codes
- ORDER_NOT_FOUND (404)
- ORDER_LIMIT_EXCEEDED (422)
- INVALID_STATUS_TRANSITION (422)
- ORDER_DUPLICATE (409)
```

## Boundaries

**Will:**
- 프로젝트 기존 API 패턴을 분석하고 일관성 유지
- RESTful 원칙에 따른 URL 설계
- Pydantic V2 기반 Request/Response Schema 생성
- 도메인 예외 + exception_handler 코드 생성
- API 명세 요약표 제공

**Will Not:**
- 기존 API 엔드포인트를 무단 수정
- Service/Repository 계층 전체를 생성 (→ `/fastapi-gen` 사용)
- 인증/인가 로직을 임의로 구현 (옵션으로만 제공)
- OpenAPI/Swagger 커스텀 설정 변경
- pyproject.toml 의존성 추가
