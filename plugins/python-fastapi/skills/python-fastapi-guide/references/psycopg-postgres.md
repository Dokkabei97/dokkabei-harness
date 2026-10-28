# psycopg 3 · 커넥션 풀 · PostgreSQL 마이그레이션(dbmate)

> 스페셜리스트 항목. 원시 SQL(psycopg 3) 쿼리 계층 기준이지만 PY-PG-03/06, PY-MIG-* 는 ORM 프로젝트에도 해당한다.
> 기준: psycopg 3.2+, psycopg_pool 3.2+, PostgreSQL 13+. 대상 프로젝트의 lock 파일에서 실제 버전을 먼저 확인.

## 목차
- PY-PG-01 서버사이드 바인딩: `IN %s` 튜플·`SET %s` 가 깨진다
- PY-PG-02 자동 prepared statement(임계 5회) ↔ PgBouncer transaction 모드
- PY-PG-03 풀 기본값(min 4, max=min, timeout 30s)과 커넥션 총량 산식
- PY-PG-04 풀은 커넥션 건강을 확인하지 않는다 — `check` 콜백
- PY-PG-05 AsyncConnectionPool 은 생성자에서 열지 말 것
- PY-PG-06 고갈 시 30초 무한 대기열 — 부하 차단(shed) 설계
- PY-PG-07 커넥션을 쥔 채 외부 I/O 를 await — idle in transaction
- PY-PG-08 기본 커서는 결과 전체를 메모리에 적재한다
- PY-PG-09 대량 적재는 executemany 가 아니라 COPY
- PY-PG-10 asyncpg(+SQLAlchemy) ↔ PgBouncer transaction 모드: `__asyncpg_stmt_N__` 충돌
- PY-MIG-01 dbmate 는 파일 단위 트랜잭션 — CONCURRENTLY 는 `transaction:false`
- PY-MIG-02 DDL 락 대기열이 전체 트래픽을 막는다 — `lock_timeout`
- PY-MIG-03 dbmate 운영 함정: 마이그레이션 락·pg_dump·순서 역전(`--strict`)
- PY-MIG-04 ADD COLUMN DEFAULT 의 테이블 재작성 조건
- PY-MIG-05 NOT NULL/FK 를 락 없이 추가하는 2단계

---

### PY-PG-01 · psycopg 3 는 서버사이드 바인딩 — `IN %s` 튜플, `SET x = %s`, DDL 파라미터가 실패한다
- 적용: psycopg2 에서 이전했거나 psycopg2 관용구를 쓰는 코드
- 신호: `WHERE id IN %s` + 튜플 인자 → `syntax error at or near "$1"`, `SET search_path = %s` / `NOTIFY ch, %s` / `CREATE TABLE ... DEFAULT %s` 실패, 세미콜론으로 이어 붙인 다중 문장 + 파라미터 실패
- 메커니즘: psycopg 3 는 쿼리와 파라미터를 따로 보낸다(서버가 `$1` 로 바인딩). 서버 바인딩은 값 자리에만 허용되므로 유틸리티 문장(SET/NOTIFY/DDL)에는 파라미터를 못 쓰고, 튜플이 값 목록으로 펼쳐지지 않는다.
- 처방: `WHERE id = ANY(%s)` + `list` 인자(배열로 적응). `SET` → `SELECT set_config('search_path', %s, false)`, `NOTIFY` → `SELECT pg_notify(%s, %s)`. 식별자·DDL 은 `psycopg.sql.SQL/Identifier/Literal` 로 클라이언트 조립. 다중 문장은 파라미터 없이 보내거나 분리.
- 반례: `ClientCursor` 로 psycopg2 식 클라이언트 바인딩을 되살릴 수 있지만 prepared statement·바이너리 이점을 잃는다 — 전면 적용은 마이그레이션 임시 수단으로만.
- 검증: 쿼리 단위 테스트를 실제 PostgreSQL(Testcontainers 등)로 실행 — 모킹으로는 잡히지 않는다.
- 근거: https://www.psycopg.org/psycopg3/docs/basic/from_pg2.html#server-side-binding

