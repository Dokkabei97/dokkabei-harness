> [English](README.md) · **한국어**

# feature-loop

> 기존(브라운필드) 코드베이스에 자연어 기능 요청 한 줄을 얹어 회귀 없이 완주시키는 루프 엔지니어링 하네스.

## 개요

`feature-loop`는 이미 개발 중이거나 완료된 프로젝트에 기능을 추가·수정할 때, "이 기능 추가해줘" 같은 자연어 요청 한 줄을 **코드베이스 분석 기반 작업 분해(`tasks.json`) → baseline 캡처 → 회귀 안전 개발 루프**로 자율 완주시키는 오케스트레이터다. 핵심 명제는 **"완료 판정은 모델이 아니라 하네스가 한다"**이며, 브라운필드에 맞춰 **"회귀 없음도 하네스가 baseline 대비로 판정한다"**를 더한다.

설계상 `mvp` 하네스의 검증된 루프 인프라(Stop훅 루프 엔진 + maker/checker 반증 검증 + 가드레일 + `.planning/` 메모리)를 재사용하되, 두 지점을 브라운필드로 교체한다. 입력은 PRD 생성이 아니라 **작업 분해**이고, 게이트는 생성 검증이 아니라 **baseline 회귀 방지**다. 루프 안에서는 스택 플러그인(`kotlin-spring`·`python-fastapi`·`go-mux`·`nextjs`)·`analyze`(checker 렌즈)·`test`(tdd/e2e)·`workflow`(spec/ship)를 필요에 따라 호출한다.

경계가 분명하다. **빈/신규 레포의 기획부터 시작하는 그린필드 신규 서비스에는 발동하지 않으며, 그 경우는 `mvp` 플러그인(`/mvp-new`)에 위임한다.** 사용자 개입은 작업 목록 승인(★G1) 게이트 1개로 최소화되어 있다.

## 구성요소

### 커맨드

- `/floop-new` — 하네스 진입점. 자연어 기능 요청 한 줄을 받아 Stage A(인테이크 + 스택 감지 + baseline 캡처) → Stage B(코드베이스 분석 기반 작업 분해 + ★G1 작업 목록 승인)를 게이트 상태기계로 실행한다. 브라운필드 전용이며 `--worktree`로 전용 git worktree 격리 시작을 지원한다.
- `/floop-run` — 개발 루프(Stage C) 시작/재개. 마스터 파일 status 기반 재개 프로토콜을 수행한 뒤 `loop-active` 플래그와 `loop-state.json`을 초기화하고 Stop훅 루프 엔진에 진입한다. `--max-iter`로 이번 가동 반복 상한을, `--headless`로 무인 러너 실행을 다룬다.
- `/floop-status` — 진행 현황 읽기 전용 조회. task passes n/m, 반복 수·상한, 경과 시간, baseline 상태, verified 마커, BLOCKED 여부, `loop-active` 잔존 여부를 1화면으로 보고한다. 어떤 상태도 변경하지 않는다.
- `/floop-stop` — 루프 안전 중단(킬스위치). `loop-active`를 삭제해 Stop훅 루프 엔진을 즉시 무력화하고, 현 task 상태를 `progress.md`에 핸드오프 기록한 뒤 마스터 status를 `paused`로 전환한다. 가드레일과 별개의 수동 중단 수단이며 멱등 동작이다.
- `/floop-gate` — 현 Stage 게이트 수동 (재)실행. 마스터 파일에서 Stage를 판별해 해당 결정론 게이트 스크립트(`hooks/gates/*.sh`)를 실행하고 baseline 회귀를 점검한 뒤 `feature-verifier`를 디스패치해 ✅통과/⚠️실패/❓모호로 보고한다. Stage 전이나 산출물 수정은 하지 않는다.

### 에이전트 (전원 `opus`)

