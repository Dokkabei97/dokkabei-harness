---
name: loop-run
description: |
  단발 반복 작업용 경량 루프 시작 — 목표 프롬프트와 --gate-cmd(필수)로 loop-active(engine=generic)·loop-state.json을 초기화하고 Stop훅 루프 엔진(generic-loop-stop-hook.sh)에 진입. 정지조건(결정론 게이트 그린+completion promise)은 훅이 판정. prd/tasks 산출물 구조 없이 'lint 0까지'·'테스트 그린까지' 류 반복에 사용
  Starts a lightweight generic loop for one-off iterative tasks: a goal prompt plus required --gate-cmd initializes loop-active (engine=generic) and loop-state.json and enters the Stop-hook loop engine (generic-loop-stop-hook.sh), which judges the stop condition (deterministic gate green + completion promise). Use when: loop until lint is 0 or tests are green, no prd/tasks artifacts needed.
category: workflow
complexity: basic
mcp-servers: []
personas: []
---

# /loop-run - 경량 반복 루프 시작

산출물 구조(prd.json/tasks.json) 없이 **단발 반복 작업**을 게이트 그린까지 돌리는 미니 루프를 가동한다.
완료 판정의 주체는 모델이 아니라 하네스 — Stop훅 루프 엔진(`generic-loop-stop-hook.sh`)이 매 반복마다
정지조건(① gate-cmd 그린(exit 0 + 실패 표지 보정) ② completion promise 정확 문자열)을 검증하고,
미충족 시 exit 2 재주입으로 루프를 지속시킨다. `loop-active`에는 `engine=generic`을 기록해
mvp/floop 루프 엔진과 소유권이 겹치지 않는다(engine 스코프 공유 계약).

## Triggers
- "lint 에러 0까지", "테스트 전부 그린까지", "빌드 통과까지" 류 단일 목표 반복 작업을 맡길 때
- 그린필드 파이프라인(/mvp-run)도 브라운필드 작업분해(/floop-run)도 과한, 산출물 구조 없는 반복이 필요할 때
- 결정론적 검증 명령 1개(gate-cmd)로 완료를 기계 판정할 수 있는 작업을 자율 반복시킬 때
- 가드레일(max-iter/시간 상한/no-progress)이 걸린 안전한 자기반복 루프가 필요할 때

## Usage
```
/loop-run "<목표 프롬프트>" --gate-cmd "<명령>" [옵션]

Arguments:
  <목표 프롬프트>     반복의 목표 1문장 (필수 — .planning/loop-goal.md 에 기록, 재주입 메시지에 포함)

Options:
  --gate-cmd <명령>   결정론 게이트 명령 (필수 — .planning/gate-cmd 1행에 기록, exit 0 = 그린)
  --promise <문자열>  completion promise (기본 <promise>LOOP_COMPLETE</promise> — progress.md 정확 문자열 일치)
  --max-iter <n>      최대 반복 수 — loop-state.json max_iter 필드에 기록 (기본 12)
  --max-minutes <n>   시간 상한(분) — loop-state.json max_minutes 필드에 기록 (기본 60, started_at(epoch 초) 대비)
```

## Behavioral Flow

### Phase 1: 인자 검증과 경계 판정
1. **필수 인자 확인**: 목표 프롬프트와 `--gate-cmd` 둘 중 하나라도 없으면 가동하지 않고 Usage 안내 후 종료
2. **경계 판정**: 요청이 사실상 그린필드 제품 개발이면 `/mvp-run`, 기존 코드베이스의 다건 기능 작업이면 `/floop-run`을 안내하고 진행 여부를 확인 (아래 Boundaries의 3중 루프 경계 표 기준)
3. **이중 가동 확인**: `.planning/loop-active` 존재 시 engine 줄 판독 —
   - `engine=mvp`/`engine=floop` 또는 engine 줄 없음(레거시 = mvp/floop 소유): 타 엔진 루프 가동 중 — 가동 거부, `/mvp-stop`·`/floop-stop`으로 해제 후 재시도 안내
   - `engine=generic`: 기존 generic 루프 재가동으로 간주하고 Phase 2에서 상태 갱신
4. **게이트 시운전**: `--gate-cmd`를 1회 실행해 명령 자체가 실행 가능한지 확인(오타·미설치 도구로 인한 헛루프 방지). 현재 red여도 무방 — red를 green으로 만드는 것이 루프의 일이다

### Phase 2: 루프 가동 준비
1. **산출물 기록**: `mkdir -p .planning` 후 —
   - `.planning/gate-cmd` 1행에 `--gate-cmd` 기록. 기존 gate-cmd가 있고 내용이 다르면(mvp/floop 잔존물) 덮어쓰기 전 사용자 확인
   - `.planning/loop-goal.md` 1행에 목표 프롬프트 기록 (Stop훅이 재주입 메시지에 포함)
2. **상태 초기화**: loop-state.json 기록 — `{"iteration":0,"last_fail_sig":"","started_at":<date +%s>,"promise":"<promise>LOOP_COMPLETE</promise>","max_iter":12,"max_minutes":60}` (`--promise`/`--max-iter`/`--max-minutes` 지정 시 해당 값 — Stop훅은 env `LOOP_PROMISE`/`LOOP_MAX_ITER`/`LOOP_MAX_MINUTES` > loop-state.json 필드 > 기본값 순으로 로드)
3. **플래그 생성**: `.planning/loop-active`에 `engine=generic` 1줄 기록 — engine 스코프 공유 계약에 따라 generic Stop훅만 이 루프를 소유하고, mvp/floop 훅은 타 엔진 값을 보고 즉시 exit 0 한다