### PY-PG-02 · 같은 쿼리 5회 실행 후 자동 prepare — PgBouncer transaction 모드에서 `prepared statement "_pg3_N" does not exist`
- 적용: psycopg 3 + PgBouncer(transaction pooling) 또는 Supabase/Neon 등 풀러 엔드포인트
- 신호: 배포 직후는 정상, 트래픽이 쌓이면 간헐적 `prepared statement ... does not exist` / `already exists`
- 메커니즘: psycopg 3 는 커넥션별로 같은 쿼리가 `prepare_threshold`(기본 **5**, 소스 `_preparing.py`) 회를 넘으면 서버에 PREPARE 한다(커넥션당 최대 `prepared_max`=100). transaction 모드 PgBouncer 는 트랜잭션마다 다른 서버 커넥션을 줄 수 있어 이름이 엇갈린다.
- 처방: (a) `psycopg.connect(..., prepare_threshold=None)` / 풀 `kwargs={"prepare_threshold": None}` 로 비활성. (b) PgBouncer **1.22+** 이고 `max_prepared_statements > 0` 이며 클라이언트 libpq 가 **PostgreSQL 17+** 이면 그대로 사용 가능. libpq 17 이 없으면 `prepared_max=None` 로 deallocate 를 끈다(psycopg 문서).
- 반례: PgBouncer 없이 직접 연결하는 앱에서 끄면 반복 쿼리의 파싱·플래닝 이점을 잃는다. session 모드 PgBouncer 는 문제없다. (b) 의 `prepared_max=None` 은 psycopg 쪽 deallocate 를 끄므로 커넥션마다 준비된 문장 목록이 상한 없이 쌓인다 — 쿼리 종류가 유한·소수일 때만 쓰고, 동적 SQL(조건 조합으로 문장이 계속 달라지는 검색 쿼리)이 많으면 (a) 비활성이 안전하다(누적 영향은 문서 의미에서의 추론, 실측 아님). (b) 를 쓰면 PgBouncer `max_prepared_statements` 가 0 이 아닌지(0 = 추적 비활성) 먼저 확인. asyncpg 는 처방이 다르다 → PY-PG-10.
- 검증: `SELECT name FROM pg_prepared_statements` (직접 연결 시), 풀러 환경에서 동일 쿼리 6회 이상 반복하는 통합 테스트.
- 근거: https://www.psycopg.org/psycopg3/docs/advanced/prepare.html#using-prepared-statements-with-pgbouncer

### PY-PG-03 · 풀 기본값은 `min_size=4`, `max_size=None`(=min, 고정 4개), `timeout=30s` — 총량은 워커×레플리카로 곱해진다
- 적용: `psycopg_pool.ConnectionPool/AsyncConnectionPool`(ORM 의 풀도 동일 산식)
- 신호: 부하 시 `PoolTimeout`, 또는 반대로 스케일아웃 직후 `FATAL: sorry, too many clients already`
- 메커니즘: `max_size` 를 안 주면 min 과 같은 **고정 4개**. 커넥션 총량 = 레플리카 × uvicorn 워커 × `max_size` (+ 마이그레이션·관리 커넥션) — 워커는 독립 프로세스라 lifespan 에서 각자 풀을 만든다. 예) 레플리카 4 × 워커 4 × max 10 = 160 > 기본 `max_connections` 100. PostgreSQL `max_connections` 기본 100, 그중 `superuser_reserved_connections` 기본 3. 기타 기본값: `max_lifetime=3600s`, `max_idle=600s`, `reconnect_timeout=300s`, `num_workers=3`.
- 처방: 풀 크기는 "DB 코어 수 기준 소수"에서 시작해 측정으로 키운다(psycopg 문서가 HikariCP 풀 사이징 글을 참조). 워커 수를 바꾸는 배포 설정과 풀 크기를 같은 곳(환경변수 하나)에서 계산. 스케일아웃 상한이 `max_connections` 를 넘으면 서버측 풀러(PgBouncer)를 앞에 둔다.
- 반례: "넉넉하게 50" 은 DB 측 컨텍스트 스위칭·메모리(work_mem × 커넥션)로 처리량을 떨어뜨린다.
- 검증: `pool.get_stats()` (`pool_size`, `pool_available`, `requests_waiting`), DB 측 `SELECT count(*), state FROM pg_stat_activity GROUP BY state`.
- 근거: https://www.psycopg.org/psycopg3/docs/api/pool.html · https://www.psycopg.org/psycopg3/docs/advanced/pool.html#pool-connection-and-sizing