- `task-planner` — 브라운필드 작업 분해 maker. 자연어 요청을 기존 코드베이스 분석(영향 범위·기존 패턴·재사용 지점)을 근거로 수직 슬라이스 단위 `tasks.json`으로 분해한다. 각 AC는 `feature-verifier`가 반증 가능한 Given-When-Then 검증형 문장이며 1 task = 1 루프 반복 크기다.
- `feature-builder` — 개발 루프 maker 규율. 기본 모드는 메인 세션이 규율을 체화해 직접 수행한다. 미완(`passes:false`) task를 한 번에 1개만 골라 테스트 먼저 작성 후 최소 구현으로 게이트 그린(신규 AC green AND baseline 회귀 0)을 만들고, 검증 통과 후 구현·`tasks.json`·`progress.md`를 `feat: T-xx` 1커밋으로 마감한다. 병렬 구현 시에만 worktree 격리 서브에이전트로 디스패치된다.
- `feature-verifier` — 회의적 검증자(checker). maker와 완전 분리되어 삼중 반증(① task AC 반증 ②ᴿ baseline 대비 회귀 반증 ③ 테스트 사기 적발)을 수행한다. **의도적으로 `Edit` 도구를 보유하지 않아** 검증자가 대상을 직접 고쳐 통과시키는 경로를 원천 차단하며, 반증 실패 시에만 `.planning/verified/{task-id}` 마커를 생성한다.

### 스킬

- `feature-loop-orchestrator` — 하네스 오케스트레이터. 자연어 요청을 Stage A~C 게이트 상태기계로 자율 완주시키고 각 Stage의 maker/checker를 전문 에이전트에 위임한다. `/floop-new`·`/floop-run` 실행이나 브라운필드 기능 추가·수정 요청 시 적용된다.
- `floop-loop-protocol` — Stage C 개발 루프 운영 규약. 매 반복 표준 사이클, `/floop-run` 재개 프로토콜 4단계, 정지조건 결합, 환경변수 튜닝, `loop-active` 수명주기, 가드레일 5종, BLOCKED 에스컬레이션을 정의한다. `references/worktree-lanes.md`에 worktree 격리→병렬 레인→Agent Teams 3단계 로드맵을 담는다.
- `task-decomposition` — 작업 분해 표준. 수직 슬라이스 사이징, Given-When-Then 검증형 AC 작성법, 회귀 보존 AC 의무, `tasks.json` 스키마와 jq 검증식, `gate-tasks.sh` 통과 기준(id `^T-[0-9]{2}$` · 개수 2~10 · 전건 `passes:false`)을 규정한다.

### 훅

- `SessionStart` → `floop-session-init.sh` — 진행 중 feature-loop(마스터 파일 status `in_progress`) 감지 시에만 재개 안내 컨텍스트를 주입하고, 그 외에는 무동작한다.
- `Stop` → `floop-loop-stop-hook.sh` — 루프 엔진. `loop-active` 존재 시에만 정지조건 결합(게이트 그린 + baseline 회귀 0 + verified 마커 + completion promise)을 검증하고, 미충족 시 exit 2로 재주입해 루프를 지속시킨다.
- `PreCompact` → `precompact-anchor.sh floop` — compaction 직전 루프 재개 앵커. `loop-active`가 있고 floop 엔진일 때만 마스터 경로·다음 대상·게이트·반복·규율을 5줄 이내로 출력하고, 일반 세션에는 개입하지 않는다.
- `SubagentStop` → `subagent-stop-verify.sh floop` — verifier 결과 기록 집행. `verify-round/{id}` pending 상태에서 verified/refuted 마커 없이 종료하면 exit 2로 재주입한다(최대 2라운드).
- `PreToolUse(Bash)` → `test-guard.sh` — 루프 활성 중 테스트 파일 삭제를 차단해 회귀 게이트 신뢰성을 결정론적으로 지킨다(`rm test|spec` 패턴 필터는 스크립트 내부).
- `PostToolUse(Edit|Write)` → `tasks-guard.sh` — maker/checker 분리 강제. verified 마커 없는 `passes:true`를 exit 2로 차단하고 `false`로 되돌린다.

