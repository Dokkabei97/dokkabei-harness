# 무중단 변경 패턴과 롤백

## expand-contract

| 단계 | DB | 앱 | 공존 조건 |
|---|---|---|---|
| 1 expand | 새 컬럼/테이블 추가(nullable 또는 fast default), 필요 시 동기화 트리거 | 변경 없음 | 구 앱 + 새 스키마 |
| 2 dual | — | 새 구조에 쓰기(+ 구 구조에도 쓰기), 읽기는 구 구조 | 구/신 앱 혼재 |
| 3 backfill | 배치 백필(PG-MIG-15), 제약 NOT VALID→VALIDATE | — | — |
| 4 switch | — | 읽기를 새 구조로 전환 | 신 앱만 |
| 5 contract | 트리거·구 컬럼 제거(PG-MIG-14 순서) | 구 구조 참조 제거가 **먼저** 배포됨 | — |

각 단계는 별도 배포이며, 단계 사이에 롤백 가능해야 한다. 트리거 동기화를 쓰는 경우 단계 2 를 생략할 수 있지만 트리거 비용(쓰기 지연)을 측정한다.

### rename (컬럼)

```sql
-- 1 expand
ALTER TABLE users ADD COLUMN full_name text;
CREATE FUNCTION users_sync_name() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.full_name := COALESCE(NEW.full_name, NEW.name);
    NEW.name      := COALESCE(NEW.name, NEW.full_name);
  ELSIF NEW.name IS DISTINCT FROM OLD.name THEN
    NEW.full_name := NEW.name;
  ELSIF NEW.full_name IS DISTINCT FROM OLD.full_name THEN
    NEW.name := NEW.full_name;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER users_sync_name BEFORE INSERT OR UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION users_sync_name();
-- 3 backfill: 배치로 full_name IS NULL 채움
-- 5 contract (앱이 name 을 더는 참조하지 않게 배포된 뒤)
DROP TRIGGER users_sync_name ON users; DROP FUNCTION users_sync_name();
ALTER TABLE users DROP COLUMN name;
```

짧은 rename 이 꼭 필요하면 대안: rename 후 구 이름으로 `CREATE VIEW` 를 두는 방식은 쓰기 경로(ORM)가 뷰를 대상으로 하지 않는 한 효과가 없다 — 대부분의 서비스에서는 expand-contract 가 기본.

### 타입 변경

새 컬럼(`price_v2 bigint`) + 트리거 동기화 + 배치 백필 + 읽기 전환 + 구 컬럼 DROP 후 rename. binary-coercible 이면 직접 ALTER(PG-MIG-11).

### 테이블 제거

① 앱 참조 제거 배포 → ② 일정 기간 접근 감시(`pg_stat_user_tables.seq_scan/idx_scan` 증가 여부, 레플리카 포함) → ③ `ALTER TABLE x RENAME TO _deprecated_x_YYYYMMDD` (짧은 락, 되돌리기 쉬움) → ④ 보존 기간 후 DROP. 외부 소비자(CDC, ETL, BI)가 있는지 먼저 확인.

## 롤백

- **down 마이그레이션은 스키마만 되돌린다.** DROP/축소로 잃은 데이터는 돌아오지 않는다. 이런 변경은 "되돌리기" 가 아니라 **전진 수정**(새 마이그레이션) 계획을 리뷰에 적는다.
- expand 단계는 롤백이 쉽다(추가한 것을 지우면 됨) — 위험은 contract 단계에 몰린다. contract 는 앱 안정화 확인 후, 별도 배포로.
- 롤백 시나리오별 확인: (a) 앱만 롤백 — 새 스키마에서 구 앱이 동작하는가, (b) 스키마도 롤백 — 그 사이 신규 데이터(새 컬럼에만 쓰인 값)는 어디로 가는가.
- 대형 테이블 롤백 소요 시간은 정방향과 같은 락 규칙을 따른다(인덱스 DROP 도 CONCURRENTLY, PG-MIG-09).

검증 SQL 모음:

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;                -- INVALID 인덱스
SELECT conname, convalidated FROM pg_constraint WHERE conrelid = 't'::regclass; -- 미검증 제약
SELECT count(*) FROM t WHERE new_col IS NULL;                                   -- 백필 잔여
SELECT pid, now()-xact_start, state, left(query,80) FROM pg_stat_activity
 WHERE xact_start < now() - interval '1 min';                                   -- 장기 트랜잭션
```
