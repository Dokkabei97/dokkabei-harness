---
name: python-fastapi-guide
description: |
  Python/FastAPI 스페셜리스트 트리아지 — 이벤트루프 블로킹, 스레드풀 40 한계, psycopg 풀·PgBouncer prepared statement, Pydantic·응답 직렬화 비용, GIL/free-threaded, 메모리·GC, uvicorn 워커·keep-alive 502, BackgroundTasks, PostGIS 반경·KNN 인덱스. 쿼리 계층(ORM/원시 SQL)을 먼저 감지.
  Specialist triage for Python/FastAPI pitfalls. Use when: writing or reviewing FastAPI code, slow async endpoints, DB pool errors, memory growth, uvicorn tuning, PostGIS queries.
paths:
  - "**/*.py"
  - "**/pyproject.toml"
---

# Python / FastAPI 스페셜리스트 트리아지

증상 → 레퍼런스 항목(ID)으로 안내하는 진입 스킬. 관용구·튜토리얼(타입 힌트, f-string, Depends 기초)은 다루지 않는다 — 필요하면 `references/fastapi-idioms.md`.
항목은 `ID · 적용 · 신호 · 메커니즘 · 처방 · 반례 · 검증 · 근거` 형식이며, **적용 조건이 맞을 때만** 권한다(가이드이지 강제가 아니다).

## 1. 먼저 프로젝트 사실을 확인한다 (단정 금지)

코드를 쓰거나 처방하기 전에 아래를 읽어 확정한다. 프로젝트 `CLAUDE.md`/`.claude/rules/` 에 이미 적혀 있으면 그것을 따른다.

| 확인 대상 | 어디서 | 판정 |
|---|---|---|
| 쿼리 계층 | `pyproject.toml`/lock 의존성 + `import` grep | `sqlalchemy`/`sqlmodel` → ORM · `psycopg`(3)/`asyncpg`/`psycopg2` 직접 사용 → 원시 SQL · 둘 다 → 경로별 혼용 |
| 동기/비동기 | `AsyncConnectionPool`/`AsyncSession`/`async def` 엔드포인트 비율 | 혼용이면 FA-ASYNC-01, FA-THREAD-01 우선 점검 |
| 마이그레이션 | `alembic.ini` · `db/migrations/*.sql` + `dbmate` · `migrations/` 기타 · 없음 | 도구가 정해지면 그 도구 문법으로만 작성 |
| DB 확장 | 마이그레이션의 `CREATE EXTENSION postgis` 등 | PostGIS 면 `postgis.md` 활성 |
| 풀러 | `DATABASE_URL` 포트(6432 등)·인프라 문서의 PgBouncer/Supabase pooler | transaction 모드면 PY-PG-02(psycopg) / PY-PG-10(asyncpg) |
| 버전 | lock 파일의 fastapi/pydantic/psycopg/uvicorn, Dockerfile 의 Python 패치 버전 | FastAPI 0.118/0.121 경계(FA-BG-02/03), 0.128·0.130 경계(FA-RESP-01~03), Python 3.13·3.14.5 경계(PY-GC-01/02) |
| 기동 방식 | Dockerfile `CMD`, compose, k8s manifest, `fastapi run` | 워커 수·keep-alive·graceful 설정(FA-SRV-*) |

- 쿼리 계층이 원시 SQL 이면 ORM 예시(`sqlalchemy-patterns.md`, `layer-patterns.md` 의 Repository 예시)를 그대로 쓰지 않는다 — SQL 은 기존 리포지토리 모듈의 스타일(`%s` 바인딩, row factory, 트랜잭션 경계)을 따른다.
- 버전 민감 API 는 `backend-shared:context7-docs-guide` 규약으로 최신 문서를 조회한다(미설치 시 생략).

## 2. 증상 → 항목 트리아지

