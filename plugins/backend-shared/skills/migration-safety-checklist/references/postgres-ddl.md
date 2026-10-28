# PostgreSQL DDL 스페셜리스트 항목 (PG-MIG)

각 항목은 `적용` 조건이 맞을 때만 쓴다. 소형·저트래픽 테이블에는 대부분 과최적화다.
버전 표기는 PostgreSQL 메이저 버전. 근거는 공식 문서(현재 버전) 기준.

---

### PG-MIG-01 · ACCESS EXCLUSIVE 대기 중인 DDL 하나가 뒤따르는 모든 SELECT 를 막는다
- 적용: 트래픽이 있는 테이블에 대한 거의 모든 `ALTER TABLE`, `DROP`, `TRUNCATE`, 일반 `CREATE INDEX`(SHARE)
- 신호: 마이그레이션 중 API p99 급등·커넥션 풀 고갈, `pg_stat_activity.wait_event_type = 'Lock'` 행이 줄줄이 쌓임, DDL 자체는 "빠른" 메타데이터 변경인데 장애
- 메커니즘: 락 큐는 FIFO 다. DDL 이 긴 트랜잭션 뒤에서 ACCESS EXCLUSIVE 를 기다리는 동안, 이후 들어온 ACCESS SHARE(일반 SELECT)도 DDL 뒤에 줄을 선다. "1ms 짜리 ALTER" 가 선행 트랜잭션 길이만큼 전체 테이블을 정지시킨다.
- 처방: DDL 파일 맨 앞에 세션/트랜잭션 단위 `SET lock_timeout = '3s';` (값은 서비스 SLO 에 맞춤) 를 두고, 실패하면 재시도(배포 파이프라인 재실행 또는 도구 재시도). `statement_timeout` 은 락 대기가 아니라 실행 시간 상한이므로 대체재가 아니다.
- 반례: 유지보수 창에서 트래픽을 끊고 하는 작업, 신규(아직 참조 없는) 테이블. 이 경우 lock_timeout 은 불필요한 재시도만 만든다.
- 검증: 스테이징에서 `BEGIN; SELECT ... FROM t; -- 열어둠` 상태로 마이그레이션 실행 → lock_timeout 으로 실패하고 다른 세션 SELECT 가 막히지 않는지 확인. `pg_locks` + `pg_blocking_pids()` 로 대기 그래프 확인.
- 근거: https://www.postgresql.org/docs/current/explicit-locking.html , https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-LOCK-TIMEOUT

### PG-MIG-02 · 무관한 테이블의 긴 트랜잭션·idle in transaction 도 DDL 과 CONCURRENTLY 를 지연시킨다
- 적용: 배치/분석 쿼리, 커넥션 풀에서 트랜잭션을 열어둔 채 외부 호출하는 앱 코드가 있는 DB
- 신호: `pg_stat_activity` 에 `state = 'idle in transaction'` 또는 `now() - xact_start` 가 수 분 이상인 세션
- 메커니즘: 대상 테이블을 만진 트랜잭션은 DDL 락을 막고(PG-MIG-01), `CREATE INDEX CONCURRENTLY` 는 테이블과 무관하게 **더 오래된 스냅샷을 가진 모든 트랜잭션**의 종료를 기다린다(PG-MIG-08).
- 처방: 실행 직전 점검 쿼리 `SELECT pid, state, now()-xact_start AS age, query FROM pg_stat_activity WHERE xact_start < now() - interval '1 min' ORDER BY age DESC;`. 앱 쪽은 `idle_in_transaction_session_timeout` 을 역할(role) 단위로 설정해 상시 차단.
- 반례: 의도된 장기 트랜잭션(논리 복제 초기 동기화 등)을 강제 종료하지 말 것 — 일정을 조정한다.
- 검증: 위 쿼리 결과를 마이그레이션 실행 로그에 남긴다.
- 근거: https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-IDLE-IN-TRANSACTION-SESSION-TIMEOUT

