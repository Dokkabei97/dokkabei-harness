#!/usr/bin/env bash
# specialist-index.sh — 스택 플러그인 references 의 스페셜리스트 항목을 1줄 TSV 로 색인한다.
# 사용: specialist-index.sh <root|auto> [plugin...]
#   <root>: 플러그인들이 형제로 놓인 디렉터리
#           - Claude Code 설치본: ~/.claude/plugins/cache/dokkabei-harness        (<plugin>/<version>/skills/…)
#           - Codex 설치본:       ~/.codex/plugins/cache/dokkabei-harness         (<plugin>/<version>/skills/…)
#           - Antigravity 설치본: ~/.gemini/config/plugins, <ws>/.agents/plugins  (<plugin>/skills/…, agy plugin install 변환본)
#           - 레포:               <dokkabei-harness clone>/plugins                (<plugin>/skills/…)
#   auto:   플러그인마다 아래 순서로 처음 찾은 곳을 쓴다(Codex·Antigravity 는 ${CLAUDE_PLUGIN_ROOT} 를 스킬 본문에
#           치환하지 않으므로 경로를 이 스크립트가 정한다):
#           1) 이 스크립트가 놓인 설치본의 형제 플러그인(<pluginroot>/.. 평면형, <pluginroot>/../.. 버전형)
#           2) ~/.claude/plugins/cache/dokkabei-harness  3) ${CODEX_HOME:-~/.codex}/plugins/cache/dokkabei-harness
#           4) ./.agents/plugins  5) ~/.gemini/config/plugins
#   plugin 을 생략하면 root(auto 면 1번 위치) 아래 전부.
# 출력(TSV, stdout): plugin  skill  id  title  applies  file
#   항목 포맷 계약: "### <PREFIX>-<AREA>-<NN> · <제목>" (PREFIX·AREA 는 대문자로 시작, 숫자 허용 — 예: NX-V16-01) 다음 줄들 중 "- 적용: …" 을 applies 로 읽는다.
# 원천 요약(stderr): 플러그인마다 "source<TAB>plugin<TAB>version<TAB>items<TAB>dir" 1줄 — 0 이면 구버전 설치본, 못 찾으면 dir=-.
# 버전 디렉터리가 여럿이면 sort -V 기준 최신 1개만 본다. 읽기 전용 — 아무것도 쓰지 않는다.
set -u
root="${1:?usage: specialist-index.sh <root|auto> [plugin...]}"
shift

# 한 후보 루트에서 플러그인 디렉터리(skills 를 가진 곳)를 찾는다 — 평면형 우선, 아니면 최신 버전 디렉터리.
plugin_dir() { # <root> <plugin>
  local base="$1/$2" v
  [ -d "$base" ] || return 1
  if [ -d "$base/skills" ]; then printf '%s\n' "$base"; return 0; fi
  v=$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)
  [ -n "$v" ] && [ -d "$base/$v/skills" ] || return 1
  printf '%s\n' "$base/$v"
}

if [ "$root" = auto ]; then
  sd=$(cd "$(dirname "$0")" && pwd)          # …/skills/project-rules/scripts
  proot=$(cd "$sd/../../.." && pwd)          # workflow 플러그인 루트(평면형 <root>/workflow, 버전형 <root>/workflow/<ver>)
  roots=("$(dirname "$proot")" "$(dirname "$(dirname "$proot")")"
         "$HOME/.claude/plugins/cache/dokkabei-harness"
         "${CODEX_HOME:-$HOME/.codex}/plugins/cache/dokkabei-harness"
         "$PWD/.agents/plugins" "$HOME/.gemini/config/plugins")
  if [ "$#" -eq 0 ]; then
    self=$(dirname "$proot")
    [ -d "$self/workflow/skills" ] || self=$(dirname "$self")
    root="$self"
  fi
else
  [ -d "$root" ] || { echo "no such dir: $root" >&2; exit 1; }
  roots=("$root")
fi
if [ "$#" -eq 0 ]; then
  root=$(cd "$root" && pwd)
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    set -- "$@" "${d##*/}"
  done
fi

for p in "$@"; do
  pdir=""
  for r in "${roots[@]}"; do
    [ -d "$r" ] || continue
    pdir=$(plugin_dir "$(cd "$r" && pwd)" "$p") && break   # file 열을 절대 경로로 — 다른 cwd 에서 읽어도 깨지지 않게
    pdir=""
  done
  if [ -z "$pdir" ]; then printf 'source\t%s\t-\t0\t-\n' "$p" >&2; continue; fi
  ver=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$pdir/.claude-plugin/plugin.json" "$pdir/plugin.json" 2>/dev/null | head -1)
  n=0
  for f in "$pdir"/skills/*/references/*.md; do
    [ -f "$f" ] || continue
    skill=$(basename "$(dirname "$(dirname "$f")")")
    out=$(awk -v plugin="$p" -v skill="$skill" -v file="$f" '
      function flush() { if (id != "") printf "%s\t%s\t%s\t%s\t%s\t%s\n", plugin, skill, id, title, applies, file }
      /^### [A-Z][A-Z0-9]*-[A-Z][A-Z0-9]*-[0-9]+ · / {
        flush()
        id = $2; title = $0; sub(/^### [^ ]+ · /, "", title); applies = ""; next
      }
      /^#{1,3} / { flush(); id = ""; next }
      id != "" && applies == "" && /^- 적용:/ { applies = $0; sub(/^- 적용:[ ]*/, "", applies); gsub(/\t/, " ", applies) }
      END { flush() }
    ' "$f")
    [ -n "$out" ] || continue
    printf '%s\n' "$out"
    n=$((n + $(printf '%s\n' "$out" | wc -l)))
  done
  printf 'source\t%s\t%s\t%s\t%s\n' "$p" "${ver:--}" "$n" "$pdir" >&2
done
