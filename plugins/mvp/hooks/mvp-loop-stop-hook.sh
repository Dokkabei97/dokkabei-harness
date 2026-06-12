#!/usr/bin/env bash
# =============================================================================
# mvp-loop-stop-hook.sh — MVP PRD-driven 개발 루프 엔진 (Stop 훅)
# flow-scaffolding templates/loop-stop-hook.sh 확장판 (확장 6건: 안전핀 ·
# gate-cmd 동적 로드 · all-passes AND 결합 · verified 마커 재검사 · 시간 상한 ·
# 종료 경로 loop-active 해제).
#   - exit 0 : 종료 허용 (루프 비활성 / 정지조건 충족 / 가드레일 도달)
#   - exit 2 : 종료 차단. stderr가 Claude에게 전달되어 다음 반복이 이어진다.
#
# 정지조건 3결합 (판정 주체 = 본 훅, 모델 아님):
#   ① 결정론 게이트: .planning/gate-cmd 실행(exit code 우선·grep 보조)
#      AND jq -e '[.stories[].passes]|all' .planning/prd.json
#   ② 회의적 Evaluator: passes:true 전환은 prd-guard.sh가 verified 마커로 1차 강제
#      (단 Edit|Write 만 포착 — Bash 리다이렉션 우회 가능) → 본 훅이 all-passes
#      확인 시 passes==true 각 id 의 .planning/verified/{id} 존재를 재검사 (최종 방어선)
#   ③ completion promise: progress.md 의 정확 문자열 일치 (grep -qF, 정규식 금지)
#   종료 허용 = ① ∧ ③
# 가드레일: max iterations · no-progress(md5 시그니처 연속 동일) · 시간 상한
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"

# (a) 안전핀 — 루프 미가동 세션의 종료는 절대 방해하지 않는다 (즉시 종료 허용)
[ -f "$PLAN/loop-active" ] || exit 0

# jq 부재 시 graceful degrade — 재주입도 통과 판정도 하지 않고, 사유 명시 후 종료 허용
if ! command -v jq >/dev/null 2>&1; then
  echo "[mvp-loop] jq 미설치 — 정지조건 판정 불가. 루프를 진행할 수 없어 종료를 허용한다. jq 설치 후 /mvp-run 으로 재개하라. (loop-active 유지 — 해제는 /mvp-stop)" >&2
  exit 0
fi

# ▼ CONFIG — env > loop-state.json 필드 > 기본값 순 로드 (§5 가드레일 표)
PROMISE="${LOOP_PROMISE:-<promise>MVP_COMPLETE</promise>}"
PROGRESS_FILE="$PLAN/progress.md"
STATE_FILE="$PLAN/loop-state.json"
PRD_JSON="$PLAN/prd.json"
BLOCKED_FILE="$PLAN/BLOCKED.md"

# max_iter/max_minutes — env(LOOP_MAX_ITER/LOOP_MAX_MINUTES) > loop-state.json
# (max_iter/max_minutes — /mvp-run 의 --max-iter/--max-minutes 가 기록) > 기본값(24/120)
state_max_iter=""; state_max_minutes=""
if [ -f "$STATE_FILE" ]; then
  state_max_iter="$(jq -r '.max_iter // empty' "$STATE_FILE" 2>/dev/null || echo "")"
  state_max_minutes="$(jq -r '.max_minutes // empty' "$STATE_FILE" 2>/dev/null || echo "")"
fi
case "$state_max_iter" in (''|*[!0-9]*) state_max_iter="";; esac
case "$state_max_minutes" in (''|*[!0-9]*) state_max_minutes="";; esac
MAX_ITER="${LOOP_MAX_ITER:-${state_max_iter:-24}}"
MAX_MINUTES="${LOOP_MAX_MINUTES:-${state_max_minutes:-120}}"

# 숫자 방어 — 비정상 값이면 기본값으로 복원 (set -e 환경에서 -ge 오류 방지)
case "$MAX_ITER" in (''|*[!0-9]*) MAX_ITER=24;; esac
case "$MAX_MINUTES" in (''|*[!0-9]*) MAX_MINUTES=120;; esac

# (b) 게이트 명령 동적 로드 — LOOP_TEST_CMD env 우선, 없으면 .planning/gate-cmd 1행
GATE_CMD="${LOOP_TEST_CMD:-}"
if [ -z "$GATE_CMD" ] && [ -s "$PLAN/gate-cmd" ]; then
  GATE_CMD="$(head -n 1 "$PLAN/gate-cmd" | tr -d '\r')"