### PY-PG-04 · 풀은 보관 중인 커넥션 상태를 확인하지 않는다 — 끊긴 커넥션을 받는다
- 적용: 클라우드 LB/NAT 뒤의 DB, `idle_session_timeout` 설정 서버, 페일오버가 있는 관리형 DB
- 신호: 한동안 조용하다가 첫 요청들만 `server closed the connection unexpectedly` / `OperationalError`
- 메커니즘: psycopg_pool 은 반납·보관 중 커넥션을 능동 점검하지 않는다(공식 문서). 중간 장비의 idle 타임아웃(예: AWS NLB TCP 350초)이 `max_idle` 기본 600초보다 짧으면 풀은 죽은 소켓을 들고 있게 된다.
- 처방: 3.2+ `check=ConnectionPool.check_connection`(획득 시 왕복 1회, 실패 시 새 커넥션). 또는 `max_idle` 을 경로상 가장 짧은 idle 타임아웃보다 작게. 둘 다 적용 가능.
- 반례: 초저지연 경로에서 check 의 왕복 비용이 부담되면 `max_idle` 축소 + 재시도 가능한 읽기에 한해 1회 재시도로 대체.
- 검증: DB 에서 `pg_terminate_backend()` 로 풀 커넥션을 죽인 뒤 다음 요청이 성공하는지.
- 근거: https://www.psycopg.org/psycopg3/docs/advanced/pool.html#connection-quality

### PY-PG-05 · `AsyncConnectionPool(...)` 을 생성자에서 열지 말 것 — lifespan 에서 `open(wait=True)`
- 적용: psycopg_pool 3.2+ async 풀
- 신호: 기동 시 `RuntimeWarning`/`DeprecationWarning`(constructor open), 모듈 import 시점에 풀 생성, DB 다운 상태에서도 앱이 "healthy" 로 뜸
- 메커니즘: 3.2 부터 `open` 미지정 시 생성자에서 여는 동작에 경고, async 풀은 향후 오류가 될 예정. 생성자 open 은 루프 밖에서 백그라운드 워커를 띄우려 한다.
- 처방: `pool = AsyncConnectionPool(conninfo, open=False, ...)` 후 lifespan 에서 `await pool.open(wait=True, timeout=10)` (DB 없으면 기동 실패 = fail fast), 종료 시 `await pool.close()`. 또는 `async with AsyncConnectionPool(..., open=False) as pool:` 를 lifespan 안에서.
- 반례: DB 가 늦게 뜨는 로컬 compose 환경이면 `wait=False` 로 두고 readiness probe 에서 확인.
- 검증: DB 를 내린 채 기동해 readiness 가 실패하는지.
- 근거: https://www.psycopg.org/psycopg3/docs/api/pool.html

### PY-PG-06 · 풀 고갈 시 기본 동작은 "무제한 대기열에서 30초 대기" — 연쇄 지연을 만든다
- 적용: 트래픽 급증·느린 쿼리가 있는 서비스
- 신호: DB 가 느려지면 앱 지연이 정확히 ~30초 근처로 몰림, 클라이언트 재시도가 대기열을 더 키움
- 메커니즘: `timeout=30.0`, `max_waiting=0`(대기열 제한 없음). 요청은 커넥션을 30초까지 기다리고, 그동안 상위 LB/클라이언트는 타임아웃 후 재시도한다.
- 처방: `timeout` 을 API SLO 에 맞춰(예: 2~5초) 줄이고 `max_waiting` 으로 대기열 상한 → `PoolTimeout`/`TooManyRequests` 를 503 + `Retry-After` 로 매핑해 빠르게 거절.
- 반례: 배치/관리 작업 전용 풀은 긴 timeout 이 맞다 — 풀을 용도별로 분리.
- 검증: 쿼리에 `pg_sleep` 을 넣은 부하 테스트로 대기열·거절 동작 확인.
- 근거: https://www.psycopg.org/psycopg3/docs/api/pool.html

