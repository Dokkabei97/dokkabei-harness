#!/usr/bin/env bash
# feed-gate.sh — wiki-harness-feed 의 feed 직전 2차 결정론 게이트.
#
# 1차 게이트(observe-export.js 의 원문 필드 fail-closed)와 별개의 심층방어다:
# 렌더러 버그·수기 편집 혼입까지 커버하도록, ingest 후보 파일을 정형 비밀 패턴
# (workflow:document-latest 마스킹 표 재사용)과 홈 경로 준식별자로 한 번 더 검사한다.
# 이 정규식들은 정형 비밀 전용이며 자유 텍스트 기밀에는 무력하다 — 1차 수단이 아니라
# 최후 안전망이다 (1차 방어는 원문 필드의 구조적 제거).
#
# exit 0 = 통과 / exit 1 = 차단(소견 stdout 출력) / exit 2 = 사용법·파일 오류.
# 훅이 아니라 스킬이 Bash 로 호출하는 게이트 스크립트다 (PreToolUse exit 2 규약 무관).
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: feed-gate.sh <snapshot.md>" >&2
  exit 2
fi
file="$1"
if [ ! -f "$file" ]; then
  echo "feed-gate: no such file: $file" >&2
  exit 2
fi

findings=0

check() { # $1=라벨, $2=ERE 패턴 (-e 필수 — '-----BEGIN' 류 선행 하이픈 패턴의 옵션 오해석 방지)
  if grep -E -q -e "$2" "$file"; then
    echo "BLOCK [$1]"
    # || true: 매치 대량 파일에서 head -3 조기 종료 → grep SIGPIPE(141)가 pipefail 로
    # 스크립트를 즉사시켜 exit 0/1/2 계약과 소견 전수 보고가 깨지는 실측 결함 방지
    grep -E -n -e "$2" "$file" | head -3 || true
    findings=$((findings + 1))
  fi
}

# document-latest 마스킹 표 (plugins/workflow/skills/document-latest/SKILL.md §5) 재사용
check "credential-assignment" '(password|secret|api_key|token|credential|private_key|db_password|connection_string|aws_access_key)[[:space:]]*[=:][[:space:]]*[^[:space:]]+'
check "bearer-token" 'Bearer[[:space:]]+[A-Za-z0-9._~+/-]+=*'
check "ssh-private-key" '-----BEGIN[[:space:]]+[A-Za-z0-9]+[[:space:]]+PRIVATE[[:space:]]+KEY-----'
check "private-ip-10" '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
check "private-ip-172" '172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
check "private-ip-192" '192\.168\.[0-9]{1,3}\.[0-9]{1,3}'

# 홈/마운트 경로 준식별자 — 렌더러 자기 검사(PATH_LEAK_RE)와 동일 기준의 이중화.
# /Users·/home 만으로는 회사 공유드라이브(/Volumes)·리눅스 마운트(/mnt·/media·/srv)가 샌다(실측)
check "home-path" '/(Users|home|Volumes|mnt|media|srv)/[^[:space:])"'"'"']+'

# attr: 줄 — 렌더러는 절대 내지 않는다. 수기 편집·주입 혼입 시 entity contradiction
# 오염(0.83→0.61 실측)을 일으키므로 feed 전에 차단한다
check "attr-line" '^[[:space:]]*attr:'
if [ -n "${HOME:-}" ]; then
  if grep -F -q "$HOME" "$file"; then
    echo "BLOCK [home-env-path]"
    findings=$((findings + 1))
  fi
fi

if [ "$findings" -gt 0 ]; then
  echo "feed-gate: $findings finding(s) — ingest blocked"
  exit 1
fi
echo "feed-gate: PASS"
exit 0