### 기타 구성

- `bin/floop-headless.sh` — 무인/야간 배치용 헤드리스 러너(컨텍스트 리셋형 Ralph 패턴). 외부 `while` 루프가 매 반복 `claude -p`를 새로 띄우며, Stop훅 엔진과 동일 `.planning`·동일 게이트(②ᴿ baseline 회귀 게이트 포함)를 공유하는 보조 엔진이다.
- `hooks/gates/capture-baseline.sh`, `hooks/gates/gate-tasks.sh` — 결정론 게이트 스크립트. 훅에 등록되지 않고 오케스트레이터/커맨드가 Bash로 호출한다(baseline 캡처 · tasks.json 스키마 게이트).

## 사용법

1. **시작** — 기존 코드베이스에서 `/floop-new "<기능 요청 한 줄>"`을 호출한다. Stage A에서 스택을 감지하고 baseline을 캡처한 뒤, Stage B에서 `tasks.json`을 분해하고 ★G1(작업 목록 승인) 게이트에서 사용자 확인을 받는다. `--worktree`로 전용 worktree/브랜치에서 격리 시작할 수 있고, `--gate-cmd`·`--e2e-cmd`·`--tasks-max`로 게이트 명령과 task 상한을 조정한다.
2. **루프 가동** — `/floop-run`으로 Stage C 개발 루프에 진입한다. Stop훅 루프 엔진이 매 반복마다 미완 task 1개를 test-first로 구현→검증→커밋하고, 정지조건을 스스로 판정한다.
3. **정지조건(결합)** — ① 결정론 게이트 그린(exit 0 + 실패 표지 보정) ∧ jq all-passes, ②ᴿ baseline 회귀 0, ② verified 마커, ②ᴱ E2E 수용 게이트 그린(설정 시), ③ `<promise>FEATURE_COMPLETE</promise>`가 모두 충족될 때만 루프가 종료된다.
4. **상태/중지** — 언제든 `/floop-status`로 현황을 읽고, `/floop-stop`으로 즉시 안전 중단(paused 전환 + 핸드오프)한다. 중단된 루프는 `/floop-run`이 재개 프로토콜로 이어받는다.

자동 발화: `feature-loop-orchestrator` 스킬은 "이 기능 추가해줘", "X 리팩토링", "이 코드베이스에 Y 붙여줘"처럼 이미 코드가 있는 프로젝트의 기능 작업 요청에 트리거된다. 빈/신규 레포 요청에는 발동하지 않는다.

## 의존성

- `requires`: `base`
- 함께 쓰면 좋은 플러그인: 스택 플러그인(`kotlin-spring`·`python-fastapi`·`go-mux`·`nextjs`), `analyze`(checker 렌즈), `test`(tdd/e2e), `workflow`(spec/ship). 그린필드 신규 서비스는 `mvp`로 위임한다.

## 참고

- **가드레일**: 루프는 max-iter(기본 24) · no-progress(2회) · 시간 상한(기본 120분)을 포함한 5종 안전장치로 무한 반복을 막는다. `/floop-stop`은 이와 별개의 수동 킬스위치다.
- **환경변수**(루프 튜닝): `LOOP_TEST_CMD` · `LOOP_E2E_CMD` · `LOOP_PROMISE` · `LOOP_MAX_ITER` · `LOOP_MAX_MINUTES`.
- **worktree 격리**는 stage①(구현됨)이며 순차 루프 불변이다. 병렬 레인(stage②)·Agent Teams(stage③)는 로드맵 단계로 기본 비활성이다(`references/worktree-lanes.md`).
- **회귀 게이트 신뢰 보존**: 기존 테스트의 삭제·약화·기대값 역수정은 훅과 verifier가 차단한다. 유료 플랜/토큰 소비를 전제로 하는 자율 루프이므로, 특히 `--headless` 무인 실행 시 반복 상한과 게이트 명령을 확인하고 가동하라.
