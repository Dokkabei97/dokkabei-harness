# 동시성 · 이벤트루프 · 스레드풀 · BackgroundTasks

> 스페셜리스트 항목 — 각 항목은 ID·적용 조건을 가진다. 프로젝트 규칙(`.claude/rules`)으로 옮길 때는 적용 조건이 맞는 항목만 고른다.
> 버전 민감: FastAPI 0.118/0.121/0.130 경계, anyio 4.x 기준. 대상 프로젝트의 실제 버전을 `pyproject.toml`/lock 에서 먼저 확인.

## 목차
- FA-ASYNC-01 async def 안의 블로킹 호출 → 워커 전체 정지
- FA-ASYNC-02 블로킹 탐지: asyncio debug 모드 slow callback
- FA-ASYNC-03 fire-and-forget create_task 가 GC 로 사라짐
- FA-ASYNC-04 asyncio.to_thread 와 anyio 스레드풀은 별개 풀
- FA-THREAD-01 def 엔드포인트·def 의존성은 anyio 토큰 40개를 공유
- FA-THREAD-02 사소한 def 의존성이 요청마다 스레드 홉
- FA-THREAD-03 def 엔드포인트의 응답 검증도 스레드풀에서 실행
- FA-BG-01 BackgroundTasks 는 큐가 아니다
- FA-BG-02 yield 의존성 종료 시점이 세 번 바뀜 — 요청 자원을 백그라운드에 넘기지 말 것
- FA-BG-03 yield teardown 의 commit 은 응답 전송 후 — 커밋 실패가 2xx 로 가려진다

---

### FA-ASYNC-01 · async def 안의 블로킹 호출이 워커의 모든 요청을 멈춘다
- 적용: `async def` 엔드포인트/의존성/미들웨어가 있는 모든 FastAPI 앱
- 신호: `async def` 본문에서 `requests.`, `time.sleep`, 동기 DB 드라이버(`psycopg.connect`, `psycopg2`, 동기 SQLAlchemy `Session`), `open().read()` 대용량, CPU 연산(이미지·PDF·bcrypt/argon2 해시, 큰 JSON 파싱). p99 가 동시 요청 수에 비례해 계단식으로 증가, 헬스체크 타임아웃.
- 메커니즘: 워커 프로세스당 이벤트루프 1개·스레드 1개. `await` 없는 구간은 선점되지 않으므로 50ms 블로킹 = 그 워커에 걸린 모든 in-flight 요청이 50ms 정지. `def` 엔드포인트였다면 스레드풀로 빠졌을 코드를 `async def` 로 "업그레이드"하면서 생기는 회귀가 가장 흔하다.
- 처방: (1) 비동기 드라이버로 교체(`psycopg.AsyncConnection`/`AsyncConnectionPool`, `httpx.AsyncClient`) (2) 불가하면 `await anyio.to_thread.run_sync(fn, *args)` / `starlette.concurrency.run_in_threadpool` (3) 순수 CPU 작업은 `ProcessPoolExecutor` 또는 작업 큐 — 스레드로 보내도 GIL 때문에 루프 스레드와 경쟁한다(해시 라이브러리처럼 GIL 을 놓는 C 확장은 예외). (4) 엔드포인트 전체가 동기 I/O 라면 그냥 `def` 로 선언.
- 반례: 수 µs 수준의 dict 조작·짧은 정규식까지 스레드로 보내면 스레드 홉(수십 µs)이 더 비싸다. 기준은 "측정상 1ms 이상".
- 검증: FA-ASYNC-02 의 debug 모드 로그, `py-spy dump --pid <worker>` 로 루프 스레드가 어떤 동기 함수에 있는지 확인, 부하 중 `/health` 지연 측정.
- 근거: https://fastapi.tiangolo.com/async/ · https://docs.python.org/3/library/asyncio-dev.html

