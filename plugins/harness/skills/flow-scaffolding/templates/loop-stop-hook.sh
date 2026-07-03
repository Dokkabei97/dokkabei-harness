#!/usr/bin/env bash
# =============================================================================
# Loop Stop-Hook Template — 검증 게이트 기반 세션 내 자율 루프 엔진
# -----------------------------------------------------------------------------
# Stop 훅이 Claude의 종료 시도를 가로채, 정지 조건이 충족될 때까지 작업을 재주입한다.
#   - exit 0  : 종료 허용 (정지 조건 충족 or 가드레일 도달)
#   - exit 2  : 종료 차단. stderr가 Claude에게 전달되어 작업이 이어진다.
#
# 정지 조건(셋 결합): ① 결정론적 게이트(TEST_CMD) ② completion promise ③ max iter
# 가드레일: max iterations · no-progress 감지
#
# 사용: hooks.json의 Stop 이벤트에 등록 (templates/loop-hooks.json 참조)
# 커스터마이즈: 아래 ▼ CONFIG 4개 값만 프로젝트에 맞게 수정.
# =============================================================================
set -euo pipefail

# ▼ CONFIG ───────────────────────────────────────────────────────────────────
TEST_CMD="${LOOP_TEST_CMD:-npm test}"          # 결정론적 게이트 (테스트/린트/타입체크)
PROMISE="${LOOP_PROMISE:-ALL_TASKS_COMPLETE}"  # 완료 약속문 (정확 문자열 일치)
MAX_ITER="${LOOP_MAX_ITER:-10}"                # 반복 상한 (무한루프 차단)
PROGRESS_FILE="${LOOP_PROGRESS_FILE:-.planning/progress.md}"  # promise를 찾을 파일
# ─────────────────────────────────────────────────────────────────────────────

# ── 옵션: 안전핀 + engine 스코프 가드 (프로덕션 역이식 — generic-loop-stop-hook.sh 29·31-35행) ──
# 멀티 루프 엔진 공존 시 .planning/loop-active 의 "engine=<값>" 1줄로 소유권을 판별한다.
# tr -d '\r' 은 CRLF 로 기록된 loop-active 방어 — mvp/floop/generic 프로덕션 훅과 동일 패턴.
# 활성화: 아래 4줄 주석 해제 + <my-engine> 을 자기 엔진명으로 교체 (LOOP-001/002 룰 충족).
# PLAN="${CLAUDE_PROJECT_DIR:-.}/.planning"
# [ -f "$PLAN/loop-active" ] || exit 0                                      # 루프 미가동 세션은 무개입
# loop_engine="$(grep -m1 '^engine=' "$PLAN/loop-active" 2>/dev/null | tr -d '\r' || true)"
# [ "${loop_engine#engine=}" = "<my-engine>" ] || exit 0                    # 타 엔진 소유·레거시는 무주장
# ─────────────────────────────────────────────────────────────────────────────

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.planning/loop-state.json"
mkdir -p "$(dirname "$STATE_FILE")"

