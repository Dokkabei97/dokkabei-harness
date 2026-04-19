---
name: migration-safety-checklist
description: "DB 마이그레이션 안전성 체크리스트 — 무중단 변경 판단, Expand-Contract 패턴, Flyway/Alembic 규칙, 롤백 전략"
---

# DB 마이그레이션 안전성 체크리스트

## 1. 무중단 변경 판단 트리

스키마 변경을 수행하기 전 아래 판단 트리를 따라 무중단 가능 여부를 확인한다.

```
[변경 유형은?]
│
├─ 컬럼 추가 (nullable)
│   └─ 무중단 가능 ✅ → 그대로 진행
│
├─ 컬럼 추가 (NOT NULL + DEFAULT)
│   └─ DB 엔진 확인
│       ├─ PostgreSQL 11+ → DEFAULT가 메타데이터에만 저장 ✅ 안전
│       └─ MySQL → 테이블 크기 확인
│           ├─ < 100만 행 → 락 시간 짧음 ✅ 주의하며 진행
│           └─ >= 100만 행 → ⚠️ pt-online-schema-change 또는 gh-ost 사용
│
├─ 컬럼 삭제
│   └─ 애플리케이션에서 해당 컬럼 참조 제거 완료?
│       ├─ Yes → 무중단 가능 ✅ (단, 롤백 시 데이터 유실 주의)
│       └─ No → ❌ 먼저 코드에서 컬럼 참조 제거 배포 필요
│
├─ 컬럼 이름 변경
│   └─ ❌ 무중단 불가 → 3-step 안전 대안 사용 (섹션 2 참조)
│
├─ 컬럼 타입 변경
│   └─ ❌ 무중단 불가 → 새 컬럼 + cast 복사 + 교체 (섹션 2 참조)
│
├─ NOT NULL 제약 추가
│   └─ 기존 데이터에 NULL 존재?
│       ├─ Yes → ❌ 먼저 백필 필요
│       └─ No → DEFAULT 설정 → 백필 확인 → NOT NULL 적용 ✅
│
├─ 인덱스 추가
│   └─ DB 엔진 확인
│       ├─ PostgreSQL → CREATE INDEX CONCURRENTLY ✅
│       └─ MySQL → 테이블 크기 확인
│           ├─ < 100만 행 → ✅ 주의하며 진행
│           └─ >= 100만 행 → ⚠️ pt-osc 또는 gh-ost
│
├─ 테이블 DROP
│   └─ ❌ 즉시 삭제 금지 → soft delete → 안정화 후 삭제 (섹션 2 참조)
│
└─ 테이블 생성
    └─ 무중단 가능 ✅ → 그대로 진행
```

---

## 2. 위험 작업 목록 & 안전한 대안

### 컬럼 이름 변경 → 3-Step 패턴

```
Phase 1 (Expand):   새 컬럼 추가, 트리거로 양방향 동기화
Phase 2 (Migrate):  코드를 새 컬럼 사용으로 전환, 기존 데이터 백필
Phase 3 (Contract): 구 컬럼 삭제
```

```sql
-- Phase 1: 새 컬럼 추가 + 동기화
ALTER TABLE users ADD COLUMN full_name VARCHAR(200);
UPDATE users SET full_name = name WHERE full_name IS NULL;

-- 트리거: 양방향 동기화 (PostgreSQL)
CREATE OR REPLACE FUNCTION sync_user_name() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.name IS DISTINCT FROM OLD.name THEN
        NEW.full_name := NEW.name;
    END IF;
    IF TG_OP = 'INSERT' OR NEW.full_name IS DISTINCT FROM OLD.full_name THEN
        NEW.name := NEW.full_name;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Phase 2: 코드 배포 (full_name 사용으로 전환) + 백필 확인
-- Phase 3: 구 컬럼 삭제 (트리거 제거 → 컬럼 DROP)
DROP TRIGGER IF EXISTS sync_user_name_trigger ON users;
ALTER TABLE users DROP COLUMN name;
```

### 타입 변경 → 새 컬럼 + Cast 복사

```sql
-- Bad: 직접 타입 변경 — 테이블 락 + 데이터 유실 위험
ALTER TABLE products ALTER COLUMN price TYPE BIGINT;

-- Good: 안전한 3-step
-- Step 1: 새 컬럼 추가
ALTER TABLE products ADD COLUMN price_v2 BIGINT;

-- Step 2: 데이터 복사 (배치 처리 권장)
UPDATE products SET price_v2 = price::BIGINT WHERE price_v2 IS NULL;

-- Step 3: 코드 전환 후 구 컬럼 삭제
ALTER TABLE products DROP COLUMN price;
ALTER TABLE products RENAME COLUMN price_v2 TO price;
```

