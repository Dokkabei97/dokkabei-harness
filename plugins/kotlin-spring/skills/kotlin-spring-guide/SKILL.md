---
name: kotlin-spring-guide
description: |
  JVM·Kotlin·Spring 스페셜리스트 트리아지 — GC 선택·튜닝(G1/ZGC/Shenandoah, 컨테이너 힙·OOMKilled), HashMap 용량·박싱·EnumMap, 코루틴 Dispatchers.IO·취소·MDC 유실, 가상 스레드 pinning, @Transactional·readOnly·JPA N+1·HikariCP 풀, Jackson, JFR·async-profiler. 증상에서 함정 항목(ID)으로 안내.
  Specialist triage for JVM/Kotlin/Spring pitfalls strong seniors miss: GC and container memory, map/collection choice, coroutines and virtual threads, transactions/JPA/pool, profiling. Use when: Kotlin/Spring performance, memory, latency, GC or concurrency issues, or reviewing hot-path or transactional code.
---

# JVM · Kotlin · Spring 스페셜리스트 트리아지

범용 관용구(data class, null safety, 레이어 의존 방향, 기본 JPA 사용법)는 다루지 않는다.
이 스킬은 **강한 시니어 제너럴리스트도 놓치는 함정**을 증상에서 찾아 들어가는 인덱스다.
각 항목은 `적용 / 신호 / 메커니즘 / 처방 / 반례 / 검증 / 근거` 를 가진다 — 처방 전에 `적용` 조건과 `반례` 를 반드시 대조한다.

## 0. 먼저 프로젝트 사실을 확인 (단정 금지)

항목을 적용하기 전에 아래를 읽어 사실로 확정한다. 확인할 수 없으면 가정을 명시하고 진행한다.

| 확인 대상 | 어디서 |
|---|---|
| JDK 메이저 버전·배포판 | Dockerfile 베이스 이미지, `toolchain`/`jvmTarget`(build.gradle.kts), `java -version` |
| Spring Boot/Framework·Kotlin·kotlinx.coroutines 버전 | `build.gradle.kts`, `gradle/libs.versions.toml` |
| 데이터 접근 기술 | 의존성(spring-data-jpa / jooq / jdbc / r2dbc / exposed), 기존 Repository 코드 |
| 마이그레이션 도구 | 의존성·디렉터리(flyway / liquibase / 기타) — 추측하지 않는다 |
| 웹 스택 | spring-boot-starter-web(MVC) vs webflux, `spring.threads.virtual.enabled` |
| 배포 환경 | k8s 매니페스트/Helm values 의 requests·limits, JVM 옵션(`JAVA_TOOL_OPTIONS`) |
| 프로젝트 규칙 | 프로젝트 `CLAUDE.md`, `.claude/rules/` — 이 스킬보다 우선 |

프로젝트별로 어떤 항목이 해당되는지 고정하고 싶으면 `workflow:project-rules` 로 항목 ID 를 프로젝트 규칙에 선별·기록한다.

## 1. 증상 → 항목

### 메모리·GC
| 증상 | 항목 |
|---|---|
| 컨테이너 OOMKilled(exit 137), 힙은 여유 | JVM-GC-02, JVM-MEM-01, JVM-GC-09 |
| 힙 OOM 인데 리밋 대비 힙이 너무 작다 | JVM-GC-02 |
| 1 vCPU 파드에서 GC pause 가 길다 | JVM-GC-01 |
| GC 스레드·풀 스레드가 비정상적으로 많다 | JVM-GC-03 |
| 힙을 32GB 이상으로 늘렸는데 개선이 없다 | JVM-GC-04 |
| GC 원인 `G1 Humongous Allocation` | JVM-GC-05 |
| ZGC 전환 후 `Allocation Stall` / 메모리 증가 | JVM-GC-06 |
| Shenandoah 옵션으로 기동 실패 | JVM-GC-07 |
| pause 목표를 낮췄더니 처리량 하락 | JVM-GC-08 |
| `direct buffer memory` OOM | JVM-GC-09 |
| 한국어 데이터 메모리 추정이 2배 틀림 | JVM-MEM-02 |
| 작은 객체가 힙 대부분 | JVM-MEM-03, KT-COL-02 |
| OOM 원인 분석용 덤프가 없다 | JVM-MEM-04 |

### 자료구조·컬렉션
| 증상 / 코드 패턴 | 항목 |
|---|---|
| 대량 적재 시 `HashMap.resize` 핫스팟 | JVM-COL-01 |
| 맵 조회가 키 수에 비례해 느려짐(해시 충돌) | JVM-COL-02 |
| enum 키 HashMap/HashSet | JVM-COL-03 |
| 객체 그래프 방문 집합, 비싼 equals | JVM-COL-04 |
| LinkedHashMap LRU 캐시의 CME/손상 | JVM-COL-05 |
| `Recursive update`, CHM 계산 중 대기 | JVM-COL-06 |
| `mutableMapOf` 대형 상주 맵 | KT-COL-01 |
| `List<Int>`/`Map<Long, V>` 대형 | KT-COL-02 |
| Sequence 를 쓸지 말지 | KT-COL-03 |
| Kotlin 업그레이드 후 `list - list`/`removeAll(list)` 느려짐 | KT-COL-05 |
| value class 컬렉션·프레임워크 호환 | KT-COL-06 |

