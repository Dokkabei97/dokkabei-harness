---
name: tdd-workflow
description: |
  TDD·테스트 작성 가이드 — 실패 테스트 먼저(RED→GREEN→REFACTOR), 버그 재현 테스트, flaky·느린 테스트, 커버리지 해석, Kotest/MockK/Spring 컨텍스트 캐시, Go table test·-race·synctest, Vitest/Jest, pytest 롤백 격리, Testcontainers 함정 인덱스.
  Test-first guide plus a triage index of testing pitfalls specialists know (Spring context cache, Kotest hooks, runTest virtual time, Go test cache/synctest, fake timers, DB rollback isolation, ES refresh, mutation testing).
  Use when: writing tests first, reproducing a bug with a test, flaky or slow tests, coverage questions, TDD.
---

# TDD Workflow

테스트를 먼저 써서 "무엇이 완료인가"를 실행 가능한 기준으로 고정하는 가이드. 사이클 자체는 짧게 두고,
본문은 **현장에서 시니어도 자주 놓치는 테스트 함정**으로 가는 인덱스 역할을 한다.

## 0. 먼저 프로젝트를 확인

스택·도구를 단정하지 말 것. 테스트를 쓰기 전에 아래를 읽고 기존 컨벤션을 따른다.

- 빌드 파일: `build.gradle.kts`/`pom.xml`, `go.mod`(go 디렉티브 버전), `package.json`, `pyproject.toml`
- 기존 테스트 1~2개: 프레임워크(Kotest vs JUnit5, Vitest vs Jest, pytest 플러그인), mock 라이브러리, 픽스처 위치
- 프로젝트 `CLAUDE.md`/`.claude/rules`/CONTRIBUTING: 커버리지 기준·테스트 명령·통합 테스트 인프라
- 테스트 실행 명령을 **한 번 실제로 돌려** 현재 그린인지 확인(이미 깨진 테스트 위에 쌓지 않기)

## 1. 사이클

```
RED      실패하는 테스트 1개 — 실패 이유가 "기능 없음"인지 확인 (컴파일 에러·오타로 인한 실패는 RED 아님)
GREEN    통과시키는 최소 코드
REFACTOR 그린 유지하며 정리 — 테스트도 리팩터 대상
반복     다음 시나리오(경계값·에러 경로)
```

- RED 를 **눈으로 확인**하는 것이 핵심이다. 처음부터 통과하는 테스트는 아무것도 증명하지 않는다
  (assert 누락, 잘못된 대상 호출, 캐시된 결과 — TST-GO-01, TST-JVM-09).
- 한 번에 한 행위. 여러 행위를 한 테스트에 넣으면 실패 메시지가 원인을 가리키지 못한다.
- 인터페이스를 먼저 스캐폴드할 때는 구현을 `TODO()`/`panic("not implemented")`/`throw` 로 둬서 RED 를 보장.

## 2. 버그 수정 = Prove-It

1. 버그를 재현하는 테스트를 먼저 쓴다 → **버그 때문에** 실패하는지 확인
2. 수정 → 통과
3. 전체 스위트로 회귀 확인

재현 테스트는 수정 내용을 모르는 상태에서 쓰는 편이 견고하다. 복잡한 버그면 재현 테스트 작성을
서브에이전트에 분리해 맡기는 것도 방법이다. 재현이 안 되면 수정하지 말고 재현 조건(시간·순서·동시성·데이터)을 먼저 좁힌다.

## 3. 무엇을 어느 레벨에서

| 질문 | 레벨 |
|------|------|
| 부수효과 없는 순수 로직인가 | 단위 |
| DB/큐/검색엔진 쿼리·매핑이 맞는지가 핵심인가 | 실제 의존성 통합 테스트 (Testcontainers 등) |
| 사용자 여정 전체인가 | E2E (`/e2e`, `e2e-chrome` 스킬) |

비율(피라미드 80/15/5 등)은 출발점일 뿐이다. 쿼리·매핑이 로직의 대부분인 서비스는 통합 테스트 비중이 더 큰 게 맞다.

Test double 선호: **Real > Fake(in-memory) > Stub > Mock(상호작용 검증)**. Mock 은 실제 구현이 느리거나
비결정적이거나 통제 불가한 부수효과가 있을 때만. DB 를 mock 하면 SQL·매핑·제약 위반을 하나도 검증하지 못한다.

테스트 코드는 DRY 보다 **DAMP**(각 테스트가 공유 헬퍼를 따라가지 않아도 읽히게). 픽스처 빌더는 "기본값 + 이 테스트에서 의미 있는 필드만 명시" 형태로.

## 4. 커버리지

- 팀/프로젝트 기준이 있으면 그것을 따른다. 없으면 80% 는 **출발점 제안**이지 목표가 아니다.
- 커버리지는 "실행됨"의 증거지 "검증됨"의 증거가 아니다. 변경한 분기·에러 경로가 덮였는지를 본다.
- 결제·인증·권한 같은 핵심 경로는 라인 % 대신 **경계값·에러 경로 시나리오 목록**으로 점검하고, 필요하면 뮤테이션 테스트(TST-COV-02).

