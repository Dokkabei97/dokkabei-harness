---
name: async-event-patterns
description: |
  백엔드 인프라 스페셜리스트 허브 — PostgreSQL 느린 쿼리·인덱스 선택·bloat·autovacuum·커넥션 풀 고갈·idle in transaction, Kafka 리밸런스·컨슈머 랙·중복/유실·파티션 스큐, Valkey/Redis 빅키·핫키·KEYS·만료 이벤트·분산락, 타임아웃·재시도 폭풍·서킷·멱등키·캐시 스탬피드·outbox. 증상→ID 항목(PG/KFK/VK/DIST) 트리아지 + 팀 규칙.
  Specialist pitfalls for PostgreSQL, Kafka, Valkey/Redis and distributed calls that strong generalists miss, with version-accurate defaults.
  Use when: diagnosing or reviewing DB/Kafka/Valkey integration code or config, slow queries, consumer lag, pool exhaustion, cache stampede, retry/timeout design.
---

# 백엔드 인프라 스페셜리스트 허브

모델이 이미 아는 관용구(인덱스를 걸어라, 캐시를 써라)는 다루지 않는다. 여기 있는 것은 **기본값·버전·내부 동작 때문에 시니어도 놓치는 함정**이다.
본문은 증상→항목 ID 인덱스이고, 근거·처방·반례·측정법은 `references/` 의 항목에 있다.

## 0. 쓰기 전에 확인

- **버전과 클라이언트**를 먼저 확인한다: PostgreSQL 메이저(11/12/13/16/18 경계가 많음), `kafka-clients` 버전(3.0, 4.0 경계), Valkey 8.0 vs Redis/Valkey 7.x, 드라이버(pgjdbc/pgx/psycopg, Lettuce/Redisson/go-redis). 빌드 파일·compose·Testcontainers 이미지 태그·인프라 문서에서 찾는다.
- 프로젝트 CLAUDE.md / `.claude/rules` 에 이미 선별된 항목 ID 나 다른 규칙이 있으면 그것이 우선이다.
- 각 항목의 `반례` 를 반드시 읽는다 — 소규모·저트래픽에서는 과최적화인 항목이 많다.

## 1. 증상 → 항목

### PostgreSQL → [references/postgres.md](references/postgres.md)

| 증상/코드 신호 | 항목 |
|---|---|
| 복합 인덱스가 있는데 `Filter` 로 많은 행 제거 | PG-IDX-01 |
| 처음엔 빠르다 5회 이후 느려짐, psql 에선 빠름 | PG-IDX-02, PG-PLAN-01 |
| `Index Only Scan` 인데 `Heap Fetches` 큼 | PG-IDX-03 |
| jsonb 검색 인덱스 미사용, GIN 쓰기 스파이크 | PG-IDX-04 |
| `LIKE 'abc%'`/`'%abc%'` Seq Scan | PG-IDX-05 |
| 인덱스 정리·쓰기 성능 | PG-IDX-06, PG-MVCC-01 |
| UUID PK 삽입 지연·WAL 급증 | PG-IDX-07 |
| 시계열/로그 대형 테이블 인덱스 크기 | PG-IDX-08 |
| 갱신 위주 테이블 bloat, HOT 비율 낮음 | PG-MVCC-01, PG-MVCC-02 |
| vacuum 돌아도 dead tuple 그대로 | PG-MVCC-03 |
| `to prevent wraparound` vacuum, DDL 멈춤 | PG-MVCC-04 |
| 큰 jsonb 부분 갱신의 쓰기 증폭 | PG-MVCC-05 |
| `too many clients`, 스케일아웃 후 풀 대기 | PG-POOL-01 |
| Go 서비스 연결 수 폭증·재연결 반복 | PG-POOL-02 |
| PgBouncer 뒤 `prepared statement ... already exists` | PG-POOL-03 |
| DB 는 한가한데 풀 고갈 | PG-POOL-04 |
| 행 수 추정 오차 → Nested Loop | PG-PLAN-02, PG-PLAN-07 |
| 가변 `IN (...)`, 바인드 파라미터 수 초과 | PG-PLAN-03 |
| 키셋 페이지네이션 정렬 방향 혼합 | PG-IDX-01 |
| `ORDER BY ... LIMIT 10` 이 수 초 | PG-PLAN-05 |
| EXPLAIN 하단 JIT 시간 | PG-PLAN-06 |
| `NOT IN` 결과 비어 있음/느림 | PG-QRY-01 |
| `saveAll`/`executeBatch` 가 단건 속도 | PG-QRY-02 |
| 자식 INSERT 가 부모 락 대기, deadlock | PG-LOCK-01, PG-LOCK-02 |
| 스키마 변경·마이그레이션 | → `migration-safety-checklist` 스킬 |

### Kafka → [references/kafka.md](references/kafka.md)

