---
name: api-gen
description: |
  API 엔드포인트 스캐폴딩 생성 — Controller/Router, Service, DTO/Schema, 테스트 스텁 (REST/GraphQL, Kotlin/Python)
  Scaffolds API endpoints — Controller/Router, Service, DTO/Schema, and test stubs for REST/GraphQL in Kotlin/Python. Use when: scaffolding a new endpoint, generating boilerplate controller/service/DTO layers, creating test stubs for a new API.
category: scaffold
complexity: basic
mcp-servers: []
personas: []
---

# /api-gen - API 엔드포인트 스캐폴딩 생성

## Triggers
- 새로운 API 엔드포인트 개발 시작 시 보일러플레이트 코드가 필요할 때
- REST 또는 GraphQL API의 표준 구조(Controller, Service, DTO)를 빠르게 생성하고 싶을 때
- 기존 프로젝트 패턴을 따르는 일관된 코드 스캐폴딩이 필요할 때
- 새로운 도메인 영역의 API 레이어를 한 번에 구축할 때

## Usage
```
/api-gen [설명] [옵션]

Options:
  --lang kotlin|python          대상 언어 (기본: auto-detect from project)
  --style rest|graphql|both|event  API 스타일 (기본: rest)
  --with-test                   테스트 스텁 포함
  --with-docs                   문서 포함 (OpenAPI/SDL)
```

## Behavioral Flow

### 스캐폴딩 생성 플로우
1. **Discover**: 프로젝트 구조 분석, 언어/프레임워크 감지, 기존 패턴 파악
   - 빌드 파일(build.gradle.kts, pyproject.toml)에서 프레임워크 식별
   - 기존 Controller/Router 파일에서 네이밍/구조 패턴 추출
   - 패키지/모듈 구조 및 디렉토리 레이아웃 확인
2. **Design**: API 설명 기반으로 엔드포인트 설계
   - REST: HTTP 메서드, 경로, 요청/응답 구조 결정
   - GraphQL: Type, Query, Mutation, Input 정의
3. **Generate**: 코드 스캐폴딩 생성
   - REST Kotlin: Controller + Service interface/impl + Request/Response DTO + (Test)
   - REST Python: Router + Service + Pydantic schema + (Test)
   - GraphQL Kotlin: Schema SDL + @SchemaMapping resolver + Input type + DataLoader + (Test)
   - GraphQL Python: Strawberry type + resolver + input type + DataLoader + (Test)
   - Event Kotlin: Event DTO + KafkaTemplate Producer + @KafkaListener Consumer + Config + (Test)
   - Event Python: Pydantic event schema + AIOKafkaProducer + AIOKafkaConsumer + (Test)
4. **Validate**: 생성된 코드 컴파일/타입 체크
5. **Document**: (--with-docs) OpenAPI fragment 또는 GraphQL SDL 추출

## Tool Coordination
- **Glob**: 프로젝트 구조 탐색, 기존 파일 패턴 발견
- **Read**: 기존 코드 패턴 분석, 빌드 설정 확인
- **Write**: 스캐폴드 파일 생성
- **Bash**: 컴파일 체크, 린트 실행

## Examples

### REST API 스캐폴딩 (Kotlin)
```
/api-gen "주문 관리 CRUD with 검색, 페이지네이션" --lang kotlin --style rest --with-test
# 생성 파일:
#   OrderController.kt, OrderService.kt, OrderServiceImpl.kt
#   CreateOrderRequest.kt, OrderResponse.kt, OrderSearchRequest.kt
#   OrderControllerTest.kt
```

### GraphQL API 스캐폴딩 (Python)
```
/api-gen "사용자 프로필 조회/수정" --lang python --style graphql
# 생성 파일:
#   user_types.py, user_resolvers.py, user_inputs.py
#   user_dataloader.py
```

### 양방향 API 스캐폴딩 + 문서
```
/api-gen "상품 카탈로그 API" --style both --with-docs
# REST + GraphQL 코드 모두 생성
# OpenAPI YAML + GraphQL SDL 문서 포함
```

### 이벤트 기반 스캐폴딩 (Kafka)
```
/api-gen "주문 완료 이벤트" --lang kotlin --style event --with-test
# 생성 파일:
#   OrderCompletedEvent.kt, OrderEventProducer.kt
#   OrderEventConsumer.kt, OrderEventConsumerTest.kt
#   KafkaConfig.kt (Producer/Consumer 설정)
```

### 간단한 단일 엔드포인트
```
/api-gen "헬스체크 엔드포인트" --lang kotlin --style rest
# HealthCheckController.kt + HealthCheckService.kt
```

## Output Format
```
## 스캐폴딩 결과

### 프로젝트 정보
- 언어: Kotlin (Spring Boot 3.x)
- 스타일: REST
- 기존 패턴: [감지된 패턴 요약]

### 생성된 파일
| 파일                        | 유형        | 경로                           |
|---------------------------|-----------|------------------------------|
| OrderController.kt        | Controller | src/main/kotlin/.../controller/ |
| OrderService.kt           | Service    | src/main/kotlin/.../service/    |
| CreateOrderRequest.kt     | DTO        | src/main/kotlin/.../dto/        |

### TODO 항목
- [ ] OrderServiceImpl.kt 비즈니스 로직 구현
- [ ] Repository 레이어 연결
- [ ] 인증/인가 설정 추가
```

## Boundaries

**Will:**
- 프로젝트 기존 패턴을 분석하여 일관된 코드 스캐폴딩 생성
- Controller/Router, Service, DTO/Schema 등 전체 레이어 파일 생성
- 테스트 스텁 및 API 문서 프래그먼트 생성 (옵션 사용 시)
- 생성된 코드의 컴파일/타입 체크 수행

**Will Not:**
- 비즈니스 로직 구현 (Service 레이어에 TODO 주석으로 표시)
- 배포 설정 또는 인프라 구성 변경
- 기존 코드 수정 또는 리팩토링
- 데이터베이스 마이그레이션 생성 (→ `/migrate` 사용)

## Related
- `/api-test` — 생성된 API의 통합 테스트 작성
- `/api-doc` — API 문서 생성 및 어노테이션 보강
- `/migrate` — 새 엔드포인트에 필요한 DB 마이그레이션 생성
