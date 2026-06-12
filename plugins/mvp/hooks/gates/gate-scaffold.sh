#!/usr/bin/env bash
# =============================================================================
# gate-scaffold.sh — Stage 3 결정론 게이트 (훅 미등록, 오케스트레이터/커맨드가 Bash 호출)
# 검사 (정본: gate-policy.md):
#   ① git 작업 트리 클린(git status --porcelain 무출력 — gate-cmd 실행 전 검사)
#      + git 초기 커밋 존재(git rev-parse HEAD)
#   ② .planning 필수 파일 — mvp-*.md 마스터(1+)/prd.md/prd.json/design-spec.md/
#      stack-decision.md/gate-cmd/progress.md 존재 + verified/ 디렉토리 존재
#   ③ gate-cmd 비어있지 않은 정확히 1줄 + bash -c 실행 그린(exit 0)
# 실패 항목은 stderr 에 전부 나열. 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"
fail=0

# ① git 작업 트리 클린 — gate-cmd 실행 전에 검사 (실행 산출물로 인한 오염 판정 방지)
if [ -n "$(git -C "$PROJ" status --porcelain 2>/dev/null)" ]; then
  echo "[gate-scaffold] 실패: git 작업 트리 미클린 (git status --porcelain 출력 존재 — 스캐폴드 커밋 필요)" >&2; fail=1
fi
# ① git 초기 커밋 존재
if ! git -C "$PROJ" rev-parse HEAD >/dev/null 2>&1; then
  echo "[gate-scaffold] 실패: git 초기 커밋 없음 (git rev-parse HEAD 실패 — git init + 초기 커밋 필요)" >&2; fail=1
fi

# ② .planning 필수 파일 + verified/ 디렉토리
for f in prd.md prd.json design-spec.md stack-decision.md gate-cmd progress.md; do
  if [ ! -f "$PLAN/$f" ]; then
    echo "[gate-scaffold] 실패: .planning/$f 없음" >&2; fail=1
  fi
done
master_found=0
for f in "$PLAN"/mvp-*.md; do
  if [ -f "$f" ]; then master_found=1; break; fi
done
if [ "$master_found" -eq 0 ]; then
  echo "[gate-scaffold] 실패: .planning/mvp-*.md 마스터 파일 없음" >&2; fail=1
fi
if [ ! -d "$PLAN/verified" ]; then
  echo "[gate-scaffold] 실패: .planning/verified/ 디렉토리 없음" >&2; fail=1
fi

# ③ gate-cmd — 비어있지 않은 정확히 1줄 + bash -c 실행 그린 (eval 금지)
GATE_FILE="$PLAN/gate-cmd"
if [ ! -s "$GATE_FILE" ]; then
  echo "[gate-scaffold] 실패: $GATE_FILE 없음 또는 빈 파일 (tech-architect 가 기록해야 함)" >&2; fail=1
else
  lines="$(grep -c '' "$GATE_FILE" 2>/dev/null || true)"
  case "$lines" in (''|*[!0-9]*) lines=0;; esac
  GATE_CMD="$(head -n 1 "$GATE_FILE" | tr -d '\r')"
  if [ "$lines" -ne 1 ] || [ -z "${GATE_CMD//[[:space:]]/}" ]; then
    echo "[gate-scaffold] 실패: gate-cmd 는 비어있지 않은 정확히 1줄이어야 함 (현재 ${lines}줄)" >&2; fail=1
  else
    gate_exit=0
    out="$( (cd "$PROJ" && bash -c "$GATE_CMD") 2>&1 )" || gate_exit=$?
    if [ "$gate_exit" -ne 0 ]; then
      echo "[gate-scaffold] 실패: gate-cmd 실행 실패 (exit=$gate_exit, cmd: $GATE_CMD). 출력 tail -10:" >&2
      printf '%s\n' "$out" | tail -10 >&2
      fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-scaffold] 통과: git 클린 트리·초기 커밋 + .planning 필수 파일(verified/ 포함) + gate-cmd 1줄·실행 그린"
fi
exit "$fail"
