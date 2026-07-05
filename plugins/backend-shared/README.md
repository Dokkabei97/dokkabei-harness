# backend-shared

> 언어·프레임워크에 종속되지 않는 백엔드 공통 계층 — API 설계부터 마이그레이션·아키텍처·운영 패턴까지 어느 스택에서든 재사용한다.

## 개요

`backend-shared`는 Kotlin/Spring, Python/FastAPI, Go/mux 등 어떤 백엔드 스택에서도 통용되는 **언어 중립 공통 계층**을 제공한다. REST/GraphQL API 계약 설계, 안전한 DB 마이그레이션, 헥사고날 아키텍처, 그리고 관측성·캐싱·이벤트·회복탄력성·보안·DTO·테스트 같은 횡단 관심사를 커맨드(실행)·에이전트(전문 분석)·스킬(레퍼런스)의 3계층으로 나눠 담았다.

설계 의도는 "언어별로 중복되는 판단 기준을 한곳에 모으는 것"이다. 특정 프레임워크의 관용 코드나 세부 API는 언어 특화 플러그인(`kotlin-spring`, `python-fastapi`, `go-mux`)이 맡고, 이 플러그인은 스택이 바뀌어도 변하지 않는 원칙·체크리스트·계약 설계를 담당한다. 새 API를 뚫거나, 스키마를 무중단으로 바꾸거나, 아키텍처 경계를 검증할 때 언어와 무관하게 먼저 참조하는 기반 레이어로 쓴다. 여기에 더해 `context7-docs-guide`가 버전 민감 API의 환각을 차단하는 최신 문서 조회 공통 규약을 제공해, 4종 스택의 코드 생성이 이를 참조한다.

## 구성요소

### 커맨드

- `/api-design` — REST API 엔드포인트를 요구사항 기반으로 설계하고 Controller + DTO + 에러 핸들링 코드까지 생성한다.
- `/api-gen` — API 엔드포인트 스캐폴딩(Controller/Router, Service, DTO/Schema, 테스트 스텁)을 REST/GraphQL·Kotlin/Python으로 생성한다.
- `/api-doc` — 코드 기반으로 API 문서를 생성한다(OpenAPI 3.0 스펙, GraphQL SDL, 요청/응답 예시, springdoc/FastAPI 어노테이션).
- `/api-test` — 기존 API 엔드포인트의 통합 테스트를 자동 생성한다(@WebMvcTest/TestClient, MockK/pytest-mock, 인증·GraphQL 시나리오).
- `/api-perf` — API 성능을 분석한다(N+1 쿼리 JPA/SQLAlchemy 탐지, 커넥션 풀 설정, 쿼리 실행계획 힌트).
- `/bean-check` — DI 설정을 검증한다(순환 의존성, 누락된 Bean, `@Transactional` 오용, `Depends` 체인, GraphQL DataLoader).
- `/graphql-check` — GraphQL 스키마의 품질·성능·보안을 검증한다(네이밍, N+1, DataLoader 누락, depth limit, introspection, field-level 권한).
- `/event-gen` — 이벤트 기반 코드 스캐폴딩을 생성한다(Kafka Producer/Consumer, Spring ApplicationEvent, AsyncAPI 스펙).
- `/migrate` — 안전한 DB 마이그레이션을 생성한다(Flyway/Alembic, 무중단 호환성 검증, expand-contract 패턴, 롤백 스크립트).
- `/security-check` — 인증/인가 설정을 검증한다(CORS, CSRF, 헤더 보안, 엔드포인트 보호 누락 탐지 — Spring Boot/FastAPI).

### 에이전트

- `api-designer` — REST/GraphQL API 계약 설계 전문가. OpenAPI 스펙, GraphQL SDL, DTO/Input Type 설계, 유효성 검증, 에러 응답 표준화, 버전 관리를 담당한다.
- `migration-advisor` — DB 마이그레이션 안전성 전문가. 무중단 스키마 변경, expand-contract, 롤백 전략, 데이터 백필, 인덱스 영향 분석을 수행한다(model: opus).
- `infra-integration-guide` — PG/Valkey/Kafka 인프라 연동 전문가. 커넥션 관리, 직렬화, 에러 처리, 테스트 패턴을 안내한다.

### 스킬 (레퍼런스)

