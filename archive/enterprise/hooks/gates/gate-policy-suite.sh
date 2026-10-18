#!/usr/bin/env bash
# =============================================================================
# gate-policy-suite.sh — GRC 결정론 게이트 (/policy-suite 커맨드가 Bash 호출)
# 대상: .planning/grc/policies/ + .planning/grc/policy-index.json
# 검사:
#   ① 필수 문서 존재 — code-of-conduct.md(행동강령) + whistleblowing-policy.md(내부신고 규정)
#   ② 각 정책(.md) frontmatter 에 owner:·review_date: 존재, review_date < TODAY → 실패
#   ③ policy-index.json 의 정책 목록(basename) ↔ policies/ 실제 *.md diff ≠ 0 → 실패
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
POLDIR="$PROJ/.planning/grc/policies"
INDEX="$PROJ/.planning/grc/policy-index.json"
TODAY="${GATE_TODAY:-$(date +%F)}"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-policy-suite] 실패: jq 미설치 — policy-index.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -d "$POLDIR" ]; then
  echo "[gate-policy-suite] 실패: $POLDIR 디렉토리 없음" >&2
  exit 1
fi

# ① 필수 문서
for req in code-of-conduct.md whistleblowing-policy.md; do
  if [ ! -f "$POLDIR/$req" ]; then
    echo "[gate-policy-suite] 실패: 필수 정책 문서 부재 — policies/$req" >&2
    fail=1
  fi
done

# ② 각 정책 frontmatter owner/review_date + review_date 도과
shopt -s nullglob
for f in "$POLDIR"/*.md; do
  base="$(basename "$f")"
  owner_line="$(grep -m1 '^owner:' "$f" || true)"
  rd_line="$(grep -m1 '^review_date:' "$f" || true)"
  if [ -z "$owner_line" ]; then
    echo "[gate-policy-suite] 실패: $base frontmatter 에 owner 없음" >&2
    fail=1
  fi
  if [ -z "$rd_line" ]; then
    echo "[gate-policy-suite] 실패: $base frontmatter 에 review_date 없음" >&2
    fail=1
    continue
  fi
  # review_date 값 추출 (따옴표·공백 제거)
  rd="${rd_line#review_date:}"
  rd="$(printf '%s' "$rd" | tr -d '[:space:]"'"'"'')"
  if [ "$rd" \< "$TODAY" ]; then
    echo "[gate-policy-suite] 실패: $base review_date 도과 (review_date=$rd < $TODAY)" >&2
    fail=1
  fi
done
shopt -u nullglob

# ③ index ↔ 실파일 diff
if [ ! -f "$INDEX" ]; then
  echo "[gate-policy-suite] 실패: $INDEX 없음" >&2
  fail=1
elif ! jq -e '.policies | type=="array"' "$INDEX" >/dev/null 2>&1; then
  echo "[gate-policy-suite] 실패: policy-index.json 에 policies 배열 없음(또는 파싱 불가)" >&2
  fail=1
else
  actual="$( (cd "$POLDIR" && ls -1 ./*.md 2>/dev/null) | sed 's#.*/##' | sort -u || true)"
  indexed="$(jq -r '.policies[]?' "$INDEX" | sed 's#.*/##' | sort -u || true)"
  if [ "$actual" != "$indexed" ]; then
    only_files="$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$indexed") | tr '\n' ' ')"
    only_index="$(comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$indexed") | tr '\n' ' ')"
    echo "[gate-policy-suite] 실패: policy-index ↔ 실파일 불일치 — 인덱스누락:[$only_files] 파일누락:[$only_index]" >&2
    fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-policy-suite] 통과: 필수 문서·frontmatter(owner/review_date)·review_date·index 정합 검증 완료"
fi
exit "$fail"
