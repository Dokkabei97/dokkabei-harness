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

# ① 결정론적 게이트 실행
test_out="$(eval "$TEST_CMD" 2>&1 || true)"
fail_sig="$(printf '%s' "$test_out" | grep -Ei 'fail|error' | sort | hash_stdin 2>/dev/null || echo "")"
tests_pass=true
printf '%s' "$test_out" | grep -Eqi 'fail|error' && tests_pass=false

# ② completion promise 확인
promise_found=false
[ -f "$PROGRESS_FILE" ] && grep -qF "$PROMISE" "$PROGRESS_FILE" && promise_found=true

# 상태 갱신
next_iter=$((iter + 1))
jq -n --argjson it "$next_iter" --arg sig "$fail_sig" \
  '{iteration:$it, last_fail_sig:$sig}' > "$STATE_FILE"

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