### Phase 3: 루프 진입과 첫 반복 착수
1. **가동 보고**: 목표·gate-cmd·promise·가드레일 설정(max-iter/시간 상한/no-progress 2회/킬스위치 `/loop-stop`)을 1화면 보고
2. **작업 착수**: 목표를 향해 즉시 작업 시작 — 게이트 red 원인 수정 → 게이트 재확인 → 목표 달성 시 progress.md에 promise 정확 문자열 기록. 이후 종료 시도마다 Stop훅이 정지조건(게이트 그린 ∧ promise)을 판정하고, 미충족이면 실패 출력 tail과 함께 재주입한다

## Tool Coordination
- **Bash**: gate-cmd 시운전, `mkdir -p .planning`, `date +%s`, loop-active(engine=generic)·gate-cmd·loop-goal.md 기록
- **Write**: loop-state.json 초기화, progress.md promise 기록(목표 달성 시)
- **Read**: 기존 `.planning/` 잔존물(gate-cmd·loop-active) 충돌 확인
- **Hook(Stop)**: `generic-loop-stop-hook.sh` — 정지조건·가드레일 판정의 주체 (모델 아님)

## Examples

### lint 0까지 반복
```
/loop-run "ESLint 에러를 0으로 만들어라" --gate-cmd "npx eslint src --max-warnings 0"
# 게이트 시운전(현재 red 확인) → loop-active(engine=generic)·loop-state.json 초기화
# 가드레일: 12회 / 60분 / no-progress 2회 / 킬스위치 /loop-stop
# 루프 진입: 에러 수정 → 종료 시도 → Stop훅이 게이트 red면 실패 출력과 함께 재주입
# 게이트 그린 + progress.md에 <promise>LOOP_COMPLETE</promise> 기록 시 정상 종료
```

### 테스트 그린까지 (상한·promise 조정)
```
/loop-run "깨진 단위 테스트를 전부 고쳐라" --gate-cmd "npm test" --promise "<promise>TESTS_GREEN</promise>" --max-iter 6 --max-minutes 30
# loop-state.json에 promise/max_iter=6/max_minutes=30 기록
# Stop훅은 progress.md에서 '<promise>TESTS_GREEN</promise>' 정확 문자열(grep -qF)을 확인
```

### 타 엔진 루프 가동 중 호출 (거부)
```
/loop-run "빌드 고쳐라" --gate-cmd "make build"
# .planning/loop-active 내용: engine=mvp → 가동 거부
# "MVP 루프 가동 중 — /mvp-stop 으로 해제 후 재시도" 안내 후 종료
```

## Boundaries

**3중 루프 경계 표 — 언제 무엇을 쓰나:**

| 상황 | 진입점 | 산출물 구조 | 정지조건 |
|------|--------|-------------|----------|
| 그린필드 신규 제품 — 아이디어→PRD→스토리 파이프라인 완주 | `/mvp-run` (mvp 플러그인) | prd.json·verified 마커·E2E 게이트 | 게이트+all-passes+마커+E2E+promise |
| 브라운필드 기존 코드베이스 — 기능 요청의 작업 분해·회귀 방지 | `/floop-run` (feature-loop 플러그인) | tasks.json·baseline.json·verified 마커 | 게이트+회귀 0+all-passes+마커+E2E+promise |
| 단발 반복 작업 — 'lint 0까지'·'테스트 그린까지' 단일 목표 | `/loop-run` (본 커맨드) | 없음 (gate-cmd·loop-goal 만) | 게이트+promise |

판단 기준: **스토리/작업 목록이 필요하면** mvp·floop, **검증 명령 1개로 완료가 정의되면** loop-run.
loop-run 도중 작업이 다건 분해가 필요할 만큼 커지면 `/loop-stop` 후 `/floop-new`로 승격한다.

**Will:**
- 목표 프롬프트·`--gate-cmd` 필수 검증과 게이트 시운전 후에만 루프 가동
- `loop-active`에 `engine=generic` 기록 — mvp/floop 루프와 소유권 비침범 (engine 스코프 공유 계약)
- loop-state.json에 promise·max_iter·max_minutes를 기록하고 가드레일 설정을 보고한 뒤 작업 착수
- 타 엔진(engine=mvp/floop/레거시) loop-active 감지 시 가동 거부와 해제 방법 안내

**Will Not:**
- `--gate-cmd` 없이 루프 가동 (결정론 게이트 없는 반복은 완료를 판정할 수 없다)
- prd.json·tasks.json 등 산출물 구조 생성 (필요하면 `/mvp-new`·`/floop-new`로 안내)
- 정지조건·완료 판정을 모델 스스로 수행 (판정 주체는 Stop훅 루프 엔진)
- 타 엔진 소유 loop-active의 삭제·덮어쓰기 (해제는 각 엔진의 킬스위치 몫)
- 게이트 명령의 약화·우회 (테스트 삭제, --max-warnings 완화 등)

## Related
- `/loop-stop` — 수동 킬스위치 (loop-active 삭제 + 핸드오프 기록)
- `/mvp-run`·`/floop-run` — 산출물 구조가 필요한 그린필드/브라운필드 루프 (경계 표 참조)
- `skills/flow-scaffolding/templates/loop-stop-hook.sh` — 본 루프 엔진의 원형 템플릿
- `skills/flow-validation/references/loop-rules.md` — 루프 훅 검증 룰셋 (LOOP-001~010)
