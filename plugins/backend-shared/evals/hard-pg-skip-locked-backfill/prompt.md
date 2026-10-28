---
description: "hard: SKIP LOCKED 백필 루프가 '갱신 0건' 으로 조기 종료 → NULL 잔존 (PG-MIG-16)"
tags: [hard, should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

PostgreSQL 16 + Flyway. orders 테이블(2억 행)은 주문 상태 UPDATE 가 초당 수천 건 들어오는 핫 테이블이야. 새 컬럼 region 을 NOT NULL 로 만드는 중이고, 신규 행은 이미 새 버전 앱이 region 을 채워서 넣고 있어. 기존 행 백필과 제약은 이렇게 했어.

```sql
-- V42__backfill_orders_region.sql   (이 파일만 executeInTransaction=false)
DO $$
DECLARE n int;
BEGIN
  LOOP
    UPDATE orders SET region = 'KR'
    WHERE id IN (
      SELECT id FROM orders
      WHERE region IS NULL
      ORDER BY id
      LIMIT 5000
      FOR UPDATE SKIP LOCKED
    );
    GET DIAGNOSTICS n = ROW_COUNT;
    EXIT WHEN n = 0;
    COMMIT;
  END LOOP;
END $$;

-- V43__orders_region_check.sql
ALTER TABLE orders ADD CONSTRAINT orders_region_nn CHECK (region IS NOT NULL) NOT VALID;

-- V44__orders_region_validate.sql
ALTER TABLE orders VALIDATE CONSTRAINT orders_region_nn;
```

스테이징에서는 매번 통과했는데, 운영에서는 V42 가 정상 종료됐는데도 V44 가 가끔 `check constraint "orders_region_nn" of relation "orders" is violated by some row` 로 실패해. 왜 그런지, 백필을 어떻게 고쳐야 하는지 리뷰해줘.