### FA-ASYNC-02 · 블로킹 탐지는 asyncio debug 모드의 slow callback 로그로 한다
- 적용: 로컬/스테이징 진단 (운영 상시 활성 금지)
- 신호: 원인 불명 지연, FA-ASYNC-01 의심
- 메커니즘: debug 모드에서 100ms 넘게 걸린 콜백(= 루프를 잡고 있던 코루틴 스텝)이 `Executing <Task ...> took 0.153 seconds` 로 로깅된다. 임계값은 `loop.slow_callback_duration`.
- 처방: `PYTHONASYNCIODEBUG=1` (또는 `python -X dev`) 로 기동, lifespan 에서 `asyncio.get_running_loop().slow_callback_duration = 0.02` 로 낮춰 20ms 블로킹까지 잡는다. 진단 중엔 `uvicorn --loop asyncio` 로 표준 루프를 써서 uvloop 차이를 배제.
- 반례: debug 모드는 코루틴 생성 위치 추적 등으로 느려진다 — 벤치마크 수치를 이 상태로 비교하지 말 것.
- 검증: 의도적으로 `time.sleep(0.05)` 를 넣은 엔드포인트로 로그가 찍히는지 먼저 확인.
- 근거: https://docs.python.org/3/library/asyncio-dev.html#debug-mode

### FA-ASYNC-03 · `asyncio.create_task()` 결과를 버리면 태스크가 중간에 사라질 수 있다
- 적용: 엔드포인트나 lifespan 에서 fire-and-forget 태스크를 띄우는 코드
- 신호: `asyncio.create_task(send_event(...))` 반환값 미보관, 간헐적으로 실행이 끝나지 않는 부수효과, "Task was destroyed but it is pending!" 경고
- 메커니즘: 이벤트루프는 태스크를 **약한 참조**로만 들고 있다. 다른 곳에서 참조하지 않으면 완료 전에 GC 될 수 있다(공식 문서 경고).
- 처방: 모듈/앱 state 의 `set` 에 넣고 `task.add_done_callback(tasks.discard)`. 더 나은 선택은 lifespan 소유의 `anyio.create_task_group()` / `asyncio.TaskGroup`(3.11+) 으로 수명과 예외 전파를 명시하는 것.
- 반례: 응답 후 실행·재시도·내구성이 필요하면 태스크가 아니라 작업 큐(FA-BG-01).
- 검증: 태스크 수 메트릭(`len(app.state.bg_tasks)`), 종료 시 미완료 태스크 로깅.
- 근거: https://docs.python.org/3/library/asyncio-task.html#asyncio.create_task

### FA-ASYNC-04 · `asyncio.to_thread`/`run_in_executor(None)` 와 Starlette 스레드풀은 서로 다른 풀이다
- 적용: 같은 앱에서 두 API 를 섞어 쓸 때, 스레드 상한을 튜닝할 때
- 신호: anyio 토큰을 늘렸는데 `asyncio.to_thread` 쪽 대기가 그대로, 혹은 그 반대
- 메커니즘: FastAPI/Starlette 의 `def` 엔드포인트·`run_in_threadpool` 은 anyio 기본 limiter(40 토큰)를 쓴다. `asyncio.to_thread`/`loop.run_in_executor(None, ...)` 는 루프 기본 `ThreadPoolExecutor` 를 쓰며 기본 `max_workers = min(32, cpu + 4)` (3.13+ 는 `os.process_cpu_count()` 기준). anyio 문서도 limiter 가 asyncio 기본 executor 에 영향이 없다고 명시.
- 처방: 한 앱에서는 한 경로(`anyio.to_thread.run_sync` 권장)로 통일하고, 상한은 그 풀에서만 조정. DB 풀 크기와 함께 설계(FA-THREAD-01).
- 반례: 라이브러리 내부가 `run_in_executor` 를 쓰는 경우는 통제 불가 — 그 풀은 `loop.set_default_executor()` 로만 조정.
- 검증: `threading.active_count()` 와 스레드 이름(`AnyIO worker thread` vs `asyncio_N`)을 py-spy 로 확인.
- 근거: https://anyio.readthedocs.io/en/stable/threads.html · https://docs.python.org/3/library/concurrent.futures.html#threadpoolexecutor

