#!/usr/bin/env bash
# version-bump-reminder.sh — 이 레포 전용 PreToolUse(Bash) 비차단 넛지.
#
# 왜: 설치본은 plugin.json version 이 바뀔 때만 /plugin update 로 갱신된다. 버전 범프 누락으로
#   설치본이 수개월 전 상태에 머문 사고(2026-10 실측)의 재발 방지. 강제가 아니라 안내다.
# 동작: Bash 명령이 git commit 일 때만(matcher 는 tool-name 만 받으므로 필터는 여기서) 커밋 대상 파일 중
#   plugins/<name>/ 변경이 있는데
#     (1) plugins/<name>/.claude-plugin/plugin.json 의 version 이 HEAD 대비 그대로이거나
#     (2) .claude-plugin/marketplace.json 의 <name> 엔트리 version 과 다르면
#   hookSpecificOutput.additionalContext 로 한 줄 안내 후 exit 0. 해당 없으면 무출력 exit 0.
# 커밋 대상: 기본은 index(staged). commit -a/--all 이면 작업 트리의 추적 파일 변경.
#   --no-renames: plugins/<name>/ → archive/ 이동(git mv)도 원래 플러그인 변경으로 잡는다(rename 감지 시 새 경로만 나와 누락).
# 한계: "git add X && git commit" 처럼 같은 명령에서 stage 하는 파일은 훅 시점 index 에 아직 없다.
#   git 은 명령 시작(줄 머리 또는 ; & | ( 뒤)에서만 인식한다 — "echo git commit" 은 무시하지만
#   따옴표 안의 "x; git commit" 같은 문자열은 여전히 잡힐 수 있다(비차단 넛지라 감수).
#   -a/--all 판정은 commit 뒤 옵션을 -m/-F/--message/--file 또는 ; & | 전까지만 본다(메시지 본문 무시).
# fail-open: jq·git 부재, 파싱 실패, 레포 밖 → 무출력 exit 0. 절대 차단(exit 2)하지 않는다.
set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# 명령 시작의 git [전역 옵션…] commit — "git log --grep commit"·"echo git commit" 오탐 배제
nl=$'\n'
commit_re="(^|[;&|(${nl}])[[:space:]]*"'git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+--?[A-Za-z-]+(=[^[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'
[[ $cmd =~ $commit_re ]] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
mkt=".claude-plugin/marketplace.json"
[ -f "$top/$mkt" ] || exit 0

after=${cmd#*"${BASH_REMATCH[0]}"}
# commit 옵션만 훑는다: 메시지 인자(-m/-F/--message/--file) 이후·다음 명령 구분자 이후는 보지 않는다
use_all=0
read -r -a toks <<<"${after%%[;&|]*}" || true
for t in ${toks[@]+"${toks[@]}"}; do
  case $t in
  --all) use_all=1 ;;
  --message* | --file* | --) break ;;
  --*) ;;
  -*)
    o=${t#-}
    o=${o%%[mFCct]*} # 인자를 받는 짧은 옵션 이후 문자는 그 값이다
    [[ $o == *a* ]] && use_all=1
    [[ ${t#-} == "$o" ]] || break
    ;;
  esac
done
if [ "$use_all" = 1 ]; then
  files=$(git -C "$top" diff HEAD --no-renames --name-only 2>/dev/null) || exit 0
  read_new() { cat "$top/$1" 2>/dev/null; }
else
  files=$(git -C "$top" diff --cached --no-renames --name-only 2>/dev/null) || exit 0
  read_new() { git -C "$top" show ":$1" 2>/dev/null; }
fi

names=$(printf '%s\n' "$files" | sed -n 's#^plugins/\([^/][^/]*\)/.*#\1#p' | sort -u)
[ -n "$names" ] || exit 0

mkt_json=$(read_new "$mkt")
msgs=()
while IFS= read -r n; do
  pj="plugins/$n/.claude-plugin/plugin.json"
  new=$(read_new "$pj" | jq -r '.version // empty' 2>/dev/null)
  [ -n "$new" ] || continue # 플러그인 삭제·이동(archive) 또는 manifest 없음 — 범프 대상 아님
  old=$(git -C "$top" show "HEAD:$pj" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    msgs+=("$n: plugin.json version $new 이 HEAD 와 같음(범프 없음)")
  fi
  mv_ver=$(printf '%s' "$mkt_json" | jq -r --arg n "$n" \
    'first(.plugins[]? | select(.name == $n) | .version) // empty' 2>/dev/null)
  if [ -n "$mv_ver" ] && [ "$mv_ver" != "$new" ]; then
    msgs+=("$n: marketplace.json $mv_ver ≠ plugin.json $new")
  fi
done <<<"$names"

[ "${#msgs[@]}" -gt 0 ] || exit 0
joined=$(printf '%s; ' "${msgs[@]}")
ctx="버전 동기화 안내 — 이 커밋은 plugins/ 아래를 바꾸지만 ${joined%; }. 설치본은 version 이 바뀔 때만 /plugin update 로 갱신되며, CLAUDE.md 규칙상 plugin.json 과 marketplace.json 두 곳을 함께 맞춘다(문서·주석만 바꾼 커밋이면 무시해도 된다)."
jq -cn --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}' 2>/dev/null
exit 0
