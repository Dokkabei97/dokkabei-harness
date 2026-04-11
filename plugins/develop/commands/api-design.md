---
name: api-design
description: "REST API 설계 및 구현. 요구사항을 기반으로 API 엔드포인트를 설계하고, Controller + DTO + 에러 핸들링 코드를 생성한다."
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /api-design - REST API 설계 및 구현

## Triggers
- 새로운 API 엔드포인트를 설계해야 할 때
- 기존 API를 리팩토링하거나 버전업할 때
- "주문 API 설계해줘", "결제 API 만들어줘"
- API 응답 형식이나 에러 처리 전략을 결정해야 할 때
- 비표준 동작(검색, 일괄 처리, 상태 전이)의 API를 설계할 때

## Usage
```
/api-design [도메인 또는 요구사항]

Options:
  --version      API 버전 (기본: v1)
  --auth         인증 방식 (jwt, oauth2, api-key)
  --pagination   cursor | offset (기본: offset)
  --error-style  rfc7807 | custom (기본: rfc7807)
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
2. **Schema Design**: Request/Response DTO 설계
3. **Error Design**: 에러 응답 형식 및 에러 코드 체계

**API Design Checklist:**

| 원칙 | 체크 항목 | 올바른 예시 |
|------|----------|------------|
| 리소스 명명 | 복수형 명사, kebab-case | `/api/v1/order-items` |
| HTTP 메서드 | 의미에 맞는 메서드 | GET=조회, POST=생성, PUT=전체수정, PATCH=부분수정, DELETE=삭제 |
| 상태 코드 | 적절한 HTTP 상태 코드 | 200, 201, 204, 400, 404, 409, 422 |
| 페이지네이션 | 일관된 페이지네이션 | `?page=0&size=20&sort=createdAt,desc` |
| 필터링 | 쿼리 파라미터로 필터 | `?status=ACTIVE&category=FOOD` |
| 버전 관리 | URL path 기반 버전 | `/api/v1/...` |
| 에러 응답 | RFC 7807 Problem Details | `{"type":"...","title":"...","status":400}` |

**HTTP Status Code Guide:**

| 상태 코드 | 의미 | 사용 시점 |
|-----------|------|----------|
| 200 OK | 성공 (본문 있음) | GET, PUT, PATCH 성공 |
| 201 Created | 리소스 생성 | POST 성공, Location 헤더 포함 |
| 204 No Content | 성공 (본문 없음) | DELETE 성공 |
| 400 Bad Request | 잘못된 요청 | 유효성 검증 실패, 잘못된 JSON |
| 401 Unauthorized | 인증 필요 | 토큰 없음/만료 |
| 403 Forbidden | 권한 없음 | 인증됨, 권한 부족 |
| 404 Not Found | 리소스 없음 | 존재하지 않는 ID |
| 409 Conflict | 충돌 | 중복 생성, 상태 충돌 |
| 422 Unprocessable | 처리 불가 | 유효하지만 처리할 수 없는 요청 |

### Phase 3: 코드 생성
설계를 기반으로 Controller, DTO, ExceptionHandler 코드를 생성한다.

**Steps:**
1. **Controller**: REST 엔드포인트 구현
2. **DTO**: Request/Response 클래스 (Bean Validation 포함)
3. **Error Handling**: GlobalExceptionHandler + 커스텀 예외
4. **API Spec Summary**: 생성된 엔드포인트 명세표

## Tool Coordination
- **Glob**: 기존 Controller, DTO, ExceptionHandler 파일 탐색
- **Read**: 기존 API 패턴 분석 (URL 구조, 응답 형식, 에러 형식)
- **Grep**: URL 매핑 패턴, `@RequestMapping`, 에러 핸들링 패턴 검색
- **Write**: Controller, DTO, ExceptionHandler 파일 생성
- **Bash**: 빌드 검증

## Examples

### Basic Usage
```
/api-design 주문 관리
# 주문 CRUD API 설계 및 구현
# → OrderController, CreateOrderRequest, OrderResponse, OrderNotFoundException
```

### Custom Operations
```
/api-design 결제 처리
# POST /api/v1/payments          — 결제 요청
# POST /api/v1/payments/{id}/cancel — 결제 취소
# GET  /api/v1/payments/{id}/status — 결제 상태 조회
```

### Nested Resources
```
/api-design 주문 상품 관리
# GET    /api/v1/orders/{orderId}/items        — 주문 상품 목록
# POST   /api/v1/orders/{orderId}/items        — 주문 상품 추가
# DELETE /api/v1/orders/{orderId}/items/{itemId} — 주문 상품 삭제
```

### Cursor Pagination
```
/api-design 피드 조회 --pagination cursor
# GET /api/v1/feeds?cursor={cursor}&size=20
# Response: { items: [...], nextCursor: "...", hasNext: true }
```

## API Response Patterns

### 성공 응답 — Controller
```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService,
) {
    @GetMapping("/{id}")
    fun findById(@PathVariable id: Long): ResponseEntity<OrderResponse> =
        ResponseEntity.ok(orderService.findById(id))

    @GetMapping
    fun findAll(
        @PageableDefault(size = 20, sort = ["createdAt"], direction = Sort.Direction.DESC)
        pageable: Pageable,
    ): ResponseEntity<Page<OrderResponse>> =
        ResponseEntity.ok(orderService.findAll(pageable))

    @PostMapping
    fun create(@Valid @RequestBody request: CreateOrderRequest): ResponseEntity<OrderResponse> {
        val created = orderService.create(request)
        val location = URI.create("/api/v1/orders/${created.id}")
        return ResponseEntity.created(location).body(created)
    }

    @PutMapping("/{id}")
    fun update(
        @PathVariable id: Long,
        @Valid @RequestBody request: UpdateOrderRequest,
    ): ResponseEntity<OrderResponse> =
        ResponseEntity.ok(orderService.update(id, request))

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun delete(@PathVariable id: Long) {
        orderService.delete(id)
    }
}
```

### 에러 응답 — RFC 7807 Problem Details
```kotlin
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(EntityNotFoundException::class)
    fun handleNotFound(ex: EntityNotFoundException): ResponseEntity<ProblemDetail> {
        val problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND,
            ex.message ?: "리소스를 찾을 수 없습니다",
        )
        problem.title = "Not Found"
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(problem)
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ResponseEntity<ProblemDetail> {
        val problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST,
            "입력값 검증에 실패했습니다",
        )
        problem.title = "Validation Failed"
        problem.setProperty("errors", ex.bindingResult.fieldErrors.map {
            mapOf("field" to it.field, "message" to it.defaultMessage)
        })
        return ResponseEntity.badRequest().body(problem)
    }
}
```

### 커스텀 동작 — 상태 전이
```kotlin
// POST /api/v1/orders/{id}/confirm  (비표준 동작)
@PostMapping("/{id}/confirm")
fun confirm(@PathVariable id: Long): ResponseEntity<OrderResponse> =
    ResponseEntity.ok(orderService.confirm(id))