### PY-PG-07 · 커넥션을 쥔 채 외부 API 를 await 하면 `idle in transaction` 으로 풀과 락을 함께 묶는다
- 적용: `async with pool.connection() as conn:` 블록 안에서 httpx 호출·파일 업로드·sleep 하는 코드
- 신호: `pg_stat_activity.state = 'idle in transaction'` 이 오래 지속, VACUUM 지연·테이블 bloat, 풀 고갈
- 메커니즘: 비 autocommit 커넥션은 첫 SELECT 로 트랜잭션이 시작되고 블록 종료 시에야 커밋/롤백된다(풀 `connection()` 컨텍스트는 정상 종료 시 commit, 예외 시 rollback). 그 사이 외부 I/O 시간만큼 커넥션·스냅샷·행 락이 유지된다. 참고: psycopg 3 의 `with psycopg.connect() as conn:` 은 블록 끝에서 **커넥션을 닫는다**(psycopg2 는 트랜잭션만 종료).
- 처방: 커넥션 블록은 DB 작업만 감싸고, 외부 호출은 블록 밖에서. 읽기 전용 단건 조회는 `autocommit=True` 커넥션. 서버측 안전망으로 `ALTER ROLE app SET idle_in_transaction_session_timeout = '30s'`, `statement_timeout` 도 역할 단위로(PgBouncer 경유 시 startup 파라미터보다 안전).
- 반례: 외부 호출 결과와 DB 쓰기의 원자성이 필요하면 블록을 넓히지 말고 outbox/보상 트랜잭션으로 설계.
- 검증: `SELECT pid, now() - xact_start, state, query FROM pg_stat_activity WHERE state LIKE 'idle in%'`.
- 근거: https://www.psycopg.org/psycopg3/docs/advanced/pool.html · https://www.psycopg.org/psycopg3/docs/basic/from_pg2.html

### PY-PG-08 · 기본(클라이언트) 커서는 `execute()` 시점에 결과 전체를 메모리로 받는다
- 적용: 수만 행 이상 export·리포트·재색인 경로
- 신호: `for row in cur:` 로 "스트리밍"한다고 생각했는데 RSS 가 결과 크기만큼 급증
- 메커니즘: libpq 기본 모드는 결과 집합 전체를 클라이언트로 버퍼링한다. 반복은 이미 받은 버퍼를 도는 것뿐.
- 처방: (a) 서버측 커서 `conn.cursor(name="export")` — 트랜잭션 안에서 `itersize`(기본 100) 단위 FETCH. (b) `cur.stream(query)` — 단일 행 모드, libpq 17+ 이면 `size=` 로 청크 수신; 끝까지 소비하지 않으면 커넥션이 ACTIVE 상태로 남으니 반드시 소진/close. (c) 파일/CSV 출력은 `COPY ... TO STDOUT` + `cur.copy()`.
- 반례: 작은 결과에 서버측 커서를 쓰면 왕복이 늘어 더 느리다(psycopg 문서).
- 검증: `tracemalloc`/RSS 를 행 수 1만/10만/100만에서 비교.
- 근거: https://www.psycopg.org/psycopg3/docs/advanced/cursors.html#server-side-cursors · https://www.psycopg.org/psycopg3/docs/api/cursors.html

### PY-PG-09 · 대량 적재는 `executemany` 가 아니라 `COPY`
- 적용: 수천 행 이상 INSERT(시드, 동기화, 좌표 일괄 적재)
- 신호: 적재 루프 프로파일이 네트워크 대기 위주, 행당 INSERT
- 메커니즘: 3.1+ `executemany()` 는 내부적으로 파이프라인 모드를 써서 왕복을 줄이지만 여전히 행마다 문장을 실행한다. `COPY FROM STDIN` 은 단일 스트림으로 파싱·WAL 기록 경로가 가장 짧다.
- 처방: `with cur.copy("COPY t (a, b) FROM STDIN") as cp: for r in rows: cp.write_row(r)`. 업서트가 필요하면 임시 테이블에 COPY 후 `INSERT ... SELECT ... ON CONFLICT`. 대량 적재 뒤에는 `ANALYZE t`.
- 반례: 수십 행 수준, 행마다 RETURNING 이 필요한 경우는 executemany 가 단순.
- 검증: 동일 10만 행으로 두 방식 소요 비교.
- 근거: https://www.psycopg.org/psycopg3/docs/basic/copy.html · https://www.psycopg.org/psycopg3/docs/advanced/pipeline.html

