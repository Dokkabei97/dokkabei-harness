---
name: graphql-design-guide
description: "GraphQL 스키마 설계 & 성능 & 보안 가이드 — 네이밍, 페이지네이션, 에러 처리, DataLoader, 쿼리 복잡도, 보안 체크리스트"
---

# GraphQL 스키마 설계 & 성능 & 보안 가이드

## 1. 스키마 설계 원칙

### Query / Mutation / Subscription 분리

```graphql
type Query {
    """단일 상품 조회"""
    product(id: ID!): Product
    """상품 목록 (페이지네이션)"""
    products(first: Int!, after: String, filter: ProductFilter): ProductConnection!
}

type Mutation {
    """상품 생성"""
    createProduct(input: CreateProductInput!): CreateProductPayload!
    """상품 수정"""
    updateProduct(id: ID!, input: UpdateProductInput!): UpdateProductPayload!
}

type Subscription {
    """주문 상태 실시간 변경 알림"""
    orderStatusChanged(orderId: ID!): OrderStatusEvent!
}
```

### 네이밍 컨벤션

| 대상 | 규칙 | 예시 |
|---|---|---|
| Field | camelCase | `createdAt`, `totalPrice` |
| Type | PascalCase | `Product`, `OrderItem` |
| Input Type | PascalCase + Input 접미사 | `CreateProductInput` |
| Enum | PascalCase (타입), SCREAMING_SNAKE (값) | `OrderStatus.PENDING_PAYMENT` |
| Mutation | 동사 + 명사 | `createProduct`, `cancelOrder` |
| Mutation 결과 | 동사 + 명사 + Payload | `CreateProductPayload` |
| Query (단건) | 명사 단수 | `product(id: ID!)` |
| Query (복수) | 명사 복수 | `products(first: Int!)` |

### Nullable vs Non-Null 결정 기준

```graphql
type Product {
    id: ID!              # Non-null: 항상 존재하는 식별자
    name: String!        # Non-null: 필수 필드
    description: String  # Nullable: 선택 필드
    price: Int!          # Non-null: 비즈니스 필수값
    discount: Int        # Nullable: 할인이 없을 수 있음
    reviews: [Review!]!  # 리스트 자체는 Non-null, 요소도 Non-null (빈 배열 가능)
    category: Category   # Nullable: 실패 시 부분 응답 허용
}
```

**결정 기준:**
- Non-null(`!`): 항상 존재가 보장되는 필드, null이면 전체 응답이 무의미한 필드
- Nullable: 외부 시스템 의존, 계산 실패 가능, 선택적 데이터
- 리스트: `[T!]!` 패턴 권장 (빈 배열 O, null 요소 X, null 리스트 X)

### Description 필수 규칙

```graphql
# Bad: description 없음
type Product {
    id: ID!
    name: String!
    salePrice: Int!
}

# Good: 모든 타입과 필드에 description 제공
"""상품 정보"""
type Product {
    """상품 고유 식별자"""
    id: ID!
    """상품명 (최대 200자)"""
    name: String!
    """할인 적용 판매가 (원 단위)"""
    salePrice: Int!
}
```

---

## 2. Input Type vs Type

### 분리 이유

```graphql
# Type: 응답 (서버 → 클라이언트), 서버가 계산하는 필드 포함
type Product {
    id: ID!
    name: String!
    price: Int!
    createdAt: DateTime!    # 서버에서 자동 생성
    reviewCount: Int!       # 서버에서 계산
}

# Input: 요청 (클라이언트 → 서버), 사용자가 제공하는 필드만
input CreateProductInput {
    name: String!
    price: Int!
    categoryId: ID!
    # id, createdAt, reviewCount는 없음
}
```

### Partial Input (업데이트용)

```graphql
# 생성: 모든 필수 필드 필요
input CreateProductInput {
    name: String!
    price: Int!
    categoryId: ID!
    description: String
}

# 수정: 모든 필드 optional (전달된 필드만 업데이트)
input UpdateProductInput {
    name: String
    price: Int
    categoryId: ID
    description: String
}
```

### Nested Input

```graphql
input CreateOrderInput {
    """배송지 정보"""
    shippingAddress: AddressInput!
    """주문 항목 (1개 이상 필수)"""
    items: [OrderItemInput!]!
    """쿠폰 코드 (선택)"""
    couponCode: String
}

input AddressInput {
    zipCode: String!
    address1: String!
    address2: String
    receiverName: String!
    receiverPhone: String!
}

input OrderItemInput {
    productId: ID!
    quantity: Int!
    """옵션 선택 (있는 경우)"""
    optionId: ID
}
```

