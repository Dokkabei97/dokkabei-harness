---
name: api-test
description: "기존 API 엔드포인트 통합 테스트 자동 생성 — @WebMvcTest/TestClient, MockK/pytest-mock, 인증/GraphQL 시나리오"
category: testing
complexity: basic
mcp-servers: []
personas: []
---

# /api-test - API 통합 테스트 자동 생성

## Triggers
- 기존 API 엔드포인트에 대한 통합 테스트가 없거나 부족할 때
- 새로 생성한 API 스캐폴드에 테스트를 추가하고 싶을 때
- 인증/인가 시나리오를 포함한 체계적인 테스트 케이스가 필요할 때
- GraphQL 쿼리/뮤테이션에 대한 테스트를 작성해야 할 때

## Usage
```
/api-test [대상 파일|디렉토리] [옵션]

Options:
  --slice webmvc|boot|unit      Spring Boot 테스트 슬라이스 (기본: webmvc)
  --with-auth                   인증 시나리오 포함 (401/403 케이스)
  --with-graphql                GraphQL 쿼리 테스트 포함
  --with-cache                  캐싱 동작 테스트 포함 (cache hit/miss/eviction)
  --with-events                 이벤트 발행 검증 테스트 포함 (Kafka/ApplicationEvent)
  --coverage-target 80          목표 커버리지 (기본: 80)
```

## Behavioral Flow

### 테스트 생성 플로우
1. **Discover**: 대상 파일 읽기, 프레임워크/언어 감지, 엔드포인트 목록 추출
   - Kotlin: `@GetMapping`, `@PostMapping` 등 어노테이션 파싱
   - Python: `@router.get`, `@router.post` 등 데코레이터 파싱
   - GraphQL: `@QueryMapping`, `@MutationMapping` 또는 Strawberry resolver 파싱
2. **Analyze**: 각 엔드포인트별 테스트 케이스 도출
   - **Happy path**: 정상 요청 → 정상 응답 (200/201)
   - **Validation errors**: 잘못된 입력 → 400 Bad Request
   - **Not found**: 존재하지 않는 리소스 → 404 Not Found
   - **Auth scenarios**: (--with-auth) 미인증 → 401, 권한 부족 → 403
   - **Edge cases**: 빈 목록, 페이지네이션 경계, null 필드
3. **Generate**: 테스트 파일 생성
   - Kotlin: `@WebMvcTest` + MockK + Kotest BehaviorSpec
   - Python: `TestClient` + pytest + pytest-mock
   - GraphQL: `GraphQlTester` (Kotlin) / Strawberry test client (Python)
4. **Validate**: 생성된 테스트 컴파일/문법 체크

## Tool Coordination
- **Glob**: 대상 파일 탐색, 기존 테스트 파일 확인
- **Read**: 컨트롤러/라우터 코드 분석, 의존성 파악
- **Write**: 테스트 파일 생성
- **Bash**: 테스트 컴파일 체크, 테스트 실행

## Examples

### Kotlin REST 컨트롤러 테스트
```
/api-test src/main/kotlin/controller/OrderController.kt --with-auth
# 생성: src/test/kotlin/controller/OrderControllerTest.kt
# 포함 케이스:
#   - GET /orders → 200 (목록 조회)
#   - GET /orders/{id} → 200 (단건 조회)
#   - GET /orders/{id} → 404 (존재하지 않는 주문)
#   - POST /orders → 201 (주문 생성)
#   - POST /orders → 400 (잘못된 입력)
#   - 미인증 요청 → 401
#   - 권한 부족 → 403
```

### Python FastAPI 라우터 테스트
```
/api-test app/api/routes/orders.py --coverage-target 90
# 생성: tests/api/test_orders.py
# 목표 커버리지 90%에 맞춘 테스트 케이스 도출
```

### 디렉토리 단위 + GraphQL 테스트
```
/api-test src/main/kotlin/controller/ --with-graphql
# 디렉토리 내 모든 컨트롤러에 대한 테스트 생성
# GraphQL 엔드포인트: 쿼리/뮤테이션 테스트 포함
```

### 캐싱 동작 테스트 포함
```
/api-test src/main/kotlin/controller/ProductController.kt --with-cache
# 생성: ProductControllerCacheTest.kt
# 포함 케이스:
#   - GET /products/{id} → 첫 호출 (cache miss, DB 조회)
#   - GET /products/{id} → 재호출 (cache hit, DB 미조회)
#   - PUT /products/{id} → 캐시 무효화 확인
#   - Testcontainers Redis 통합 테스트
```

### 이벤트 발행 검증 테스트 포함
```
/api-test src/main/kotlin/controller/OrderController.kt --with-events
# 포함 케이스:
#   - POST /orders → 주문 생성 시 Kafka 이벤트 발행 검증
#   - POST /orders/{id}/cancel → 취소 이벤트 발행 검증
#   - Testcontainers Kafka 통합 테스트
```

### 특정 테스트 슬라이스 지정
```
/api-test src/main/kotlin/controller/PaymentController.kt --slice boot
# @SpringBootTest 기반 전체 컨텍스트 통합 테스트
# 실제 Bean 와이어링으로 더 넓은 범위 검증
```

## Output Format
```
## 테스트 생성 결과

### 분석 요약
- 대상: OrderController.kt
- 프레임워크: Spring Boot 3.x (Kotlin)
- 엔드포인트 수: 5
- 생성 테스트 케이스: 18

### 생성된 파일
| 파일                        | 테스트 수 | 커버리지 예상 |
|---------------------------|---------|-----------|
| OrderControllerTest.kt     | 18      | ~85%      |

### 테스트 케이스 목록
| 엔드포인트              | 시나리오           | 예상 상태 |
|----------------------|-----------------|---------|
| GET /orders          | 정상 목록 조회      | 200     |
| GET /orders          | 빈 목록           | 200     |
| GET /orders/{id}     | 정상 단건 조회      | 200     |
| GET /orders/{id}     | 존재하지 않음       | 404     |
| POST /orders         | 정상 생성          | 201     |
| POST /orders         | 유효성 검증 실패     | 400     |
```

## Boundaries

**Will:**
- 대상 코드를 분석하여 체계적인 테스트 케이스 도출
- 프레임워크에 맞는 테스트 코드 생성 (WebMvcTest, TestClient 등)
- Mock 객체 설정 및 의존성 주입 코드 포함
- 인증/인가 시나리오 테스트 생성 (옵션 사용 시)
- 생성된 테스트의 컴파일/문법 검증

**Will Not:**
- 실제 데이터베이스 연동 테스트 (인메모리 DB 설정 제외)
- E2E 테스트 생성 (API 레이어 통합 테스트만)
- 기존 테스트 코드 수정 또는 삭제
- 외부 서비스 연동 테스트 (Mock 처리)

## Related
- `/api-gen` — API 스캐폴딩 생성 후 테스트 추가
- `/bean-check` — 테스트에서 발견된 DI 문제 진단
- `/graphql-check` — GraphQL 테스트와 함께 스키마 검증