### PG-MIG-03 · DEFAULT 있는 컬럼 추가는 PG11+ 에서 즉시 — 단 휘발성 DEFAULT 는 여전히 전체 재작성
- 적용: PG11+, 대형 테이블에 `ADD COLUMN ... DEFAULT ...`
- 신호: DEFAULT 가 `clock_timestamp()`, `random()`, `gen_random_uuid()`, `nextval()`(serial/identity 컬럼 추가 포함), `GENERATED ... STORED`
- 메커니즘: PG11 부터 **비휘발성** DEFAULT 는 카탈로그(`pg_attribute.attmissingval`)에만 저장되어 재작성이 없다. VOLATILE 함수 DEFAULT·identity/serial·stored generated 는 행마다 값이 달라 ACCESS EXCLUSIVE 로 테이블 전체를 재작성한다. `now()` 는 STABLE 이라 즉시 처리되지만 **기존 모든 행이 마이그레이션 시각 한 값**을 갖는다(의미 확인).
- 처방: 휘발성 값이 필요하면 nullable 로 추가 → 배치 백필(PG-MIG-15) → DEFAULT 설정 → NOT NULL(PG-MIG-04).
- 반례: PG10 이하에서는 비휘발성 DEFAULT 도 재작성 — 그 경우 nullable 추가 + 백필 경로가 기본.
- 검증: `SELECT attname, atthasmissing FROM pg_attribute WHERE attrelid = 't'::regclass AND attnum > 0;` (true 면 fast default 적용). 실행 전후 `pg_relation_filenode('t')` 가 바뀌면 재작성된 것.
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html (Notes: "Adding a column with a volatile DEFAULT ... will require the entire table and its indexes to be rewritten"), https://www.postgresql.org/docs/release/11.0/

### PG-MIG-04 · `SET NOT NULL` 은 ACCESS EXCLUSIVE 로 전체 스캔 — CHECK NOT VALID → VALIDATE 로 스캔을 분리
- 적용: PG12+, 대형 테이블 NOT NULL 추가
- 신호: 마이그레이션에 `ALTER COLUMN x SET NOT NULL` 단독
- 메커니즘: SET NOT NULL 은 모든 행을 검사하는 동안 ACCESS EXCLUSIVE 를 쥔다. PG12 부터는 **유효한(validated) `CHECK (x IS NOT NULL)` 제약이 이미 있으면 스캔을 생략**한다. `VALIDATE CONSTRAINT` 는 SHARE UPDATE EXCLUSIVE 만 잡아 읽기·쓰기와 공존한다.
- 처방:
  ```sql
  SET lock_timeout = '3s';
  ALTER TABLE orders ADD CONSTRAINT orders_addr_nn CHECK (shipping_address IS NOT NULL) NOT VALID; -- 짧은 락. 이후 모든 INSERT·UPDATE 에 강제(기존 NULL 행을 값 없이 UPDATE 하면 실패)
  -- (백필 완료 확인 후, 별도 파일/트랜잭션)
  ALTER TABLE orders VALIDATE CONSTRAINT orders_addr_nn;      -- SHARE UPDATE EXCLUSIVE, 스캔
  ALTER TABLE orders ALTER COLUMN shipping_address SET NOT NULL; -- 스캔 생략
  ALTER TABLE orders DROP CONSTRAINT orders_addr_nn;
  ```
  PG18+ 는 NOT NULL 제약 자체를 `NOT VALID` 로 추가하고 나중에 VALIDATE 할 수 있다(릴리즈노트) — 문법은 사용 버전 문서로 확인.
- 반례: 수십만 행 이하 테이블은 단순 SET NOT NULL 이 더 단순하고 충분히 빠르다. NOT VALID 제약은 기존 행의 UPDATE 에도 걸리므로, 앱이 기존 NULL 행을 갱신할 때 값을 채우지 않는다면 ADD CONSTRAINT 를 백필 **후**로 옮긴다.
- 검증: `SELECT conname, convalidated FROM pg_constraint WHERE conrelid = 'orders'::regclass;`
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html (SET NOT NULL 설명), https://www.postgresql.org/docs/release/12.0/ , https://www.postgresql.org/docs/release/18.0/

