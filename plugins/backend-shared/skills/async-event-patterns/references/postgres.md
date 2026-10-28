# PostgreSQL 스페셜리스트 항목 (PG)

영역: IDX 인덱스 · MVCC 갱신/vacuum · POOL 커넥션 · PLAN 플래너 · QRY 쿼리 · LOCK 행 락.
스키마 변경(DDL) 락은 `migration-safety-checklist` 의 PG-MIG 항목을 본다.

---

## IDX

### PG-IDX-01 · 복합 B-tree 는 "등치 → 범위 → 정렬" 순서, 선두 컬럼 없는 조건은 PG18 전까지 사실상 무용
- 적용: 다중 컬럼 인덱스 설계·리뷰
- 신호: `(created_at, user_id)` 인덱스에 `WHERE user_id = ? AND created_at > ?` 질의, EXPLAIN 에서 `Index Cond` 대신 `Filter` 로 걸러지는 행 수(`Rows Removed by Filter`)가 큼
- 메커니즘: B-tree 는 선두 컬럼부터 정렬된다. 범위 조건 뒤의 컬럼은 탐색 범위를 줄이지 못하고 필터로만 쓰인다. PG18 은 B-tree skip scan 을 추가해 선두 컬럼 조건이 없을 때도 인덱스를 쓸 수 있지만, 선두 컬럼 카디널리티가 낮을 때만 효율적이다.
- 처방: 등치 조건 컬럼을 앞에, 범위/정렬 컬럼을 뒤에: `(user_id, created_at)`. `ORDER BY created_at DESC LIMIT n` 이면 정렬 방향까지 맞춰 정렬 노드를 없앤다. 키셋 페이지네이션의 행 값 비교 `WHERE (created_at, id) < ($1, $2)` 는 **모든 컬럼의 정렬 방향이 같을 때만** 인덱스 `(created_at DESC, id DESC)` 의 단일 범위로 처리된다 — 방향이 섞이면(`created_at DESC, id ASC`) 행 값 비교로 표현할 수 없어 OR 전개가 필요하고 범위 탐색이 깨진다.
- 반례: PG18+ 에서 선두 컬럼이 저카디널리티(상태값 몇 개)면 skip scan 으로 인덱스 하나를 공유하는 편이 인덱스 추가보다 낫다.
- 검증: `EXPLAIN (ANALYZE, BUFFERS)` 의 `Index Cond` vs `Filter`, `shared hit/read` 버퍼 수.
- 근거: https://www.postgresql.org/docs/current/indexes-multicolumn.html , https://www.postgresql.org/docs/release/18.0/ , https://www.postgresql.org/docs/current/functions-comparisons.html#ROW-WISE-COMPARISON

### PG-IDX-02 · 부분 인덱스는 바인드 파라미터 조건에서 generic plan 으로 바뀌는 순간 안 쓰인다
- 적용: `WHERE status = 'ACTIVE'` 같은 partial index + prepared statement(JDBC/pgx/asyncpg/psycopg 서버측 prepare)
- 신호: 처음 몇 번은 빠르다가 이후 느려지는 쿼리, 같은 SQL 이 psql 에서는 인덱스를 탐
- 메커니즘: 부분 인덱스는 쿼리 WHERE 가 인덱스 술어를 **증명 가능하게 함의**할 때만 쓰인다. `status = $1` 은 custom plan 에서는 값이 대입되어 증명되지만, `plan_cache_mode = auto` 에서 5회 실행 후 generic plan 이 선택되면 `$1` 의 값을 모르므로 부분 인덱스를 쓸 수 없다.
- 처방: 부분 인덱스 술어에 해당하는 조건은 SQL 에 **리터럴로** 쓴다(`WHERE status = 'ACTIVE' AND user_id = $1`). 또는 해당 쿼리/역할에 `plan_cache_mode = force_custom_plan`(PG12+).
- 반례: 술어 값이 요청마다 바뀌어야 하면 부분 인덱스가 아니라 일반 복합 인덱스가 맞다.
- 검증: 같은 문장을 `PREPARE` 후 6회 이상 `EXPLAIN EXECUTE` 해 계획 변화를 확인.
- 근거: https://www.postgresql.org/docs/current/indexes-partial.html , https://www.postgresql.org/docs/current/sql-prepare.html (Notes: generic vs custom plans)