### FA-THREAD-01 · `def` 엔드포인트·`def` 의존성은 워커당 40개 스레드 토큰을 공유한다
- 적용: 동기(`def`) 엔드포인트/의존성 비중이 큰 앱, 동기 DB 드라이버
- 신호: 동시 요청 ~40 근처에서 처리량이 평평해지고 지연만 증가, CPU 는 한가함. 느린 외부 호출 1개가 무관한 `def` 엔드포인트까지 막음.
- 메커니즘: FastAPI 는 `def` 경로 함수와 `def` 의존성을 `run_in_threadpool` → `anyio.to_thread.run_sync` 로 실행하며, 기본 limiter 는 **40 토큰**(anyio 공식 문서). 41번째 호출은 토큰을 기다린다. 동기 DB 풀 `max_size` 가 40보다 작으면 스레드는 받고 커넥션을 기다리는 2단 대기가 생긴다.
- 처방: lifespan 에서 `anyio.to_thread.current_default_thread_limiter().total_tokens = N`. N 은 "동시에 블로킹 I/O 를 기다릴 수 있는 수"로 잡고 DB 풀 `max_size` ≥ (DB 를 쓰는 동시 스레드 수)로 맞춘다. 근본 처방은 I/O 경로를 async 로 옮기는 것.
- 반례: 토큰을 수백으로 올리면 GIL 경쟁·메모리(스레드 스택)·DB 커넥션 폭증으로 오히려 악화. CPU 바운드 작업에는 효과 없음.
- 검증: 부하 테스트에서 동시성 30/40/60 구간 처리량 비교, `limiter.borrowed_tokens` 를 메트릭으로 노출.
- 근거: https://anyio.readthedocs.io/en/stable/threads.html · https://fastapi.tiangolo.com/async/#path-operation-functions

### FA-THREAD-02 · I/O 없는 사소한 `def` 의존성이 요청마다 스레드 홉과 토큰을 소비한다
- 적용: `def get_settings()`, `def get_current_user(token=...)` 처럼 순수 계산 의존성을 `def` 로 선언한 앱
- 신호: 의존성 체인이 길수록 단순 엔드포인트 지연이 증가, 프로파일에 `run_sync`/`to_thread` 비중
- 메커니즘: FastAPI 는 의존성이 `def` 이면 내용과 무관하게 스레드풀로 보낸다(FastAPI 문서: sub-dependencies 도 동일 규칙). 요청당 의존성 N개 = 스레드 왕복 N회 + FA-THREAD-01 토큰 경쟁.
- 처방: I/O 가 없는 의존성은 `async def` 로 선언(본문은 그대로 동기 코드여도 된다 — await 가 없을 뿐). 클래스를 `Depends(SomeClass)` 로 쓰면 `__init__` 도 동기 호출이라 스레드풀로 간다 — 팩토리 `async def` 로 감싼다. 설정 객체는 캐시는 동기 함수에, 의존성은 async 래퍼로: `@lru_cache def _settings() -> Settings: return Settings()` + `async def get_settings() -> Settings: return _settings()`. 또는 lifespan 의 `app.state`.
- 반례: 의존성 안에 동기 I/O(동기 DB, 파일)가 있으면 `def` 가 맞다 — 그걸 `async def` 로 바꾸면 FA-ASYNC-01("async 로 업그레이드" 회귀). `@lru_cache` 를 `async def` 에 직접 달지 말 것 — 코루틴 객체가 캐시돼 두 번째 요청에서 `RuntimeError: cannot reuse already awaited coroutine`.
- 검증: 의존성만 있는 빈 엔드포인트로 `def` vs `async def` 지연 비교(wrk/locust).
- 근거: https://fastapi.tiangolo.com/async/#dependencies