---

## 3. Relay-style Pagination

### Connection / Edge / Node 패턴

```graphql
type ProductConnection {
    """페이지 정보"""
    pageInfo: PageInfo!
    """상품 Edge 목록"""
    edges: [ProductEdge!]!
    """전체 개수 (COUNT 쿼리, 필요 시만 요청)"""
    totalCount: Int
}

type ProductEdge {
    """커서 (페이지네이션용 opaque string)"""
    cursor: String!
    """상품 노드"""
    node: Product!
}

type PageInfo {
    hasNextPage: Boolean!
    hasPreviousPage: Boolean!
    startCursor: String
    endCursor: String
}
```

### 사용 패턴

```graphql
# Forward pagination: first + after
query {
    products(first: 20, after: "cursor_abc") {
        pageInfo {
            hasNextPage
            endCursor
        }
        edges {
            cursor
            node {
                id
                name
                price
            }
        }
    }
}

# Backward pagination: last + before
query {
    products(last: 20, before: "cursor_xyz") {
        pageInfo {
            hasPreviousPage
            startCursor
        }
        edges {
            node { id name }
        }
    }
}
```

### Cursor-based vs Offset-based

| 방식 | 장점 | 단점 | 사용 시기 |
|---|---|---|---|
| Cursor-based | 실시간 삽입/삭제에 안전, 대용량 성능 우수 | 특정 페이지 점프 불가, 구현 복잡 | 피드, 타임라인, 무한 스크롤 |
| Offset-based | 특정 페이지 점프 가능, 구현 단순 | 데이터 변경 시 중복/누락, 대용량 성능 저하 | 관리자 페이지, 검색 결과 |

```kotlin
// Cursor 구현 예시 (Kotlin)
fun encodeCursor(id: Long, createdAt: Instant): String =
    Base64.getEncoder().encodeToString("$id:$createdAt".toByteArray())

fun decodeCursor(cursor: String): Pair<Long, Instant> {
    val decoded = String(Base64.getDecoder().decode(cursor))
    val (id, timestamp) = decoded.split(":")
    return id.toLong() to Instant.parse(timestamp)
}
```

---

## 4. 에러 처리

### errors extensions 패턴

```json
{
    "data": { "createProduct": null },
    "errors": [
        {
            "message": "재고가 부족합니다",
            "locations": [{ "line": 2, "column": 3 }],
            "path": ["createProduct"],
            "extensions": {
                "code": "INSUFFICIENT_STOCK",
                "classification": "BUSINESS_ERROR",
                "productId": "123",
                "requested": 10,
                "available": 3
            }
        }
    ]
}
```

### Union Error Type 패턴 (type-safe 에러)

```graphql
type Mutation {
    createOrder(input: CreateOrderInput!): CreateOrderResult!
}

union CreateOrderResult =
    | CreateOrderSuccess
    | StockInsufficientError
    | ProductNotFoundError
    | InvalidCouponError

type CreateOrderSuccess {
    order: Order!
}

type StockInsufficientError implements Error {
    message: String!
    productId: ID!
    requested: Int!
    available: Int!
}

type ProductNotFoundError implements Error {
    message: String!
    productId: ID!
}

type InvalidCouponError implements Error {
    message: String!
    couponCode: String!
}

interface Error {
    message: String!
}
```

```graphql
# 클라이언트 사용
mutation {
    createOrder(input: { ... }) {
        ... on CreateOrderSuccess {
            order { id status }
        }
        ... on StockInsufficientError {
            message
            productId
            available
        }
        ... on ProductNotFoundError {
            message
            productId
        }
    }
}
```

### Partial Success 처리

```graphql
type BulkUpdateResult {
    """성공한 항목"""
    succeeded: [Product!]!
    """실패한 항목 (항목별 에러 정보 포함)"""
    failed: [BulkUpdateError!]!
    """전체 처리 결과 요약"""
    summary: BulkSummary!
}

type BulkUpdateError {
    productId: ID!
    message: String!
    code: String!
}

type BulkSummary {
    total: Int!
    successCount: Int!
    failureCount: Int!
}
```

---

## 5. N+1 문제 & DataLoader

