#!/usr/bin/env bash
# =============================================================================
# floop-loop-stop-hook.sh — 브라운필드 기능 개발 루프 엔진 (Stop 훅)
# mvp-loop-stop-hook.sh 의 브라운필드판. 확장 1건: ②ᴿ baseline 회귀 게이트.
#   - exit 0 : 종료 허용 (루프 비활성 / 정지조건 충족 / 가드레일 도달)
#   - exit 2 : 종료 차단. stderr가 Claude에게 전달되어 다음 반복이 이어진다.
#
# 정지조건 (판정 주체 = 본 훅, 모델 아님):
#   ① 결정론 게이트: .planning/gate-cmd 실행(exit code 우선·grep 보조)
#      AND jq -e '[.tasks[].passes]|all' .planning/tasks.json
#   ②ᴿ baseline 회귀 게이트(신규): .planning/baseline.json 기준선 대비 신규 실패 0.
#      baseline 부재 시 미적용(회귀 0 간주)으로 MVP 동작과 호환.
#   ② 회의적 Evaluator: passes:true 전환은 tasks-guard.sh 가 verified 마커로 1차 강제
#      → 본 훅이 all-passes 확인 시 passes==true 각 id 의 .planning/verified/{id} 재검사.
#   ②ᴱ E2E 수용 게이트(선택): .planning/e2e-gate-cmd 있으면 all-passes 도달 시 1회 실행.
#   ③ completion promise: progress.md 의 정확 문자열 일치 (grep -qF, 정규식 금지)
#   종료 허용 = ① ∧ ②ᴿ ∧ ②ᴱ ∧ ③
# 가드레일: max iterations · no-progress(md5 시그니처 연속 동일) · 시간 상한
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"

# (a) 안전핀 — 루프 미가동 세션의 종료는 절대 방해하지 않는다 (즉시 종료 허용)
[ -f "$PLAN/loop-active" ] || exit 0

# (a') engine 스코프 가드 — loop-active 의 "engine=" 줄이 floop 이외 값이면 그 루프는
# 타 엔진(mvp/generic) 소유 → 개입 없이 종료 허용. 줄 없음 = 레거시 호환(자기 것)
loop_engine="$(grep -m1 '^engine=' "$PLAN/loop-active" 2>/dev/null | tr -d '\r' || true)"
[ -z "$loop_engine" ] || [ "${loop_engine#engine=}" = "floop" ] || exit 0

# jq 부재 시 graceful degrade — 재주입도 통과 판정도 하지 않고, 사유 명시 후 종료 허용
if ! command -v jq >/dev/null 2>&1; then
  echo "[floop-loop] jq 미설치 — 정지조건 판정 불가. 루프를 진행할 수 없어 종료를 허용한다. jq 설치 후 /floop-run 으로 재개하라. (loop-active 유지 — 해제는 /floop-stop)" >&2
  exit 0
fi

# ▼ CONFIG — env > loop-state.json 필드 > 기본값 순 로드
PROMISE="${LOOP_PROMISE:-<promise>FEATURE_COMPLETE</promise>}"
PROGRESS_FILE="$PLAN/progress.md"
STATE_FILE="$PLAN/loop-state.json"
TASKS_JSON="$PLAN/tasks.json"
BASELINE_FILE="$PLAN/baseline.json"
BLOCKED_FILE="$PLAN/BLOCKED.md"

# max_iter/max_minutes — env(LOOP_MAX_ITER/LOOP_MAX_MINUTES) > loop-state.json > 기본값(24/120)
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
  echo "[floop-loop] 게이트 명령 없음(.planning/gate-cmd 비어있음, LOOP_TEST_CMD 미지정) — 판정 불가로 종료를 허용한다. /floop-gate 로 점검 후 /floop-run 으로 재개하라." >&2
  exit 0
fi

# (b') E2E 수용 게이트 명령 동적 로드(선택) — LOOP_E2E_CMD env 우선, 없으면 .planning/e2e-gate-cmd 1행.
E2E_CMD="${LOOP_E2E_CMD:-}"
if [ -z "$E2E_CMD" ] && [ -s "$PLAN/e2e-gate-cmd" ]; then
  E2E_CMD="$(head -n 1 "$PLAN/e2e-gate-cmd" | tr -d '\r')"
fi