### FA-THREAD-03 · `def` 엔드포인트는 응답 검증·직렬화 일부도 스레드풀에서 돈다
- 적용: `def` 엔드포인트 + `response_model`/반환 타입
- 신호: 큰 리스트를 반환하는 `def` 엔드포인트가 스레드 토큰을 오래 점유
- 메커니즘: FastAPI `serialize_response` 는 엔드포인트가 코루틴이 아니면 응답 필드 검증을 `run_in_threadpool` 로 실행한다(fastapi/routing.py). 엔드포인트 실행 + 검증 = 토큰 2회 획득.
- 처방: DB 접근이 async 인 앱은 엔드포인트도 `async def` 로 통일. 대용량 목록은 페이지네이션/스트리밍(FA-RESP-04).
- 반례: 동기 드라이버를 쓰는 앱에서 이것만을 이유로 `async def` 로 바꾸지 말 것.
- 검증: py-spy 로 `AnyIO worker thread` 에서 `validate` 프레임 확인.
- 근거: https://github.com/fastapi/fastapi/blob/master/fastapi/routing.py (`serialize_response`)

### FA-BG-01 · `BackgroundTasks` 는 큐가 아니다 — 같은 프로세스, 내구성·재시도·격리 없음
- 적용: 이메일·웹훅·후처리를 `BackgroundTasks` 로 돌리는 코드
- 신호: 배포/재시작/OOM 후 "보냈어야 할 알림이 없음", 무거운 후처리 중 같은 워커의 다른 요청 지연, `def` 백그라운드 함수가 스레드 토큰 점유
- 메커니즘: 응답 전송 후 **같은 워커 프로세스**에서 순차 실행된다. `def` 함수면 FA-THREAD-01 의 스레드풀, `async def` 면 이벤트루프에서 돈다(→ 블로킹 시 FA-ASYNC-01). 프로세스가 죽으면 유실, 실패 재시도 없음, 진행 상태 조회 불가. `--limit-max-requests` 나 롤링 배포의 graceful timeout 을 넘기면 중단.
- 처방: 수백 ms 이하·유실 허용 작업만 `BackgroundTasks`. 그 외는 내구 큐(Celery/RQ/arq/Dramatiq, 또는 이미 PostgreSQL 이 있으면 `SELECT ... FOR UPDATE SKIP LOCKED` 기반 outbox 테이블). 외부 부수효과는 트랜잭셔널 outbox 로 DB 커밋과 원자화.
- 반례: 큐 인프라가 없는 소규모 서비스에서 "로그 적재" 수준 작업까지 큐로 빼는 것은 과설계.
- 검증: 백그라운드 작업 중 SIGTERM 을 보내 유실 여부 재현, 작업 소요 히스토그램.
- 근거: https://fastapi.tiangolo.com/tutorial/background-tasks/#caveat

### FA-BG-02 · yield 의존성의 종료 시점은 0.106 → 0.118 → 0.121 에서 바뀌었다 — 요청 자원을 백그라운드로 넘기지 말 것
- 적용: `yield` 로 DB 커넥션/세션을 주는 의존성 + `BackgroundTasks` 또는 `StreamingResponse`
- 신호: 백그라운드 함수에 `conn`/`session` 객체를 인자로 전달, 업그레이드 후 "connection is closed" 또는 반대로 풀 고갈
- 메커니즘: 0.106.0 이전엔 yield 이후 코드가 응답·백그라운드 이후 실행, 0.106.0 에서 응답 전송 전으로 당겨졌고(백그라운드에서 세션 사용 불가), 0.118.0 에서 다시 "응답 전송 후"로 되돌아갔으며, 0.121.0 에서 `Depends(dep, scope="function")`(응답 전 종료)이 추가됐다. 기본 `scope="request"` 에서는 커넥션이 응답 전송(느린 스트리밍 포함)이 끝날 때까지 점유된다 → 풀 크기 계산이 응답 전송 시간에 묶인다.
- 처방: 백그라운드 함수에는 ID 등 원시 값만 넘기고 함수 안에서 풀로부터 새 커넥션을 획득(FastAPI 공식 권고). 인증 확인처럼 엔드포인트 이후 커넥션이 필요 없는 의존성은 `scope="function"`(0.121+)으로 일찍 반납.
- 반례: 버전을 고정하지 않은 상태에서 특정 시점 동작에 기대는 코드는 금지 — 이 영역은 앞으로도 바뀔 수 있다.
- 검증: 풀 통계(`pool.get_stats()` 의 `connections_num`/`requests_waiting`)를 느린 스트리밍 응답 중 관찰.
- 근거: https://fastapi.tiangolo.com/advanced/advanced-dependencies/#dependencies-with-yield-httpexception-except-and-background-tasks

