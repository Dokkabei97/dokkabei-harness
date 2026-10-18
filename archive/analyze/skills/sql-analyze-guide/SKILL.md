---
name: sql-analyze-guide
description: Use this skill when writing or reviewing SQL queries. Provides quick reference for SQL performance anti-patterns, index strategy, subquery optimization, and join tuning across PostgreSQL, MySQL, and Oracle.
---

# SQL Performance Analysis Quick Reference

This skill provides a condensed checklist for identifying SQL performance anti-patterns during query writing or review.

## When to Activate

- SQL 쿼리 작성 또는 코드 리뷰 시
- 슬로우 쿼리 원인 분석이 필요할 때
- JOIN이나 서브쿼리의 효율성 판단이 필요할 때
- 인덱스 전략을 수립하거나 검토할 때
- 대용량 테이블 대상 쿼리를 최적화할 때
- ORM이 생성하는 쿼리를 검토할 때

## Core Principles

### 1. EXPLAIN First
추측하지 말고 `EXPLAIN (ANALYZE, BUFFERS)`로 확인하라. 옵티마이저의 실제 계획이 가장 정확하다.

### 2. Data Volume Awareness
100행 테이블과 1억행 테이블에서 같은 쿼리가 완전히 다르게 동작한다. 항상 데이터 규모를 고려하라.

### 3. Index Strategy
인덱스는 만능이 아니다. 선택도(selectivity)가 낮으면 풀스캔이 더 빠르다. 쓰기 부하도 고려하라.

## Quick Reference by Category

### 1. Full Table Scan Detection
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| WHERE 절 없는 대용량 테이블 조회 | 필터 조건 추가 | Critical |
| 인덱스 컬럼에 함수 적용 `UPPER(col)` | Expression index 또는 citext | High |
| 암묵적 타입 변환 `WHERE int_col = '123'` | 올바른 타입 매칭 | High |
| LIKE '%keyword%' 선행 와일드카드 | pg_trgm GIN 인덱스 또는 FTS | Medium |
| OR 조건 (다른 컬럼) | UNION ALL로 분리 | Medium |
| NOT IN (subquery) | LEFT JOIN IS NULL 또는 NOT EXISTS | High |

### 2. Index Usage
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| 복합 인덱스 선행 컬럼 누락 | 선행 컬럼 포함 또는 별도 인덱스 | High |
| Heap fetch 필요한 조회 | INCLUDE 커버링 인덱스 | Medium |
| 저선택도 컬럼 단독 인덱스 | Partial index | Medium |
| 인덱스 컬럼에 연산 `col * 1.1 > 100` | 상수쪽으로 이동 `col > 100/1.1` | High |

### 3. JOIN Optimization
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| JOIN 컬럼 인덱스 누락 | FK 컬럼에 인덱스 생성 | Critical |
| Cartesian product (조인 조건 누락) | ON 절 명시 | Critical |
| JOIN 컬럼 타입 불일치 | 동일 타입으로 통일 | High |
| 불필요한 LEFT JOIN (WHERE가 무효화) | INNER JOIN 사용 | Medium |
| 대용량→대용량 무필터 조인 | 필터 먼저 적용 후 조인 | High |

### 4. Subquery Efficiency
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| SELECT 절 상관 서브쿼리 | JOIN으로 변환 | High |
| WHERE 절 상관 서브쿼리 | CTE 또는 Window Function | High |
| IN (대량 결과 서브쿼리) | EXISTS (short-circuit) | Medium |
| 3단계+ 중첩 서브쿼리 | JOIN으로 평탄화 | High |
| FROM 절 서브쿼리 필터 미적용 | 서브쿼리 안으로 필터 이동 | Medium |

### 5. Data Volume Impact
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| OFFSET 페이지네이션 (대용량) | Keyset/Cursor 페이지네이션 | Critical |
| COUNT(*) 전체 테이블 | pg_class.reltuples 근사값 | Medium |
| ORDER BY without LIMIT | LIMIT 추가 | High |
| 대량 IN 리스트 (1000+) | VALUES 조인 또는 ANY(ARRAY) | Medium |

### 6. SELECT & Projection
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| SELECT * | 필요한 컬럼만 명시 | Medium |
| DISTINCT로 중복 조인 은폐 | EXISTS 또는 조인 수정 | Medium |
| 불필요한 대용량 컬럼 조회 | 필요 컬럼만 선택 | Low |

### 7. Aggregation & Grouping
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| HAVING으로 그룹 전 필터링 | WHERE로 이동 | Medium |
| 고카디널리티 GROUP BY (인덱스 없음) | Materialized View | High |
| COUNT(DISTINCT) 대용량 | HyperLogLog 근사값 | Medium |
| GROUP BY + ORDER BY 불일치 | LIMIT 추가 또는 인덱스 정렬 | Low |

