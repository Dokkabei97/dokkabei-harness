# Headless Recipe — 무인/야간용 `while + claude -p` 루프

Stage 4 개발 루프의 **보조 엔진**. 기본 엔진(Stop훅 재주입)은 대화형 세션 안에서 돌지만, 이 레시피는 외부 셸 루프가 매 반복 `claude -p`를 새로 띄우는 **컨텍스트 리셋형(Ralph 패턴)** 이다. 무인 배치·야간 실행·스토리 10개 이상의 대형 MVP(단일 세션 컨텍스트 비대 회피)에 권장한다.

## 핵심 원칙

1. **동일 `.planning` · 동일 게이트 공유** — 정지 판정 규약은 Stop훅과 동일하다(has_failure_marker 포함): `gate-cmd` exit 0 + **실패 표지 보정**(has_failure_marker — exit 0이어도 출력에 행두 `FAIL` 또는 1 이상 실패 카운트가 있으면 레드) + `prd.json` all-passes + **verified 마커 재검사**(passes:true 각 id의 `.planning/verified/{id}` 존재) + (있으면, all-passes 도달 시에만) `e2e-gate-cmd` 동일 규약 판정 + `<promise>MVP_COMPLETE</promise>`. 엔진을 바꿔도 정지조건은 불변이다.
2. **매 반복 컨텍스트 리셋** — 각 `claude -p` 세션은 이전 반복을 모른다. 재개 프로토콜(마스터 파일 → `git log` → 미완 스토리 1개)로 아티팩트에서 이해를 재생성한다. 파일시스템과 git history만이 상태다.
3. **이중 가동 금지** — Stop훅 엔진과 동시에 돌리지 않는다. headless 모드에서는 `.planning/loop-active`를 **생성하지 않는다**: Stop훅의 안전핀(`loop-active` 부재 시 무동작)이 내부 세션의 정상 종료를 보장하고, 반복은 외부 `while`이 전담한다. `loop-active`가 이미 있으면 러너가 시작을 거부하고(exit 1), 러너 가동 중 출현해도 매 반복 재검사가 감지해 중단한다(exit 1). 러너끼리의 중첩 실행(크론 겹침)은 `.planning/headless-active` 락(PID 기록, 스테일 자동 정리)이 거부한다.
4. **세션당 스토리 1개** — 프롬프트가 "이번 세션에서는 스토리 1개만 처리하고 종료"를 강제한다. 작은 단위 + 잦은 커밋이 중단·재개를 안전하게 만든다.

## 동봉 러너

러너는 플러그인에 동봉된 **`bin/mvp-headless.sh`** 하나뿐이다 — 과거처럼 본 문서에 스크립트 본문을 복붙하지 않는다(문서/러너 소스 이원화 제거). 실행 경로는 `/mvp-run --headless`가 현재 설치 기준으로 출력하며, 아래 표에서는 `$RUNNER`로 표기한다. 전제(Stage 0~3 완료, `prd.json`·`gate-cmd` 존재, jq·claude CLI 설치)는 러너가 시작 시 스스로 검증하고 미충족이면 명확한 에러와 함께 exit 1로 거부한다.

원형 레시피 스크립트 대비 개선점 (판정 규약 전체는 러너 헤더 주석 참조):

- **전제조건 검증 강화**: jq·claude 바이너리·`.planning/prd.json`·`gate-cmd` 부재 시 exit 1 — 판정 불가 상태로 헛도는 루프를 만들지 않는다.
- **verified 마커 재검사**: 정지조건에 passes:true 각 id의 `.planning/verified/{id}` 존재 확인 추가 — Stop훅 ②(회의적 Evaluator) 최종 방어선과의 등가성 강화. 모델이 마커 없이 passes만 마킹해도 러너는 완료로 판정하지 않는다.
- **`LOOP_CLAUDE_BIN`**: claude 바이너리 주입(기본 `claude`) — 래퍼 스크립트·테스트 스텁 대체용.
- **판정 규약 통일**: 게이트·E2E 판정에 exit code 우선 + has_failure_marker 실패 표지 보정을 Stop훅과 공유 — `echo "3 failed"; exit 0` 같은 게이트도 두 엔진이 동일하게 레드로 판정한다.
- **gate-cmd 반복당 1회 실행**: 같은 출력·exit를 정지 판정과 no-progress 시그니처 산출에 재사용 — 무거운 스위트의 배치 시간 2배를 방지한다.
- **no-progress 정밀화**: 실패 시그니처를 단위 게이트 또는 E2E 레드일 때만 산출(그린 게이트에서의 정상 진행 오탐 제거)하고, Stop훅과 동일하게 E2E 출력을 `E2E:` 접두로 결합해 숫자 토큰 제거 정규화 후 md5로 비교한다.
- **이중 가동 방어 강화**: 매 반복 시작 시 `loop-active` 재검사(가동 중 Stop훅 루프가 켜지면 즉시 중단) + `.planning/headless-active` 락으로 러너끼리의 중첩 실행(크론 겹침)을 거부한다.
- **워치독**: `claude -p`를 백그라운드로 띄우고 폴링(기본 30초, `LOOP_WATCHDOG_INTERVAL`)으로 전역 시간 상한 초과 시 TERM→(최대 5초)→KILL — 세션이 행(hang)해도 시간 상한이 반복 도중 발동한다.