### 동시성
| 증상 / 코드 패턴 | 항목 |
|---|---|
| 동시 요청 64 넘으면 지연 급증, IO 워커 전부 대기 | KT-CORO-01 |
| 요청 경로의 `runBlocking`, 교착 | KT-CORO-02 |
| suspend 를 `catch (e: Exception)`/`runCatching` 으로 감쌈 | KT-CORO-03 |
| 타임아웃이 조용히 끝남 / 블로킹 호출이 안 끊김 | KT-CORO-04 |
| 코루틴 로그에 traceId 없음, 트랜잭션 밖 실행 | KT-CORO-05 |
| CPU 낮은데 느림, Default 워커 BLOCKED | KT-CORO-06 |
| 가상 스레드 도입 후 처리량 정체 | JVM-CONC-01 |
| 가상 스레드 도입 후 커넥션 타임아웃 | JVM-CONC-02 |
| `@Async` 스레드가 안 늘어남 | JVM-CONC-03 |
| `supplyAsync`/`parallelStream` 안 I/O | JVM-CONC-04 |
| 공유 카운터 경합 | JVM-CONC-05 |

### JIT·할당·예외
| 증상 / 코드 패턴 | 항목 |
|---|---|
| 핫 경로 작은 객체 할당 | JVM-JIT-01 |
| `itable/vtable stub`, 공용 람다 콜사이트 | JVM-JIT-02 |
| `Pattern.compile` 핫스팟, Kotlin/Java split 차이 | JVM-JIT-03 |
| `fillInStackTrace` 핫스팟 | JVM-JIT-04 |
| 스택 없는 NPE 로그 | JVM-JIT-05 |
| 장기 실행 후 서서히 느려짐, CodeCache full | JVM-JIT-06 |
| 배포 직후 p99 급등 | JVM-JIT-07 |
| debug 로그 문자열 템플릿 | KT-LOG-01 |

### Spring·데이터 접근
| 증상 / 코드 패턴 | 항목 |
|---|---|
| final 클래스 프록시 실패, LAZY 가 즉시 로딩 | SPR-TX-01 |
| `@Transactional` 이 안 먹음(자기 호출·가시성) | SPR-TX-02 |
| 예외가 났는데 커밋됨 | SPR-TX-03 |
| `UnexpectedRollbackException` | SPR-TX-04 |
| readOnly 레플리카 라우팅 실패 | SPR-TX-05 |
| 컨트롤러에서 lazy 로딩, 풀 고갈 | SPR-JPA-01, SPR-POOL-01 |
| `HHH90003004` 메모리 페이징 | SPR-JPA-02 |
| N+1, `MultipleBagFetchException` | SPR-JPA-03 |
| 대량 insert 가 느림, 배치 루프가 점점 느려짐 | SPR-JPA-04 |
| INSERT 전 SELECT | SPR-JPA-05 |
| 대량 SELECT·Stream 조회 중 힙 OOM | SPR-JPA-06 |
| 풀 크기 산정 | SPR-POOL-01 |
| 부하 시 `getConnection` 일제 타임아웃 | SPR-POOL-02 |
| 유휴 후 첫 요청 `Connection reset` | SPR-POOL-03 |
| ObjectMapper 직접 생성, 직렬화 포맷 불일치 | SPR-JSON-01 |
| Boot 4 업그레이드 후 커스텀 Jackson 미적용 | SPR-JSON-02 |
| 누락 필드 vs null 처리 차이 | SPR-JSON-03 |
| 배포 중 502 | SPR-OPS-01 |
| Prometheus 응답 비대, Meter 증가, `Reached the maximum number of URI tags` | SPR-OPS-02 |
| `@Valid` 인데 검증이 안 됨(`@NotBlank` 무시) | KT-VAL-01 |

### 측정
| 상황 | 항목 |
|---|---|
| 상시 사후 분석 기반 | JVM-OBS-01, JVM-OBS-03 |
| 미시 최적화 효과 판단 | JMH `-prof gc` (observability.md 하단) |
| 프로파일링 모드 선택 | JVM-OBS-02 |

## 2. 레퍼런스 파일

| 파일 | ID |
|---|---|
| `references/jvm-gc-memory.md` | JVM-GC-01~09, JVM-MEM-01~04 |
| `references/collections.md` | JVM-COL-01~06, KT-COL-01~03·05~06 |
| `references/concurrency.md` | KT-CORO-01~06, JVM-CONC-01~05 |
| `references/jit-allocation.md` | JVM-JIT-01~07, KT-LOG-01 |
| `references/spring-data-tx.md` | SPR-TX-01~05, SPR-JPA-01~06, SPR-POOL-01~03 |
| `references/spring-runtime.md` | SPR-JSON-01~03, SPR-OPS-01~02, KT-VAL-01 |
| `references/observability.md` | JVM-OBS-01~03 |
| `references/team-conventions.md` | 팀 네이밍·리뷰 규칙, 코드 생성 기본값 |

필요한 파일만 읽는다. 항목을 인용할 때는 ID 를 함께 적어 추적 가능하게 한다.

## 3. 적용 원칙

- **측정 먼저**: 성능 항목은 `검증` 필드의 측정 없이 처방하지 않는다. 리뷰에서는 "신호 일치 → 측정 제안"으로 말한다.
- **버전 게이트**: `적용` 의 JDK/Spring/라이브러리 버전이 0단계 확인 결과와 맞지 않으면 그 항목은 제외한다.
- **반례 존중**: 반례에 해당하면 적용하지 않는다 — 과최적화는 가독성 비용만 남긴다.
- 버전 민감 API 는 `backend-shared:context7-docs-guide` 규약으로 최신 문서를 조회한다(미설치 시 근거 URL 확인).
- 언어 중립 백엔드 주제(API 계약, 마이그레이션 안전성, 보안 등)는 `backend-shared` 소관.
