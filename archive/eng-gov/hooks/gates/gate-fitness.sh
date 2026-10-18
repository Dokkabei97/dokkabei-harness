#!/usr/bin/env bash
# =============================================================================
# gate-fitness.sh — 아키텍처 피트니스 함수 게이트 (설정 자체가 룰의 단일 진실 원천)
# 정본: fitness-function-guide 스킬. 도구가 위반 시 비정상 exit 하는 계약을 그대로 전파한다.
# 검사 대상 감지(스택별):
#   • .dependency-cruiser.*  → $DEPCRUISE_BIN  --validate   (기본 depcruise)
#   • .importlinter          → $LINT_IMPORTS_BIN            (기본 lint-imports)
#   • build 파일 archunit 참조 → 안내(경고, exit 무영향) — ArchUnit 은 테스트 러너 몫
# 정책: 설정 0건 → "검사 대상 없음" 공허 통과 exit 0 / 설정 있고 도구 부재 → fail-closed exit 1
#       / 도구 실행 exit 그대로 전파. 인자 없이 동작(루프 gate-cmd 직결).
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
DEPCRUISE_BIN="${DEPCRUISE_BIN:-depcruise}"
LINT_IMPORTS_BIN="${LINT_IMPORTS_BIN:-lint-imports}"
fail=0
found=0

# ── dependency-cruiser (.dependency-cruiser.{js,cjs,mjs,json}) ────────────────
dc_present=0
for f in "$PROJ"/.dependency-cruiser.*; do [ -f "$f" ] && dc_present=1 && break; done
if [ "$dc_present" -eq 1 ]; then
  found=1
  if ! command -v "$DEPCRUISE_BIN" >/dev/null 2>&1; then
    echo "[gate-fitness] 실패: .dependency-cruiser.* 설정 존재하나 '$DEPCRUISE_BIN' 미설치 — 설치: npm i -g dependency-cruiser (또는 DEPCRUISE_BIN 오버라이드)" >&2
    fail=1
  else
    dc_exit=0
    out="$( (cd "$PROJ" && "$DEPCRUISE_BIN" --validate) 2>&1 )" || dc_exit=$?
    if [ "$dc_exit" -ne 0 ]; then
      echo "[gate-fitness] 실패: dependency-cruiser --validate 위반 (exit=$dc_exit)" >&2
      printf '%s\n' "$out" | tail -10 >&2
      fail=1
    fi
  fi
fi

# ── import-linter (.importlinter) ─────────────────────────────────────────────
if [ -f "$PROJ/.importlinter" ]; then
  found=1
  if ! command -v "$LINT_IMPORTS_BIN" >/dev/null 2>&1; then
    echo "[gate-fitness] 실패: .importlinter 설정 존재하나 '$LINT_IMPORTS_BIN' 미설치 — 설치: pip install import-linter (또는 LINT_IMPORTS_BIN 오버라이드)" >&2
    fail=1
  else
    il_exit=0
    out="$( (cd "$PROJ" && "$LINT_IMPORTS_BIN") 2>&1 )" || il_exit=$?
    if [ "$il_exit" -ne 0 ]; then
      echo "[gate-fitness] 실패: import-linter 계약 위반 (exit=$il_exit)" >&2
      printf '%s\n' "$out" | tail -10 >&2
      fail=1
    fi
  fi
fi

# ── ArchUnit (build 파일 참조 감지 → 안내만, exit 무영향) ─────────────────────
for bf in "$PROJ"/build.gradle "$PROJ"/build.gradle.kts "$PROJ"/pom.xml; do
  if [ -f "$bf" ] && grep -qi 'archunit' "$bf" 2>/dev/null; then
    echo "[gate-fitness] 경고: ArchUnit 참조 감지($(basename "$bf")) — 아키텍처 규칙은 테스트 러너(gate-cmd)에서 실행하세요. 이 게이트는 판정하지 않습니다." >&2
    break
  fi
done

if [ "$found" -eq 0 ] && [ "$fail" -eq 0 ]; then
  echo "[gate-fitness] 통과: 피트니스 함수 설정 없음 — 검사 대상 없음(공허 통과). /gov-adr 로 결정을 검사로 변환하는 방법은 fitness-function-guide 스킬 참조."
  exit 0
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-fitness] 통과: 감지된 피트니스 함수 설정 전부 그린(exit 0)"
fi
exit "$fail"