// POST /api/v1/orders/{id}/cancel
@PostMapping("/{id}/cancel")
fun cancel(
    @PathVariable id: Long,
    @Valid @RequestBody request: CancelOrderRequest,
): ResponseEntity<OrderResponse> =
    ResponseEntity.ok(orderService.cancel(id, request))
```

### 커서 기반 페이지네이션
```kotlin
data class CursorPageResponse<T>(
    val items: List<T>,
    val nextCursor: String?,
    val hasNext: Boolean,
)

@GetMapping
fun findAll(
    @RequestParam(required = false) cursor: String?,
    @RequestParam(defaultValue = "20") size: Int,
): ResponseEntity<CursorPageResponse<OrderResponse>> =
    ResponseEntity.ok(orderService.findAll(cursor, size))
```

## Output — API Spec Summary

생성 완료 후 아래 형식의 명세표를 출력한다:

```
## API Endpoints

| Method | URL | Description | Status |
|--------|-----|-------------|--------|
| GET | /api/v1/orders | 주문 목록 조회 (페이지네이션) | 200 |
| GET | /api/v1/orders/{id} | 주문 단건 조회 | 200, 404 |
| POST | /api/v1/orders | 주문 생성 | 201, 400 |
| PUT | /api/v1/orders/{id} | 주문 수정 | 200, 404, 400 |
| DELETE | /api/v1/orders/{id} | 주문 삭제 | 204, 404 |
| POST | /api/v1/orders/{id}/confirm | 주문 확정 | 200, 404, 409 |
| POST | /api/v1/orders/{id}/cancel | 주문 취소 | 200, 404, 409 |
```

## Boundaries

**Will:**
- RESTful 원칙에 따른 API 설계
- 일관된 응답 형식과 에러 처리 (RFC 7807)
- Bean Validation을 활용한 입력 검증
- 기존 프로젝트 API 패턴과 일관성 유지
- 커스텀 동작을 위한 적절한 URL 설계
- API 명세표 출력

**Will Not:**
- 비즈니스 로직 구현 (Service 계층에 위임)
- 인증/인가 로직 직접 구현 (Spring Security에 위임)
- DB 스키마 변경
- 프론트엔드 코드 생성
- OpenAPI YAML/JSON 파일 직접 생성 (어노테이션 기반으로 자동 생성 유도)
