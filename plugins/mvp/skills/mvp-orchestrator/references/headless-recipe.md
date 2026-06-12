# Headless Recipe — 무인/야간용 `while + claude -p` 루프

Stage 4 개발 루프의 **보조 엔진**. 기본 엔진(Stop훅 재주입)은 대화형 세션 안에서 돌지만, 이 레시피는 외부 셸 루프가 매 반복 `claude -p`를 새로 띄우는 **컨텍스트 리셋형(Ralph 패턴)** 이다. 무인 배치·야간 실행·스토리 10개 이상의 대형 MVP(단일 세션 컨텍스트 비대 회피)에 권장한다.

## 핵심 원칙

1. **동일 `.planning` · 동일 게이트 공유** — 정지 판정은 Stop훅과 똑같이 `gate-cmd` exit code + `prd.json` all-passes + `<promise>MVP_COMPLETE</promise>`로 한다. 엔진을 바꿔도 정지조건은 불변이다.
2. **매 반복 컨텍스트 리셋** — 각 `claude -p` 세션은 이전 반복을 모른다. 재개 프로토콜(마스터 파일 → `git log` → 미완 스토리 1개)로 아티팩트에서 이해를 재생성한다. 파일시스템과 git history만이 상태다.
3. **이중 가동 금지** — Stop훅 엔진과 동시에 돌리지 않는다. headless 모드에서는 `.planning/loop-active`를 **생성하지 않는다**: Stop훅의 안전핀(`loop-active` 부재 시 무동작)이 내부 세션의 정상 종료를 보장하고, 반복은 외부 `while`이 전담한다. `loop-active`가 이미 있으면 스크립트가 시작을 거부한다.
4. **세션당 스토리 1개** — 프롬프트가 "이번 세션에서는 스토리 1개만 처리하고 종료"를 강제한다. 작은 단위 + 잦은 커밋이 중단·재개를 안전하게 만든다.

## 스크립트

프로젝트 루트에 `scripts/mvp-headless.sh`로 저장 후 실행한다(전제: Stage 0~3 완료, `gate-cmd` 그린, jq 설치).

```bash
#!/usr/bin/env bash
# mvp-headless.sh — MVP Stage 4 무인 루프 (컨텍스트 리셋형 Ralph 패턴)
# 사용: 프로젝트 루트에서  bash scripts/mvp-headless.sh
set -euo pipefail

PLAN=".planning"
MAX_ITER="${LOOP_MAX_ITER:-24}"          # 반복 상한 (권장: 스토리 수×3)
MAX_MINUTES="${LOOP_MAX_MINUTES:-120}"   # 시간 상한(분)
PROMISE="${LOOP_PROMISE:-<promise>MVP_COMPLETE</promise>}"  # promise 전체 문자열(Stop훅과 동일 규약)
GATE_CMD="${LOOP_TEST_CMD:-$(cat "$PLAN/gate-cmd")}"  # 결정론 게이트 (env 우선)

# 이중 가동 금지: Stop훅 엔진이 살아 있으면 시작 거부
if [ -f "$PLAN/loop-active" ]; then
  echo "[headless] loop-active 존재 — Stop훅 엔진 가동 중. /mvp-stop 후 재시도하라." >&2
  exit 1
fi

hash_text() {  # no-progress 시그니처 (macOS/Linux 이식성 폴백)
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

stopped_ok() {  # 정지조건 3결합: ① 게이트 그린 ∧ all-passes ③ promise
  bash -c "$GATE_CMD" >/dev/null 2>&1 || return 1
  jq -e '[.stories[].passes] | all' "$PLAN/prd.json" >/dev/null 2>&1 || return 1
  grep -qF "$PROMISE" "$PLAN/progress.md" 2>/dev/null || return 1
  return 0
}

started_at="$(date +%s)"
last_sig=""
i=0
while [ "$i" -lt "$MAX_ITER" ]; do
  # 가드 1: 시간 상한
  elapsed=$(( ( $(date +%s) - started_at ) / 60 ))
  if [ "$elapsed" -ge "$MAX_MINUTES" ]; then
    echo "[headless] 시간 상한 ${MAX_MINUTES}분 도달 — 중단. 같은 명령으로 재개 가능." >&2
    exit 0
  fi

  # 정지조건 충족 시 완료 종료
  if stopped_ok; then
    echo "[headless] 정지조건 3결합 충족 — MVP 완료 (iteration $i)." >&2
    exit 0
  fi

  i=$((i + 1))
  # /mvp-status 가시성을 위해 loop-state.json 갱신
  jq -n --argjson it "$i" --arg sig "$last_sig" --arg ts "$started_at" \
    '{iteration:$it, last_fail_sig:$sig, started_at:($ts|tonumber)}' > "$PLAN/loop-state.json"

  # 1 반복 = 1 스토리 — 매 회 새 세션(컨텍스트 리셋)
  claude -p --permission-mode acceptEdits "$(cat <<'PROMPT'
MVP Stage 4 개발 루프의 1회 반복을 수행하라. mvp-loop-protocol 스킬의 재개 프로토콜을 따른다:
1) .planning/mvp-*.md 마스터와 git log --oneline -10 으로 현재 상태를 파악한다.
2) .planning/prd.json 에서 passes:false 인 최우선 스토리 1개만 선택한다.
3) 테스트 먼저 작성 → 최소 구현 → .planning/gate-cmd 의 명령이 그린(exit 0)이 될 때까지 수정한다.
4) mvp-verifier 에이전트를 디스패치해 해당 스토리 AC를 반증시킨다. 반증 실패 시에만
   .planning/verified/{story-id} 마커가 생성되며, 마커가 생긴 뒤에만 passes:true 로 마킹한다.
5) feat(mvp): S-xx 형식으로 커밋하고 .planning/progress.md 에 1줄을 추가한다.
6) 모든 스토리가 passes:true 이고 게이트가 그린이면 progress.md 에
   <promise>MVP_COMPLETE</promise> 를 정확히 기록한다.
규칙: 이번 세션에서는 스토리 1개만 처리하고 종료한다. 테스트 삭제·약화 금지.
진행 불가 시 .planning/BLOCKED.md 에 시도·원인·권장 다음 행동을 기록하고 종료한다.
PROMPT
)" || echo "[headless] iteration $i: claude 비정상 종료 — 다음 반복에서 재개 프로토콜로 복구." >&2

  # 가드 2: no-progress — 게이트 실패 시그니처가 직전과 동일하면 중단
  gate_out="$(bash -c "$GATE_CMD" 2>&1 || true)"
  sig="$(printf '%s' "$gate_out" | grep -Ei 'fail|error' | sort | hash_text || echo "")"
  if [ -n "$sig" ] && [ "$sig" = "$last_sig" ]; then
    {
      echo "## headless no-progress — iteration $i"
      echo "- 실패 시그니처: $sig"
      echo '```'
      printf '%s\n' "$gate_out" | tail -20
      echo '```'
    } >> "$PLAN/BLOCKED.md"
    echo "[headless] no-progress(동일 실패 연속) — 중단. BLOCKED.md 확인." >&2
    exit 0
  fi
  last_sig="$sig"