### NOT NULL 추가 → 안전 순서

```sql
-- Bad: 바로 NOT NULL — NULL 데이터 있으면 실패
ALTER TABLE orders ALTER COLUMN shipping_address SET NOT NULL;

-- Good: 3단계 안전 적용
-- Step 1: DEFAULT 설정
ALTER TABLE orders ALTER COLUMN shipping_address SET DEFAULT '';

-- Step 2: 백필 (배치)
UPDATE orders SET shipping_address = '' WHERE shipping_address IS NULL;
-- 대용량 시:
DO $$
DECLARE
    batch_size INT := 10000;
    rows_updated INT;
BEGIN
    LOOP
        UPDATE orders
        SET shipping_address = ''
        WHERE id IN (
            SELECT id FROM orders
            WHERE shipping_address IS NULL
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        );
        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        EXIT WHEN rows_updated = 0;
        COMMIT;
    END LOOP;
END $$;

-- Step 3: NOT NULL 적용
ALTER TABLE orders ALTER COLUMN shipping_address SET NOT NULL;
```

### 테이블 DROP → Soft Delete 패턴

```sql
-- Bad: 즉시 DROP
DROP TABLE legacy_logs;

-- Good: 단계적 제거
-- Phase 1: 테이블 이름 변경 (소프트 삭제)
ALTER TABLE legacy_logs RENAME TO _deprecated_legacy_logs_20240301;

-- Phase 2: 2주 안정화 기간 후 확인
-- SELECT COUNT(*) FROM _deprecated_legacy_logs_20240301;

-- Phase 3: 최종 삭제
DROP TABLE _deprecated_legacy_logs_20240301;
```

### 대용량 인덱스 생성

```sql
-- Bad: 일반 CREATE INDEX — 테이블 전체 락
CREATE INDEX idx_orders_user_id ON orders (user_id);

-- Good: PostgreSQL — CONCURRENTLY 옵션
CREATE INDEX CONCURRENTLY idx_orders_user_id ON orders (user_id);
-- 주의: 트랜잭션 블록 안에서 사용 불가, Flyway에서는 별도 마이그레이션 파일 필요

-- Good: MySQL — gh-ost 또는 pt-online-schema-change
-- gh-ost --alter="ADD INDEX idx_orders_user_id (user_id)" ...
```

---

## 3. Expand-Contract 패턴

### 3-Phase 설명

```
┌──────────────────────────────────────────────────────────┐
│ Phase 1: EXPAND                                          │
│ - 새 스키마 추가 (비파괴적)                                  │
│ - 이전 스키마 유지                                          │
│ - 양방향 동기화 설정                                        │
│ → 이 시점에서 old code + new schema 공존 가능                │
├──────────────────────────────────────────────────────────┤
│ Phase 2: MIGRATE                                         │
│ - 새 코드 배포 (새 스키마 사용)                              │
│ - 기존 데이터 백필                                          │
│ - 모니터링 & 안정화                                         │
│ → 이 시점에서 new code + new schema 사용 중                  │
├──────────────────────────────────────────────────────────┤
│ Phase 3: CONTRACT                                        │
│ - 이전 스키마 제거                                          │
│ - 동기화 트리거 제거                                        │
│ - 정리 완료                                                │
└──────────────────────────────────────────────────────────┘
```

### Phase별 마이그레이션 예시 (Flyway)

```sql
-- V20240301_001__expand_add_email_verified.sql (Phase 1)
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;

-- 동기화 트리거 (기존 코드와 호환)
CREATE OR REPLACE FUNCTION sync_email_verified()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'VERIFIED' AND NEW.email_verified = FALSE THEN
        NEW.email_verified := TRUE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_email_verified
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION sync_email_verified();
```

```sql
-- V20240308_001__migrate_backfill_email_verified.sql (Phase 2)
UPDATE users SET email_verified = TRUE WHERE status = 'VERIFIED' AND email_verified = FALSE;
```

```sql
-- V20240315_001__contract_remove_status_dependency.sql (Phase 3)
DROP TRIGGER IF EXISTS trg_sync_email_verified ON users;
DROP FUNCTION IF EXISTS sync_email_verified();
-- status 컬럼 제거는 코드 전환 확인 후 별도 마이그레이션
```

---

## 4. Flyway 규칙

### 명명 규칙