### PG-IDX-03 · covering(INCLUDE) 인덱스의 index-only scan 은 visibility map 이 깨끗할 때만 공짜다
- 적용: PG11+ `INCLUDE`, 갱신이 잦은 테이블
- 신호: `Index Only Scan` 인데 `Heap Fetches` 가 행 수에 근접
- 메커니즘: index-only scan 은 페이지가 all-visible 로 표시된 경우에만 힙 방문을 생략한다. vacuum 이 따라오지 못하면 매 행 힙을 읽어 일반 인덱스 스캔보다 나을 게 없다.
- 처방: 해당 테이블 autovacuum 을 공격적으로(PG-MVCC-02). INCLUDE 컬럼은 조회 전용 소수만 — 인덱스가 커질수록 캐시 적중률이 떨어진다.
- 반례: 쓰기 위주 테이블에서 넓은 INCLUDE 는 쓰기 비용과 HOT 차단(PG-MVCC-01)만 늘린다.
- 검증: `EXPLAIN (ANALYZE)` 의 `Heap Fetches`, `pg_visibility` 확장 또는 `pg_class.relallvisible / relpages`.
- 근거: https://www.postgresql.org/docs/current/indexes-index-only-scans.html

### PG-IDX-04 · jsonb GIN: `jsonb_path_ops` 는 `@>` 전용, 기본 `fastupdate` 대기 목록이 쓰기·조회 지연을 만든다
- 적용: jsonb 컬럼 검색
- 신호: `?`, `?|` 키 존재 조회가 인덱스를 안 탐 / GIN 테이블에서 주기적 INSERT 지연 스파이크
- 메커니즘: `jsonb_path_ops` 는 더 작고 빠르지만 `@>`(와 jsonpath `@?`, `@@`)만 지원하고 키 존재 연산자는 지원하지 않는다. GIN 은 기본 `fastupdate=on` 으로 신규 항목을 pending list 에 쌓았다가(`gin_pending_list_limit` 기본 4MB) 한 번에 병합하므로 그 순간의 쓰기가 느려지고, 조회는 pending list 를 선형 스캔한다.
- 처방: 질의 연산자에 맞춰 opclass 선택. 지연 스파이크가 문제면 `WITH (fastupdate = off)` 또는 pending 한도 축소. 자주 조회하는 특정 키는 GIN 대신 표현식 B-tree `((doc->>'sku'))`.
- 반례: 대량 적재 위주라면 fastupdate 가 총 처리량에 유리.
- 검증: `EXPLAIN` 의 `Bitmap Index Scan` 사용 여부, `pgstatginindex()`(pgstattuple)로 pending 크기.
- 근거: https://www.postgresql.org/docs/current/datatype-json.html#JSON-INDEXING , https://www.postgresql.org/docs/current/gin.html#GIN-FAST-UPDATE

### PG-IDX-05 · `LIKE 'abc%'` 는 C 가 아닌 collation 에서 일반 B-tree 를 못 탄다, `'%abc%'` 는 pg_trgm
- 적용: 접두 검색, 부분 문자열 검색
- 신호: `LIKE 'prefix%'` 가 Seq Scan, DB collation 이 `en_US.UTF-8`/`ko_KR.UTF-8`
- 메커니즘: 비-C collation 의 정렬 순서는 접두 범위 변환에 쓸 수 없다.
- 처방: 접두 검색은 `text_pattern_ops`(또는 `COLLATE "C"`) 인덱스. 중간 일치·`ILIKE` 는 `pg_trgm` GIN/GiST. 한국어 형태소 검색 수준이면 DB 가 아니라 검색엔진(ES) 영역.
- 반례: `text_pattern_ops` 인덱스는 `<`, `ORDER BY` 같은 일반 비교에 안 쓰인다 — 정렬용 인덱스가 따로 필요할 수 있다.
- 검증: `EXPLAIN` 의 `Index Cond: ((name ~>=~ 'abc') AND (name ~<~ 'abd'))`.
- 근거: https://www.postgresql.org/docs/current/indexes-opclass.html , https://www.postgresql.org/docs/current/pgtrgm.html

### PG-IDX-06 · 미사용 인덱스 판정은 모든 노드에서 — 통계는 노드별이다
- 적용: 인덱스 정리, 쓰기 성능 개선
- 신호: `pg_stat_user_indexes.idx_scan = 0`, `(a)` 와 `(a, b)` 처럼 선두가 겹치는 중복 인덱스
- 메커니즘: 인덱스마다 쓰기 비용이 있고, 갱신 컬럼을 포함하면 HOT 을 막는다(PG-MVCC-01). 하지만 통계는 프라이머리·레플리카 각자 따로 쌓이고 통계 리셋/재시작으로 초기화된다.
- 처방: 모든 레플리카와 충분한 관측 기간(월말 배치 등 주기 포함) 후 판단. `(a)` 는 `(a, b)` 가 있으면 대개 중복(단, `(a)` 가 UNIQUE 이면 아님).
- 반례: 제약(UNIQUE/PK/배타)을 지탱하는 인덱스, 드물지만 치명적인 경로(장애 복구 쿼리)용 인덱스.
- 검증: `pg_stat_user_indexes` 를 각 노드에서, `pg_stat_database.stats_reset` 으로 관측 기간 확인.
- 근거: https://www.postgresql.org/docs/current/monitoring-stats.html