### 8. Write Query Patterns
| Anti-Pattern | Fix | Impact |
|-------------|-----|--------|
| 행별 INSERT 반복 | Multi-row INSERT 또는 COPY | High |
| WHERE 없는 UPDATE/DELETE | 반드시 WHERE 추가 | Critical |
| 대량 DELETE 단일 트랜잭션 | 배치 DELETE (LIMIT) | High |
| UPDATE/DELETE WHERE 인덱스 없음 | WHERE 절 커버 인덱스 | High |
| SELECT → INSERT 패턴 | ON CONFLICT (UPSERT) | Medium |

## Top 5 SQL Anti-Patterns

프로덕션에서 가장 자주 발견되는 패턴:

### 1. 인덱스 무효화 함수 래핑
```sql
-- BAD: 인덱스 사용 불가
SELECT * FROM users WHERE UPPER(email) = 'TEST@EXAMPLE.COM';

-- GOOD: Expression index
CREATE INDEX idx_users_email_lower ON users (LOWER(email));
SELECT * FROM users WHERE LOWER(email) = 'test@example.com';
```

### 2. 상관 서브쿼리 (N+1 SQL 버전)
```sql
-- BAD: 외부 행마다 서브쿼리 실행
SELECT o.id,
  (SELECT c.name FROM customers c WHERE c.id = o.customer_id)
FROM orders o;

-- GOOD: JOIN 사용
SELECT o.id, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;
```

### 3. OFFSET 기반 깊은 페이지네이션
```sql
-- BAD: 100,000행 읽고 버림
SELECT * FROM orders ORDER BY id LIMIT 20 OFFSET 100000;

-- GOOD: Keyset pagination
SELECT * FROM orders WHERE id > :last_id ORDER BY id LIMIT 20;
```

### 4. JOIN 컬럼 인덱스 누락
```sql
-- BAD: orders.customer_id에 인덱스 없음 → Nested Loop Full Scan
SELECT * FROM customers c JOIN orders o ON c.id = o.customer_id;

-- GOOD: FK 컬럼에 인덱스 생성
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
```

### 5. NOT IN with NULL 위험
```sql
-- BAD: NULL이 있으면 결과가 비어짐
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- GOOD: NOT EXISTS는 NULL-safe
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM blacklist b WHERE b.user_id = u.id);
```

## Severity Guide

| Severity | When to Flag |
|----------|-------------|
| **Critical** | 대용량 테이블 풀스캔, Cartesian product, WHERE 없는 UPDATE/DELETE, 인덱스 없는 대용량 JOIN |
| **High** | 상관 서브쿼리, OFFSET 페이지네이션, 인덱스 무효화 패턴, 타입 불일치 |
| **Medium** | SELECT *, DISTINCT 남용, HAVING 오용, IN vs EXISTS 선택 |
| **Low** | 복합 인덱스 순서, 근사 카운트, ORDER BY+LIMIT 조합 |

## Phase 2 메타데이터 체크리스트

더 정확한 분석을 위해 아래 정보를 준비하세요:

| 항목 | 수집 방법 | 영향 |
|------|----------|------|
| 테이블 행 수 | `SELECT reltuples FROM pg_class WHERE relname = 'table'` | Severity 판단 |
| 인덱스 목록 | `\di+ table_name` 또는 `pg_indexes` 뷰 | 인덱스 매칭 |
| 컬럼 타입 | `\d table_name` | 타입 불일치 탐지 |
| 카디널리티 | `SELECT n_distinct FROM pg_stats WHERE tablename = 'table'` | 인덱스 효용 판단 |
| EXPLAIN 결과 | `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) [query]` | 실행계획 확인 |

## 서브쿼리 판단 가이드

| 상황 | 권장 | 이유 |
|------|------|------|
| 존재 여부 확인 | EXISTS | Short-circuit, JOIN+DISTINCT 불필요 |
| 단일 집계값 비교 | Scalar Subquery | 1회 실행, JOIN 불필요 |
| 다수 행 필터링 | JOIN | 옵티마이저가 최적 전략 선택 가능 |
| 상관 서브쿼리 (SELECT 절) | JOIN | N번 → 1번으로 감소 |
| 상관 서브쿼리 (WHERE 절) | CTE 또는 Window Function | 1회 실행 후 조인 |
| 2단계 이상 중첩 | JOIN으로 평탄화 | 가독성 + 옵티마이저 최적화 |

## Integration with Other Tools

- Use `/sql-analyze [SQL]` command for full structured analysis with 2-phase report
- Use `/perf-review --focus io` for application-level I/O and query patterns
- The `sql-analyzer` agent contains the complete 8-category checklist with all SQL examples
- This skill provides quick reference during query writing or review

---

**Remember**: EXPLAIN이 최종 판단 기준이다. 구조적 분석은 방향을 잡아주지만, 실제 실행계획과 데이터 분포가 성능을 결정한다. 항상 데이터 규모를 고려하고, 소규모 테이블에서의 안티패턴은 과도하게 최적화하지 마라.