# stdin 해시 (no-progress 시그니처용) — macOS/Linux 이식성 폴백
hash_stdin() {
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

# 출력에서 실패 수 추출 — capture-baseline.sh 와 동일 규약(일관된 회귀 판정의 전제).
# "N failed/failures/errors" 최대값. 못 찾으면 exit 0 → 0 / exit!=0 → -1(카운트 불명).
extract_fail_count() {
  local out="$1" exit_code="$2" n
  n="$(printf '%s\n' "$out" | grep -oiE '[1-9][0-9]* +(fail(ed|ure|ures)?|errors?)' | grep -oE '^[0-9]+' | sort -rn | head -n1 || true)"
  if [ -n "$n" ]; then echo "$n"
  elif [ "$exit_code" -eq 0 ]; then echo 0
  else echo -1; fi
}

# stdin 입력(JSON) 읽기 — stop_hook_active로 재진입 여부 확인
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

# 가드레일 1: max iterations — 도달 시 루프 해제 + 미완 보고
if [ "$iter" -ge "$MAX_ITER" ]; then
  rm -f "$PLAN/loop-active"
  echo "[floop-loop] max iterations($MAX_ITER) 도달 — 루프 종료(loop-active 해제). 미완 상태는 $PROGRESS_FILE 와 /floop-status 로 확인하고 /floop-run 으로 재개하라." >&2
  exit 0
fi

# 가드레일 3: 시간 상한 — started_at(epoch 초) 대비 LOOP_MAX_MINUTES 초과 시 종료
if [ "$started_at" -gt 0 ] && [ $(( now - started_at )) -ge $(( MAX_MINUTES * 60 )) ]; then
  rm -f "$PLAN/loop-active"
  elapsed_min=$(( (now - started_at) / 60 ))
  echo "[floop-loop] 시간 상한 도달(경과 ${elapsed_min}분 >= ${MAX_MINUTES}분) — 루프 종료(loop-active 해제). /floop-run 으로 재개 가능(LOOP_MAX_MINUTES 로 상한 조정)." >&2
  exit 0
fi

# 출력의 명백한 실패 표지 판정 — exit 0이어도 출력에 실패 카운트가 있으면 보수적으로 레드.
has_failure_marker() { printf '%s\n' "$1" | grep -Eqi '(^FAIL([ :]|$)|[1-9][0-9]* +(fail(ed|ure|ures)?|errors?))'; }

# ① 결정론 게이트 실행 — eval 금지, bash -c 사용. 판정은 exit code 우선.
gate_exit=0
test_out="$( (cd "$PROJ" && bash -c "$GATE_CMD") 2>&1 )" || gate_exit=$?

# raw_pass — 순수 exit 0 여부(출력 실패 표지 보정). baseline 맥락에서 gate_green 으로 해석된다.
raw_pass=false
if [ "$gate_exit" -eq 0 ]; then
  raw_pass=true
  has_failure_marker "$test_out" && raw_pass=false
fi

# ②ᴿ baseline 회귀 게이트 — "게이트 통과(gate_green)"를 baseline 맥락에서 결정한다.
# 핵심: red 기준선(기존에 깨진 테스트 존재) 프로젝트는 gate-cmd 가 항상 exit!=0 이므로,
# 순수 exit 0 을 요구하면 루프가 영원히 끝나지 않는다. 따라서 게이트 통과의 정의를
# "신규 회귀 0"으로 통합한다 — 기존 실패는 용인하고 내 변경이 추가로 깬 것만 차단한다.
#   - baseline 부재 : 순수 green 요구 (MVP 동작 100% 호환)
#   - baseline green: green = 회귀 0 (기존과 동일)
#   - baseline red  : 현재 fail_count <= 기준선이면 통과 (신규 실패만 차단)
gate_green=false
regression_note=""
if [ ! -f "$BASELINE_FILE" ]; then
  gate_green="$raw_pass"
else
  baseline_exit="$(jq -r '.baseline_exit // 0' "$BASELINE_FILE" 2>/dev/null || echo 0)"
  baseline_fc="$(jq -r '.fail_count // 0' "$BASELINE_FILE" 2>/dev/null || echo 0)"
  case "$baseline_exit" in (''|*[!0-9-]*) baseline_exit=0;; esac
  case "$baseline_fc" in (''|*[!0-9-]*) baseline_fc=0;; esac
  if [ "$baseline_exit" -eq 0 ]; then
    # 클린 기준선(green) — green 이 곧 회귀 0
    gate_green="$raw_pass"
    [ "$raw_pass" = true ] || regression_note="클린 기준선(green) 대비 현재 게이트 레드 — 신규 회귀 발생"
  elif [ "$raw_pass" = true ]; then
    # red 기준선인데 현재 전부 green — 기존 실패까지 해소(개선). 당연히 회귀 0
    gate_green=true
  else
    # red 기준선 + 현재도 레드 — 회귀 판정으로 통과 여부를 결정한다.
    # 정책: (1) 실패 수 증가 = 차단, (2) 파싱 불가(-1) = 보수적 차단, (3) 동수·감소 = 통과.
    # fail_count 비교는 "이름 집합 비교"보다 약하지만(같은 수의 다른 실패는 못 잡음) 러너
    # 독립적·결정론적이며, no-progress/max-iter 가드레일이 미세 케이스의 backstop이 된다.
    cur_fc="$(extract_fail_count "$test_out" "$gate_exit")"
    if [ "$cur_fc" -lt 0 ]; then
      regression_note="기존 red 기준선(실패 ${baseline_fc}개)에서 현재 실패 수 파싱 불가(exit=$gate_exit) — 회귀 가능성을 배제할 수 없어 보수적으로 차단. gate-cmd 를 실패 수가 출력되는 명령으로 조정하면 정확히 추적된다."
    elif [ "$cur_fc" -le "$baseline_fc" ]; then
      gate_green=true
    else
      regression_note="기준선 실패 ${baseline_fc}개 → 현재 ${cur_fc}개로 증가 — 신규 회귀 $(( cur_fc - baseline_fc ))개 발생."
    fi
  fi
fi

# ① AND 결합: tasks.json 전 task passes
all_passes=false
if [ -f "$TASKS_JSON" ] && jq -e '[.tasks[].passes]|all' "$TASKS_JSON" >/dev/null 2>&1; then
  all_passes=true
fi

# ① 보강: verified 마커 재검사 — passes==true 각 id 의 .planning/verified/{id} 존재 확인.
markers_ok=true
unverified_ids=""
if [ -f "$TASKS_JSON" ]; then
  while IFS= read -r tid; do
    [ -n "$tid" ] || continue
    if [ ! -f "$PLAN/verified/$tid" ]; then
      markers_ok=false
      unverified_ids="${unverified_ids:+$unverified_ids, }$tid"
    fi
  done < <(jq -r '.tasks[]? | select(.passes == true) | .id' "$TASKS_JSON" 2>/dev/null || true)
fi

# ②ᴱ E2E 수용 게이트 — all-passes 도달 시점에만 1회 실행.
e2e_required=false
e2e_pass=true
e2e_out=""
e2e_exit=0
if [ -n "$E2E_CMD" ] && [ "$all_passes" = true ]; then
  e2e_required=true
  e2e_out="$( (cd "$PROJ" && bash -c "$E2E_CMD") 2>&1 )" || e2e_exit=$?
  if [ "$e2e_exit" -eq 0 ]; then
    e2e_pass=true
    has_failure_marker "$e2e_out" && e2e_pass=false
  else
    e2e_pass=false
  fi
fi

# 실패 시그니처(md5) — no-progress 감지용. 게이트(회귀 포함)·E2E 중 하나라도 레드일 때 산출.
fail_sig=""
if [ "$gate_green" = false ] || [ "$e2e_pass" = false ]; then
  sig_src_raw="$test_out"
  [ "$e2e_required" = true ] && sig_src_raw="$sig_src_raw"$'\n'"E2E:"$'\n'"$e2e_out"
  # 숫자 토큰 제거 정규화 — "1 failed in 0.01s" 류 소요시간 비결정성 제거
  sig_src="$(printf '%s' "$sig_src_raw" | grep -Ei 'fail|error' | sed -E 's/[0-9]+([.][0-9]+)?//g' | sort || true)"
  if [ -z "$sig_src" ]; then
    sig_src="exit=$gate_exit e2e=$e2e_exit"$'\n'"$(printf '%s' "$sig_src_raw" | tail -20)"
  fi
  fail_sig="$(printf '%s' "$sig_src" | hash_stdin 2>/dev/null || echo "")"
fi

# ③ completion promise — 정확 문자열 일치 (grep -qF, 정규식 금지)
promise_found=false
if [ -f "$PROGRESS_FILE" ] && grep -qF "$PROMISE" "$PROGRESS_FILE"; then
  promise_found=true
fi

# 상태 갱신 — started_at은 최초 반복에서 초기화 후 보존, max_iter/max_minutes 보존
next_iter=$((iter + 1))
[ "$started_at" -gt 0 ] || started_at="$now"
jq -n --argjson it "$next_iter" --arg sig "$fail_sig" --argjson st "$started_at" \
  --argjson mi "${state_max_iter:-$MAX_ITER}" --argjson mm "${state_max_minutes:-$MAX_MINUTES}" \
  '{iteration:$it, last_fail_sig:$sig, started_at:$st, max_iter:$mi, max_minutes:$mm}' > "$STATE_FILE"

# 정지 판정: ①∧②ᴿ(게이트 그린=회귀 0) ∧ all-passes ∧ verified 마커 ∧ ②ᴱ(E2E 그린) ∧ ③(promise)
if [ "$gate_green" = true ] && [ "$all_passes" = true ] && [ "$markers_ok" = true ] && [ "$e2e_pass" = true ] && [ "$promise_found" = true ]; then
  rm -f "$PLAN/loop-active"
  e2e_note=""
  [ "$e2e_required" = true ] && e2e_note=" + E2E 그린"
  echo "[floop-loop] 정지조건 충족(게이트 그린 + 회귀 0 + all-passes + verified 마커${e2e_note} + promise) — iteration $next_iter 에서 루프 정상 종료(loop-active 해제)." >&2
  exit 0
fi

# 가드레일 2: no-progress — 직전 반복과 동일 실패 시그니처 연속 시 종료 + BLOCKED 기록
if [ -n "$fail_sig" ] && [ "$fail_sig" = "$last_fail_sig" ]; then
  rm -f "$PLAN/loop-active"
  {
    echo ""
    echo "## no-progress 차단 — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- iteration: $next_iter/$MAX_ITER"
    echo "- 실패 시그니처(md5): $fail_sig (연속 2회 동일)"
    echo "- gate-cmd: $GATE_CMD (exit=$gate_exit)"
    [ -n "$regression_note" ] && echo "- 회귀: $regression_note"
    echo "- 테스트 출력 tail -20:"
    echo '```'
    printf '%s\n' "$test_out" | tail -20
    echo '```'
    echo "- 권장 다음 행동: 실패 원인 분석 후 /floop-run 재개. 스코프 결함은 task-planner 재분해, 구조 한계는 해당 스택 플러그인 가이드 참조."
  } >> "$BLOCKED_FILE"
  echo "[floop-loop] no-progress 감지(동일 실패 시그니처 연속) — 루프 종료(loop-active 해제). 상세는 $BLOCKED_FILE 참조." >&2
  exit 0
fi

# 미충족 → 종료 차단, 작업 재주입 (stderr가 Claude에게 전달됨)
{
  echo "[floop-loop] 작업 미완료 (iteration $next_iter/$MAX_ITER, 재진입=$stop_active). 다음을 해결하고 계속 진행하라:"
  if [ "$gate_green" = false ]; then
    if [ -n "$regression_note" ]; then
      echo "- baseline 회귀 감지: $regression_note 기준선(.planning/baseline.json)에 없던 신규 실패다 — 네 변경이 기존 동작을 깼다. 신규 실패를 0으로 되돌려라(기존 테스트 수정·약화 금지). 게이트 출력 tail -20:"
    else
      echo "- 결정론 게이트 실패 (cmd: $GATE_CMD, exit=$gate_exit). 출력 tail -20:"
    fi
    printf '%s\n' "$test_out" | tail -20
  fi
  if [ "$all_passes" = false ]; then
    unpassed="$(jq -r '[.tasks[] | select(.passes != true) | .id] | join(", ")' "$TASKS_JSON" 2>/dev/null || echo "tasks.json 판독 불가")"
    echo "- 미완 task: ${unpassed:-없음}. 우선순위 최상 task 1개만 선택해 테스트 먼저→최소 구현→feature-verifier 반증→verified 마커→passes 갱신 순으로 진행하라."
  fi
  if [ "$markers_ok" = false ]; then
    echo "- verified 마커 없는 passes:true task: $unverified_ids — feature-verifier 반증을 통과시켜 마커(.planning/verified/{id})를 생성하라."
  fi
  if [ "$e2e_required" = true ] && [ "$e2e_pass" = false ]; then
    echo "- E2E 수용 게이트 실패 (cmd: $E2E_CMD, exit=$e2e_exit). 단위는 통과했으나 유저플로우가 동작하지 않는다. 출력 tail -20:"
    printf '%s\n' "$e2e_out" | tail -20
  fi
  if [ "$promise_found" = false ]; then
    echo "- 모든 task 완료·검증·회귀 0 후 $PROGRESS_FILE 에 '$PROMISE' 를 정확히 기록하라."
  fi
} >&2
exit 2