### PG-MIG-05 · FK/CHECK 추가는 검증 스캔 동안 양쪽 테이블을 잠근다 — NOT VALID + VALIDATE
- 적용: 기존 대형 테이블에 FOREIGN KEY 또는 CHECK 추가
- 신호: `ADD CONSTRAINT ... FOREIGN KEY` 가 NOT VALID 없이 바로 실행
- 메커니즘: `ADD FOREIGN KEY` 는 참조하는 테이블과 참조되는 테이블 양쪽에 SHARE ROW EXCLUSIVE 를 잡고 전체 검증한다(쓰기 차단). `NOT VALID` 로 추가하면 검증을 생략하고 신규 행만 강제하며, 이후 `VALIDATE CONSTRAINT` 는 변경 테이블에 SHARE UPDATE EXCLUSIVE, 참조 테이블에 ROW SHARE 만 잡는다.
- 처방: `ADD CONSTRAINT fk ... NOT VALID;` → (별도 트랜잭션) `VALIDATE CONSTRAINT fk;`. 또한 PostgreSQL 은 **FK 컬럼(참조하는 쪽)에 인덱스를 자동 생성하지 않는다** — 부모 DELETE/UPDATE 시 자식 테이블 순차 스캔 + 락이 길어지므로 `CREATE INDEX CONCURRENTLY` 로 함께 추가.
- 반례: 부모가 거의 삭제·키 변경되지 않는 참조(코드 테이블)는 자식 인덱스가 쓰기 비용만 늘릴 수 있다 — 쿼리 패턴으로 판단.
- 검증: `convalidated` 확인, 부모 DELETE 의 `EXPLAIN (ANALYZE)` 에서 트리거 시간(`Trigger for constraint ...`) 확인.
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html

### PG-MIG-06 · UNIQUE/PK 는 인덱스를 CONCURRENTLY 로 먼저 만들고 `USING INDEX` 로 승격
- 적용: 기존 대형 테이블에 UNIQUE 또는 PRIMARY KEY 추가
- 신호: `ADD CONSTRAINT ... UNIQUE (col)` / `ADD PRIMARY KEY` 직접 실행
- 메커니즘: 제약 추가는 내부적으로 일반 `CREATE UNIQUE INDEX` 를 수행해 빌드 내내 쓰기를 막는다.
- 처방: `CREATE UNIQUE INDEX CONCURRENTLY t_col_uq ON t (col);` → `ALTER TABLE t ADD CONSTRAINT t_col_uq UNIQUE USING INDEX t_col_uq;` (짧은 ACCESS EXCLUSIVE). PK 승격은 컬럼이 NOT NULL 이어야 하며, 아니면 승격 시 NOT NULL 스캔이 발생하므로 PG-MIG-04 를 먼저.
- 반례: 중복 데이터가 이미 있으면 CONCURRENTLY 빌드가 실패해 INVALID 인덱스를 남긴다(PG-MIG-07) — 사전 `GROUP BY col HAVING count(*) > 1` 점검.
- 검증: `\d t` 에서 제약이 해당 인덱스를 사용하는지 확인.
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html (ADD table_constraint_using_index)

### PG-MIG-07 · CREATE INDEX CONCURRENTLY 실패는 INVALID 인덱스를 남기고, `IF NOT EXISTS` 재실행은 조용히 건너뛴다
- 적용: CONCURRENTLY 인덱스 생성 전부
- 신호: 마이그레이션 재시도 후 "성공" 했는데 쿼리가 인덱스를 안 탐, 쓰기 지연이 원인 불명으로 증가
- 메커니즘: 데드락·유니크 위반·취소·lock_timeout 등으로 실패하면 인덱스가 `indisvalid = false` 로 남는다. 조회에는 쓰이지 않지만 **쓰기 시 계속 갱신되어 비용만 발생**한다. 같은 이름으로 `CREATE INDEX CONCURRENTLY IF NOT EXISTS` 를 재실행하면 이름이 존재하므로 아무것도 하지 않는다.
- 처방: 실패/재시도 후 `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;` 로 확인 → `DROP INDEX CONCURRENTLY` 후 재생성, 또는 PG12+ `REINDEX INDEX CONCURRENTLY idx;`. 마이그레이션에서 IF NOT EXISTS 를 쓴다면 앞에 INVALID 검사·정리 단계를 둔다.
- 반례: 없음 — INVALID 인덱스는 항상 정리 대상.
- 검증: 위 쿼리 결과 0행을 배포 후 점검 항목에 포함.
- 근거: https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY

### PG-MIG-08 · CONCURRENTLY 는 트랜잭션 블록 불가 — 다중 문장 파일은 "암묵적 트랜잭션" 이 된다
- 적용: CONCURRENTLY 생성/삭제, `REINDEX CONCURRENTLY`, PG11 이하 `ALTER TYPE ... ADD VALUE`
- 신호: `ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block`, 또는 도구가 파일 전체를 한 번의 Exec 로 보내는 경우(golang-migrate 등) 다른 문장과 같은 파일에 있음
- 메커니즘: CIC 는 카탈로그 등록·1차 스캔·2차 스캔을 별도 트랜잭션으로 수행하고 각 단계에서 기존 스냅샷이 끝나기를 기다린다. 도구가 BEGIN/COMMIT 으로 감싸거나, 여러 문장을 simple query 한 번으로 보내면(PostgreSQL 은 이를 하나의 암묵적 트랜잭션으로 실행) 실패한다.
- 처방: CIC 문장을 **단독 파일**로 분리하고 도구별 비트랜잭션 지시자를 사용 → [tools.md](tools.md). 가능하면 `lock_timeout` 대신 사전 장기 트랜잭션 점검(PG-MIG-02)으로 대기 시간을 관리.
- 반례: 빈 신규 테이블의 인덱스는 CONCURRENTLY 가 필요 없다 — 같은 트랜잭션에서 CREATE TABLE 과 함께 일반 CREATE INDEX.
- 검증: 스테이징에서 도구로 실제 실행(문법 검사만으로는 래핑 여부를 알 수 없음).
- 근거: https://www.postgresql.org/docs/current/sql-createindex.html , https://www.postgresql.org/docs/current/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT

### PG-MIG-09 · `DROP INDEX` 도 테이블에 ACCESS EXCLUSIVE
- 적용: 핫 테이블에서 미사용/중복 인덱스 제거
- 신호: 마이그레이션의 일반 `DROP INDEX`
- 메커니즘: 일반 DROP INDEX 는 부모 테이블에 ACCESS EXCLUSIVE 를 잡아 PG-MIG-01 대기열 문제를 그대로 겪는다.
- 처방: `DROP INDEX CONCURRENTLY IF EXISTS idx;` (단독 파일, 트랜잭션 블록 불가). 제약을 지탱하는 인덱스는 CONCURRENTLY 로 지울 수 없으므로 `ALTER TABLE ... DROP CONSTRAINT` + lock_timeout.
- 반례: 소형 테이블은 일반 DROP + lock_timeout 으로 충분.
- 검증: 제거 전 `pg_stat_user_indexes.idx_scan` 을 **모든 레플리카에서** 확인 — 통계는 노드별이라 프라이머리에서 0이어도 레플리카 읽기에서 쓰일 수 있다.
- 근거: https://www.postgresql.org/docs/current/sql-dropindex.html

### PG-MIG-10 · 파티션 테이블 부모에는 CREATE INDEX CONCURRENTLY 를 쓸 수 없다
- 적용: 선언적 파티셔닝 테이블에 인덱스 추가
- 신호: 파티션 부모에 일반 CREATE INDEX → 모든 파티션 쓰기 차단
- 메커니즘: 공식 문서상 파티션 테이블에 대한 concurrent build 는 지원되지 않는다.
- 처방:
  ```sql
  CREATE INDEX idx_p ON ONLY measurements (ts);              -- 부모에만, INVALID 상태로 생성
  CREATE INDEX CONCURRENTLY idx_p_2026_10 ON measurements_2026_10 (ts); -- 파티션별 (각각 단독 파일)
  ALTER INDEX idx_p ATTACH PARTITION idx_p_2026_10;           -- 모든 파티션 attach 시 부모가 VALID
  ```
- 반례: 파티션이 적고 작으면 유지보수 창의 일반 생성이 단순하다.
- 검증: `pg_index.indisvalid` 로 부모 인덱스 VALID 전환 확인.
- 근거: https://www.postgresql.org/docs/current/sql-createindex.html (Notes: partitioned tables), https://www.postgresql.org/docs/current/ddl-partitioning.html