| 증상/코드 신호 | 항목 |
|---|---|
| idempotence 켰다고 생각했는데 중복·재정렬 | KFK-PRD-01, KFK-PRD-05 |
| `retries=3` 으로 빠른 실패 기대, send 가 오래 블록 | KFK-PRD-02 |
| 4.0 업그레이드 후 publish 지연 증가 | KFK-PRD-03 |
| Go 프로듀서 키 순서 깨짐·쓰기당 ~1s·acks=0 | KFK-PRD-06 |
| 일부 파티션만 lag, 파티션 수 변경 계획 | KFK-PRD-04 |
| `poll timeout has expired`, 같은 배치 반복 처리 | KFK-CON-01 |
| 배포·스케일마다 전체 처리 정지 | KFK-CON-02 |
| 실패 레코드가 10번 후 사라짐/역직렬화 무한 루프 (Spring Kafka) | KFK-CON-03 |
| 리스너에서 비동기 위임 후 유실, `suspend` 리스너 | KFK-CON-04 |
| 신규 그룹이 과거 메시지 못 받음/장기 중단 후 오프셋 리셋 | KFK-CON-05 |
| lag 알람 오탐 | KFK-CON-06 |
| `acks=all` 인데 유실 | KFK-TOP-01 |
| 컴팩션 토픽 재구성 후 삭제 키 부활 | KFK-TOP-02 |
| "EOS 니까 DB 쓰기도 한 번" | KFK-EOS-01, DIST-MSG-01 |

### Valkey/Redis → [references/valkey.md](references/valkey.md)

| 증상/코드 신호 | 항목 |
|---|---|
| 패턴 삭제·`SCAN` 순회 누락/중복 | VK-KEY-01 |
| 큰 컬렉션·큰 값, 삭제/만료 시 지연 | VK-KEY-02 |
| 클러스터 노드 하나만 과부하 | VK-KEY-03 |
| 만료 이벤트로 예약 작업 | VK-EXP-01 |
| TTL 주기 DB 스파이크 | DIST-CACHE-01 |
| `OOM command not allowed`, 오류 없이 OOMKill | VK-MEM-01 |
| 저장 시점 지연 스파이크·OOMKill | VK-MEM-02 |
| 한 기능 지연이 모든 Redis 호출로 전파 (Lettuce) | VK-CLI-01 |
| 페일오버 후 `MOVED`/연결 오류 지속 | VK-CLI-02 |
| 루프 안 개별 GET/SET, `CROSSSLOT` | VK-CLI-03 |
| `\xac\xed`·`@class` 값, 배포 후 역직렬화 오류 | VK-CLI-04 |
| 분산락으로 정합성 보장 | VK-LOCK-01 |
| Pub/Sub 무효화 누락, Streams PEL 증가 | VK-STR-01 |

### 분산 호출·캐시·운영 → [references/distributed.md](references/distributed.md)

| 증상/코드 신호 | 항목 |
|---|---|
| 상위 실패 후에도 하위 처리 지속 | DIST-TMO-01 |
| 클라이언트 생성 시 타임아웃 미설정 | DIST-TMO-02 |
| 배포 때만 5xx | DIST-TMO-03 |
| 하위 장애 시 유입 트래픽 배증 | DIST-RTY-01 |
| 서킷이 안 열림 / 열린 서킷 재시도 (Resilience4j) | DIST-RTY-03 |
| 비멱등 API 재시도·중복 이벤트 | DIST-IDEM-01 |
| DB 커밋 + 이벤트 발행 | DIST-MSG-01 |
| 인기 키 만료 순간 DB 급증 | DIST-CACHE-01 |
| 드물게 갱신이 반영 안 되는 캐시 | DIST-CACHE-02 |
| 스케일아웃 후 신규 파드 트래픽 0 (gRPC/HTTP2) | DIST-NET-01 |
| Go HTTP 호출 측 TIME_WAIT 폭증·포트 고갈 | DIST-NET-02 |
| 메트릭 시계열 폭발 | DIST-OBS-01 |
| 파드 p99 평균을 서비스 p99 로 사용 | DIST-OBS-02 |
| DB 장애 시 전 파드 재시작 | DIST-OPS-01 |

### 팀 규칙 → [references/team-conventions.md](references/team-conventions.md)

타임아웃 상한표, Kafka 컨슈머 안 외부 호출 규칙, 순차 IO·중첩 조회 금지, 캐시 키·TTL 출발값, 테스트 격리 접두사.

## 2. 사용 방법

- **리뷰**: 변경 파일에서 위 표의 "코드 신호" 를 찾아 해당 항목을 읽고, 항목의 `적용` 조건이 프로젝트에 맞는지 확인한 뒤 지적한다. 지적에는 항목 ID 와 `검증` 방법을 함께 적는다.
- **진단**: 증상 → 항목 → `검증` 의 측정을 먼저 실행해 가설을 확인하고 나서 `처방` 을 제안한다.
- **설계**: 해당 영역 references 파일의 항목 제목만 훑어 설계에 걸리는 것을 고른다.
- **프로젝트 규칙화**: `workflow:project-rules` 가 이 ID 들을 선별해 프로젝트 `.claude/rules` 로 옮길 수 있도록, 항목은 ID·적용 조건 단위로 유지된다.

## 3. 범위 밖

- 언어별 관용구(코루틴·Go 동시성·FastAPI)는 각 스택 플러그인, Elasticsearch 는 `search` 플러그인, JVM GC·런타임 튜닝은 `kotlin-spring`, Go 런타임은 `go-mux`.
- DDL 락·마이그레이션 → `migration-safety-checklist`. DTO 계약 → `dto-design-patterns`.
