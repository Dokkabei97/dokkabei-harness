---
name: sql-analyze
description: "SQL 쿼리 성능 분석 — 풀스캔 탐지, 인덱스 활용도, 서브쿼리 효율성, 조인 최적화"
category: review
complexity: standard
mcp-servers: []
personas: []
---

# /sql-analyze - SQL Query Performance Analysis

## Triggers
- SQL 쿼리 성능 검토 및 최적화 요청
- 슬로우 쿼리 원인 분석이 필요한 경우
- 새로운 쿼리 작성 시 성능 사전 검증
- JOIN, 서브쿼리 등 복잡한 쿼리의 효율성 판단
- 인덱스 전략 수립 및 검토
- 대용량 테이블 대상 쿼리 최적화

## Usage
```
/sql-analyze [SQL 또는 파일 경로] [options]

Options:
  --db postgres|mysql|oracle   DB 엔진 (default: postgres)
  --depth quick|deep           분석 깊이 (default: deep)
  --meta                       메타데이터 포함 분석 (Phase 2)
```

### Input Methods
1. **인라인 SQL**: 커맨드 뒤에 SQL 직접 입력
2. **파일 경로**: `.sql` 파일 또는 코드 파일 경로 지정
3. **대화형**: 커맨드 실행 후 SQL 붙여넣기

## Behavioral Flow

### 2-Phase Analysis Model

```
┌─────────────────────────────────────────────┐
│  Phase 1: Query-Only Analysis               │
│  ─────────────────────────────              │
│  SQL 구조만으로 수행 가능한 분석               │
│  • 구문 분석 및 안티패턴 탐지                  │
│  • 구조적 문제 식별 (풀스캔, 서브쿼리 등)       │
│  • 인덱스 활용 가능성 추정                     │
│  • Severity 기반 피드백 제공                   │
│                                              │
│  ➜ "메타데이터 제공 시 정밀 분석 가능" 안내     │
└──────────────────┬──────────────────────────┘
                   │ (사용자가 메타데이터 제공)
                   ▼
┌─────────────────────────────────────────────┐
│  Phase 2: Metadata-Enriched Analysis        │
│  ─────────────────────────────              │
│  테이블 정보 + 인덱스 정보로 정밀 분석         │
│  • 실행계획 추정 (Index Scan vs Seq Scan)     │
│  • 데이터 볼륨 기반 JOIN 순서 최적화           │
│  • 인덱스 매칭 검증 및 누락 인덱스 제안         │
│  • 행 수 기반 Severity 재평가                 │
│  • 구체적 인덱스 CREATE 문 제공               │
└─────────────────────────────────────────────┘
```

### Phase 1: Query-Only Analysis
1. **Parse**: SQL 구문 파싱 — 테이블, 조인, 서브쿼리, WHERE, GROUP BY, ORDER BY 식별
2. **Detect**: 8개 카테고리 안티패턴 체크리스트 적용
   - Full Table Scan 패턴
   - Index 활용 불가 패턴
   - JOIN 최적화 이슈
   - 서브쿼리 효율성
   - 데이터 볼륨 영향
   - SELECT & Projection
   - Aggregation & Grouping
   - Write Query 패턴
3. **Evaluate**: 구조 기반 Severity 분류 (Critical / High / Medium / Low)
4. **Report**: BAD/GOOD SQL 예시와 함께 피드백 제공
5. **Guide**: Phase 2를 위한 메타데이터 요청 템플릿 제공

### Phase 2: Metadata-Enriched Analysis
사용자가 아래 정보를 추가 제공한 경우 자동으로 Phase 2 진행:
- **테이블 행 수**: 각 테이블의 예상 row count
- **인덱스 정보**: 인덱스명, 컬럼, 유니크 여부
- **DDL**: CREATE TABLE 문 또는 `\d` 결과
- **EXPLAIN 결과**: EXPLAIN (ANALYZE, BUFFERS) 출력

Phase 2에서 추가 분석:
1. WHERE/JOIN 컬럼과 실제 인덱스 매칭 검증
2. 데이터 볼륨 기반 JOIN 순서 최적화 제안
3. 행 수 기반 Seq Scan vs Index Scan 판단
4. 복합 인덱스 컬럼 순서 최적화
5. 누락 인덱스 CREATE 문 자동 생성
6. Severity 재평가 (소규모 테이블은 등급 하향)

## Tool Coordination
- **Read**: SQL 파일 또는 코드 파일에서 쿼리 추출
- **Grep**: 코드베이스에서 관련 SQL 쿼리 패턴 검색
- **Glob**: SQL 파일 탐색 및 관련 엔티티/모델 파일 탐색
- **Bash**: EXPLAIN 실행 등 외부 도구 연동 (사용자 승인 필요)

## Key Patterns
- **2-Phase Analysis**: 메타데이터 없이도 유용한 분석 → 메타데이터로 정밀도 향상
- **Anti-Pattern Detection**: 8개 카테고리 체크리스트 기반 구조적 분석
- **Severity Classification**: Critical > High > Medium > Low (데이터 볼륨 반영)
- **BAD/GOOD Examples**: 모든 피드백에 개선된 SQL 예시 포함
- **Index Recommendation**: 구체적 CREATE INDEX 문 제공

