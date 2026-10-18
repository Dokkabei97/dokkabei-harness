#!/usr/bin/env bash
# =============================================================================
# gate-adr.sh — ADR(아키텍처 결정 기록) 무결성 게이트 (완전 결정론 — 외부 도구 없음)
# 정본: governance-templates 스킬 references/madr-template.md.
# 검사 (모두 ls/grep/sort — CVE·네트워크 의존 없음):
#   ① docs/decisions/ 디렉토리 존재 (부재 → /gov-init 안내 exit 1)
#   ② 각 *.md 파일명이 ^NNNN- (4자리 번호 접두) 규약 준수 (README.md 는 예외)
#   ③ ADR 번호 중복 없음 (sort | uniq -d)
#   ④ 각 ADR 이 status: {proposed|accepted|superseded|deprecated} 중 1개를 명시
#   ⑤ status: superseded 인 ADR 은 superseded-by: NNNN 이 실재 ADR 을 가리킬 것
# 인자 없이 동작(루프 gate-cmd 직결). 위반은 stderr 1줄씩. 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
ADR_DIR="$PROJ/docs/decisions"
fail=0

# ① 디렉토리 존재
if [ ! -d "$ADR_DIR" ]; then
  echo "[gate-adr] 실패: $ADR_DIR 없음 — /gov-init 으로 베이스라인을 먼저 스캐폴딩하세요." >&2
  exit 1
fi

# ADR 파일 수집 (README.md 제외). nullglob 대신 존재 검사 idiom 사용.
adr_files=()
for f in "$ADR_DIR"/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in README.md) continue;; esac
  adr_files+=("$f")
done

if [ "${#adr_files[@]}" -eq 0 ]; then
  echo "[gate-adr] 통과: ADR 없음 — 검사 대상 없음(공허 통과). /gov-adr 로 첫 결정을 기록하세요."
  exit 0
fi

numbers=""
for f in "${adr_files[@]}"; do
  base="$(basename "$f")"
  # ② 파일명 ^NNNN- 규약
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-'; then
    echo "[gate-adr] 실패: 파일명 규약 위반 — '$base' 는 ^NNNN- (예: 0001-title.md) 형식이어야 함" >&2
    fail=1
    continue
  fi
  num="${base%%-*}"
  numbers="${numbers}${num}\n"

  # ④ status 필드 enum
  if ! grep -iqE '(^|[*-][[:space:]]*)status:[[:space:]]*"?(proposed|accepted|superseded|deprecated)"?' "$f"; then
    echo "[gate-adr] 실패: $base — status: {proposed|accepted|superseded|deprecated} 중 하나가 없음" >&2
    fail=1
  fi

  # ⑤ superseded → superseded-by: NNNN 대상 실재
  if grep -iqE '(^|[*-][[:space:]]*)status:[[:space:]]*"?superseded"?' "$f"; then
    target="$(grep -ioE 'superseded-by:[[:space:]]*"?[0-9]{4}' "$f" | grep -oE '[0-9]{4}' | head -n1 || true)"
    if [ -z "$target" ]; then
      echo "[gate-adr] 실패: $base — status superseded 인데 superseded-by: NNNN 링크가 없음" >&2
      fail=1
    else
      hit=0
      for g in "$ADR_DIR"/"$target"-*.md; do [ -f "$g" ] && hit=1 && break; done
      if [ "$hit" -eq 0 ]; then
        echo "[gate-adr] 실패: $base — superseded-by: $target 가 실재하는 ADR 을 가리키지 않음" >&2
        fail=1
      fi
    fi
  fi
done

# ③ 번호 중복
dups="$(printf '%b' "$numbers" | grep -vE '^$' | sort | uniq -d || true)"
if [ -n "$dups" ]; then
  echo "[gate-adr] 실패: 중복된 ADR 번호 — $(printf '%s' "$dups" | paste -sd, -)" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-adr] 통과: ${#adr_files[@]}개 ADR — 파일명 규약·번호 유일성·status enum·supersede 링크 무결성 검증 완료"
fi
exit "$fail"