```
V{timestamp}__{description}.sql     # 버전 마이그레이션 (한 번만 실행)
R__{description}.sql                # 반복 마이그레이션 (변경 시 재실행, 뷰/함수용)
U{timestamp}__{description}.sql     # 실행 취소 마이그레이션 (Teams 에디션만)
```

```
예시:
V20240301_001__create_users_table.sql
V20240301_002__add_users_email_index.sql
V20240315_001__add_orders_table.sql
R__create_product_search_view.sql
```

### 중요 규칙

```yaml
# application.yml
spring:
  flyway:
    baseline-on-migrate: true        # 기존 DB에 Flyway 도입 시
    baseline-version: "0"
    validate-on-migrate: true        # 체크섬 검증
    out-of-order: false              # 순서 외 실행 방지 (CI에서는 true 가능)
    locations: classpath:db/migration
```

- 이미 적용된 마이그레이션 파일은 절대 수정 금지 (체크섬 불일치 오류)
- `CREATE INDEX CONCURRENTLY`는 트랜잭션 불가이므로 별도 파일 + `executeInTransaction = false` 설정
- 하나의 마이그레이션 파일에 하나의 논리적 변경만 포함

---

## 5. Alembic 규칙

### revision ID 관리

```bash
# 자동 생성
alembic revision --autogenerate -m "add_product_sku_column"

# 수동 생성
alembic revision -m "backfill_product_sku"
```

### depends_on & 브랜치 관리

```python
"""add shipping address to orders

Revision ID: c3d4e5f6
Revises: a1b2c3d4
"""
revision = "c3d4e5f6"
down_revision = "a1b2c3d4"
depends_on = None  # 다른 브랜치의 revision에 의존 시 지정

def upgrade() -> None:
    op.add_column("orders", sa.Column("shipping_address", sa.Text(), nullable=True))

def downgrade() -> None:
    op.drop_column("orders", "shipping_address")
```

### batch migrations (SQLite 호환 & 안전)

```python
def upgrade() -> None:
    with op.batch_alter_table("products") as batch_op:
        batch_op.add_column(sa.Column("sku", sa.String(50)))
        batch_op.create_unique_constraint("uq_products_sku", ["sku"])
```

### async engine 설정

```python
# alembic/env.py
from sqlalchemy.ext.asyncio import create_async_engine

async def run_async_migrations():
    connectable = create_async_engine(settings.DATABASE_URL)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()
```

---

## 6. 롤백 전략 템플릿

### 컬럼 추가 롤백

```sql
-- Flyway 롤백
ALTER TABLE products DROP COLUMN IF EXISTS sku;
```

```python
# Alembic downgrade
def downgrade() -> None:
    op.drop_column("products", "sku")
```

### 컬럼 타입 변경 롤백 (3-step 방식 사용 시)

```sql
-- 새 컬럼이 추가된 상태에서 롤백
ALTER TABLE products DROP COLUMN IF EXISTS price_v2;
```

### NOT NULL 추가 롤백

```sql
-- Flyway 롤백
ALTER TABLE orders ALTER COLUMN shipping_address DROP NOT NULL;
ALTER TABLE orders ALTER COLUMN shipping_address DROP DEFAULT;
```

```python
# Alembic downgrade
def downgrade() -> None:
    op.alter_column("orders", "shipping_address", nullable=True)
    op.execute("ALTER TABLE orders ALTER COLUMN shipping_address DROP DEFAULT")
```

### 인덱스 추가 롤백

```sql
-- Flyway 롤백
DROP INDEX IF EXISTS idx_orders_user_id;
-- PostgreSQL CONCURRENTLY로 생성한 인덱스도 일반 DROP으로 삭제 가능
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_user_id;
```

```python
# Alembic downgrade
def downgrade() -> None:
    op.drop_index("ix_orders_user_id", table_name="orders")
```

### 테이블 생성 롤백

```sql
-- Flyway 롤백
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;  -- FK 의존성 순서 주의
```

```python
# Alembic downgrade
def downgrade() -> None:
    op.drop_table("order_items")
    op.drop_table("orders")
```

### 롤백 체크리스트

```
[ ] 롤백 SQL/코드가 작성되어 있는가?
[ ] 롤백 시 데이터 유실이 없는가?
[ ] 롤백 순서가 FK 의존성을 고려하는가?
[ ] 롤백 후 애플리케이션이 정상 동작하는가?
[ ] 롤백을 스테이징에서 먼저 검증했는가?
[ ] 롤백 소요 시간을 추정했는가? (대용량 테이블 주의)
```