브라운필드용은 feature-loop 플러그인의 `bin/floop-headless.sh` — 동일 골격에 ②ᴿ baseline 회귀 게이트(기준선 대비 신규 실패 0)가 결합된다. `/floop-run --headless` 참조.

## 실행·재개·스케줄

아래 표의 `$RUNNER`는 동봉 러너 경로다 (정확한 경로는 `/mvp-run --headless` 출력 참조).

| 작업 | 방법 |
|------|------|
| 야간 무인 실행 | 프로젝트 루트에서 `nohup bash "$RUNNER" > .planning/headless.log 2>&1 &` |
| 가드 조정 | `LOOP_MAX_ITER=36 LOOP_MAX_MINUTES=300 bash "$RUNNER"` |
| **재개** | **같은 명령을 다시 실행** — 별도 재개 절차 없음. 정지조건·no-progress·시간 상한이 처음부터 재평가되고, 각 세션이 마스터+git에서 상태를 복구한다(어느 시점에 중단됐어도 안전) |
| 진행 확인 | 다른 터미널/세션에서 `/mvp-status` 또는 `jq '.stories[] | {id, passes}' .planning/prd.json` |
| 중단 | 셸 프로세스 종료(Ctrl-C/kill). `loop-active`를 쓰지 않으므로 잔존 플래그 정리 불필요 — `headless-active` 락은 EXIT trap이 정리하고, 강제 종료로 남아도 다음 실행이 스테일(죽은 PID) 락으로 판정해 자동 제거한다 |
| 크론 등록 | `MVP_PROJECT_DIR`(프로젝트 루트)·`MVP_RUNNER`(러너 경로) 환경변수를 지정해 crontab에 `cd "$MVP_PROJECT_DIR" && bash "$MVP_RUNNER"` 형태로 등록(절대경로 하드코딩 대신 env 사용) |

## 가드레일 대응표 (Stop훅 엔진과의 등가성)

| 가드 | Stop훅 엔진 | headless 엔진 |
|------|------------|---------------|
| max iterations | 훅이 `loop-state.json` iteration 검사 | 외부 `while` 카운터 (`LOOP_MAX_ITER`) |
| no-progress | 실패 시그니처 md5 연속 2회 | 동일 — 외부 루프가 단위 게이트 또는 E2E 레드의 실패 시그니처(E2E 출력 `E2E:` 접두 결합, 정규화 md5)를 직전 반복과 비교 |
| 시간 상한 | `loop-state.json` started_at 대비 | 동일 — 스크립트 시작 시각 대비 (`LOOP_MAX_MINUTES`). 반복 도중에는 워치독(기본 30초 폴링, `LOOP_WATCHDOG_INTERVAL`)이 행(hang)한 `claude -p`를 TERM→KILL로 강제 종료 후 같은 경로로 합류 |
| 킬스위치 | `/mvp-stop` (loop-active 삭제) | 셸 프로세스 종료 |
| circuit breaker | 오케스트레이터 정책(동일 스토리 3연속 skip) | 세션 내 동일 — 각 세션의 BLOCKED 기록이 다음 세션에 승계 |

## 주의

- `--permission-mode acceptEdits`는 무인 실행 전제다. 신뢰 가능한 그린필드 레포에서만 사용하고, 운영 자격증명이 있는 환경에서는 돌리지 않는다.
- 비용 상한이 곧 안전장치다: 반복·시간 상한 없이 돌린 Stop훅 루프가 $3600/day를 청구한 실제 사고가 있다. 기본값(24회/120분)을 지우지 말 것.
- 완료 판정은 promise 출력이 아니라 **외부 루프의 정지조건 검사(게이트 그린(실패 표지 보정 포함) + all-passes + verified 마커 + E2E 그린(있을 때) + promise)** 가 한다 — 모델이 promise를 성급히 기록해도 게이트 레드거나 마커가 없으면 루프는 계속된다.
