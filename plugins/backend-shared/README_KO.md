> [English](README.md) · **한국어**

# backend-shared

> Kotlin/Go/Python 공통 백엔드 계층 — 현직 시니어도 놓치는 PostgreSQL·Kafka·Valkey·분산 호출 스페셜리스트 지식과 팀 고유 규칙.

## 개요

`backend-shared`는 모델이 이미 아는 범용 패턴(“인덱스를 걸어라”, “캐시를 써라”)을 다시 서술하지 않는다. 대신 **기본값·버전·내부 동작 때문에 강한 시니어 제너럴리스트도 놓치는 함정**을 ID 가 붙은 항목(적용 조건·신호·메커니즘·처방·반례·검증·근거)으로 담고, 팀 고유 규칙(DTO `channel` 필수, 타임아웃 상한, 캐시 키 규약)을 함께 제공한다.

ORM·마이그레이션 도구·프레임워크 버전을 단정하지 않는다. 각 스킬은 프로젝트의 빌드 파일·기존 컨벤션·프로젝트 CLAUDE.md 를 먼저 확인하는 절차로 시작하며, 프로젝트별로 필요한 항목 ID 선별은 `workflow:project-rules` 가 `.claude/rules` 로 생성·점검한다.

## 구성 요소

### 스킬 (모델 발화 진입점 3개)

- `migration-safety-checklist` — 무중단 스키마 변경. 도구 감지(Flyway·Liquibase·Alembic·dbmate·golang-migrate·goose·Atlas)와 도구별 트랜잭션 경계, PostgreSQL DDL 락 항목 PG-MIG-01~16(lock_timeout·락 대기열, PG11+ fast default, CHECK NOT VALID→VALIDATE, CONCURRENTLY 실패 시 INVALID 인덱스, 대량 백필).
- `async-event-patterns` — 백엔드 인프라 스페셜리스트 허브. 증상→항목 인덱스 + `references/` 의 PostgreSQL(PG-IDX/MVCC/POOL/PLAN/QRY/LOCK), Kafka(KFK-PRD/CON/TOP/EOS), Valkey(VK-KEY/EXP/MEM/CLI/LOCK/STR), 분산(DIST-TMO/RTY/IDEM/MSG/CACHE/NET/OBS/OPS) 항목과 팀 규칙(team-conventions.md).
- `dto-design-patterns` — 팀 DTO 규칙(DTO-T-*) + 직렬화 함정(DTO-S-*: Jackson Kotlin 명시적 null, Go nil slice, int64 ID 의 JS 정밀도, Pydantic v2 Optional, Jackson 3 unknown 필드 기본값 — `references/serialization.md`).
- `context7-docs-guide` — 버전 민감 API 의 Context7 조회 규약(짧은 레퍼런스). 스택 가이드 스킬(kotlin-spring·go-mux·python-fastapi·nextjs)이 가리킨다.

### 커맨드 (사용자 `/` 호출 전용, `disable-model-invocation`)

- `/api-design` — REST API 설계·구현(Kotlin/Spring 기준; Go·FastAPI 는 `/go-api-design`·`/fastapi-api-design`).
- `/api-doc` — 코드 기반 OpenAPI/GraphQL SDL 문서 생성.
- `/api-test` — 기존 엔드포인트 통합 테스트 생성.
- `/api-perf` — N+1·풀 설정·실행계획 분석(PG-POOL/PLAN 항목 참조).
- `/bean-check` — DI 설정 검증(Spring Boot/FastAPI).
- `/event-gen` — Kafka/ApplicationEvent 스캐폴딩(KFK 항목 참조).
- `/graphql-check` — GraphQL 스키마 검증.
- `/security-check` — 인증/인가 설정 검증.

### 에이전트

- `api-designer` — REST/GraphQL 계약 설계(`dto-design-patterns` 사전 로드, 팀 API 직관성 체크리스트 포함).
- `infra-integration-guide` — PG/Kafka/Valkey 연동 진단·리뷰(`async-event-patterns` 사전 로드, ID 항목 근거로 보고).

## 사용법

- 마이그레이션 작성·리뷰, 느린 쿼리·풀 고갈·컨슈머 랙·캐시 문제 같은 증상이 나오면 해당 스킬이 문맥으로 활성화된다. 진입 스킬 본문은 트리아지 인덱스이고 상세는 `references/` 에서 필요한 항목만 읽는다.
- 서비스 전반의 인프라 연동 점검은 `infra-integration-guide` 에이전트에 위임한다.
- 커맨드는 `/api-design 주문 생성`, `/api-perf`, `/event-gen 주문 완료 이벤트` 처럼 직접 호출한다.

## 의존성

강제 `dependencies` 없음. 스택 관용구는 `kotlin-spring`, `go-mux`, `python-fastapi`, Elasticsearch 는 `search` 플러그인과 함께 쓴다.

## 정리 이력 (2026-10)

범용 패턴 스킬(backend-testing-patterns, caching-patterns, graphql-design-guide, hexagonal-architecture, observability-patterns, security-patterns, resilience-patterns), `/api-gen`(스택별 `*-gen` 과 중복), `/migrate`·`migration-advisor`(→ `migration-safety-checklist` 로 흡수)는 `archive/components/backend-shared/` 로 이동했다. 스페셜리스트 항목과 팀 고유 문단은 허브 references 로 추출했다. 복원은 해당 경로를 되돌리면 된다.

## 참고

- Context7 MCP 는 선택 사항이다. 미설치 시 규약에 따라 조회 없이 진행한다.
- 보안 점검(`/security-check`)은 개발 단계 설정 검증 보조이며 정식 보안 감사를 대체하지 않는다.