done

echo "[headless] max iterations($MAX_ITER) 도달 — 중단. 미완 스토리는 prd.json 참조, 같은 명령으로 재개." >&2
exit 0
```

## 실행·재개·스케줄

| 작업 | 방법 |
|------|------|
| 야간 무인 실행 | 프로젝트 루트에서 `nohup bash scripts/mvp-headless.sh > .planning/headless.log 2>&1 &` |
| 가드 조정 | `LOOP_MAX_ITER=36 LOOP_MAX_MINUTES=300 bash scripts/mvp-headless.sh` |
| **재개** | **같은 명령을 다시 실행** — 별도 재개 절차 없음. 정지조건·no-progress·시간 상한이 처음부터 재평가되고, 각 세션이 마스터+git에서 상태를 복구한다(어느 시점에 중단됐어도 안전) |
| 진행 확인 | 다른 터미널/세션에서 `/mvp-status` 또는 `jq '.stories[] | {id, passes}' .planning/prd.json` |
| 중단 | 셸 프로세스 종료(Ctrl-C/kill). `loop-active`를 쓰지 않으므로 잔존 플래그 정리 불필요 |
| 크론 등록 | `MVP_PROJECT_DIR` 환경변수에 프로젝트 루트를 지정해 crontab에 `cd "$MVP_PROJECT_DIR" && bash scripts/mvp-headless.sh` 형태로 등록(절대경로 하드코딩 대신 env 사용) |

## 가드레일 대응표 (Stop훅 엔진과의 등가성)

| 가드 | Stop훅 엔진 | headless 엔진 |
|------|------------|---------------|
| max iterations | 훅이 `loop-state.json` iteration 검사 | 외부 `while` 카운터 (`LOOP_MAX_ITER`) |
| no-progress | 실패 시그니처 md5 연속 2회 | 동일 — 외부 루프가 게이트 출력 시그니처 비교 |
| 시간 상한 | `loop-state.json` started_at 대비 | 동일 — 스크립트 시작 시각 대비 (`LOOP_MAX_MINUTES`) |
| 킬스위치 | `/mvp-stop` (loop-active 삭제) | 셸 프로세스 종료 |
| circuit breaker | 오케스트레이터 정책(동일 스토리 3연속 skip) | 세션 내 동일 — 각 세션의 BLOCKED 기록이 다음 세션에 승계 |

## 주의

- `--permission-mode acceptEdits`는 무인 실행 전제다. 신뢰 가능한 그린필드 레포에서만 사용하고, 운영 자격증명이 있는 환경에서는 돌리지 않는다.
- 비용 상한이 곧 안전장치다: 반복·시간 상한 없이 돌린 Stop훅 루프가 $3600/day를 청구한 실제 사고가 있다. 기본값(24회/120분)을 지우지 말 것.
- 완료 판정은 promise 출력이 아니라 **외부 루프의 정지조건 3결합 검사**가 한다 — 모델이 promise를 성급히 기록해도 게이트 레드면 루프는 계속된다.