### PG-IDX-07 · 랜덤 UUID(v4) PK 는 B-tree 전역에 무작위 삽입 — 캐시 미스와 WAL full-page image 증폭
- 적용: 쓰기량이 큰 테이블의 UUID PK/인덱스
- 신호: 인덱스 크기가 메모리를 넘으면서 INSERT 지연·WAL 생성량 급증
- 메커니즘: v4 는 무작위라 매 삽입이 임의 리프 페이지를 건드린다. 체크포인트 이후 첫 수정 페이지마다 full-page image 가 WAL 에 기록되어 WAL 이 커지고, 작업 집합이 인덱스 전체가 된다.
- 처방: 시간순 정렬 가능한 UUIDv7(PG18 `uuidv7()`, 또는 앱에서 생성) 또는 bigint identity + 외부 노출용 UUID 별도 컬럼.
- 반례: 키 추측 방지가 요구사항이면 v7 의 시각 노출을 검토. 소형 테이블은 무관.
- 검증: `pg_stat_wal.wal_fpi`(PG14+), 인덱스 크기 추이.
- 근거: https://www.postgresql.org/docs/release/18.0/ , https://www.postgresql.org/docs/current/wal-configuration.html

### PG-IDX-08 · 추가 전용·시간 상관 테이블에는 B-tree 대신 BRIN
- 적용: 로그·이벤트·시계열처럼 물리 순서와 컬럼 값이 상관된 대형 테이블
- 신호: 타임스탬프 B-tree 인덱스가 테이블의 상당 비율 크기
- 메커니즘: BRIN 은 블록 범위의 min/max 만 저장해 수천 배 작다. 상관이 깨지면(UPDATE·무작위 삽입) 효과가 사라진다.
- 처방: `pg_stats.correlation` 이 ±1 에 가까운 컬럼에 `USING brin`. PG16+ 는 BRIN 컬럼만 갱신하는 UPDATE 도 HOT 가능.
- 반례: 단건 조회·소범위 고선택도 조회는 B-tree 가 낫다.
- 검증: `SELECT correlation FROM pg_stats WHERE tablename='t' AND attname='ts';`, EXPLAIN 의 `Rows Removed by Index Recheck`.
- 근거: https://www.postgresql.org/docs/current/brin.html

## MVCC

### PG-MVCC-01 · HOT 갱신 조건: 인덱스 컬럼 불변 + 같은 페이지 여유 공간 — 갱신 위주 테이블은 fillfactor 를 낮춘다
- 적용: 같은 행을 자주 UPDATE 하는 테이블(상태·카운터·재고)
- 신호: `pg_stat_user_tables` 에서 `n_tup_hot_upd / n_tup_upd` 비율이 낮음, 인덱스 크기가 계속 증가
- 메커니즘: HOT 은 (1) 어떤 인덱스 컬럼도 바뀌지 않고 (2) 새 버전이 같은 힙 페이지에 들어갈 때만 인덱스 항목 추가를 생략한다. 기본 fillfactor 100 은 페이지를 꽉 채워 (2) 를 실패하게 만든다. PG16+ 는 BRIN 인덱스 컬럼 변경은 HOT 을 막지 않는다.
- 처방: `ALTER TABLE t SET (fillfactor = 80);` (신규/재작성 페이지부터 적용). 자주 바뀌는 컬럼에 걸린 불필요한 인덱스 제거. `updated_at` 을 인덱싱하면 모든 UPDATE 가 non-HOT.
- 반례: 추가 전용 테이블은 fillfactor 를 낮추면 공간만 낭비.
- 검증: 변경 전후 HOT 비율, PG16+ `n_tup_newpage_upd`.
- 근거: https://www.postgresql.org/docs/current/storage-hot.html , https://www.postgresql.org/docs/current/sql-createtable.html#RELOPTION-FILLFACTOR

