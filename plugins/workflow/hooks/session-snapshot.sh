#!/usr/bin/env bash
# =============================================================================
# session-snapshot.sh — HANDOFF.md 자동 스냅샷 (PreCompact + SessionEnd 공용 훅)
#
# 결정론 스냅샷 전용 — 훅 프로세스에는 LLM이 없어 대화 요약이 불가능하다.
# 여기서는 기계적으로 수집 가능한 상태(타임스탬프·git 상태·미완 마커 수)만
# 기록하고, 의미 요약(세션 목표·시도·다음 단계)은 /handoff 커맨드 소관이다.
# 두 축은 상호 보완: 훅이 "마지막 순간의 기계 상태"를 자동 보존하고,
# /handoff 가 "대화 맥락의 의미"를 사람이 트리거해 채운다.
#
# 동작: HANDOFF.md 안의 '<!-- auto-snapshot -->' ~ '<!-- /auto-snapshot -->'
# 마커 섹션만 갱신한다. 파일 부재 시 마커 섹션만으로 생성하고, 마커 부재 시
# 말미에 덧붙인다 — 마커 밖의 수동 작성 내용은 어떤 경로에서도 접촉하지 않는다.
# (마커 라인을 수동 편집/부분 삭제하면 섹션 인식이 깨지므로 그대로 둘 것)
#
# 소유권 가드([공유 계약 1] 스코프 분리): .planning/loop-active 존재 시 즉시
# exit 0 — 루프 세션의 컨텍스트 앵커는 mvp/floop 플러그인 PreCompact 소관이다.
#
# 충돌 확인: base 플러그인 block-md-creation.js 는 PreToolUse 에서 Write 도구의
# tool_input.file_path 만 매치한다 — 본 훅처럼 셸이 직접 파일을 쓰는 경로는
# 도구 호출이 아니므로 차단 비대상이다.
#
# 항상 exit 0 — 스냅샷 실패가 컴팩션/세션 종료를 방해해서는 안 된다
# (수집 명령 전부 || true 방어 + 본체 main || true 이중 방어).
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# (a) 소유권 가드 — 루프 세션의 앵커는 mvp/floop PreCompact 소관 (무접촉 종료)
if [ -f "$PROJ/.planning/loop-active" ]; then exit 0; fi

# (b) git repo 가 아니면 무동작 — 스냅샷의 핵심이 git 상태라 기록할 것이 없다
git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

HANDOFF="$PROJ/HANDOFF.md"
BEGIN_MARK='<!-- auto-snapshot -->'
END_MARK='<!-- /auto-snapshot -->'

SNAP_TMP="$(mktemp "${TMPDIR:-/tmp}/handoff-snap.XXXXXX" 2>/dev/null)" || exit 0
OUT_TMP="$SNAP_TMP.out"
trap 'rm -f "$SNAP_TMP" "$OUT_TMP"' EXIT

# 마커 섹션 본문 생성 — 수집 명령 전부 || true (일부 실패해도 나머지는 기록)
build_snapshot() {
  local ts branch status_lines commits pending
  ts="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || true)"
  branch="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
  status_lines="$(git -C "$PROJ" status --short 2>/dev/null | head -n 10 || true)"
  commits="$(git -C "$PROJ" log --oneline -5 2>/dev/null || true)"
  [ -n "$ts" ]           || ts="(시각 수집 실패)"
  [ -n "$branch" ]       || branch="(브랜치 없음)"
  [ -n "$status_lines" ] || status_lines="(변경 없음)"
  [ -n "$commits" ]      || commits="(커밋 없음)"

  printf '%s\n' "$BEGIN_MARK"
  printf '## 자동 스냅샷 (session-snapshot 훅)\n'
  printf '> PreCompact/SessionEnd 시점에 훅이 기계적으로 기록한 상태다. 세션 의미 요약(목표·시도·다음 단계)은 /handoff 커맨드로 생성하라.\n'
  printf '\n'
  printf -- '- 기록 시각: %s\n' "$ts"
  printf -- '- 브랜치: %s\n' "$branch"
  # 미완 마커 — .planning 존재 시에만 prd.json/tasks.json 의 passes:false 를 계수.
  # jq 부재 환경 graceful degrade 를 위해 처음부터 grep 계수만 사용한다.
  if [ -d "$PROJ/.planning" ]; then
    pending="$({ grep -oh '"passes"[[:space:]]*:[[:space:]]*false' \
      "$PROJ/.planning/prd.json" "$PROJ/.planning/tasks.json" 2>/dev/null || true; } \
      | wc -l | tr -d ' ')"
    printf -- '- 미완 마커(passes:false): %s건\n' "${pending:-0}"
  fi
  printf '\n'
  printf '### 변경 파일 (git status --short 상위 10줄)\n'
  printf '```\n%s\n```\n' "$status_lines"
  printf '\n'
  printf '### 최근 커밋 5줄\n'
  printf '```\n%s\n```\n' "$commits"
  printf '%s\n' "$END_MARK"
}

main() {
  build_snapshot > "$SNAP_TMP"

  if [ ! -f "$HANDOFF" ]; then
    # (c) 파일 부재 — 마커 섹션만으로 생성
    cp "$SNAP_TMP" "$HANDOFF"
  elif grep -qxF "$BEGIN_MARK" "$HANDOFF" && grep -qxF "$END_MARK" "$HANDOFF"; then
    # (d) 마커 쌍 존재 — 섹션만 새 내용으로 교체, 마커 밖은 바이트 그대로 통과
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v snap="$SNAP_TMP" '
      $0 == begin && !inblock {
        inblock = 1
        while ((getline line < snap) > 0) print line
        close(snap)
        next
      }
      $0 == end && inblock { inblock = 0; next }
      !inblock { print }
    ' "$HANDOFF" > "$OUT_TMP"
    # 빈 산출물이면 교체하지 않는다 — 수동 작성 내용 보호 최종 방어선
    if [ -s "$OUT_TMP" ]; then mv "$OUT_TMP" "$HANDOFF"; fi
  else
    # (e) 마커 없음(수동 작성 파일 또는 마커 쌍 훼손) — 기존 내용 무접촉, 말미에 추가
    { printf '\n'; cat "$SNAP_TMP"; } >> "$HANDOFF"
  fi
}

main || true
exit 0
