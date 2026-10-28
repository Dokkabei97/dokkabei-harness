# CPython 런타임: GIL · free-threaded · 메모리 · GC

> 스페셜리스트 항목. CPython 3.12~3.14 기준 — 버전마다 기본값이 다르므로 대상 런타임에서 `python -VV`, `gc.get_threshold()` 로 먼저 확인.

## 목차
- PY-GIL-01 free-threaded 빌드 판단: I/O 웹 서버엔 대개 이득 없음
- PY-GIL-02 3.14 Linux: ProcessPoolExecutor 기본 시작 방식이 fork → forkserver
- PY-MEM-01 대량 소형 객체: `__slots__`/튜플 — 단, 3.11+ 에선 측정 후
- PY-MEM-02 dict 는 삭제로 줄어들지 않는다 — 장수 캐시의 고점 메모리
- PY-MEM-03 메서드에 `lru_cache` = self 누수, 무한 `@cache` = 입력 수만큼 누수
- PY-MEM-04 멀티스레드 RSS 증가: glibc malloc 아레나
- PY-MEM-05 예외 객체 보관 → traceback → 프레임 → 지역변수 전부 보관
- PY-GC-01 할당 많은 서비스의 GC 빈도와 `gc.freeze()` 로 장수 객체 제외
- PY-GC-02 3.14.0~3.14.4 의 incremental GC 는 3.14.5 에서 되돌려졌다
- PY-GC-03 `gc.freeze()` 의 CoW 이점은 fork 모델에서만 — uvicorn 은 spawn

---