### PG-MVCC-02 · autovacuum 기본값(scale factor 0.2)은 대형 테이블에 너무 늦다
- 적용: 수천만 행 이상, 갱신/삭제가 있는 테이블
- 신호: `n_dead_tup` 이 수백만, `last_autovacuum` 이 오래됨, 테이블·인덱스 bloat
- 메커니즘: 트리거 조건은 `autovacuum_vacuum_threshold(50) + autovacuum_vacuum_scale_factor(0.2) × reltuples` — 1억 행이면 2천만 dead tuple 이 쌓여야 시작한다. 비용 제한(`vacuum_cost_limit` 200, PG12+ `autovacuum_vacuum_cost_delay` 2ms)으로 큰 테이블에선 한 번이 오래 걸린다. 추가 전용 테이블은 PG13 부터 `autovacuum_vacuum_insert_threshold/scale_factor` 로 vacuum 되어 visibility map 이 갱신된다. PG18+ 는 `autovacuum_vacuum_max_threshold`(기본 1억)로 위 계산값에 상한을 둔다 — 약 5억 행 이상 테이블부터 트리거가 1억 dead tuple 로 고정되지만, 그래도 대부분의 핫 테이블엔 늦으므로 테이블 단위 조정은 여전히 필요.
- 처방: 테이블 단위 `ALTER TABLE t SET (autovacuum_vacuum_scale_factor = 0.01, autovacuum_vacuum_cost_limit = 1000);` 등. 전역보다 핫 테이블 단위 조정이 안전.
- 반례: 소형 테이블은 기본값으로 충분. cost_limit 를 무작정 올리면 I/O 를 잠식한다.
- 검증: `pg_stat_user_tables(n_dead_tup, last_autovacuum, autovacuum_count)`, `pgstattuple` 로 bloat 측정, 진행 중 vacuum 은 `pg_stat_progress_vacuum`(9.6+, PG17 에서 `dead_tuple_bytes`·`indexes_total` 등 컬럼 변경).
- 근거: https://www.postgresql.org/docs/current/routine-vacuuming.html#AUTOVACUUM , https://www.postgresql.org/docs/current/runtime-config-autovacuum.html (`autovacuum_vacuum_max_threshold`, PG18)

### PG-MVCC-03 · xmin 지평선을 붙잡는 것은 긴 트랜잭션만이 아니다 — 복제 슬롯·hot_standby_feedback·준비된 트랜잭션
- 적용: vacuum 이 돌아도 dead tuple 이 줄지 않는 DB
- 신호: `VACUUM VERBOSE` 의 "dead row versions cannot be removed yet", `n_dead_tup` 고착
- 메커니즘: vacuum 은 가장 오래된 스냅샷(xmin) 이후의 죽은 튜플만 지울 수 있다. 붙잡는 주체: 오래된 트랜잭션/`idle in transaction`, 비활성 논리 복제 슬롯(CDC 커넥터 중단 시), 레플리카의 `hot_standby_feedback=on` + 긴 조회, 방치된 `PREPARE TRANSACTION`. DB 전체 테이블에 영향.
- 처방: 다음을 모두 감시:
  ```sql
  SELECT pid, age(backend_xmin), state FROM pg_stat_activity WHERE backend_xmin IS NOT NULL ORDER BY 2 DESC;
  SELECT slot_name, active, age(xmin), age(catalog_xmin) FROM pg_replication_slots;
  SELECT gid, age(transaction) FROM pg_prepared_xacts;
  ```
  앱 역할에 `idle_in_transaction_session_timeout`, 슬롯은 `max_slot_wal_keep_size`(PG13+) 로 WAL 무한 보존 방지.
- 반례: 의도된 CDC 슬롯을 지우면 데이터 유실 — 커넥터 복구가 먼저.
- 검증: 위 쿼리를 대시보드 알람으로.
- 근거: https://www.postgresql.org/docs/current/routine-vacuuming.html , https://www.postgresql.org/docs/current/view-pg-replication-slots.html

### PG-MVCC-04 · 트랜잭션 ID wraparound 방지 vacuum 은 취소되지 않고 DDL 을 막는다
- 적용: 쓰기량이 큰 DB, 대형 정적 테이블
- 신호: `pg_stat_activity` 에 `autovacuum: VACUUM ... (to prevent wraparound)`, 마이그레이션이 그 테이블에서 멈춤
- 메커니즘: `age(relfrozenxid)` 가 `autovacuum_freeze_max_age`(기본 2억)를 넘으면 강제 vacuum 이 시작되며, 이 vacuum 은 락 충돌로 자동 취소되지 않는다. 방치하면 쓰기 중단 보호 모드까지 간다.
- 처방: `age(datfrozenxid)`/`age(relfrozenxid)` 를 모니터링하고, 대형 테이블은 한가한 시간에 수동 `VACUUM (FREEZE)`. DDL 일정은 강제 vacuum 진행 여부를 보고 잡는다.
- 반례: —
- 검증: `SELECT relname, age(relfrozenxid) FROM pg_class WHERE relkind='r' ORDER BY 2 DESC LIMIT 10;`
- 근거: https://www.postgresql.org/docs/current/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND

### PG-MVCC-05 · 큰 jsonb/text 의 일부만 바꿔도 TOAST 값 전체가 다시 쓰인다
- 적용: 수 KB 이상 jsonb 문서를 부분 갱신(`jsonb_set`)하는 패턴
- 신호: 작은 UPDATE 대비 WAL·디스크 쓰기가 큼, TOAST 테이블 bloat
- 메커니즘: 행이 약 2kB(`TOAST_TUPLE_THRESHOLD`)를 넘으면 큰 값은 압축·분할되어 TOAST 테이블에 저장된다. jsonb 는 부분 갱신 개념이 없어 키 하나를 바꿔도 값 전체를 새로 쓴다.
- 처방: 자주 바뀌는 필드는 일반 컬럼으로 분리. 큰 문서는 불변(추가 전용) 설계.
- 반례: 드물게 갱신되는 문서는 문제없다.
- 검증: `pg_total_relation_size` vs `pg_relation_size`(TOAST 비중), 갱신 전후 `pg_current_wal_lsn()` 차이.
- 근거: https://www.postgresql.org/docs/current/storage-toast.html

## POOL

### PG-POOL-01 · 풀 크기는 "파드 수 × 풀 크기 ≤ max_connections − 여유" 와 처리량 법칙으로 정한다
- 적용: 수평 확장되는 서비스
- 신호: 오토스케일 후 `FATAL: sorry, too many clients already`, 풀 대기(`hikaricp_connections_pending`) 증가인데 DB CPU 는 여유
- 메커니즘: PostgreSQL 연결은 프로세스 하나다. 활성 연결이 코어 수를 크게 넘으면 경합으로 처리량이 오히려 떨어진다. HikariCP 문서의 출발점은 `connections ≈ (core_count × 2) + effective_spindle_count`(DB 서버 기준). 필요 동시성은 Little 의 법칙: 처리량(QPS) × 평균 DB 점유 시간(s).
- 처방: 서비스별 풀 = 필요 동시성 + 여유, 파드 최대 수를 곱해 DB 한도 이내로. 파드가 많으면 풀을 늘리지 말고 PgBouncer 같은 외부 풀러. HikariCP 기본 `maximumPoolSize` 10.
- 반례: 긴 분석 쿼리 전용 풀은 별도로 작게 분리(OLTP 풀 오염 방지).
- 검증: 풀 대기 시간 메트릭, DB `pg_stat_activity` 의 `active` 수 vs 코어 수.
- 근거: https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing , https://www.postgresql.org/docs/current/runtime-config-connection.html

### PG-POOL-02 · Go `database/sql` 기본값: MaxOpenConns 무제한, MaxIdleConns 2 — 부하 시 연결 폭주와 재연결 반복
- 적용: Go 서비스(`database/sql` + pgx stdlib/lib/pq), pgxpool
- 신호: 부하 테스트 중 DB 연결 수 급증, TIME_WAIT 다수, 연결 수립 지연이 p99 에 반영
- 메커니즘: `SetMaxOpenConns` 기본 0(무제한)이라 동시 요청만큼 연결을 연다. 유휴 보관은 기본 2개라 반납 즉시 닫았다가 다시 연다. pgxpool 의 기본 최대 연결은 `max(4, runtime.NumCPU())`.
- 처방: `db.SetMaxOpenConns(n); db.SetMaxIdleConns(n); db.SetConnMaxLifetime(…); db.SetConnMaxIdleTime(…)` 을 명시. pgxpool 은 `pool_max_conns` 를 PG-POOL-01 기준으로.
- 반례: 서버리스/단발 CLI 는 유휴 연결 유지가 낭비.
- 검증: `db.Stats()`(`WaitCount`, `WaitDuration`, `MaxIdleClosed`) 를 메트릭으로 노출.
- 근거: https://pkg.go.dev/database/sql#DB.SetMaxIdleConns , https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool#ParseConfig