| 증상 / 리뷰에서 본 패턴 | 먼저 볼 항목 | 레퍼런스 |
|---|---|---|
| 동시 요청이 늘면 p99 가 계단식 증가, 헬스체크 타임아웃 | FA-ASYNC-01, FA-ASYNC-02 | `async-concurrency.md` |
| 동시성 ~40 에서 처리량 정체, CPU 는 한가 | FA-THREAD-01, FA-THREAD-02 | `async-concurrency.md` |
| `asyncio.create_task(...)` 반환값을 버림 | FA-ASYNC-03 | `async-concurrency.md` |
| 이메일·웹훅을 BackgroundTasks 로, 재시작 후 유실 | FA-BG-01 | `async-concurrency.md` |
| 백그라운드에 conn/session 전달, 업그레이드 후 커넥션 오류 | FA-BG-02 | `async-concurrency.md` |
| 2xx 응답인데 데이터 미반영, 커밋 예외가 서버 로그에만 (yield teardown commit) | FA-BG-03 | `async-concurrency.md` |
| `IN %s` 튜플·`SET %s` 실패 (psycopg2 → 3) | PY-PG-01 | `psycopg-postgres.md` |
| `prepared statement "_pg3_N" does not exist` | PY-PG-02 | `psycopg-postgres.md` |
| `prepared statement "__asyncpg_stmt_N__" already exists` | PY-PG-10 | `psycopg-postgres.md` |
| `PoolTimeout`, 지연이 ~30초에 몰림, `too many clients` | PY-PG-03, PY-PG-06 | `psycopg-postgres.md` |
| 조용한 뒤 첫 요청만 `server closed the connection` | PY-PG-04 | `psycopg-postgres.md` |
| `idle in transaction` 장기 지속 | PY-PG-07 | `psycopg-postgres.md` |
| export/대량 조회에서 RSS 급증 | PY-PG-08, FA-RESP-04 | `psycopg-postgres.md`, `pydantic-serialization.md` |
| 대량 INSERT 가 느림 | PY-PG-09 | `psycopg-postgres.md` |
| 마이그레이션: CONCURRENTLY 실패·ALTER 중 전체 정지·컬럼 추가 락 | PY-MIG-01~05 | `psycopg-postgres.md` |
| `ORJSONResponse`/`response_class` 지정, 응답 직렬화가 프로파일 상위 | FA-RESP-01, FA-RESP-02 | `pydantic-serialization.md` |
| 서비스에서 모델 만들고 라우터에서 또 다른 모델로 검증 | FA-RESP-03 | `pydantic-serialization.md` |
| `json.loads` 후 `model_validate`, 함수 안 `TypeAdapter(...)`, `model_construct` | FA-PYD-01~03 | `pydantic-serialization.md` |
| 큰 요청 바디 검증이 느림, 유니온 오류 폭발 | FA-PYD-04 | `pydantic-serialization.md` |
| "GIL 때문에 느리다" / free-threaded 도입 검토 | PY-GIL-01 | `runtime-memory-gc.md` |
| 3.14 업그레이드 후 프로세스 풀 `PicklingError` | PY-GIL-02 | `runtime-memory-gc.md` |
| 피크 후 메모리가 안 내려감, 스레드풀 워커 RSS 증가 | PY-MEM-02, PY-MEM-04 | `runtime-memory-gc.md` |
| 메서드 `@lru_cache`(ruff B019), 예외 객체 보관 | PY-MEM-03, PY-MEM-05 | `runtime-memory-gc.md` |
| 할당 많은 엔드포인트의 지연 스파이크, GC 튜닝 | PY-GC-01~03 | `runtime-memory-gc.md` |
| 저트래픽 시간대 간헐 502 (LB 뒤) | FA-SRV-03 | `deployment-uvicorn.md` |
| client IP 가 전부 프록시 IP | FA-SRV-04 | `deployment-uvicorn.md` |
| 컨테이너 워커 수·503 폭주·배포 중 요청 유실 | FA-SRV-02, FA-SRV-05, FA-SRV-06 | `deployment-uvicorn.md` |
| 반경 검색이 전체 반환 / Seq Scan / 최근접 정렬이 느림 | PY-GIS-01~05 | `postgis.md` |
| 좌표 뒤바뀜, geometry 가 hex 문자열로 응답 | PY-GIS-06, PY-GIS-08 | `postgis.md` |

## 3. 코드 리뷰 시 빠른 스캔 (grep 신호)

| grep | 의심 항목 |
|---|---|
| `async def` 함수 안의 `requests\.\|time\.sleep\|psycopg\.connect(` | FA-ASYNC-01 |
| `create_task(` 결과 미할당 | FA-ASYNC-03 |
| `IN %s` | PY-PG-01 |
| `AsyncConnectionPool(` 에 `open=False` 없음 | PY-PG-05 |
| `async with .*connection()` 블록 안 `httpx\|await client` | PY-PG-07 |
| `ORJSONResponse\|default_response_class\|response_class=` | FA-RESP-01 |
| 함수 본문의 `TypeAdapter(` | FA-PYD-02 |
| `model_construct(` | FA-PYD-03 |
| 메서드 위 `@lru_cache\|@cache` | PY-MEM-03 |
| `ST_Distance(.*) <` · `geometry(.*4326)` + `ST_DWithin` | PY-GIS-02, PY-GIS-01 |
| 마이그레이션의 `CONCURRENTLY` (dbmate `transaction:false` + 블록당 1문장 확인) | PY-MIG-01 |
| yield 의존성의 `yield` 뒤 `commit()` · `session.begin():` 안의 `yield` | FA-BG-03 |

## 4. 레퍼런스 목록

| 파일 | 내용 | 항목 |
|---|---|---|
| `references/async-concurrency.md` | 이벤트루프·스레드풀·BackgroundTasks·yield 의존성 수명 | FA-ASYNC, FA-THREAD, FA-BG |
| `references/psycopg-postgres.md` | psycopg 3·풀·PgBouncer·dbmate/PostgreSQL DDL | PY-PG, PY-MIG |
| `references/pydantic-serialization.md` | Pydantic v2 검증 비용·FastAPI 응답 직렬화 | FA-PYD, FA-RESP |
| `references/runtime-memory-gc.md` | GIL/free-threaded·메모리·GC | PY-GIL, PY-MEM, PY-GC |
| `references/deployment-uvicorn.md` | 워커 수·keep-alive·프록시·graceful shutdown | FA-SRV |
| `references/postgis.md` | geography/geometry·SRID·GiST·KNN | PY-GIS |
| `references/fastapi-idioms.md` | (범용) Depends·Pydantic·lifespan·httpx·Settings 관용구 | — |
| `references/layer-patterns.md` | (범용) Router/Service/Repository 계층 예시 — Repository 는 SQLAlchemy 예시 | — |
| `references/sqlalchemy-patterns.md` | (ORM 프로젝트 전용) 모델·N+1·Alembic | — |
| `references/testing-patterns.md` | (범용) pytest·httpx·factory | — |

## 5. 프로젝트 규칙으로 옮기기

반복해서 적용할 항목은 프로젝트의 `CLAUDE.md` 또는 `.claude/rules/*.md` 에 **항목 ID + 적용 조건 + 프로젝트 사실**(예: "PgBouncer transaction 모드 → `prepare_threshold=None`")로 기록하는 것이 효과적이다. 생성·점검은 `workflow:project-rules` 가 있으면 그것을 사용한다. 이 스킬의 항목 전체를 복사하지 말고, 적용 조건이 맞는 것만 고른다.