### PG-MIG-11 · `ALTER COLUMN TYPE` 은 binary-coercible 이 아니면 테이블+모든 인덱스 재작성
- 적용: 컬럼 타입 변경
- 신호: `ALTER COLUMN ... TYPE` (특히 `USING` 절 동반)
- 메커니즘: ACCESS EXCLUSIVE 상태로 테이블과 인덱스를 재작성한다. 예외는 binary-coercible 변경(예: `varchar(n)`→`varchar(m)` (m>n), `varchar`→`text`)으로, 이때는 재작성 없이 카탈로그만 바뀐다. 축소(`varchar(100)`→`varchar(50)`)는 전체 검사가 필요하다.
- 처방: 재작성 대상이면 새 컬럼 + 트리거 동기화 + 배치 백필 + 교체(expand-contract). 길이 제한 강화는 타입 대신 `CHECK (char_length(x) <= 50) NOT VALID` → VALIDATE.
- 반례: binary-coercible 변경에 expand-contract 를 쓰는 것은 과최적화.
- 검증: 실행 전후 `pg_relation_filenode` 비교, 스테이징 복제본에서 소요 시간 측정.
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html (Notes: rewrite rules)

### PG-MIG-12 · int4 PK/시퀀스 고갈(2,147,483,647)은 bigint 전환에 수 주가 걸린다 — 미리 감시
- 적용: `serial`/`integer` PK, 쓰기량이 큰 테이블(이벤트·로그·주문 항목)
- 신호: `SELECT last_value FROM t_id_seq;` 가 상한의 50% 이상, FK 로 int4 를 참조하는 자식 테이블 다수
- 메커니즘: 직접 `ALTER TYPE bigint` 는 PG-MIG-11 재작성. PG10+ 시퀀스도 자체 타입(`AS integer`)을 가져 컬럼만 바꾸면 시퀀스에서 터진다. 참조하는 FK 컬럼도 모두 바꿔야 한다.
- 처방: 새 `id_new bigint` 추가 → 트리거로 신규 행 동기화 → 키셋 배치 백필 → `CREATE UNIQUE INDEX CONCURRENTLY` → 짧은 트랜잭션에서 rename + `ADD CONSTRAINT ... PRIMARY KEY USING INDEX` + `ALTER SEQUENCE ... AS bigint` + `OWNED BY` 교체. 자식 FK 도 같은 패턴 + NOT VALID FK. 신규 테이블은 처음부터 `bigint GENERATED ... AS IDENTITY`.
- 반례: 성장률로 계산해 수십 년 여유면 하지 않는다.
- 검증: 시퀀스 사용률 알람(예: 70%) 을 모니터링에 등록.
- 근거: https://www.postgresql.org/docs/current/sql-altersequence.html , https://www.postgresql.org/docs/current/datatype-numeric.html

### PG-MIG-13 · `ALTER TYPE ... ADD VALUE` 로 추가한 enum 값은 커밋 전까지 사용할 수 없다
- 적용: PostgreSQL enum 타입 사용 프로젝트
- 신호: 같은 마이그레이션 파일에서 ADD VALUE 후 그 값으로 UPDATE/INSERT, 또는 PG11 이하에서 트랜잭션 래핑 파일 안의 ADD VALUE
- 메커니즘: PG12+ 는 트랜잭션 블록 안에서 ADD VALUE 를 허용하지만 새 값은 그 트랜잭션이 커밋될 때까지 쓸 수 없다(`unsafe use of new value`). PG11 이하는 트랜잭션 블록 자체가 불가. enum 값 삭제는 지원되지 않는다(이름 변경은 `RENAME VALUE`).
- 처방: ADD VALUE 를 별도 마이그레이션으로 분리하고 사용은 다음 파일에서. 값 집합이 자주 바뀌면 enum 대신 `text + CHECK` 또는 참조 테이블.
- 반례: 값이 사실상 고정인 상태 머신은 enum 이 저장 효율·타입 안전에 유리.
- 검증: 스테이징에서 도구로 실제 실행.
- 근거: https://www.postgresql.org/docs/current/sql-altertype.html

### PG-MIG-14 · 컬럼 DROP/rename 은 실행 중인 구버전 파드와 서버측 prepared statement 를 깬다
- 적용: 롤링 배포 환경, JDBC(pgjdbc)·ORM 사용 서비스
- 신호: 배포 중 `column "x" does not exist`, `cached plan must not change result type`
- 메커니즘: ORM 은 매핑된 컬럼을 명시적으로 SELECT/INSERT 하므로 DROP 이 코드 배포보다 먼저 나가면 구버전 파드가 실패한다. pgjdbc 는 같은 문장이 `prepareThreshold`(기본 5)회 실행되면 서버측 prepared statement 로 전환하는데, `SELECT *` 결과 컬럼이 DDL 로 바뀌면 캐시된 계획이 무효화되어 위 오류가 난다.
- 처방: 순서는 ① 코드에서 읽기/쓰기 제거 배포(ORM 매핑 삭제, Hibernate 는 엔티티에서 필드 제거) → ② DROP. rename 은 expand-contract(새 컬럼 + 동기화) 로. `SELECT *` 를 앱 쿼리에서 금지. DROP COLUMN 은 공간을 즉시 회수하지 않는다(재작성 시 회수).
- 반례: 단일 인스턴스 + 다운타임 허용 배포.
- 검증: 스테이징에서 구버전 앱을 띄운 채 마이그레이션 적용 후 스모크 테스트.
- 근거: https://jdbc.postgresql.org/documentation/server-prepare/ , https://www.postgresql.org/docs/current/sql-altertable.html