### PG-POOL-03 · PgBouncer transaction 모드 + 서버측 prepared statement = "prepared statement already exists/does not exist"
- 적용: PgBouncer(또는 RDS Proxy 등) transaction pooling 뒤의 앱
- 신호: 5번째 실행부터 발생하는 `prepared statement "S_1" already exists`(pgjdbc), pgx 의 `prepared statement ... does not exist`
- 메커니즘: pgjdbc 는 같은 문장을 `prepareThreshold`(기본 5)회 실행하면 이름 있는 서버측 prepared statement 로 전환한다. pgx 의 기본 실행 모드도 문장을 캐시·prepare 한다. transaction 모드에서는 다음 트랜잭션이 다른 서버 연결로 가므로 이름이 어긋난다. PgBouncer 는 `max_prepared_statements` > 0 이면 프로토콜 수준 named prepared statement 를 추적해 이를 지원하며, **버전별 기본이 다르다**: < 1.21 미지원 · 1.21~1.23 기본 0(꺼짐, 명시 필요) · **1.24.0+ 기본 200(켜짐)**. SQL 수준 `PREPARE`/`EXECUTE` 는 추적 대상이 아니다.
- 처방: 먼저 PgBouncer 버전과 실효값을 확인(admin 콘솔 `SHOW CONFIG;`). 1.24+ 면 기본으로 해결되므로 드라이버를 건드리지 않는다(`prepareThreshold=0` 은 불필요한 성능 손실). 1.21~1.23 은 `max_prepared_statements` 를 0 보다 크게 명시. 1.21 미만이거나 RDS Proxy 등 추적하지 않는 풀러는 드라이버 측 `prepareThreshold=0`(pgjdbc) / `default_query_exec_mode=exec`·`simple_protocol`(pgx). 추적을 켠 뒤 스키마 마이그레이션 후 `cached plan must not change result type` 이 나면 admin 콘솔 `RECONNECT`. transaction 모드에서는 세션 상태(`SET`, advisory lock, `LISTEN`, 임시 테이블)도 유지되지 않는다.
- 반례: session 모드 풀러에서는 해당 없음.
- 검증: 동일 쿼리 10회 반복 통합 테스트를 PgBouncer 경유로 실행.
- 근거: https://www.pgbouncer.org/config.html#max_prepared_statements , https://www.pgbouncer.org/changelog.html (1.21.0 도입, 1.24.0 기본 200) , https://jdbc.postgresql.org/documentation/server-prepare/ , https://pkg.go.dev/github.com/jackc/pgx/v5#QueryExecMode

### PG-POOL-04 · 트랜잭션·영속성 컨텍스트가 외부 호출 동안 연결을 쥔다 (Spring OSIV 기본 on 포함)
- 적용: Spring Boot + JPA, `@Transactional` 메서드 안에서 HTTP/Kafka 호출
- 신호: DB 는 한가한데 풀 고갈, `hikaricp_connections_usage` 가 외부 API 지연과 같은 모양
- 메커니즘: 트랜잭션이 열린 동안 연결은 반납되지 않는다. Spring Boot 는 `spring.jpa.open-in-view` 기본 true(기동 시 경고 로그) — 요청 중 한 번 연결을 얻으면 뷰 렌더링/응답 직렬화 끝까지 붙잡을 수 있다.
- 처방: 외부 호출은 트랜잭션 밖으로(읽기 → 커밋 → 호출 → 짧은 쓰기 트랜잭션). `spring.jpa.open-in-view=false` 로 두고 필요한 연관은 조회 시 fetch.
- 반례: 외부 호출 결과와 DB 쓰기가 원자적이어야 하면 트랜잭션 연장 대신 outbox(DIST-MSG-01).
- 검증: HikariCP `leakDetectionThreshold` 를 스테이징에서 짧게 켜 장시간 점유 스택 확인.
- 근거: https://docs.spring.io/spring-boot/appendix/application-properties/index.html (spring.jpa.open-in-view), https://github.com/brettwooldridge/HikariCP#frequently-used

## PLAN

### PG-PLAN-01 · prepared statement 는 5회 후 generic plan 으로 바뀔 수 있다 — 값 분포가 치우친 컬럼에서 계획 급변
- 적용: 서버측 prepare 를 쓰는 드라이버, 값 분포가 치우친 컬럼(테넌트 ID, 상태)
- 신호: 특정 파라미터에서만 느린 쿼리, 재시작 직후엔 빠름
- 메커니즘: `plan_cache_mode = auto` 는 처음 5회 custom plan 을 만들고 이후 generic plan 비용이 평균 custom 비용보다 크게 나쁘지 않으면 generic 을 고정 사용한다. 대형 테넌트에 맞지 않는 계획이 고정될 수 있다.
- 처방: 문제 쿼리에 한해 `SET plan_cache_mode = force_custom_plan`(PG12+, 역할/트랜잭션 단위) 또는 드라이버의 prepare 임계 조정.
- 반례: 전역 force_custom_plan 은 모든 실행에 계획 비용을 지불시킨다.
- 검증: `auto_explain`(`log_min_duration`, `log_analyze`) 로 느린 실행의 실제 계획 캡처.
- 근거: https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-PLAN-CACHE-MODE

### PG-PLAN-02 · 상관된 컬럼 조건은 행 수를 과소추정한다 — CREATE STATISTICS
- 적용: `WHERE city = ? AND zip = ?` 처럼 함수 종속 관계가 있는 다중 조건
- 신호: EXPLAIN 의 `rows=` 추정치가 실제보다 수십~수천 배 작아 Nested Loop 선택
- 메커니즘: 플래너는 기본적으로 컬럼 독립을 가정해 선택도를 곱한다.
- 처방: `CREATE STATISTICS s (dependencies, ndistinct, mcv) ON city, zip FROM addr; ANALYZE addr;` (mcv 는 PG12+). 특정 컬럼 분포가 넓으면 `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS 1000`(기본 `default_statistics_target` 100).
- 반례: 독립 컬럼에 만들면 ANALYZE 비용만 늘어난다.
- 검증: 적용 전후 `EXPLAIN (ANALYZE)` 추정/실제 행 수 비교.
- 근거: https://www.postgresql.org/docs/current/planner-stats.html#PLANNER-STATS-EXTENDED