### PY-PG-10 · asyncpg 는 모든 문장을 prepare 한다 — PgBouncer transaction 모드/풀러에서 `prepared statement "__asyncpg_stmt_N__" already exists`
- 적용: `asyncpg` 직접 사용 또는 SQLAlchemy `postgresql+asyncpg` + PgBouncer(transaction/statement 모드) 또는 Supabase/Neon 등 풀러 엔드포인트. psycopg 3 는 PY-PG-02.
- 신호: `asyncpg.exceptions.DuplicatePreparedStatementError: prepared statement "__asyncpg_stmt_N__" already exists`, 또는 `... does not exist`, `InvalidSQLStatementNameError`
- 메커니즘: asyncpg 는 psycopg 처럼 임계 횟수 후가 아니라 **매 문장**을 prepare 하고 커넥션별 statement cache(기본 100)에 보관하며, 이름을 순번(`__asyncpg_stmt_1__`, …)으로 붙인다. transaction 모드 풀러는 트랜잭션마다 다른 서버 커넥션을 주므로 다른 클라이언트가 같은 순번 이름을 이미 만들어 둔 서버 커넥션을 받으면 충돌한다. SQLAlchemy asyncpg 방언은 그 위에 자체 prepared statement 캐시(`prepared_statement_cache_size`, 기본 100)를 따로 둔다.
- 처방: asyncpg 직접 사용 — `asyncpg.connect(..., statement_cache_size=0)`/`create_pool(..., statement_cache_size=0)`(asyncpg FAQ). SQLAlchemy(방언이 `connection.prepare()` 를 직접 호출) — `connect_args={"prepared_statement_name_func": lambda: f"__asyncpg_{uuid4()}__"}` 로 이름을 고유하게 만들어 충돌 자체를 없앤다(SQLAlchemy 문서 "Prepared Statement Name with PGBouncer"). 캐시 이점이 없으면 URL `?prepared_statement_cache_size=0` 으로 방언 캐시도 끈다. 이 경우 SQLAlchemy 문서는 앱 쪽 `poolclass=NullPool` 과 PgBouncer 의 반납 시 `DISCARD`(server_reset_query) 설정을 함께 권한다 — 아니면 고유 이름 문장이 서버 커넥션에 쌓인다.
- 반례: 직접 연결(풀러 없음)이나 session 모드 PgBouncer 에서 캐시를 끄면 asyncpg 의 주된 성능 이점(파싱·플래닝 재사용, SQLAlchemy 문서 기준 10%+)을 잃는다. 풀러가 커넥션 다중화 목적이 아니라면 asyncpg 자체 풀 + 직접 연결이 낫다(asyncpg FAQ).
- 검증: 풀러 경유 통합 테스트에서 동일·상이 쿼리를 여러 동시 태스크로 반복, 서버측 `SELECT count(*) FROM pg_prepared_statements` 추세.
- 근거: https://magicstack.github.io/asyncpg/current/faq.html · https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#prepared-statement-cache · https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#prepared-statement-name-with-pgbouncer

