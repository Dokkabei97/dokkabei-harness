# Python · pytest 테스트 함정

적용 전 확인: `pyproject.toml` 의 pytest 플러그인(pytest-asyncio, pytest-xdist), DB 드라이버(psycopg 원시 SQL vs ORM), 마이그레이션 도구(dbmate/Alembic 등 — 프로젝트 것을 그대로 테스트 DB 구성에 사용).

### TST-PY-01 · "테스트마다 롤백" 은 앱이 같은 커넥션을 쓸 때만 성립한다
- 적용: pytest fixture 가 트랜잭션을 열고 끝에 롤백하는 격리 전략 + psycopg/커넥션 풀
- 신호: 테스트 후 데이터가 남음, 순서 의존 실패, 앱 코드의 `commit()` 이후 롤백 무효
- 메커니즘: 롤백 격리는 테스트와 앱 코드가 **같은 커넥션·같은 트랜잭션**일 때만 유효하다. 앱이 풀에서 다른 커넥션을 꺼내거나 직접 `conn.commit()` 하면 테스트 트랜잭션 밖에서 커밋된다. psycopg 3 의 중첩 `conn.transaction()` 블록은 SAVEPOINT 로 구현되므로, 앱 쓰기 경로가 `transaction()` 블록을 쓰면 외곽 트랜잭션 안에 안전하게 중첩된다. `conn.transaction(force_rollback=True)` 는 정상 종료여도 롤백한다.
- 처방: 커넥션을 의존성 주입(FastAPI `dependency_overrides`)으로 테스트 커넥션 하나에 고정하고, 앱 코드는 `commit()` 대신 `with conn.transaction():`. 앱 구조상 불가하면 테스트 후 TRUNCATE 또는 템플릿 DB 재생성(TST-PY-02).
- 반례: 커밋 자체(트리거, 커밋 후 훅, LISTEN/NOTIFY)를 검증하는 테스트는 롤백 격리 대상이 아니다.
- 검증: 테스트 직후 별도 커넥션으로 대상 테이블 count.
- 근거: https://www.psycopg.org/psycopg3/docs/basic/transactions.html

### TST-PY-02 · pytest-xdist 워커가 DB 하나를 공유하면 격리가 깨진다
- 적용: `pytest -n auto` + 실제 Postgres(PostGIS 포함)
- 신호: 직렬 실행은 그린, `-n` 에서 unique 충돌·데드락
- 메커니즘: 워커는 별도 프로세스라 각자 커넥션·트랜잭션을 가진다. 같은 DB 에서 시퀀스·고유키·TRUNCATE 가 서로 간섭.
- 처방: `worker_id` fixture 로 워커별 DB(`test_gw0` …) 생성. 마이그레이션을 1회 적용한 템플릿 DB 를 만들고 `CREATE DATABASE test_gwN TEMPLATE test_template` 로 복제하면 빠르다(템플릿에 다른 접속이 없어야 함). PostGIS 확장도 템플릿에 포함돼 복제된다.
- 반례: 테스트 수가 적으면 xdist 기동 비용이 이득보다 크다.
- 검증: `-n 4` 반복 실행으로 간헐 실패 확인.
- 근거: https://pytest-xdist.readthedocs.io/en/stable/how-to.html#identifying-the-worker-process-during-a-test · https://www.postgresql.org/docs/current/manage-ag-templatedbs.html

### TST-PY-03 · 세션 스코프 async 풀 + 함수 스코프 이벤트 루프 = "different loop" 에러
- 적용: pytest-asyncio + 세션/모듈 스코프 async fixture(커넥션 풀, httpx AsyncClient)
- 신호: `attached to a different loop`, `Event loop is closed`, 첫 테스트만 통과
- 메커니즘: pytest-asyncio 는 기본으로 테스트마다 이벤트 루프를 만든다. 다른 루프에서 만든 async 리소스(풀, 소켓)는 다른 루프에서 쓸 수 없다.
- 처방: 공유 리소스와 그걸 쓰는 테스트의 루프 스코프를 일치시킨다(최근 버전은 fixture/marker 의 `loop_scope` 지정 — 프로젝트의 pytest-asyncio 버전 문서 확인). 아니면 리소스를 함수 스코프로.
- 반례: 함수 스코프로 내리면 풀 생성 비용이 테스트마다 발생 — 테스트 수가 많으면 루프 스코프 확장이 낫다.
- 검증: 해당 fixture 를 쓰는 테스트 2개 이상을 연속 실행.
- 근거: https://pytest-asyncio.readthedocs.io/en/stable/concepts.html