### PG-PLAN-03 · 가변 길이 `IN (?, ?, …)` 대신 단일 배열 파라미터 `= ANY(?)`
- 적용: ID 목록 조회, 배치 조회
- 신호: 목록 길이마다 다른 SQL 문자열(문장 캐시·`pg_stat_statements` 오염), 대량 목록에서 `Tried to send an out-of-range integer as a 2-byte value`(pgjdbc)
- 메커니즘: 바인드 파라미터 수는 프로토콜상 16비트 필드라 상한이 있고(구버전 pgjdbc 32767, 프로토콜 최대 65535), 길이별로 별개 문장이 되어 prepare 캐시 재사용이 깨진다.
- 처방: `WHERE id = ANY(?)` + 배열 바인딩 — JDBC `connection.createArrayOf("bigint", ids)`, pgx 는 `[]int64` 를 그대로, psycopg 는 list 를 그대로. 수만 건 이상이면 `JOIN unnest(?::bigint[]) AS u(id)` 또는 임시 테이블/COPY.
- 반례: 고정된 소수(2~3개) 값은 IN 리터럴이 더 읽기 쉽다.
- 검증: `pg_stat_statements` 에서 해당 쿼리 패턴의 행 수가 1개로 수렴하는지.
- 근거: https://www.postgresql.org/docs/current/functions-comparisons.html#FUNCTIONS-COMPARISONS-ANY-SOME , https://www.postgresql.org/docs/current/protocol-message-formats.html (Bind)

### PG-PLAN-05 · `ORDER BY … LIMIT` 이 정렬 인덱스를 따라 끝없이 걷는 함정
- 적용: 선택도가 낮은(희귀) 필터 + 다른 컬럼 정렬 + 작은 LIMIT
- 신호: `LIMIT 10` 인데 수 초, EXPLAIN 에 `Index Scan using idx_created_at` + 큰 `Rows Removed by Filter`
- 메커니즘: 플래너는 조건을 만족하는 행이 정렬 순서에 고르게 퍼져 있다고 가정하고 정렬 인덱스를 따라가다 LIMIT 에서 멈출 것으로 기대한다. 일치 행이 드물거나 끝쪽에 몰리면 인덱스 대부분을 훑는다.
- 처방: 필터+정렬 복합 인덱스 `(status, created_at)`, 또는 통계 보강(PG-PLAN-02).
- 반례: 필터가 흔한 값이면 원래 계획이 최적.
- 검증: 희귀 값/흔한 값 각각으로 `EXPLAIN (ANALYZE)`.
- 근거: https://www.postgresql.org/docs/current/using-explain.html

### PG-PLAN-06 · OLTP 에서 JIT 컴파일이 수~수십 ms 를 더한다
- 적용: PG12+(jit 기본 on), 행 수 추정이 큰 OLTP 쿼리
- 신호: EXPLAIN ANALYZE 하단 `JIT: ... Timing: Generation ... Total` 이 실행 시간 대비 큼
- 메커니즘: 추정 비용이 `jit_above_cost`(기본 100000)를 넘으면 JIT 이 켜진다. 추정이 부풀려진 짧은 쿼리도 컴파일 비용을 낸다.
- 처방: OLTP 역할/DB 에 `jit = off`, 또는 `jit_above_cost` 상향. 분석용 역할만 on.
- 반례: 대량 집계·분석 쿼리는 JIT 이득이 클 수 있다.
- 검증: 같은 쿼리를 `SET jit = off` 전후 비교.
- 근거: https://www.postgresql.org/docs/current/jit-decision.html

### PG-PLAN-07 · 대량 적재 직후·임시 테이블은 통계가 없다
- 적용: 배치 적재 후 즉시 조회, 임시 테이블을 쓰는 배치
- 신호: 적재 직후 첫 쿼리만 비정상 계획
- 메커니즘: autovacuum 의 analyze 는 임계 도달 후 비동기로 돈다. 임시 테이블은 autovacuum 이 아예 처리하지 않는다.
- 처방: 적재 직후 `ANALYZE t;` 를 배치 코드에 명시.
- 반례: 소량 적재.
- 검증: `pg_stat_user_tables.last_analyze/last_autoanalyze`.
- 근거: https://www.postgresql.org/docs/current/routine-vacuuming.html#VACUUM-FOR-STATISTICS

## QRY