# stdin 해시 (no-progress 시그니처용) — macOS/Linux 이식성 폴백
hash_stdin() {
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

# stdin 입력(JSON) 읽기 — stop_hook_active로 재진입 여부 확인
input="$(cat || true)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"

# 상태 로드
iter=0; last_fail_sig=""
if [ -f "$STATE_FILE" ]; then
  iter="$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  last_fail_sig="$(jq -r '.last_fail_sig // ""' "$STATE_FILE" 2>/dev/null || echo "")"
fi

# 가드레일 1: max iterations
if [ "$iter" -ge "$MAX_ITER" ]; then
  echo "[loop] max iterations($MAX_ITER) 도달 — 종료. 미완 상태는 $PROGRESS_FILE 참조." >&2
  exit 0   # 종료 허용
fi

# ── 옵션: 가드레일 — 시간 상한 (프로덕션 역이식 — mvp-loop-stop-hook.sh 113-119행) ──
# loop-state.json 의 started_at(epoch 초, 최초 반복에서 기록) 대비 상한(분) 초과 시 종료 허용.
# 활성화: 주석 해제 + 아래 '상태 갱신' jq 에 started_at 필드를 추가해 최초 값을 보존하라.
# MAX_MINUTES="${LOOP_MAX_MINUTES:-60}"
# case "$MAX_MINUTES" in (''|*[!0-9]*) MAX_MINUTES=60;; esac
# started_at="$(jq -r '.started_at // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
# case "$started_at" in (''|*[!0-9]*) started_at=0;; esac
# if [ "$started_at" -gt 0 ] && [ $(( $(date +%s) - started_at )) -ge $(( MAX_MINUTES * 60 )) ]; then
#   echo "[loop] 시간 상한 도달(${MAX_MINUTES}분 초과) — 종료. 미완 상태는 $PROGRESS_FILE 참조." >&2
#   exit 0
# fi
# ─────────────────────────────────────────────────────────────────────────────

# 출력의 명백한 실패 표지 판정 — exit 0 이어도 출력에 실패 카운트가 있으면 보수적으로 레드.
# "0 failed" 류 오탐 방지: 행두 FAIL 또는 1 이상 카운트가 붙은 실패 표지만 매칭 (LOOP-009).
# ※ 정규식은 mvp/floop/generic 프로덕션 훅과 공유 규약 — 변경 시 함께 갱신하라.
has_failure_marker() { printf '%s\n' "$1" | grep -Eqi '(^FAIL([ :]|$)|[1-9][0-9]* +(fail(ed|ure|ures)?|errors?))'; }

# ① 결정론적 게이트 실행 — eval 금지, bash -c 사용 (LOOP 룰). 판정은 exit code 우선.
gate_exit=0
test_out="$(bash -c "$TEST_CMD" 2>&1)" || gate_exit=$?
tests_pass=true
if [ "$gate_exit" -ne 0 ]; then
  tests_pass=false
elif has_failure_marker "$test_out"; then
  tests_pass=false
fi

# 실패 시그니처 — no-progress 감지용. 게이트 레드일 때만 산출.
fail_sig=""
if [ "$tests_pass" = false ]; then
  fail_sig="$(printf '%s' "$test_out" | grep -Ei 'fail|error' | sort | hash_stdin 2>/dev/null || echo "")"
  [ -n "$fail_sig" ] || fail_sig="$(printf 'exit=%s\n%s' "$gate_exit" "$(printf '%s' "$test_out" | tail -20)" | hash_stdin 2>/dev/null || echo "")"
fi

# ── 옵션: E2E 수용 게이트 / baseline 회귀 게이트 (프로덕션 역이식 — mvp ②ᴱ 155-170행 · floop ②ᴿ 140-177행) ──
# E2E: .planning/e2e-gate-cmd(또는 LOOP_E2E_CMD env)가 있으면 최종 수용 시점에 1회 실행해
#      단위 게이트가 놓치는 전체 유저플로우 동작을 보증한다. 파일 부재 시 미적용(통과 간주).
# 활성화: 주석 해제 후 아래 '정지 판정' 조건에 [ "$e2e_pass" = true ] 를 AND 로 추가하라.
# e2e_pass=true
# E2E_CMD="${LOOP_E2E_CMD:-}"
# if [ -z "$E2E_CMD" ] && [ -s "${CLAUDE_PROJECT_DIR:-.}/.planning/e2e-gate-cmd" ]; then
#   E2E_CMD="$(head -n 1 "${CLAUDE_PROJECT_DIR:-.}/.planning/e2e-gate-cmd" | tr -d '\r')"
# fi
# if [ -n "$E2E_CMD" ]; then
#   e2e_out="$(bash -c "$E2E_CMD" 2>&1)" || e2e_pass=false
# fi
# baseline 회귀 게이트(브라운필드): red 기준선 프로젝트는 "신규 회귀 0"을 게이트 통과로 재정의한다
# — .planning/baseline.json 의 baseline_exit/fail_count 대비 현재 실패 수를 비교해 증가분만 차단.
# 구현 전체는 floop-loop-stop-hook.sh 85-93행(extract_fail_count)·140-177행(판정 정책)을 복제하라.
# ─────────────────────────────────────────────────────────────────────────────

# ② completion promise 확인
promise_found=false
[ -f "$PROGRESS_FILE" ] && grep -qF "$PROMISE" "$PROGRESS_FILE" && promise_found=true

# 상태 갱신
next_iter=$((iter + 1))
jq -n --argjson it "$next_iter" --arg sig "$fail_sig" \
  '{iteration:$it, last_fail_sig:$sig}' > "$STATE_FILE"

# ── 옵션: verified 마커 재검사 (프로덕션 역이식 — mvp-loop-stop-hook.sh 141-153행) ──
# prd.json/tasks.json 산출물 구조를 쓰는 루프에서 passes:true 각 id 의 .planning/verified/{id}
# 존재를 재검사한다 — guard 훅(Edit|Write 포착)을 Bash 리다이렉션으로 우회한 자기승인의 최종 방어선.
# 활성화: 주석 해제 후 아래 '정지 판정' 조건에 [ "$markers_ok" = true ] 를 AND 로 추가하라.
# markers_ok=true
# while IFS= read -r sid; do
#   [ -n "$sid" ] || continue
#   [ -f "${CLAUDE_PROJECT_DIR:-.}/.planning/verified/$sid" ] || markers_ok=false
# done < <(jq -r '.stories[]? | select(.passes == true) | .id' \
#   "${CLAUDE_PROJECT_DIR:-.}/.planning/prd.json" 2>/dev/null || true)
# ─────────────────────────────────────────────────────────────────────────────

# 정지 판정: 게이트 통과 AND promise 존재 → 종료 허용
if [ "$tests_pass" = true ] && [ "$promise_found" = true ]; then
  echo "[loop] 정지 조건 충족(테스트 그린 + promise) — iteration $iter 종료." >&2
  exit 0
fi

# 가드레일 2: no-progress (동일 실패 시그니처 연속) → 종료 + 기록
if [ -n "$fail_sig" ] && [ "$fail_sig" = "$last_fail_sig" ]; then
  echo "[loop] no-progress 감지(동일 실패 반복) — 종료. BLOCKED.md에 기록 권장." >&2
  exit 0
fi

# 미충족 → 종료 차단, 작업 재주입 (stderr가 Claude에게 전달됨)
{
  echo "작업 미완료(iteration $next_iter/$MAX_ITER). 계속 진행하라:"
  [ "$tests_pass" = false ] && echo "- 실패한 테스트가 남아 있다. 다음 출력을 보고 수정하라:"
  [ "$tests_pass" = false ] && printf '%s\n' "$test_out" | tail -20
  [ "$promise_found" = false ] && echo "- 모든 작업 완료 시 $PROGRESS_FILE 에 '$PROMISE' 를 기록하라."
} >&2
exit 2