- `hexagonal-architecture` — 헥사고날 아키텍처 가이드. 포트/어댑터 구조, 패키지 레이아웃, 의존성 방향, 모듈 경계.
- `dto-design-patterns` — DTO 설계 패턴. Request/Response/Projection 구분, Map 지양 data class 우선, nullable 정책, Jackson/Pydantic 직렬화.
- `graphql-design-guide` — GraphQL 스키마 설계·성능·보안 가이드. 네이밍, 페이지네이션, 에러 처리, DataLoader, 쿼리 복잡도, 보안 체크리스트.
- `async-event-patterns` — 비동기 & 이벤트 패턴. Kotlin Coroutines, Spring Kafka, FastAPI BackgroundTasks, PG/Valkey/Kafka 연동.
- `caching-patterns` — 캐싱 패턴. Spring Cache `@Cacheable`/`@CacheEvict`, Valkey 패턴, FastAPI 캐싱, TTL 전략.
- `resilience-patterns` — 회복 탄력성 패턴. Circuit Breaker(Resilience4j), Retry, Timeout, Bulkhead, WebClient/httpx 에러 처리.
- `observability-patterns` — 관측성 패턴. OpenTelemetry 기반 로깅/트레이싱/메트릭, OTel Collector, Actuator, Health Check.
- `security-patterns` — 인증/인가 패턴. Spring Security JWT/OAuth2/RBAC, FastAPI OAuth2/Depends 권한, Three-Tier Boundary, OWASP Top 10 매핑.
- `migration-safety-checklist` — DB 마이그레이션 안전성 체크리스트. 무중단 변경 판단, Expand-Contract, Flyway/Alembic 규칙, 롤백 전략.
- `backend-testing-patterns` — 백엔드 테스트 설정·패턴. Spring Boot 슬라이스, MockK, Kotest, FastAPI, pytest, Testcontainers, GraphQL 테스트.
- `context7-docs-guide` — Context7 최신 문서 조회 공통 규약. 버전 민감 API 판단 기준, `resolve-library-id` → `query-docs` 절차, 미설치 시 graceful degrade, 스택별 적용 지점, 조회 비용 트레이드오프.

## 사용법

- **커맨드**는 슬래시로 직접 호출한다. 예: `/api-design 주문 생성 엔드포인트`, `/migrate orders 테이블에 status 컬럼 추가`, `/graphql-check`, `/security-check`.
- **에이전트**는 API 계약 설계·마이그레이션 안전성·인프라 연동처럼 전문 판단이 필요한 작업에서 위임·호출되어 분석 결과를 돌려준다. `migration-advisor`는 위험도가 높은 스키마 변경을 다루므로 opus 모델을 사용한다.
- **스킬**은 관련 작업(아키텍처 설계, DTO 작성, 캐싱/보안/관측성 도입 등) 중 문맥에 맞게 자동 활성화되어 판단 기준과 패턴을 주입한다. 별도 명령 없이 참조된다.
- 코드 생성 계열 커맨드(`/api-gen`, `/api-design`, `/event-gen` 등)는 버전 민감 API를 다룰 때 `context7-docs-guide` 규약에 따라 최신 문서를 조회해 환각을 줄인다.

## 의존성

`plugin.json`에 강제 `dependencies`나 `requires`는 없다. 이 플러그인만으로 언어 중립 공통 작업을 수행할 수 있다. 다만 특정 스택의 관용 코드·프레임워크 세부까지 다루려면 언어 특화 플러그인과 함께 사용하는 것을 권장한다.

- `kotlin-spring` — Kotlin/Spring Boot 특화
- `python-fastapi` — Python/FastAPI 특화
- `go-mux` — Go 특화

## 참고

- `context7-docs-guide`가 참조하는 Context7 MCP 서버는 선택 사항이다. 설치되어 있지 않으면 규약에 따라 graceful degrade하여 조회 없이 진행하므로, 미설치 환경에서도 나머지 기능은 정상 동작한다.
- 이 플러그인은 언어·프레임워크에 독립적인 공통 계층이다. 스택별 세부 구현·관용 코드는 해당 언어 특화 플러그인에서 다루므로, 두 계층을 함께 쓰면 중복 없이 역할이 나뉜다.
- `/security-check`·`security-patterns`가 제공하는 보안 점검은 개발 단계의 설정 검증 보조 도구이며, 정식 보안 감사나 침투 테스트를 대체하지 않는다.