fi
if [ -z "$GATE_CMD" ]; then
  echo "[mvp-loop] 게이트 명령 없음(.planning/gate-cmd 비어있음, LOOP_TEST_CMD 미지정) — 판정 불가로 종료를 허용한다. /mvp-gate 로 점검 후 /mvp-run 으로 재개하라." >&2
  exit 0
fi

# stdin 해시 (no-progress 시그니처용) — macOS/Linux 이식성 폴백 (템플릿 로직 유지)
hash_stdin() {
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

# stdin 입력(JSON) 읽기 — stop_hook_active로 재진입 여부 확인 (템플릿 로직 유지)
# 재진입(stop_hook_active=true)이라도 우회하지 않는다 — 차단/허용은 가드레일이 판정.
input="$(cat || true)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"

# 상태 로드 — iteration / last_fail_sig / started_at (epoch 초)
iter=0; last_fail_sig=""; started_at=0
if [ -f "$STATE_FILE" ]; then
  iter="$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  last_fail_sig="$(jq -r '.last_fail_sig // ""' "$STATE_FILE" 2>/dev/null || echo "")"
  started_at="$(jq -r '.started_at // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
fi
case "$iter" in (''|*[!0-9]*) iter=0;; esac
case "$started_at" in (''|*[!0-9]*) started_at=0;; esac

now="$(date +%s)"

# 가드레일 1: max iterations — 도달 시 루프 해제(e) + 미완 보고
if [ "$iter" -ge "$MAX_ITER" ]; then
  rm -f "$PLAN/loop-active"
  echo "[mvp-loop] max iterations($MAX_ITER) 도달 — 루프 종료(loop-active 해제). 미완 상태는 $PROGRESS_FILE 와 /mvp-status 로 확인하고 /mvp-run 으로 재개하라." >&2
  exit 0
fi

# 가드레일 3 (d): 시간 상한 — started_at(epoch 초) 대비 LOOP_MAX_MINUTES 초과 시 종료(e)
if [ "$started_at" -gt 0 ] && [ $(( now - started_at )) -ge $(( MAX_MINUTES * 60 )) ]; then
  rm -f "$PLAN/loop-active"
  elapsed_min=$(( (now - started_at) / 60 ))
  echo "[mvp-loop] 시간 상한 도달(경과 ${elapsed_min}분 >= ${MAX_MINUTES}분) — 루프 종료(loop-active 해제). /mvp-run 으로 재개 가능(LOOP_MAX_MINUTES 로 상한 조정)." >&2
  exit 0
fi

# ① 결정론 게이트 실행 — eval 금지, bash -c 사용. 판정은 exit code 우선.
gate_exit=0
test_out="$( (cd "$PROJ" && bash -c "$GATE_CMD") 2>&1 )" || gate_exit=$?

tests_pass=false
if [ "$gate_exit" -eq 0 ]; then
  tests_pass=true
  # 보조 판정(grep): exit 0이어도 출력에 명백한 실패 표지가 있으면 보수적으로 실패 처리.
  # "0 failed" 류 오탐 방지 — 행두 FAIL 또는 1 이상 카운트가 붙은 실패 표지만 매칭.
  if printf '%s\n' "$test_out" | grep -Eqi '(^FAIL([ :]|$)|[1-9][0-9]* +(fail(ed|ure|ures)?|errors?))'; then
    tests_pass=false
  fi
fi

# 실패 시그니처(md5) — no-progress 감지용 (실패 시에만 산출)
fail_sig=""
if [ "$tests_pass" = false ]; then
  # 숫자 토큰 제거 정규화 — pytest "1 failed in 0.01s" 류 소요시간 비결정성 제거
  sig_src="$(printf '%s' "$test_out" | grep -Ei 'fail|error' | sed -E 's/[0-9]+([.][0-9]+)?//g' | sort || true)"
  if [ -z "$sig_src" ]; then
    sig_src="exit=$gate_exit"$'\n'"$(printf '%s' "$test_out" | tail -20)"
  fi
  fail_sig="$(printf '%s' "$sig_src" | hash_stdin 2>/dev/null || echo "")"
fi

# ① AND 결합 (c): prd.json 전 스토리 passes
all_passes=false
if [ -f "$PRD_JSON" ] && jq -e '[.stories[].passes]|all' "$PRD_JSON" >/dev/null 2>&1; then
  all_passes=true
fi

# ① 보강: verified 마커 재검사 — passes==true 각 id 의 .planning/verified/{id} 존재 확인.
# prd-guard 는 Edit|Write 만 포착하고 Bash 리다이렉션 우회가 가능하므로 본 훅이 최종 방어선.
markers_ok=true
unverified_ids=""
if [ -f "$PRD_JSON" ]; then
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    if [ ! -f "$PLAN/verified/$sid" ]; then
      markers_ok=false
      unverified_ids="${unverified_ids:+$unverified_ids, }$sid"
    fi
  done < <(jq -r '.stories[]? | select(.passes == true) | .id' "$PRD_JSON" 2>/dev/null || true)
fi

# ③ completion promise — 정확 문자열 일치 (grep -qF, 정규식 금지)
promise_found=false
if [ -f "$PROGRESS_FILE" ] && grep -qF "$PROMISE" "$PROGRESS_FILE"; then
  promise_found=true
fi

# 상태 갱신 — started_at은 최초 반복에서 초기화 후 보존,
# max_iter/max_minutes 는 /mvp-run 기록 값 보존 (없으면 현재 해석값으로 채움)
next_iter=$((iter + 1))
[ "$started_at" -gt 0 ] || started_at="$now"
jq -n --argjson it "$next_iter" --arg sig "$fail_sig" --argjson st "$started_at" \
  --argjson mi "${state_max_iter:-$MAX_ITER}" --argjson mm "${state_max_minutes:-$MAX_MINUTES}" \
  '{iteration:$it, last_fail_sig:$sig, started_at:$st, max_iter:$mi, max_minutes:$mm}' > "$STATE_FILE"

# 정지 판정: ①(게이트 그린 AND all-passes AND verified 마커) ∧ ③(promise) → 종료 허용 + 루프 해제(e)
if [ "$tests_pass" = true ] && [ "$all_passes" = true ] && [ "$markers_ok" = true ] && [ "$promise_found" = true ]; then
  rm -f "$PLAN/loop-active"
  echo "[mvp-loop] 정지조건 충족(게이트 그린 + all-passes + verified 마커 + promise) — iteration $next_iter 에서 루프 정상 종료(loop-active 해제)." >&2
  exit 0
fi

# 가드레일 2: no-progress — 직전 반복과 동일 실패 시그니처 연속 시 종료(e) + BLOCKED 기록
if [ -n "$fail_sig" ] && [ "$fail_sig" = "$last_fail_sig" ]; then
  rm -f "$PLAN/loop-active"
  {
    echo ""
    echo "## no-progress 차단 — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- iteration: $next_iter/$MAX_ITER"
    echo "- 실패 시그니처(md5): $fail_sig (연속 2회 동일)"
    echo "- gate-cmd: $GATE_CMD (exit=$gate_exit)"
    echo "- 테스트 출력 tail -20:"
    echo '```'
    printf '%s\n' "$test_out" | tail -20
    echo '```'
    echo "- 권장 다음 행동: 실패 원인 분석 후 /mvp-run 재개. 스코프 재협상은 product-strategist, 구조 재설계는 tech-architect 에스컬레이션."
  } >> "$BLOCKED_FILE"
  echo "[mvp-loop] no-progress 감지(동일 실패 시그니처 연속) — 루프 종료(loop-active 해제). 상세는 $BLOCKED_FILE 참조." >&2
  exit 0
fi

# 미충족 → 종료 차단, 작업 재주입 (stderr가 Claude에게 전달됨)
{
  echo "[mvp-loop] 작업 미완료 (iteration $next_iter/$MAX_ITER, 재진입=$stop_active). 다음을 해결하고 계속 진행하라:"
  if [ "$tests_pass" = false ]; then
    echo "- 결정론 게이트 실패 (cmd: $GATE_CMD, exit=$gate_exit). 출력 tail -20:"
    printf '%s\n' "$test_out" | tail -20
  fi
  if [ "$all_passes" = false ]; then
    unpassed="$(jq -r '[.stories[] | select(.passes != true) | .id] | join(", ")' "$PRD_JSON" 2>/dev/null || echo "prd.json 판독 불가")"
    echo "- 미완 스토리: ${unpassed:-없음}. 우선순위 최상 스토리 1개만 선택해 테스트 먼저→최소 구현→mvp-verifier 반증→verified 마커→passes 갱신 순으로 진행하라."
  fi
  if [ "$markers_ok" = false ]; then
    echo "- verified 마커 없는 passes:true 스토리: $unverified_ids — mvp-verifier 반증을 통과시켜 마커(.planning/verified/{id})를 생성하라."
  fi
  if [ "$promise_found" = false ]; then
    echo "- 모든 스토리 완료·검증 후 $PROGRESS_FILE 에 '$PROMISE' 를 정확히 기록하라."
  fi
} >&2
exit 2