### FA-BG-03 · yield 의존성 teardown 에서 commit 하면(0.118+ 기본 scope) 응답이 나간 **뒤에** 커밋된다 — 커밋 실패가 2xx 로 가려진다
- 적용: FastAPI 0.118+ 의 기본(`scope="request"`) yield 의존성에서 `yield session` 뒤 `await session.commit()`, `async with session.begin(): yield session`, psycopg `async with pool.connection() as conn: yield conn`(블록 정상 종료 시 commit) 형태로 커밋하는 코드
- 신호: 클라이언트는 200/201 을 받았는데 데이터가 없음, `IntegrityError`/`SerializationFailure`/deadlock 트레이스가 요청 로그와 분리돼 서버 로그에만 찍힘, 업그레이드(0.106~0.117 → 0.118+) 후 나타난 회귀
- 메커니즘: fastapi/routing.py 는 `function_stack`(scope="function") 을 엔드포인트 실행·응답 직렬화 직후 닫고, `request_stack`(기본 scope="request") 은 `await response(scope, receive, send)` **이후**에 닫는다. 그래서 teardown 의 commit 은 응답 바이트가 전송된 뒤 실행되고, 거기서 난 예외는 이미 보낸 상태 코드를 바꿀 수 없다. 유니크·FK 지연 제약(DEFERRABLE), SERIALIZABLE 직렬화 실패, flush 를 미룬 ORM 의 제약 위반은 commit 시점에 드러나므로 "성공 응답 + 미반영"이 된다. 응답을 받은 클라이언트의 즉시 후속 요청이 아직 커밋 전 데이터를 못 보는 창도 생긴다.
- 처방: (a) 쓰기 경로는 서비스(또는 엔드포인트)에서 `await session.commit()`/`await conn.commit()` 을 명시한 뒤 반환하고, teardown 은 rollback·close 만. (b) 또는 그 의존성을 `Depends(get_db, scope="function")`(0.121+)로 선언 — teardown(commit)이 응답 전에 돌아 실패가 500 으로 전달된다. 단 function scope 자원은 `StreamingResponse` 본문 생성·BackgroundTasks 에서 쓸 수 없고, scope="request" yield 의존성은 scope="function" 의존성에 의존할 수 없다(`DependencyScopeError`).
- 반례: 읽기 전용 경로·유실 허용 로그 적재처럼 커밋 실패가 응답 의미를 바꾸지 않는 곳은 teardown commit 도 무방. 0.106~0.117 고정 프로젝트는 teardown 이 응답 전이라 해당 없음(FA-BG-02).
- 검증: 유니크 위반을 일으키는 요청을 보내 상태 코드 확인 — teardown commit 이면 2xx + 서버 로그 예외, (a)/(b) 적용 후 4xx/5xx.
- 근거: https://fastapi.tiangolo.com/advanced/advanced-dependencies/#dependencies-with-yield-httpexception-except-and-background-tasks · https://fastapi.tiangolo.com/release-notes/ (0.118.0, 0.121.0) · https://github.com/fastapi/fastapi/blob/master/fastapi/routing.py (`request_stack`/`function_stack`)
