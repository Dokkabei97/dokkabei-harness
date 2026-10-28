#!/usr/bin/env bash
# specialist-index.sh — 스택 플러그인 references 의 스페셜리스트 항목을 1줄 TSV 로 색인한다.
# 사용: specialist-index.sh <root> [plugin...]
#   <root>: 플러그인들이 형제로 놓인 디렉터리
#           - 설치본: ~/.claude/plugins/cache/dokkabei-harness   (<plugin>/<version>/skills/…)
#           - 레포:   <dokkabei-harness clone>/plugins            (<plugin>/skills/…)
#   plugin 을 생략하면 root 아래 전부.
# 출력(TSV): plugin  skill  id  title  applies  file
#   항목 포맷 계약: "### <PREFIX>-<AREA>-<NN> · <제목>" (PREFIX·AREA 는 대문자로 시작, 숫자 허용 — 예: NX-V16-01) 다음 줄들 중 "- 적용: …" 을 applies 로 읽는다.
# 버전 디렉터리가 여럿이면 sort -V 기준 최신 1개만 본다. 읽기 전용 — 아무것도 쓰지 않는다.
set -u
root="${1:?usage: specialist-index.sh <root> [plugin...]}"
shift
[ -d "$root" ] || { echo "no such dir: $root" >&2; exit 1; }
root=$(cd "$root" && pwd)   # file 열을 절대 경로로 — 호출자가 다른 cwd 에서 awk 로 읽어도 깨지지 않게
if [ "$#" -eq 0 ]; then
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    set -- "$@" "${d##*/}"
  done
fi
for p in "$@"; do
  base="$root/$p"
  [ -d "$base" ] || continue
  if [ -d "$base/skills" ]; then
    pdir="$base"
  else
    v=$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)
    [ -n "$v" ] && [ -d "$base/$v/skills" ] || continue
    pdir="$base/$v"
  fi
  for f in "$pdir"/skills/*/references/*.md; do
    [ -f "$f" ] || continue
    skill=$(basename "$(dirname "$(dirname "$f")")")
    awk -v plugin="$p" -v skill="$skill" -v file="$f" '
      function flush() { if (id != "") printf "%s\t%s\t%s\t%s\t%s\t%s\n", plugin, skill, id, title, applies, file }
      /^### [A-Z][A-Z0-9]*-[A-Z][A-Z0-9]*-[0-9]+ · / {
        flush()
        id = $2; title = $0; sub(/^### [^ ]+ · /, "", title); applies = ""; next
      }
      /^#{1,3} / { flush(); id = ""; next }
      id != "" && applies == "" && /^- 적용:/ { applies = $0; sub(/^- 적용:[ ]*/, "", applies); gsub(/\t/, " ", applies) }
      END { flush() }
    ' "$f"
  done
done