### PY-GIL-01 · free-threaded(no-GIL) 빌드는 "CPU 바운드 스레드 병렬"이 필요할 때만 — async I/O 웹 서버엔 대개 이득이 없다
- 적용: CPython 3.13(실험, PEP 703) / 3.14(공식 지원 단계, PEP 779 — 기본 빌드는 여전히 GIL)
- 신호: "GIL 때문에 느리다"는 가설, 스레드풀에서 CPU 작업(이미지 리사이즈, 지오메트리 연산)이 직렬화됨
- 메커니즘: GIL 빌드에서 순수 파이썬 CPU 작업은 스레드가 늘어도 병렬화되지 않는다. free-threaded 빌드는 이를 해소하지만 단일 스레드 오버헤드가 있다(3.14 What's New: 약 5~10%, 3.14 how-to: pyperformance 평균 macOS aarch64 약 1% ~ x86-64 Linux 약 8%), 메모리 사용량이 늘고, free-threading 지원 표시가 없는 C 확장을 import 하면 **GIL 이 자동으로 다시 켜지며 경고만 출력**된다. 이벤트루프 기반 I/O 서버는 애초에 GIL 이 병목이 아닌 경우가 대부분.
- 처방: 판단 순서 — ① 프로파일로 CPU 바운드 확인 ② GIL 을 놓는 C 확장(numpy, shapely 의 GEOS 연산 등)으로 해결되는지 ③ 프로세스 풀/작업 큐 ④ 그래도 스레드 병렬이 필요하면 free-threaded 를 시험: `sysconfig.get_config_var("Py_GIL_DISABLED") == 1` 로 빌드 확인, 런타임에 `sys._is_gil_enabled()` 가 False 인지 반드시 확인(의존성 하나가 GIL 을 되살릴 수 있음).
- 반례: 3.14 의 `concurrent.interpreters`/`InterpreterPoolExecutor`(서브인터프리터)는 시작 비용·메모리 최적화가 아직이고 객체 공유 수단이 제한적(공식 문서) — 웹 서버 병렬화 수단으로 성급히 쓰지 말 것.
- 검증: 동일 워크로드를 GIL/free-threaded 빌드에서 처리량·RSS 비교, 기동 로그의 GIL 재활성 경고 확인.
- 근거: https://docs.python.org/3.14/howto/free-threading-python.html · https://docs.python.org/3.14/whatsnew/3.14.html

### PY-GIL-02 · Python 3.14 부터 Linux 의 `ProcessPoolExecutor` 기본 시작 방식은 `fork` 가 아니라 `forkserver`
- 적용: Python 3.14+, macOS 외 Unix(컨테이너 Linux 포함)
- 신호: 3.14 업그레이드 후 `PicklingError`(람다·로컬 함수·열린 커넥션 전달), 부모에서 초기화한 전역 상태가 자식에서 비어 있음
- 메커니즘: fork 는 부모 메모리를 복제해 전역을 상속했지만 forkserver 는 새 프로세스에서 모듈을 다시 import 하고 작업·인자를 pickle 로 전달한다. (macOS·Windows 는 원래 spawn.)
- 처방: 작업 함수는 모듈 최상위 함수로, 인자는 pickle 가능한 원시 값으로. 자원(DB 풀 등)은 `initializer=` 로 자식에서 생성. 꼭 fork 가 필요하면 `mp_context=multiprocessing.get_context("fork")` 를 명시하되 스레드가 있는 프로세스에서 fork 는 교착 위험.
- 반례: 없음 — 명시적 context 지정이 가장 이식성이 높다.
- 검증: 3.14 CI 매트릭스에서 프로세스 풀 경로 테스트.
- 근거: https://docs.python.org/3.14/whatsnew/3.14.html (concurrent.futures)

### PY-MEM-01 · 메모리에 수십만 개 이상 상주하는 소형 객체는 `__slots__`/`dataclass(slots=True)`/튜플로 — 단 3.11+ 는 측정 후
- 적용: 인메모리 인덱스·캐시(예: 좌표 목록, 행정구역 코드 테이블)에 객체가 대량 상주
- 신호: 객체 수 × 인스턴스 크기가 RSS 대부분, `tracemalloc` 상위가 `__init__`
- 메커니즘: 일반 인스턴스는 속성을 dict 로 들고 있다. `__slots__` 는 고정 슬롯으로 dict 를 없앤다. 다만 3.11+ 는 인스턴스 속성 저장을 최적화(키 공유·인라인 값)해 차이가 예전보다 작다. Pydantic `BaseModel` 인스턴스는 필드 dict 외에 `__pydantic_fields_set__` 등 부가 상태를 가져 대량 상주용으로는 무겁다.
- 처방: 대량 상주 데이터는 `@dataclass(slots=True, frozen=True)`(3.10+) 또는 `NamedTuple`/튜플, 수치 대량은 `array`/numpy. 경계(API 입출력)에서만 Pydantic.
- 반례: 객체 수가 수천 이하면 가독성 손해만 있다. `__slots__` 는 동적 속성·일부 다중 상속을 막는다.
- 검증: `tracemalloc.take_snapshot()` 비교 또는 `sys.getsizeof` + 객체 수로 추정 → 실제 RSS 로 확인.
- 근거: https://docs.python.org/3/reference/datamodel.html#slots · https://docs.python.org/3/library/tracemalloc.html

### PY-MEM-02 · dict 는 키를 지워도 줄어들지 않는다 — 장수 dict 캐시는 고점 크기를 계속 점유
- 적용: 모듈 전역 dict 를 캐시/세션 저장소로 쓰고 만료 키를 `del`/`pop` 하는 코드
- 신호: 트래픽 피크 후 키 수는 줄었는데 RSS 는 피크 수준 유지
- 메커니즘: CPython dict 는 삭제 시 슬롯을 더미로 표시할 뿐 테이블을 재할당하지 않는다. 축소는 이후 삽입으로 리사이즈가 일어날 때나 `clear()`/재생성 시에만.
- 처방: 상한 있는 캐시(`cachetools.TTLCache/LRUCache`, `functools.lru_cache(maxsize=N)`) 사용. 직접 구현이면 주기적으로 `cache = dict(cache)` 로 재구성하거나 세대 교체(새 dict 로 swap). 다중 워커에서 일관성이 필요하면 외부 캐시.
- 반례: 키 집합이 고정된 룩업 테이블은 해당 없음.
- 검증: 피크 부하 → 만료 후 `tracemalloc` 의 해당 dict 할당 크기.
- 근거: https://github.com/python/cpython/blob/main/Objects/dictobject.c (삭제 시 DKIX_DUMMY, 리사이즈는 삽입 경로)

### PY-MEM-03 · 메서드에 `@lru_cache` 를 달면 `self` 가 캐시 키로 붙잡혀 인스턴스가 해제되지 않는다
- 적용: 요청마다 생성되는 서비스/리포지토리 클래스의 메서드 캐시, `@functools.cache`(무한) 를 요청 파라미터 함수에 적용한 코드
- 신호: 인스턴스 수가 요청 수에 비례해 증가, ruff `B019` 경고
- 메커니즘: 캐시는 클래스 수준 함수 객체에 붙고 인자 튜플(`self` 포함)을 강참조한다. `@cache` 는 `maxsize=None` 이라 고유 입력 수만큼 무한 증가.
- 처방: 인스턴스 수명 캐시는 `functools.cached_property` 또는 인스턴스 속성 dict, 전역 캐시는 모듈 함수 + `maxsize` 지정. 요청 입력을 키로 하는 캐시는 반드시 상한·TTL.
- 반례: 애플리케이션 수명 동안 1개뿐인 싱글톤의 메서드는 실질적 누수가 아니다(그래도 B019 는 억제 주석으로 의도 표시).
- 검증: `fn.cache_info().currsize` 모니터링, `gc.get_referrers(instance)`.
- 근거: https://docs.astral.sh/ruff/rules/cached-instance-method/ · https://docs.python.org/3/library/functools.html#functools.lru_cache

### PY-MEM-04 · 스레드풀을 쓰는 워커의 RSS 가 계속 오르면 누수보다 glibc malloc 아레나 단편화를 먼저 의심
- 적용: Linux(glibc) 컨테이너 + `def` 엔드포인트/스레드풀(FA-THREAD-01) + 512바이트 초과 할당이 많은 워크로드(큰 bytes/JSON/numpy)
- 신호: `tracemalloc` 상 파이썬 할당은 평탄한데 RSS 만 단계적으로 증가, 재시작하면 정상
- 메커니즘: pymalloc 은 512바이트 이하 객체만 자체 아레나에서 관리하고 그보다 큰 할당은 시스템 malloc 으로 간다. glibc 는 경합을 줄이려 스레드별 아레나를 만들며 상한은 CPU 수의 배수로 구현 정의된다(glibc `malloc/arena.c` 의 `NARENAS_FROM_NCORES` — 64비트에서 코어 수 × 8). 그래서 스레드 40개가 각자 아레나에 해제된 조각을 남긴다.
- 처방: 환경변수 `MALLOC_ARENA_MAX=2` 로 시험, 또는 jemalloc 을 `LD_PRELOAD`. 보조 수단으로 uvicorn `--limit-max-requests` + jitter(FA-SRV-05).
- 반례: musl(Alpine) 등 glibc 가 아니면 해당 없음(대신 musl malloc 자체 성능 이슈가 있다). 실제 파이썬 누수(PY-MEM-02/03)를 먼저 배제.
- 검증: 같은 부하에서 `MALLOC_ARENA_MAX` 유무별 RSS 추세 비교, `tracemalloc` 총량과 RSS 의 괴리 확인. 스레드풀 동시성이 높은 경로는 처리량·p99 도 함께 비교 — 아레나 축소는 malloc 락 경합 증가와 맞바꾸는 것이다(glibc 가 스레드별 아레나를 두는 이유; 수치는 워크로드 의존).
- 근거: https://docs.python.org/3/c-api/memory.html#the-pymalloc-allocator · https://man7.org/linux/man-pages/man3/mallopt.3.html (M_ARENA_MAX)

### PY-MEM-05 · 예외 객체를 보관하면 traceback 이 참조하는 모든 프레임의 지역변수(요청 바디, 결과 리스트)까지 살아남는다
- 적용: `self.last_error = e`, 실패 목록에 예외 객체 append, 커스텀 에러 수집기
- 신호: 오류가 많은 시간대에 메모리 증가, `gc.get_referrers` 추적 시 `frame` → `traceback`
- 메커니즘: `e.__traceback__` → `tb_frame` → `f_locals`. 프레임이 다시 예외를 참조하면 순환 참조가 되어 refcount 로는 해제되지 않고 순환 GC 를 기다린다. `except ... as e` 블록 끝에서 이름 `e` 를 지우는 것도 이 순환 때문이다.
- 처방: 보관은 `repr(e)`/`traceback.format_exception(e)` 문자열이나 `traceback.TracebackException.from_exception(e)`(지역변수 미캡처 기본값)로.
- 반례: 즉시 재전파·로깅만 하는 코드는 해당 없음.
- 검증: `tracemalloc` 의 traceback 기준 스냅샷 diff.
- 근거: https://docs.python.org/3/reference/compound_stmts.html#except-clause · https://docs.python.org/3/library/traceback.html

### PY-GC-01 · 할당이 많은 서비스는 순환 GC 가 꼬리 지연을 만든다 — 임계값 조정과 기동 후 `gc.freeze()`
- 적용: 요청당 객체를 대량 생성하는 서비스(큰 Pydantic 트리, 대량 행 처리), p99 민감 API
- 신호: 지연 스파이크가 할당량과 상관, `gc.callbacks` 로 측정한 gen2 수집 시간이 수십 ms
- 메커니즘: (할당 − 해제) 가 `threshold0` 을 넘으면 gen0 수집, 누적 횟수에 따라 상위 세대까지. 전체 수집은 추적 중인 모든 컨테이너 객체를 훑으므로 기동 시 로드된 장수 객체(모듈, 설정, 대형 룩업)가 많을수록 매번 비싸다. 기본 임계값은 버전마다 다르다 — ≤3.12: `(700, 10, 10)`, 3.13+: `(2000, 10, 10)`(3.14.0~3.14.4 의 incremental GC 는 별도, PY-GC-02).
- 처방: ① `gc.callbacks` 로 세대별 수집 시간·빈도 계측 ② lifespan 기동 완료 → `gc.collect()` → `gc.freeze()` 순서로 기동 객체를 영구 세대로 옮겨 이후 수집 대상에서 제외 ③ 필요 시 `gc.set_threshold()` 로 `threshold0` 상향 — 값은 반드시 측정으로 결정.
- 반례: `gc.disable()` 은 순환 참조 누수를 무한히 쌓는다(PY-MEM-05 류가 있으면 OOM). 임계값을 크게 올리면 수집 1회당 시간이 길어질 수 있다. freeze 전에 `gc.collect()` 를 하지 않으면 기동 중 생긴 순환 가비지까지 영구 세대로 옮겨져 프로세스 수명 내내 회수되지 않는다.
- 검증: 조정 전후 p99, gc 콜백 기반 히스토그램, RSS 추세를 같은 부하로 비교.
- 근거: https://docs.python.org/3/library/gc.html · https://github.com/python/cpython/blob/3.13/Include/internal/pycore_runtime_init.h (기본 threshold 2000/10/10)

### PY-GC-02 · Python 3.14.0~3.14.4 의 incremental GC 는 운영 메모리 압박 보고로 3.14.5 에서 3.13 세대별 GC 로 되돌려졌다
- 적용: Python 3.14 런타임(컨테이너 베이스 이미지 패치 버전 확인)
- 신호: 3.14 초기 패치 버전에서 메모리 사용 증가, 3.14 기준으로 작성된 `gc.collect(1)` 의미 차이
- 메커니즘: 3.14.0~3.14.4 는 young/old 2세대 incremental GC(일시정지 감소 목적)였고 `gc.collect(1)` 이 "증분 1회" 의미였다. 3.14.5 부터 다시 3.13 의 세대별 GC.
- 처방: 3.14 를 쓰면 3.14.5 이상으로 고정(`python:3.14.x` 태그의 패치 버전 명시). GC 튜닝 값·벤치마크는 패치 버전을 함께 기록.
- 반례: 없음.
- 검증: `python -VV`, 배포 이미지의 패치 버전 확인.
- 근거: https://docs.python.org/3.14/whatsnew/3.14.html (Garbage collection)

### PY-GC-03 · `gc.freeze()` 로 fork 후 Copy-on-Write 를 아끼는 기법은 fork 모델(gunicorn `--preload`)에만 유효 — uvicorn `--workers` 는 spawn 이다
- 적용: 워커당 메모리를 줄이려는 멀티 워커 배포
- 신호: "preload + gc.freeze 를 했는데 메모리가 그대로" (uvicorn 멀티프로세스 매니저 사용 시)
- 메커니즘: fork 된 자식은 부모 페이지를 공유하지만, GC 가 객체 헤더를 건드리면 페이지가 복사된다. 공식 문서 권장: 부모에서 일찍 `gc.disable()`, fork 직전 `gc.freeze()`, 자식에서 `gc.enable()`. uvicorn 의 멀티프로세스 매니저는 pre-fork 가 아니라 spawn 이라 자식이 앱을 새로 import 하므로 공유 자체가 없다.
- 처방: 공유가 필요하면 gunicorn + `uvicorn-worker` + `--preload` + 위 freeze 패턴. 컨테이너에서 1 프로세스/파드로 스케일하는 구조라면 이 최적화는 무관 — PY-GC-01 의 지연 목적 freeze 만 고려.
- 반례: preload 는 DB 풀·스레드를 fork 전에 만들면 자식이 소켓을 공유하는 사고가 난다 — 자원은 반드시 자식(lifespan)에서 생성.
- 검증: 워커별 PSS(`smem` 또는 `/proc/<pid>/smaps_rollup`)로 공유 페이지 확인.
- 근거: https://docs.python.org/3/library/gc.html#gc.freeze · https://github.com/Kludex/uvicorn/blob/main/docs/deployment/index.md