## Examples

### 기본 SQL 분석 (Phase 1)
```
/sql-analyze
SELECT u.*, o.total, o.status
FROM users u
LEFT JOIN orders o ON u.id = o.customer_id
WHERE UPPER(u.email) = 'TEST@EXAMPLE.COM'
ORDER BY o.created_at DESC
```
결과: SELECT * 지적, 함수 래핑 인덱스 무효화, LEFT JOIN 필요성 검토 등

### 서브쿼리 효율성 분석
```
/sql-analyze --depth deep
SELECT * FROM products
WHERE category_id IN (
    SELECT id FROM categories WHERE department IN (
        SELECT id FROM departments WHERE name = 'Electronics'
    )
)
```
결과: 중첩 서브쿼리 → JOIN 변환 제안, EXISTS 대안 제시

### 메타데이터 포함 정밀 분석 (Phase 2)
```
/sql-analyze --meta
SQL:
  SELECT o.id, o.total, c.name
  FROM orders o
  JOIN customers c ON o.customer_id = c.id
  WHERE o.status = 'PENDING' AND o.created_at > '2024-01-01'
  ORDER BY o.created_at DESC
  LIMIT 50 OFFSET 5000

Meta:
  orders: ~10M rows, INDEX(id PK), INDEX(customer_id), INDEX(status, created_at)
  customers: ~500K rows, INDEX(id PK)
```
결과: OFFSET 페이지네이션 대안, 커버링 인덱스 제안, 데이터 볼륨 기반 정밀 분석

### 코드 내 SQL 탐색 및 분석
```
/sql-analyze src/repository/OrderRepository.kt
# 파일 내 모든 SQL 쿼리를 추출하여 분석
# @Query, createNativeQuery, JPQL 등 패턴 탐지
```

## Output Format

### Phase 1 Output
```
## SQL Performance Analysis Report

### Query
[formatted SQL]

### Analysis Phase: Phase 1 (Query-Only)
### DB Dialect: PostgreSQL
### Tables Referenced: [table list]

---

### Critical (X issues)

#### [Issue Title]
- **Category**: [category]
- **Pattern**: [anti-pattern description]
- **Impact**: [estimated impact]
- **Bad**:
  ```sql
  [problematic SQL]
  ```
- **Good**:
  ```sql
  [optimized SQL]
  ```
- **Why**: [explanation]

### High (X issues)
...

### Medium (X issues)
...

### Low (X issues)
...

---

### Optimization Summary
- Total issues: X
- Top 3 quick wins: [prioritized list]

---

### Phase 2 정밀 분석을 위한 메타데이터

아래 정보를 추가로 제공하면 더 정확한 분석이 가능합니다:

| 테이블명 | 예상 행 수 | 비고 |
|---------|-----------|------|
| [table1] | ? | |

| 테이블명 | 인덱스명 | 컬럼 | 유니크 |
|---------|---------|------|-------|
| [table1] | ? | ? | ? |

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) 결과가 있다면 함께 제공해주세요.
```

### Phase 2 Output (Phase 1에 추가)
```
### Phase 2 Enrichment

#### Index Coverage Analysis
| Table | Column(s) | Used In | Index Available | Status |
|-------|-----------|---------|----------------|--------|
| orders | customer_id | JOIN | idx_orders_cust | OK |
| orders | status | WHERE | (none) | MISSING |

#### Data Volume Impact
- orders (10M rows) JOIN customers (500K rows): 예상 결과 ~2M rows
- OFFSET 5000 on 10M rows: ~5000 rows discarded per request

#### Recommended Index Changes
| Action | Table | DDL |
|--------|-------|-----|
| CREATE | orders | `CREATE INDEX idx_orders_status_date ON orders (status, created_at DESC) INCLUDE (id, total, customer_id);` |

#### Revised Severity (볼륨 반영)
- [Issue X]: Medium → Critical (테이블 10M rows 기준)
```

## Boundaries

**Will:**
- SQL 쿼리의 구조적 성능 안티패턴 탐지 및 최적화 제안
- 풀스캔, 슬로우 쿼리 위험도 평가
- 서브쿼리 vs JOIN 변환 판단 및 개선안 제시
- 인덱스 활용도 분석 및 CREATE INDEX 문 생성
- 데이터 볼륨 기반 JOIN 순서 및 페이지네이션 최적화
- BAD/GOOD SQL 예시를 통한 구체적 피드백

**Will Not:**
- 실제 DB에 접속하여 EXPLAIN 실행 (사용자 승인 없이)
- 스키마 변경 또는 인덱스 직접 생성
- 비즈니스 로직의 정확성 검증 (성능 관점만 분석)
- 특정 벤더 종속 기능에 대한 마이그레이션 가이드
- 실시간 모니터링 또는 프로파일링 실행

## Related

- `/analyze --focus performance` - 코드 레벨 성능 분석 (SQL 포함)
- `/perf-review` - 코드 전반 성능 안티패턴 탐지
- `sql-analyzer` agent - SQL 분석 전문 에이전트 (전체 체크리스트)
- `skills/sql-analyze-guide/SKILL.md` - SQL 분석 퀵 레퍼런스
