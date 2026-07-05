---
name: api-perf
description: |
  API 성능 분석 — N+1 쿼리(JPA/SQLAlchemy), 커넥션 풀 설정, 쿼리 실행계획 힌트
  Analyzes API performance — N+1 queries (JPA/SQLAlchemy), connection pool configuration, and query execution plan hints. Use when: an API endpoint is slow, hunting N+1 query problems, tuning connection pools, reviewing query execution plans.
category: validation
complexity: intermediate
mcp-servers: []
personas: []
---

# /api-perf - API 성능 분석

## Triggers
- API 응답 시간이 느려졌을 때
- JPA/SQLAlchemy 쿼리 최적화가 필요할 때
- 커넥션 풀 설정이 적절한지 확인하고 싶을 때
- N+1 쿼리 문제가 의심될 때
- 대량 데이터 조회 성능을 개선하고 싶을 때

## Usage
```
/api-perf [대상] [옵션]

Options:
  --lang kotlin|python|auto     대상 언어 (기본: auto)
  --focus query|pool|fetch|all  분석 영역 (기본: all)
  --fix                         최적화 제안 포함
```

## Behavioral Flow

### 분석 플로우
1. **Discover**: Repository/Query 파일 스캔, JPA 엔티티 관계 분석, SQLAlchemy relationship 매핑
   - Kotlin: `@Entity`, `@Repository`, `@Query`, `@EntityGraph` 스캔
   - Python: `relationship()`, `selectinload`, `joinedload`, `session.execute()` 패턴 스캔
2. **Analyze**: focus 영역별 성능 분석
   - **query**: N+1 패턴 탐지 (List<Entity> 반환에 @EntityGraph/JOIN FETCH/selectinload 미사용), 불필요한 SELECT * 탐지, 대량 IN절
   - **pool**: HikariCP/asyncpg 커넥션 풀 설정 분석, maximumPoolSize vs 예상 동시성, connectionTimeout 적정성
   - **fetch**: EAGER fetch 과다 사용, over-fetching (불필요한 연관 엔티티 로딩), DTO projection 미사용
3. **Evaluate**: 영향도 기반 심각도 분류 (Critical: 핫 패스의 N+1, High: 커넥션 풀 부족, Medium: over-fetching)
4. **Report**: 구조화된 성능 분석 리포트
5. **Optimize**: (--fix) 최적화 코드 제안

## Detection Patterns

### Spring Boot (Kotlin)
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| List<Entity> 반환 + @EntityGraph 없음 | 🔴 Critical | N+1 쿼리 — 개별 연관 로딩 |
| `@ManyToOne(fetch = EAGER)` | 🟡 High | 불필요한 연관 항상 로딩 |
| SELECT * 패턴 (DTO projection 미사용) | 🟡 Medium | 불필요한 컬럼 전송 |
| HikariCP maximumPoolSize 기본값(10) 사용 | 🟡 Medium | 고부하 시 커넥션 고갈 위험 |
| connectionTimeout < 3000ms | 🟡 High | 커넥션 대기 시 빠른 실패 |
| `findAll()` 무조건 호출 (페이징 없음) | 🔴 Critical | 대량 데이터 OOM 위험 |
| 복합 WHERE 조건 인덱스 미확인 | 🟡 Medium | 풀 테이블 스캔 가능 |
| `@Transactional` 범위 내 외부 HTTP 호출 | 🟡 High | 커넥션 점유 시간 증가 |

### FastAPI (Python)
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| `relationship(lazy="select")` 기본값 | 🔴 Critical | N+1 쿼리 |
| selectinload/joinedload 미사용 | 🔴 Critical | 연관 엔티티 개별 로딩 |
| asyncpg pool_size 기본값(10) | 🟡 Medium | 고부하 시 풀 고갈 |
| `session.execute(select(Model))` 전체 컬럼 | 🟡 Medium | 불필요한 데이터 전송 |
| 동기 DB 드라이버 in async context | 🔴 Critical | 이벤트 루프 블로킹 |

## Tool Coordination
- **Glob**: Repository, Entity, Model 파일 탐색
- **Grep**: N+1 패턴, fetch 전략, 커넥션 풀 설정 검색
- **Read**: 엔티티 관계 추적, 쿼리 상세 분석
- **Bash**: application.yml/config 파싱, 설정값 추출

## Examples

### 전체 분석
```
/api-perf
# 프로젝트 전체 N+1 + 커넥션 풀 + fetch 전략 분석
# 종합 성능 리포트 출력
```

### N+1 쿼리 집중 분석
```
/api-perf src/main/kotlin/ --focus query
# JPA N+1 패턴만 집중 탐지
# @EntityGraph, JOIN FETCH 누락 확인
```

### Python 커넥션 풀 분석
```
/api-perf app/ --lang python --focus pool
# asyncpg 풀 설정 분석
# pool_size, max_overflow 적정성 검토
```

### 자동 수정 포함
```
/api-perf --focus fetch --fix
# EAGER fetch, over-fetching 탐지
# 최적화 코드 제안 포함 (LAZY 전환, DTO projection 등)
```

## Output Format
```
## API 성능 분석 결과

### 요약
- 스캔 파일: 32개
- 발견 항목: 11건 (Critical: 3, High: 4, Medium: 4)
- 예상 영향: 주요 API 3개 응답시간 40-60% 개선 가능

### 상세 결과
| 심각도 | 카테고리 | 파일:라인 | 문제 | 제안 |
|--------|---------|----------|------|------|
| 🔴 Critical | query | OrderRepository.kt:28 | findByUserId() N+1 — OrderItem 개별 로딩 | @EntityGraph(attributePaths = ["items"]) 추가 |
| 🔴 Critical | query | ProductService.kt:45 | findAll() 페이징 없이 전체 조회 | Pageable 파라미터 추가, Page<Product> 반환 |
| 🟡 High | pool | application.yml:15 | HikariCP maximumPoolSize=10, 예상 동시요청 50+ | maximumPoolSize=20, minimumIdle=5 권장 |
| 🟡 High | fetch | CategoryEntity.kt:12 | @ManyToOne(fetch = EAGER) — 항상 부모 로딩 | LAZY 전환 + 필요 시 JOIN FETCH |
| 🟡 Medium | fetch | UserService.kt:30 | SELECT * — 비밀번호 포함 전체 컬럼 조회 | UserSummaryDto projection 사용 |
```

## Boundaries

**Will:**
- 정적 코드 분석 기반의 N+1 쿼리 패턴 탐지
- HikariCP/asyncpg 커넥션 풀 설정 분석
- EAGER/LAZY fetch 전략 검토
- DTO projection 미사용 탐지
- 최적화 코드 제안 (--fix 옵션)

**Will Not:**
- 실제 쿼리 실행 및 실행계획(EXPLAIN) 분석 (DBA 영역)
- 인덱스 DDL 생성 (DBA 영역)
- 부하 테스트 실행 (별도 성능 테스트 도구 필요)
- 코드 자동 수정 적용 (제안만 제공, 적용은 사용자 판단)
- APM/모니터링 연동

## Related
- `/bean-check` — DI/트랜잭션 검증
- `/graphql-check` — GraphQL N+1 특화 분석
- `spring-boot-patterns` 스킬 — JPA 쿼리 패턴 레퍼런스