### 문제 설명

```graphql
# 이 쿼리 실행 시:
query {
    products(first: 20) {
        edges {
            node {
                id
                name
                reviews { content rating }  # 상품마다 별도 쿼리 발생!
            }
        }
    }
}

# 실행되는 SQL:
# 1. SELECT * FROM products LIMIT 20                    (1회)
# 2. SELECT * FROM reviews WHERE product_id = 1          (N회)
# 3. SELECT * FROM reviews WHERE product_id = 2
# ... 총 21회 쿼리 (1 + N)
```

### DataLoader 패턴

```python
# Strawberry (Python) — batch function
async def load_reviews(product_ids: list[int]) -> list[list[Review]]:
    """product_id 목록을 받아 한 번의 쿼리로 모든 리뷰 조회"""
    # SELECT * FROM reviews WHERE product_id IN (1, 2, 3, ..., 20)  (1회)
    async with get_session() as session:
        stmt = select(ReviewModel).where(ReviewModel.product_id.in_(product_ids))
        result = await session.execute(stmt)
        reviews = result.scalars().all()

    # product_id 순서에 맞게 그룹핑하여 반환
    review_map: dict[int, list[Review]] = {pid: [] for pid in product_ids}
    for r in reviews:
        review_map[r.product_id].append(Review.from_orm(r))
    return [review_map[pid] for pid in product_ids]
```

```kotlin
// Spring @BatchMapping (Kotlin)
@Controller
class ProductController(private val reviewService: ReviewService) {

    // products 리스트 전체의 reviews를 한 번에 조회
    @BatchMapping(typeName = "Product", field = "reviews")
    fun reviews(products: List<Product>): Map<Product, List<Review>> {
        val ids = products.map { it.id }
        // SELECT * FROM reviews WHERE product_id IN (?, ?, ...) (1회)
        val grouped = reviewService.findByProductIds(ids).groupBy { it.productId }
        return products.associateWith { grouped[it.id] ?: emptyList() }
    }
}
```

### 캐시 전략

```python
# DataLoader는 요청 단위로 캐시 (같은 요청 내 동일 key는 1회만 조회)
# 요청 간 캐시는 별도 구현 필요

# 요청 단위 캐시 (기본)
loader = DataLoader(load_fn=load_reviews)
# 같은 요청 내에서 loader.load(1)을 여러 번 호출해도 1회만 실행

# 글로벌 캐시가 필요한 경우: Redis + DataLoader 조합
async def load_with_cache(keys: list[int]) -> list[Product]:
    cached = await redis.mget([f"product:{k}" for k in keys])
    missing_keys = [k for k, v in zip(keys, cached) if v is None]

    if missing_keys:
        from_db = await fetch_products(missing_keys)
        await redis.mset({f"product:{p.id}": p.json() for p in from_db})

    # keys 순서대로 결과 조합
    ...
```

---

## 6. 성능

### 쿼리 복잡도 분석

**Depth Limit** (중첩 깊이 제한)

```graphql
# depth = 4 — 너무 깊은 중첩은 서버 부하 유발
query {
    user {                    # depth 1
        orders {              # depth 2
            items {           # depth 3
                product {     # depth 4
                    reviews { # depth 5 — 차단!
                        author { ... }
                    }
                }
            }
        }
    }
}
```

```kotlin
// Spring for GraphQL — depth limit 설정
@Configuration
class GraphQlConfig {
    @Bean
    fun runtimeWiringConfigurer(): RuntimeWiringConfigurer {
        return RuntimeWiringConfigurer { builder ->
            builder.directiveWiring(MaxDepthDirectiveWiring(maxDepth = 10))
        }
    }
}
```

**Cost Analysis** (필드별 비용 산정)

```graphql
# 비용 계산 예시:
# - 스칼라 필드: 1
# - 오브젝트 필드: 5
# - 리스트 필드: 5 * first 인자값
# 최대 허용 비용: 1000

query {
    products(first: 50) {           # 비용: 5 * 50 = 250
        edges {
            node {
                name                # 비용: 1
                reviews(first: 10) { # 비용: 5 * 10 * 50 = 2500 → 초과!
                    content
                }
            }
        }
    }
}
```

### Persisted Queries & APQ

