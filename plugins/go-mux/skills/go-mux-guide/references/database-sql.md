# Go database/sql·pgx 스페셜리스트 항목 (GO-DB)

드라이버(`database/sql` + 드라이버, `pgx` 네이티브, `sqlx`)와 마이그레이션 도구는 프로젝트마다 다르다 — `go.mod` 와 기존 저장소 코드를 먼저 확인하고 해당하는 항목만 적용한다.
일반 CRUD/트랜잭션 관용구는 `db-patterns.md`.

---

### GO-DB-01 · SetMaxIdleConns 기본값 2 를 방치해 부하 시 커넥션을 계속 열고 닫는다
- 적용: `database/sql` 풀(pgx stdlib, lib/pq, mysql 드라이버 등)
- 신호: `db.Stats().MaxIdleClosed` 가 빠르게 증가; DB 측 신규 연결/인증 로그 폭증; TLS 연결이면 핸드셰이크 CPU
- 메커니즘: `defaultMaxIdleConns = 2`. MaxOpenConns 를 50 으로 올려도 반납 시 2개 초과분은 닫힌다. 또 MaxIdleConns 가 MaxOpenConns 보다 크면 자동으로 MaxOpenConns 로 낮춰진다.
- 처방: `SetMaxIdleConns` 를 정상 동시성 수준(보통 MaxOpenConns 와 같거나 약간 작게)으로. `SetConnMaxIdleTime` 으로 유휴 회수.
- 반례: 서버리스/저빈도 배치는 유휴 커넥션 유지가 DB 커넥션 슬롯 낭비.
- 검증: `db.Stats()` 의 `MaxIdleClosed`, `OpenConnections`
- 근거: https://pkg.go.dev/database/sql#DB.SetMaxIdleConns · Go 소스 `database/sql/sql.go` (`defaultMaxIdleConns = 2`)

### GO-DB-02 · 풀 고갈을 DB 지연으로 오판한다 — WaitCount/WaitDuration 을 보지 않는다
- 적용: 요청 지연이 DB 호출 구간에서 늘어나는 서비스
- 신호: DB 쿼리 자체 지연(DB 측 슬로우 로그)은 정상인데 앱 측 DB 호출 시간이 김
- 메커니즘: MaxOpenConns 에 도달하면 `db.Conn`/쿼리는 커넥션을 기다린다. 이 대기는 DB 지연이 아니라 풀 크기·커넥션 점유 시간(긴 트랜잭션, Rows 미종료) 문제다. `sql.DBStats` 의 `WaitCount`, `WaitDuration`, `InUse` 로 구분된다.
- 처방: `db.Stats()` 를 주기적으로 메트릭 노출(대기 횟수·시간 증가율 경보). 점유 시간 단축(트랜잭션 안의 외부 HTTP 호출 제거)이 풀 확대보다 먼저.
- 반례: 풀을 무작정 키우면 DB `max_connections`·서버 메모리를 압박 — 인스턴스 수 × MaxOpenConns 합산으로 판단.
- 검증: 부하 테스트 중 WaitDuration 증가율
- 근거: https://pkg.go.dev/database/sql#DBStats

### GO-DB-03 · Rows 를 닫지 않거나 QueryRow 결과를 Scan 하지 않아 커넥션이 반납되지 않는다
- 적용: `db.QueryContext`, `QueryRowContext`
- 신호: 조기 return 분기에서 `rows.Close()` 누락; 결과를 안 쓰는 쿼리에 `Query` 사용; `rows.Err()` 미확인; `InUse` 가 MaxOpenConns 에 붙어 있음
- 메커니즘: Rows 는 Close(또는 Next 가 false 를 반환할 때까지 순회)될 때 커넥션을 반납한다. `*sql.Row` 는 Scan 호출 시 반납된다. `rows.Next()` 가 false 인 이유가 오류일 수 있어 `rows.Err()` 를 봐야 부분 결과를 성공으로 오인하지 않는다.
- 처방: `defer rows.Close()` 즉시; 루프 후 `if err := rows.Err(); err != nil`; 결과 없는 문장은 `ExecContext`. `sqlclosecheck`/`rowserrcheck` 린터.
- 반례: 없음.
- 검증: `db.Stats().InUse` 추이, 린터
- 근거: https://pkg.go.dev/database/sql#Rows · https://go.dev/doc/database/querying

### GO-DB-04 · pgx 의 기본 실행 모드(준비 문장 캐시)가 PgBouncer 트랜잭션 풀링과 충돌한다
- 적용: pgx v5 + PgBouncer(transaction pool mode) 또는 유사 프록시
- 신호: `prepared statement "stmtcache_..." already exists`/`does not exist` 간헐 에러
- 메커니즘: pgx v5 기본 `QueryExecModeCacheStatement` 는 커넥션별로 서버측 준비 문장을 만들고 재사용한다. 트랜잭션 풀링은 매 트랜잭션마다 다른 서버 커넥션을 줄 수 있어 준비 문장이 엇갈린다. PgBouncer 1.21+ 는 `max_prepared_statements` 로 프로토콜 수준 준비 문장을 지원한다.
- 처방: 프록시 설정을 확인 — 지원(1.21+, `max_prepared_statements` > 0)하면 기본 모드 유지. 미지원이면 `ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeExec` 를 우선; 대안은 `QueryExecModeCacheDescribe` 또는 `QueryExecModeSimpleProtocol`(텍스트 프로토콜, 타입 처리 차이 주의 — pgx 문서도 Exec 를 SimpleProtocol 보다 우선 권장).
- 반례: 프록시 없이 직접 연결이면 기본 모드가 가장 빠르다 — 바꾸지 말 것. `QueryExecModeDescribeExec` 는 트랜잭션 풀링에서 쓰면 안 된다 — describe 와 execute 단계 사이에 PgBouncer 가 다른 서버 커넥션을 줄 수 있어 같은 계열 에러가 재현된다.
- 검증: 프록시 경유 통합 테스트에서 동일 쿼리 반복 실행
- 근거: https://pkg.go.dev/github.com/jackc/pgx/v5#QueryExecMode · https://pkg.go.dev/github.com/jackc/pgx/v5#hdr-PgBouncer · https://www.pgbouncer.org/config.html#max_prepared_statements