## 5. 증상 → 레퍼런스 트리아지

| 증상 / 상황 | 항목 | 파일 |
|------------|------|------|
| Spring 테스트 스위트가 갈수록 느림, 컨텍스트가 여러 번 뜸 | TST-JVM-01, 02 | [jvm-kotlin.md](references/jvm-kotlin.md) |
| `@SpringBootTest(RANDOM_PORT)` 테스트 후 DB 데이터가 남음 | TST-JVM-03 | jvm-kotlin.md |
| JPA 테스트는 그린인데 운영에서 제약 위반·LazyInit 예외 | TST-JVM-04 | jvm-kotlin.md |
| Kotest BehaviorSpec 에서 mock stub 이 사라지거나 상태가 테스트 간 샘 | TST-JVM-05, 06 | jvm-kotlin.md |
| `mockkObject`/`mockkStatic` 이후 무관한 테스트가 깨짐 | TST-JVM-07 | jvm-kotlin.md |
| `runTest` 인데 delay 가 실제로 기다림 / 타임아웃 | TST-JVM-08 | jvm-kotlin.md |
| Gradle 테스트가 "실행 안 됐는데" 그린, JDK 올린 뒤 JaCoCo 실패 | TST-JVM-09, 10 | jvm-kotlin.md |
| Mockito vs MockK 선택, `@MockBean` deprecated 경고 | TST-JVM-11 | jvm-kotlin.md |
| Go 테스트가 수정했는데도 같은 결과(캐시) | TST-GO-01 | [go.md](references/go.md) |
| table test + `t.Parallel()` 이 마지막 케이스만 검증 | TST-GO-02 | go.md |
| `t.Setenv` panic, 병렬 테스트 간 전역 상태 오염 | TST-GO-03, 04 | go.md |
| 타이머·타임아웃·재시도 로직 테스트가 느리거나 flaky | TST-GO-05 / TST-TS-01 / TST-JVM-08 | go.md · typescript.md · jvm-kotlin.md |
| 바이너리 통합 테스트 커버리지 수집 | TST-GO-06 | go.md |
| 테스트 종료 후에도 goroutine 이 살아있음, 테스트용 context | TST-GO-07 | go.md |
| fake timer + Promise 에서 테스트가 멈춤 | TST-TS-01 | [typescript.md](references/typescript.md) |
| `vi.mock`/`jest.mock` 이 안 먹거나 변수 참조 에러 | TST-TS-02 | typescript.md |
| Next.js async Server Component 단위 테스트 | TST-TS-03 | typescript.md |
| IntersectionObserver·가상 스크롤·크기 의존 UI 테스트가 무의미하게 통과 | TST-TS-04 | typescript.md |
| mock·spy 상태가 테스트 간 샘(TS) | TST-TS-05 | typescript.md |
| pytest DB 롤백 격리가 깨짐, xdist 병렬에서 충돌 | TST-PY-01, 02 | [python.md](references/python.md) |
| pytest-asyncio "attached to a different loop" 에러 | TST-PY-03 | python.md |
| 색인 직후 검색하면 0건(ES), 랭킹 assert 가 가끔 깨짐 | TST-INT-01, 02 | [integration-data.md](references/integration-data.md) |
| ES 8 Testcontainers 연결 실패(SSL/인증) | TST-INT-03 | integration-data.md |
| Testcontainers 가 테스트 클래스마다 재시작돼 느림 | TST-INT-04 | integration-data.md |
| 시간·난수·순서 의존 flaky | TST-INT-05, 06 | integration-data.md |
| 커버리지는 높은데 버그가 샘 | TST-COV-01, 02 | [coverage-mutation.md](references/coverage-mutation.md) |

브라우저 E2E·시각 검증은 `e2e-chrome` 스킬(Playwright 함정 포함), 스택 고유의 성능·GC·동시성 지식은 각 스택 플러그인 가이드
(`kotlin-spring-guide`, `go-mux-guide`, `python-fastapi-guide`, `nextjs-guide`, `es-deep-patterns`)를 본다.

## 6. 흔한 자기합리화

| 말 | 현실 |
|----|------|
| "구현 끝나고 테스트 쓸게" | 사후 테스트는 구현을 베껴 쓰기 쉽다 — 동작이 아니라 현재 코드를 검증한다 |
| "수동으로 확인했다" | 다음 변경 때 아무도 다시 확인하지 않는다 |
| "너무 단순해서 불필요" | 단순한 코드는 테스트도 단순하다 — 비용이 낮을 때 고정해 둔다 |
| "flaky 라서 재시도 걸었다" | 재시도는 증상을 숨긴다. 원인(시간·순서·공유 상태·비동기 대기)을 찾는다 |

## 7. 루프와 연계

결정론 게이트가 필요하면 테스트 명령을 harness generic 루프에 넘긴다:
`/loop-run "<목표>" --gate-cmd "./gradlew test"` (또는 `go test ./...`, `pnpm test`).
빠른 단위 게이트를 먼저, 느린 E2E 는 뒤에 체이닝한다.