### PG-MIG-15 · 대량 백필을 한 번의 UPDATE 로 하면 테이블 2배·WAL 폭증·복제 지연
- 적용: 수백만 행 이상 갱신하는 데이터 마이그레이션
- 신호: `UPDATE big_table SET ... WHERE ...` 단일 문장, 마이그레이션 파일 안의 백필
- 메커니즘: MVCC 에서 UPDATE 는 새 튜플 버전을 쓴다. 한 트랜잭션이면 끝날 때까지 죽은 튜플을 회수할 수 없어 테이블·인덱스가 최대 2배로 팽창하고, WAL 이 한꺼번에 생성되어 레플리카 재생이 밀리며, 행 락을 끝까지 쥔다. 인덱스 컬럼을 바꾸면 HOT 이 불가해 모든 인덱스에도 새 항목이 생긴다.
- 처방: 마이그레이션 도구 밖의 배치 잡(또는 도구의 비트랜잭션 파일)으로 PK 키셋 범위 단위 커밋:
  ```sql
  UPDATE orders SET shipping_address = ''
  WHERE id > $1 AND id <= $1 + 5000 AND shipping_address IS NULL;   -- 배치마다 COMMIT
  ```
  배치 크기는 측정으로 정한다(행 크기·인덱스 수에 따라 1k~10k 출발). 배치 사이 `pg_stat_replication.replay_lag` 가 임계 이상이면 대기. 진행 중 autovacuum 이 따라오지 못하면 수동 `VACUUM (ANALYZE) orders;` (FULL 아님). 바뀌지 않을 행은 `WHERE col IS DISTINCT FROM newval` 로 제외.
- 반례: 수만 행 이하 테이블은 단일 UPDATE 가 더 안전하고 단순.
- 검증: 백필 전후 `pg_total_relation_size`, `n_dead_tup`, 레플리카 지연 그래프; 완료 후 잔여 행 `count(*) WHERE col IS NULL = 0` 확인.
- 근거: https://www.postgresql.org/docs/current/routine-vacuuming.html , https://www.postgresql.org/docs/current/storage-hot.html

### PG-MIG-16 · DO 블록 안의 COMMIT 은 마이그레이션 도구의 트랜잭션 안에서 실패하고, `SKIP LOCKED` 루프는 덜 끝난 채 종료된다
- 적용: PL/pgSQL 로 배치 백필을 작성할 때
- 신호: `DO $$ ... LOOP ... COMMIT; END LOOP $$` 를 마이그레이션 파일에 넣음, `FOR UPDATE SKIP LOCKED` 후 `EXIT WHEN rows_updated = 0`
- 메커니즘: 프로시저/DO 블록의 트랜잭션 제어는 바깥에 명시적 트랜잭션 블록이 없을 때만 허용된다(`invalid transaction termination`). 대부분의 도구는 파일을 트랜잭션으로 감싼다. 또한 SKIP LOCKED 는 잠긴 행을 건너뛰므로 남은 행이 모두 잠겨 있으면 0건으로 루프가 끝나 NULL 이 남는다 → 이후 NOT NULL 단계 실패.
- 처방: 배치 백필은 앱/잡 코드나 비트랜잭션 파일로 실행. 루프 종료 조건은 "갱신 0건" 이 아니라 "대상 잔여 0건(`NOT EXISTS`)" 으로, 키셋 진행(PG-MIG-15)을 우선.
- 반례: 없음.
- 검증: 백필 종료 후 잔여 행 count 를 단언.
- 근거: https://www.postgresql.org/docs/current/plpgsql-transactions.html
