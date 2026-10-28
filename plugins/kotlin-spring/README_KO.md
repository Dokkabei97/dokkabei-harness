> [English](README.md) · **한국어**

# kotlin-spring

> JVM · Kotlin · Spring 스페셜리스트 레이어 — 강한 시니어 제너럴리스트도 놓치는 함정(GC·컨테이너 메모리, 맵·컬렉션 선택, 코루틴·가상 스레드, 트랜잭션·JPA·커넥션 풀, 프로파일링)을 증상에서 찾아가는 트리아지 스킬과, 컨벤션 우선 CRUD 스캐폴딩, 읽기 전용 런타임 진단 에이전트.

## 개요

`kotlin-spring` 은 모델이 이미 아는 관용구를 다시 서술하지 않는다. 핵심은 `kotlin-spring-guide` — 증상(OOMKilled, 동시 요청 64 초과 시 지연 급증, `UnexpectedRollbackException`, `HHH90003004`, 스택 없는 NPE 등)을 고정 ID(`JVM-GC-02`, `KT-CORO-03`, `SPR-JPA-05` …)를 가진 **67개 스페셜리스트 항목**으로 연결하는 인덱스다. 각 항목은 적용 조건(JDK/Spring/라이브러리 버전·환경), 신호, 메커니즘, 처방, 반례, 검증 방법, 근거 URL 을 가져서 맞는 곳에만 적용되고, `workflow:project-rules` 가 프로젝트별로 선별할 수 있다.

스택을 단정하지 않는다: 스킬·커맨드·두 에이전트 모두 빌드 파일, Dockerfile/매니페스트, 기존 코드를 먼저 읽어 JDK·Boot 버전, 데이터 접근 기술, 웹 스택, 마이그레이션 도구를 확정한다.

언어 중립 백엔드 주제(API 계약, 마이그레이션 안전성, 보안 등)는 `backend-shared` 소관.

## 구성요소

### 스킬

- `kotlin-spring-guide` — 스페셜리스트 트리아지(진입 스킬, 두 에이전트가 사전 로드). `SKILL.md` 는 사실 확인 표 + 증상 → 항목 ID 인덱스이고 상세는 1단계 `references/` 에 있다.
  - `jvm-gc-memory.md` — JVM-GC-01~09, JVM-MEM-01~04 (소형 컨테이너 Serial GC, MaxRAMPercentage, JDK 19 CPU shares 변경, 압축 OOP 32GB 경계, G1 humongous, JDK 버전별 세대형 ZGC, Shenandoah 배포판, DisableExplicitGC 와 다이렉트 버퍼, glibc 아레나, 한글 문자열과 Compact Strings, Compact Object Headers, OOM 힙 덤프)
  - `collections.md` — JVM-COL-01~06, KT-COL-01~03·05~06 (HashMap 용량 vs threshold, 트리화 조건, EnumMap/EnumSet, IdentityHashMap, LRU 의 get 구조 변경, CHM computeIfAbsent, Kotlin Linked 기본값, 박싱·원시 맵, Sequence 손익분기, Kotlin 1.6 minus/removeAll 의 Set 변환 제거, value class 박싱)
  - `concurrency.md` — KT-CORO-01~06, JVM-CONC-01~05 (Dispatchers.IO 64 상한·limitedParallelism, runBlocking, 취소 삼킴, withTimeout, MDC·트랜잭션 컨텍스트 유실, 가상 스레드 pinning·JEP 491, Boot 실행기 기본값, commonPool, false sharing)
  - `jit-allocation.md` — JVM-JIT-01~07, KT-LOG-01 (이스케이프 분석 한계, 메가모픽 콜사이트, 정규식 재컴파일과 Kotlin/Java split 차이, 예외 비용, OmitStackTraceInFastThrow, 코드 캐시, CDS/AOT 워밍업, 로그 템플릿)
  - `spring-data-tx.md` — SPR-TX-01~05, SPR-JPA-01~06, SPR-POOL-01~03 (plugin.spring/allOpen 프록시, 자기 호출·Spring 6 가시성, checked 예외 롤백, rollback-only, readOnly 라우팅, open-in-view, 메모리 페이징, batch fetch, 대량 쓰기, isNew merge, 대량 조회 시 드라이버 ResultSet 전체 버퍼링, Hikari 크기, 풀 교착, maxLifetime)
  - `spring-runtime.md` — SPR-JSON-01~03, SPR-OPS-01~02, KT-VAL-01 (ObjectMapper 재사용, Boot 4 의 Jackson 2 vs 3, Kotlin 모듈 null 시맨틱, k8s graceful shutdown, 메트릭 카디널리티, Bean Validation 애노테이션 use-site target)
  - `observability.md` — JVM-OBS-01~03 (JFR 상시 기록, async-profiler 모드, GC/safepoint 로그)
  - `team-conventions.md` — 팀 고유 네이밍·리뷰 결정과 코드 생성 기본값(프로젝트에 자체 컨벤션이 없을 때만)

### 커맨드

- `/spring-gen [도메인명]` — Entity → Repository → Service → Controller → DTO → Test 스캐폴딩. 사용자 직접 호출 전용(`disable-model-invocation`). 생성 전 Phase 1 에서 스택을 감지(빌드 파일, 컴파일러 플러그인, 데이터 접근, 웹 스택, 테스트 라이브러리, 마이그레이션 도구, 기존 도메인 샘플)하고, 감지된 컨벤션이 동봉 예시보다 우선한다. 옵션: `--fields`, `--layers`, `--no-test`, `--reactive`, `--soft-delete`, `--audit`.

### 에이전트

- `spring-developer` — `/spring-gen` 의 생성 엔진. 컨벤션 감지 → 생성 → 관련 함정 ID(SPR-TX-01, SPR-JPA-05, KT-CORO-03 …) 점검 → 컴파일·테스트.
- `spring-boot-guide` — 읽기 전용 런타임 진단. 사실 확인 → 증상을 항목 ID 로 매핑 → 적용 조건·반례로 탈락 → 코드 증거 수집 → 처방 전 구체 측정 제시.

## 사용법

```
/plugin install kotlin-spring@dokkabei-harness

/spring-gen Order
/spring-gen Product --fields "name:String, price:BigDecimal, stock:Int"
/spring-gen Notification --reactive
```

`kotlin-spring-guide` 는 Kotlin/Spring 의 성능·메모리·GC·동시성·트랜잭션 질문과 핫 경로·트랜잭션 코드 리뷰에서 쓰인다. 프로젝트에 중요한 항목은 `workflow:project-rules` 로 그 프로젝트의 `CLAUDE.md`/`.claude/rules` 에 고정한다.

## 의존성

- `backend-shared` (언어 중립 백엔드 패턴).

## 참고

- 2026-10 정리로 `archive/components/kotlin-spring/` 로 이동: `spring-boot-patterns`·`naming-conventions` 스킬(범용 관용구 — 팀 고유 네이밍 규칙은 `references/team-conventions.md` 로 병합), 범용 `layer-patterns`/`jpa-patterns`/`testing-patterns` 레퍼런스.
- `/spring-gen` 은 확인 없이 기존 파일 수정·빌드 의존성 추가를 하지 않고, 비즈니스 로직은 `TODO(human)` 으로 남긴다.