### PG-QRY-01 · `NOT IN (subquery)` 는 anti-join 이 되지 않는다 — 서브쿼리 결과가 hash_mem 을 넘으면 행마다 재스캔(O(N×M))
- 적용: 제외 조회
- 신호: `WHERE id NOT IN (SELECT ref_id FROM ...)`
- 메커니즘: NULL 의미론(서브쿼리에 NULL 하나면 결과 0행) 때문에 플래너는 NOT IN 을 anti-join 으로 바꾸지 못하고 SubPlan 으로 실행한다. 결과가 `work_mem × hash_mem_multiplier` 에 들어가면 hashed SubPlan(해시 1회 구축), **넘으면 plain SubPlan** — 외부 행마다 서브쿼리 결과(Materialize)를 다시 훑어 O(N×M). 데이터가 커지는 순간 계획이 조용히 바뀌어 수 ms 쿼리가 수십 분이 된다.
- 처방: `WHERE NOT EXISTS (SELECT 1 FROM ... WHERE ref_id = t.id)`.
- 반례: 상수 리스트 NOT IN 은 무관.
- 검증: 바꾸기 전 EXPLAIN 에서 `Filter: (NOT (hashed SubPlan N))` vs `Filter: (NOT (SubPlan N))` 구분, 바꾼 후 `Hash Anti Join`/`Merge Anti Join` 확인.
- 근거: https://www.postgresql.org/docs/current/functions-subquery.html#FUNCTIONS-SUBQUERY-NOTIN

### PG-QRY-02 · 대량 INSERT: JDBC 배치는 `reWriteBatchedInserts=true` 없이는 문장 단위 왕복, 최상은 COPY
- 적용: 수천 행 이상 적재
- 신호: `saveAll()`/`executeBatch()` 인데 처리량이 단건과 비슷
- 메커니즘: pgjdbc 는 기본적으로 배치의 각 INSERT 를 개별 문장으로 보낸다. `reWriteBatchedInserts=true` 는 다중 VALUES 로 재작성한다. Hibernate 는 `IDENTITY` 생성 전략이면 JDBC 배치 자체를 비활성화한다.
- 처방: 연결 URL 에 `reWriteBatchedInserts=true`, Hibernate `hibernate.jdbc.batch_size` + 시퀀스 기반 ID(`allocationSize`). 최대 처리량은 COPY(`CopyManager`, pgx `CopyFrom`, psycopg `cursor.copy()`).
- 반례: 적재 중 행별 오류 처리가 필요하면 COPY 는 전체 실패 — 스테이징 테이블 + `INSERT ... SELECT`.
- 검증: 1만 행 적재 시간 비교.
- 근거: https://jdbc.postgresql.org/documentation/use/#connection-parameters , https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#batch

## LOCK

### PG-LOCK-01 · `SELECT … FOR UPDATE` 는 자식 테이블의 FK 삽입을 막는다 — 키를 안 바꾸면 `FOR NO KEY UPDATE`
- 적용: 비관적 락으로 부모 행을 잠그는 코드 + 그 행을 참조하는 자식 INSERT 가 동시에 일어나는 도메인(주문-주문항목)
- 신호: 자식 INSERT 가 부모 락 대기, `pg_locks` 에 `tuple` 락 대기
- 메커니즘: FK 검사는 부모 행에 `FOR KEY SHARE` 를 잡는다. 이는 `FOR UPDATE` 와 충돌하지만 `FOR NO KEY UPDATE` 와는 충돌하지 않는다. 일반 UPDATE(키 컬럼 불변)는 내부적으로 NO KEY UPDATE 락을 쓴다.
- 처방: 키를 바꾸지 않는 갱신을 위한 명시 잠금은 `FOR NO KEY UPDATE`. ORM 의 비관적 락이 어떤 SQL 을 내는지 로그로 확인.
- 반례: PK/UNIQUE 키 변경이나 삭제 예정이면 FOR UPDATE 가 맞다.
- 검증: 두 세션 재현(부모 잠금 → 자식 INSERT) 으로 대기 여부 확인.
- 근거: https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS

### PG-LOCK-02 · 다건 UPDATE 의 잠금 순서가 요청마다 다르면 교착
- 적용: 한 트랜잭션에서 여러 행(재고 여러 SKU, 잔액 이체)을 갱신
- 신호: `deadlock detected`, `log_lock_waits` 로그
- 메커니즘: 두 트랜잭션이 같은 행 집합을 다른 순서로 잠근다.
- 처방: 갱신 전 키 정렬 후 `SELECT ... WHERE id = ANY(?) ORDER BY id FOR NO KEY UPDATE` 로 일괄 선점, 또는 단일 UPDATE 문.
- 반례: —
- 검증: `log_lock_waits = on`, `deadlock_timeout`(기본 1s) 로그 분석.
- 근거: https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-DEADLOCKS