### GO-DB-05 · ConnMaxLifetime 미설정으로 DB 페일오버/DNS 변경 후 죽은 엔드포인트에 계속 붙어 있다
- 적용: 관리형 DB(RDS/Aurora/Cloud SQL) 페일오버, DNS 기반 리더/라이터 엔드포인트
- 신호: 페일오버 후 일부 인스턴스만 오래 에러/읽기 전용 에러(`cannot execute ... in a read-only transaction`)
- 메커니즘: 풀의 커넥션은 명시적 수명이 없으면 무기한 재사용되어 DNS 변경을 반영하지 않는다(`database/sql` 의 기본 ConnMaxLifetime 은 0 = 무제한. pgxpool 은 기본 `MaxConnLifetime` 1시간·`MaxConnIdleTime` 30분·`MaxConnLifetimeJitter` 0 — 페일오버 반영이 최대 1시간 늦을 수 있다).
- 처방: `SetConnMaxLifetime` 을 수 분 단위로(인스턴스 간 동시 만료 폭주를 피하려면 값이 다른 인스턴스 간 지터는 드라이버/풀 기능 확인 — pgxpool 은 `MaxConnLifetimeJitter` 제공). 읽기 전용 에러를 받으면 해당 커넥션 폐기.
- 반례: 너무 짧으면 재연결 비용·인증 부하 증가.
- 검증: 스테이징 페일오버 훈련에서 에러 지속 시간
- 근거: https://pkg.go.dev/database/sql#DB.SetConnMaxLifetime · https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool#Config

### GO-DB-06 · 트랜잭션 안에서 tx 대신 db 로 쿼리해 같은 트랜잭션이 아니게 되거나 커넥션 교착이 생긴다
- 적용: Repository 가 `*sql.DB` 를 필드로 들고 서비스가 트랜잭션을 여는 구조
- 신호: 트랜잭션 함수 안에서 `r.db.QueryContext` 호출; MaxOpenConns 가 작을 때 부하 시 전체 정지
- 메커니즘: tx 는 커넥션 하나를 점유한다. 그 안에서 db 로 쿼리하면 *다른* 커넥션을 요구한다 — 격리 밖에서 실행되고, 풀이 꽉 차면 모든 고루틴이 tx 커넥션을 쥔 채 두 번째 커넥션을 기다려 교착한다(타임아웃 없으면 영구).
- 처방: `DBTX` 인터페이스(QueryContext/ExecContext/QueryRowContext)를 Repository 가 받도록 하고 트랜잭션 범위에선 tx 를 주입(`db-patterns.md` DBTX 절). 모든 DB 호출에 ctx 데드라인.
- 반례: 의도적으로 트랜잭션 밖에서 실행해야 하는 감사 로그 등은 명시적으로 분리하고 주석.
- 검증: MaxOpenConns=1 로 테스트를 돌려 교착 재현
- 근거: https://pkg.go.dev/database/sql#Tx · https://go.dev/doc/database/execute-transactions

### GO-DB-07 · pgxpool MaxConns 기본값이 노드 CPU 수에 따라 달라 인스턴스 합계가 max_connections 를 넘는다
- 적용: pgxpool(pgx v5) 을 쓰는 다중 인스턴스 서비스(k8s HPA 등), `MaxConns`/`pool_max_conns` 미지정
- 신호: 같은 이미지·설정인데 파드마다 풀 크기가 다름(`pool.Stat().MaxConns()`); 스케일아웃 시 Postgres `FATAL: sorry, too many clients already` / `remaining connection slots are reserved`
- 메커니즘: pgxpool `MaxConns` 기본값은 `max(4, runtime.NumCPU())` 다. `NumCPU` 는 프로세스 CPU affinity 기준 논리 CPU 수로 cgroup CPU limit(쿼터)을 반영하지 않는다 — 64코어 노드에 limit 2 인 파드도 64 를 받는다. 레플리카 수 × MaxConns 가 DB `max_connections` 를 쉽게 넘는다.
- 처방: `MaxConns` 를 명시(`cfg.MaxConns = N` 또는 DSN `pool_max_conns=N`). 산정: `레플리카 최대수(HPA max) × MaxConns ≤ max_connections − superuser_reserved_connections − 운영 여유분`(마이그레이션·배치·관리 접속). 필요하면 앞단 PgBouncer 로 다중화.
- 반례: 단일 인스턴스·전용 DB 이면 기본값도 무해할 수 있다. 너무 작게 잡으면 풀 대기(GO-DB-02 의 `AcquireDuration`/`EmptyAcquireCount`)가 지연이 된다.
- 검증: 기동 로그에 `pool.Stat().MaxConns()` 출력, DB 측 `SELECT count(*) FROM pg_stat_activity` 를 HPA max 시나리오로 확인
- 근거: https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool#Config · https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool#ParseConfig · https://pkg.go.dev/runtime#NumCPU · https://www.postgresql.org/docs/current/runtime-config-connection.html#GUC-MAX-CONNECTIONS
