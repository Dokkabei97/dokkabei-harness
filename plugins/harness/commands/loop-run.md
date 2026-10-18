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
타 엔진과 소유권이 겹치지 않는다(engine 스코프 공유 계약). 루프 중 테스트 파일 `rm`은
PreToolUse 훅(`test-guard.sh`)이 exit 2로 차단한다.

## Triggers
- "lint 에러 0까지", "테스트 전부 그린까지", "빌드 통과까지" 류 단일 목표 반복 작업을 맡길 때
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
2. **이중 가동 확인**: `.planning/loop-active` 존재 시 engine 줄 판독 —
   - `engine=generic`: 기존 generic 루프 재가동으로 간주하고 Phase 2에서 상태 갱신
   - 그 외 값 또는 engine 줄 없음: archive된 엔진(mvp/feature-loop)의 잔존물일 가능성이 높다 — 내용을 보여주고 사용자 확인 후에만 덮어쓴다
3. **게이트 시운전**: `--gate-cmd`를 1회 실행해 명령 자체가 실행 가능한지 확인(오타·미설치 도구로 인한 헛루프 방지). 현재 red여도 무방 — red를 green으로 만드는 것이 루프의 일이다

### Phase 2: 루프 가동 준비
1. **산출물 기록**: `mkdir -p .planning` 후 —
   - `.planning/gate-cmd` 1행에 `--gate-cmd` 기록. 기존 gate-cmd가 있고 내용이 다르면(이전 루프 잔존물) 덮어쓰기 전 사용자 확인
   - `.planning/loop-goal.md` 1행에 목표 프롬프트 기록 (Stop훅이 재주입 메시지에 포함)
2. **상태 초기화**: loop-state.json 기록 — `{"iteration":0,"last_fail_sig":"","started_at":<date +%s>,"promise":"<promise>LOOP_COMPLETE</promise>","max_iter":12,"max_minutes":60}` (`--promise`/`--max-iter`/`--max-minutes` 지정 시 해당 값 — Stop훅은 env `LOOP_PROMISE`/`LOOP_MAX_ITER`/`LOOP_MAX_MINUTES` > loop-state.json 필드 > 기본값 순으로 로드)
3. **플래그 생성**: `.planning/loop-active`에 `engine=generic` 1줄 기록 — engine 스코프 공유 계약에 따라 generic Stop훅·test-guard만 이 루프를 소유한다

### Phase 3: 루프 진입과 첫 반복 착수
1. **가동 보고**: 목표·gate-cmd·promise·가드레일 설정(max-iter/시간 상한/no-progress 2회/킬스위치 `/loop-stop`)을 1화면 보고
   - **턴 블록 상한**: Claude Code는 한 턴에 Stop 블록을 연속 8회까지만 허용한다. 엔진이 이를 세어(`turn_blocks`) 8회째 뒤에는 progress.md에 핸드오프를 남기고 턴을 넘긴다 — loop-active는 유지되므로 '계속'으로 다음 턴을 시작하면 이어진다. 즉 세션 내 한 턴의 실효 반복은 8회다
2. **작업 착수**: 목표를 향해 즉시 작업 시작 — 게이트 red 원인 수정 → 게이트 재확인 → 목표 달성 시 progress.md에 promise 정확 문자열 기록. 이후 종료 시도마다 Stop훅이 정지조건(게이트 그린 ∧ promise)을 판정하고, 미충족이면 실패 출력 tail과 함께 재주입한다

## Tool Coordination
- **Bash**: gate-cmd 시운전, `mkdir -p .planning`, `date +%s`, loop-active(engine=generic)·gate-cmd·loop-goal.md 기록
- **Write**: loop-state.json 초기화, progress.md promise 기록(목표 달성 시)
- **Read**: 기존 `.planning/` 잔존물(gate-cmd·loop-active) 충돌 확인
- **Hook(Stop)**: `generic-loop-stop-hook.sh` — 정지조건·가드레일·턴 블록 상한 판정의 주체 (모델 아님)
- **Hook(PreToolUse: Bash)**: `test-guard.sh` — engine=generic 루프 중 테스트 파일 `rm` 차단(exit 2)

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