### PY-MIG-01 · dbmate 는 마이그레이션 파일마다 트랜잭션 — `CREATE INDEX CONCURRENTLY` 는 `transaction:false` 필요
- 적용: dbmate + PostgreSQL
- 신호: `CREATE INDEX CONCURRENTLY cannot run inside a transaction block`, 또는 CONCURRENTLY 를 빼서 운영 테이블에 쓰기 락
- 메커니즘: dbmate 는 기본으로 각 migration 블록을 트랜잭션으로 감싼다. CONCURRENTLY 는 트랜잭션 밖에서만 가능하고, 실패하면 `INVALID` 인덱스를 남긴다. `transaction:false` 여도 dbmate 는 블록 전체를 `Exec` 한 번으로 보내는데, PostgreSQL 은 여러 문장이 담긴 단일 simple Query 를 **암묵적 트랜잭션 블록**으로 실행하므로 블록에 문장이 2개 이상이면 CONCURRENTLY 가 다시 `cannot run inside a transaction block` 으로 실패한다(`PreventInTransactionBlock` 이 implicit block 도 거부).
- 처방: 해당 블록 첫 줄 `-- migrate:up transaction:false`, **블록 안 문장은 정확히 1개**(CONCURRENTLY 문 하나뿐 — `SET lock_timeout` 등도 같은 블록에 넣지 않는다). 실패로 남은 INVALID 인덱스 정리는 별도 마이그레이션 파일(역시 `transaction:false`, `DROP INDEX CONCURRENTLY IF EXISTS ...` 1문장)이나 수동 운영 절차로. down 블록도 `-- migrate:down transaction:false` + 1문장.
- 반례: 작은 신규 테이블이면 일반 `CREATE INDEX`(트랜잭션 내)가 더 단순하고 원자적이다.
- 검증: `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;` 로 INVALID 인덱스 확인.
- 근거: https://github.com/amacneil/dbmate#migration-options · https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY

### PY-MIG-02 · DDL 이 락 대기열에 서면 뒤의 모든 쿼리가 막힌다 — 마이그레이션 첫 줄에 `lock_timeout`
- 적용: 운영 중 테이블에 `ALTER TABLE` 하는 모든 마이그레이션(도구 무관)
- 신호: 1초짜리여야 할 ALTER 동안 서비스 전체 타임아웃, `pg_locks` 에 `AccessExclusiveLock` 대기
- 메커니즘: 대부분의 `ALTER TABLE` 은 ACCESS EXCLUSIVE 락이 필요하다. 긴 트랜잭션이 테이블을 잡고 있으면 ALTER 는 대기하고, 락 큐는 FIFO 라 그 뒤의 평범한 SELECT 까지 ALTER 뒤에 줄 선다.
- 처방: 마이그레이션 상단 `SET lock_timeout = '3s';`(dbmate 트랜잭션 안이면 `SET LOCAL`) — 실패 시 재시도. 배포 전 `idle in transaction` 세션 정리(PY-PG-07).
- 반례: 유지보수 창에서 트래픽을 끊고 하는 작업에는 불필요.
- 검증: 별도 세션에서 `BEGIN; SELECT * FROM t LIMIT 1;` 로 락을 잡아 두고 마이그레이션이 3초 후 실패하는지.
- 근거: https://www.postgresql.org/docs/current/explicit-locking.html · https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-LOCK-TIMEOUT

### PY-MIG-03 · dbmate 운영 함정 — 마이그레이션 락은 PgBouncer transaction 모드를 통과하지 못하고, 순서 역전은 기본값으로 허용된다
- 적용: 여러 레플리카가 기동 시 `dbmate up` 을 실행하는 배포, CI 에서 schema.sql 을 커밋하는 흐름
- 신호: 동시 기동 시 같은 마이그레이션 중복 적용 시도, CI 에서 `pg_dump: server version mismatch`, 오래된 브랜치의 낮은 버전 마이그레이션이 경고 없이 적용
- 메커니즘: `--migration-lock`(PostgreSQL 전용)은 세션 수명 락이라 직접 연결 또는 session 풀링이 필요하다(transaction 모드 PgBouncer 는 락을 유지하지 못한다 — dbmate README). 락 대기는 `--migration-lock-timeout`(기본 5m, 0 = 무한)으로 제한된다. `dbmate up/migrate` 는 기본으로 `pg_dump` 를 불러 `db/schema.sql` 을 갱신한다(로컬 pg_dump 메이저 버전이 서버보다 낮으면 실패). 기본값으로는 커밋 순서가 뒤바뀐 마이그레이션도 미적용이면 그냥 적용한다 — `--strict` 를 켜야 실패한다.
- 처방: CI·운영의 `dbmate up` 에 `--strict`(또는 `DBMATE_STRICT=true`)로 순서 역전을 실패 처리 — PR 리뷰의 "main 최신 마이그레이션보다 낮은 타임스탬프" 확인은 보조 수단. 마이그레이션은 앱 기동이 아닌 별도 Job 1개로, 직접 연결 URL 로 실행(동시 실행 가능성이 있으면 `--migration-lock` + 배포 시간에 맞춘 `--migration-lock-timeout`). 컨테이너/CI 는 `--no-dump-schema`(또는 `DBMATE_NO_DUMP_SCHEMA`), schema.sql 은 서버와 같은 메이저 pg_dump 로 생성.
- 반례: 단일 인스턴스 개인 프로젝트에선 기동 시 `dbmate up` 이 충분히 실용적.
- 검증: `dbmate status`, schema.sql diff 를 CI 에서 확인.
- 근거: https://github.com/amacneil/dbmate#command-line-options (`--strict`, `--migration-lock`, `--migration-lock-timeout`) · https://github.com/amacneil/dbmate#running-migrations