```
[Persisted Queries]
1. 빌드 타임에 허용된 쿼리를 서버에 등록
2. 클라이언트는 쿼리 ID만 전송
3. 등록되지 않은 쿼리는 거부

[APQ (Automatic Persisted Queries)]
1. 클라이언트가 쿼리 해시를 먼저 전송
2. 서버에 캐시되어 있으면 해시만으로 실행
3. 캐시 미스 시 전체 쿼리 재전송 → 서버가 캐시
```

```json
// APQ 첫 요청 (해시만)
{
    "extensions": {
        "persistedQuery": {
            "version": 1,
            "sha256Hash": "abc123..."
        }
    }
}

// 캐시 미스 → 전체 쿼리 포함 재요청
{
    "query": "query { products(first: 20) { edges { node { id name } } } }",
    "extensions": {
        "persistedQuery": {
            "version": 1,
            "sha256Hash": "abc123..."
        }
    }
}
```

---

## 7. 보안 체크리스트

### Production 환경 필수 설정

```
[ ] Introspection 비활성화
    - 프로덕션에서 스키마 노출 방지
    - 개발/스테이징에서만 활성화

[ ] Query Depth Limit 설정
    - 권장: 최대 10~15 depth
    - 무한 중첩 공격 방지

[ ] Query Breadth Limit (필드 수 제한)
    - 단일 쿼리에서 요청 가능한 최대 필드 수 제한

[ ] Query Cost/Complexity Limit 설정
    - 필드별 비용 산정 + 최대 비용 제한
    - 리스트 필드는 multiplier 적용

[ ] Rate Limiting per Query
    - 쿼리별 rate limit (단순 HTTP rate limit보다 정밀)
    - mutation은 더 엄격하게

[ ] Input Validation
    - first/last 인자 최대값 제한 (예: 100)
    - String 입력 최대 길이 제한
    - 숫자 범위 검증

[ ] Field-level Authorization
    - 필드 단위 권한 검사
    - 민감 필드(email, phone) 접근 제어

[ ] Timeout 설정
    - 쿼리 실행 최대 시간 제한 (예: 30초)
    - 무한 루프 방지
```

### Introspection 비활성화

```kotlin
// Spring for GraphQL
@Configuration
@Profile("prod")
class GraphQlSecurityConfig {
    @Bean
    fun introspectionConfigurer(): RuntimeWiringConfigurer {
        return RuntimeWiringConfigurer { builder ->
            // production에서 introspection 비활성화
        }
    }
}
```

```python
# Strawberry (Python)
import strawberry
from strawberry.extensions import DisableValidation

schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    extensions=[
        # production에서 introspection 비활성화
    ],
)
```

### Field-level Authorization

```kotlin
// Spring — @PreAuthorize와 유사한 방식
@Controller
class UserController {

    @SchemaMapping(typeName = "User", field = "email")
    fun email(user: User, @AuthenticationPrincipal principal: UserPrincipal): String? {
        // 본인이거나 관리자만 이메일 조회 가능
        return if (principal.id == user.id || principal.isAdmin) {
            user.email
        } else {
            null
        }
    }
}
```

```python
# Strawberry — permission classes
import strawberry
from strawberry.permission import BasePermission
from strawberry.types import Info

class IsAdmin(BasePermission):
    message = "관리자 권한이 필요합니다"

    def has_permission(self, source, info: Info, **kwargs) -> bool:
        return info.context["current_user"].is_admin

@strawberry.type
class Query:
    @strawberry.field(permission_classes=[IsAdmin])
    async def admin_dashboard(self, info: Info) -> DashboardData:
        ...
```

### Input Validation (first/last 제한)

```graphql
# 스키마에서 제한 명시
type Query {
    """
    상품 목록 조회.
    first는 최대 100까지 허용.
    """
    products(
        first: Int! @constraint(max: 100)
        after: String
        filter: ProductFilter
    ): ProductConnection!
}
```

```kotlin
// 서버 측 검증
@QueryMapping
fun products(
    @Argument first: Int,
    @Argument after: String?,
): ProductConnection {
    require(first in 1..100) { "first는 1~100 사이여야 합니다" }
    return productService.findProducts(first, after)
}
```

```python
# Strawberry 서버 측 검증
@strawberry.type
class Query:
    @strawberry.field
    async def products(
        self, info: Info, first: int = 20, after: str | None = None
    ) -> ProductConnection:
        if first < 1 or first > 100:
            raise ValueError("first는 1~100 사이여야 합니다")
        return await product_service.find_products(first, after)
```