### 기존 코드베이스 — 회귀 0을 게이트로 (baseline 레시피)
이미 실패 중인 테스트가 있는 레포에서 "새 실패만 막기"를 게이트로 삼는다 (archive/feature-loop의
baseline 회귀 게이트 아이디어를 gate-cmd 1행으로 축약). 시작 전에 기준선을 1회 캡처한다:
```
npm test 2>&1 | grep -E '^(FAIL|✕)' | sort > .planning/baseline-fails.txt   # 기준선 캡처 (1회)
/loop-run "X 기능 추가 — 기존 실패 외 신규 실패 0" \
  --gate-cmd "npm test 2>&1 | grep -E '^(FAIL|✕)' | sort | comm -13 .planning/baseline-fails.txt - | grep -q . && exit 1 || exit 0"
# 게이트 = 기준선에 없는 실패 줄이 하나라도 있으면 red. 실패 줄 패턴은 테스트 러너에 맞게 조정
# 주의: 게이트 출력에 "N failed" 가 섞이면 실패 표지 보정이 red 로 뒤집는다 — 위처럼 출력 없이 exit code 만 남겨라
```

### 잔존 loop-active가 있는 상태에서 호출
```
/loop-run "빌드 고쳐라" --gate-cmd "make build"
# .planning/loop-active 내용: engine=mvp (archive된 엔진 잔존물 — 소유 훅 없음)
# 내용을 보여주고 덮어쓸지 확인 → 승인 시 engine=generic 으로 재기록 후 가동
```

## Boundaries

**루프 경계 — 언제 무엇을 쓰나:**

| 상황 | 진입점 | 정지조건 |
|------|--------|----------|
| 검증 명령 1개로 완료가 정의되는 반복 — 'lint 0까지'·'테스트 그린까지'·'회귀 0' | `/loop-run` (본 커맨드) | 게이트+promise |
| 게이트조차 불필요한 단발 목표 — 검증 명령 없음 | 네이티브 `/goal` (Claude Code 내장) | 목표 달성 판단 OR max turns |
| 다건 작업 분해·스토리 파이프라인 | 대화형 진행 (mvp·feature-loop 하네스는 2026-10 archive — 실사용 0) | — |

`.planning/loop-active` 활성 중에는 네이티브 `/goal`·`/loop`를 병행 가동하지 않는다 — 재주입·판정 주체가 둘이 된다.

**Will:**
- 목표 프롬프트·`--gate-cmd` 필수 검증과 게이트 시운전 후에만 루프 가동
- `loop-active`에 `engine=generic` 기록 — 타 엔진과 소유권 비침범 (engine 스코프 공유 계약)
- loop-state.json에 promise·max_iter·max_minutes를 기록하고 가드레일 설정을 보고한 뒤 작업 착수
- generic 외 loop-active 감지 시 내용을 보여주고 사용자 확인 후에만 덮어쓰기

**Will Not:**
- `--gate-cmd` 없이 루프 가동 (결정론 게이트 없는 반복은 완료를 판정할 수 없다)
- prd.json·tasks.json 등 산출물 구조 생성
- 정지조건·완료 판정을 모델 스스로 수행 (판정 주체는 Stop훅 루프 엔진)
- 사용자 확인 없는 타 엔진 loop-active의 삭제·덮어쓰기
- 게이트 명령의 약화·우회 (테스트 삭제, --max-warnings 완화 등)

## Related
- `/loop-stop` — 수동 킬스위치 (loop-active 삭제 + 핸드오프 기록)
- `skills/flow-scaffolding/templates/loop-stop-hook.sh` — 본 루프 엔진의 원형 템플릿
- `skills/flow-validation/references/loop-rules.md` — 루프 훅 검증 룰셋 (LOOP-001~011)