### PY-MIG-04 · `ADD COLUMN ... DEFAULT` 는 기본값이 volatile 일 때만 테이블을 재작성한다
- 적용: PostgreSQL 11+
- 신호: 대형 테이블에 `DEFAULT gen_random_uuid()` / `clock_timestamp()` 컬럼 추가 시 장시간 락
- 메커니즘: 11+ 에서 non-volatile 기본값(상수, `now()` 같은 STABLE 함수)은 실행 시점에 한 번 평가해 카탈로그에 저장 → 재작성 없음. volatile 기본값은 행마다 값이 달라야 하므로 전체 재작성 + ACCESS EXCLUSIVE.
- 처방: volatile 기본값은 ① 기본값 없이 컬럼 추가 ② `ALTER ... SET DEFAULT` (신규 행만) ③ 배치로 기존 행 백필 ④ 필요 시 NOT NULL(PY-MIG-05).
- 반례: 작은 테이블이면 한 번에 해도 무방.
- 검증: 스테이징에서 `pg_relation_filenode('t')` 가 바뀌는지(바뀌면 재작성됨).
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html#SQL-ALTERTABLE-NOTES

### PY-MIG-05 · NOT NULL·FK 는 `NOT VALID` → `VALIDATE` 2단계로 추가하면 긴 배타 락을 피한다
- 적용: PostgreSQL 12+ (SET NOT NULL 스캔 생략은 12+). NOT NULL 제약 자체의 `NOT VALID` 는 **18+**
- 신호: `ALTER TABLE ... ADD FOREIGN KEY` / `SET NOT NULL` 이 대형 테이블에서 전체 스캔 동안 쓰기 차단
- 메커니즘: `ADD CONSTRAINT ... NOT VALID` 는 기존 행 검사 없이 즉시 추가되고, `VALIDATE CONSTRAINT` 는 SHARE UPDATE EXCLUSIVE 락으로 검사해 일반 읽기/쓰기를 막지 않는다. 12+ 에서는 유효한 `CHECK (col IS NOT NULL)` 제약이 있으면 `SET NOT NULL` 이 스캔을 생략한다.
- 처방: PG18+: 마이그레이션 A `ALTER TABLE t ADD CONSTRAINT c NOT NULL col NOT VALID` → 마이그레이션 B `ALTER TABLE t VALIDATE CONSTRAINT c`(SHARE UPDATE EXCLUSIVE). PG12~17: 마이그레이션 A: `ADD CONSTRAINT c CHECK (col IS NOT NULL) NOT VALID` / FK `NOT VALID`. 마이그레이션 B: `VALIDATE CONSTRAINT c` → `SET NOT NULL` → `DROP CONSTRAINT c`.
- 반례: 신규·소형 테이블은 단일 단계가 낫다.
- 검증: 스테이징 대형 테이블에서 각 단계 동안 쓰기 지연 측정.
- 근거: https://www.postgresql.org/docs/current/sql-altertable.html (18: "NOT VALID ... allowed for foreign-key, CHECK, and not-null constraints")
