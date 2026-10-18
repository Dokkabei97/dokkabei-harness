#!/usr/bin/env bash
# =============================================================================
# subagent-stop-verify.sh — verifier 결과 기록 집행 (SubagentStop 훅, mvp/floop 공유)
# 오케스트레이터가 verifier 디스패치 직전 .planning/verify-round/{id}("round=1|2")를
# 기록하는 규약 위에서, verifier 서브에이전트가 결과 마커 없이 종료하는 것을 차단한다.
#   - exit 0 : 종료 허용 (안전핀 / 결과 기록 완료 / 최대 2라운드 도달)
#   - exit 2 : 종료 차단. stderr 가 서브에이전트에게 재주입된다.
# 판정 (전부 파일 기반 — jq 불필요, stdin 페이로드는 방어적으로 소비만):
#   안전핀: loop-active 부재 → exit 0 / verify-round/ 부재·비어있음 → exit 0
#   pending {id} 마다: verified/{id}(반증 실패=통과) 또는 refuted/{id}(반증 성공 근거)
#   존재 → 해당 verify-round/{id} 제거. 둘 다 없고 round>=2 → 파일 제거 후 허용
#   (최대 2라운드 규약). 그 외(round=1) → exit 2 + 마커 기록 지시 재주입.
#   차단 자가치유: 차단마다 blocked=N 카운터를 verify-round/{id} 에 기록(임시파일→mv
#   원자성). 동일 pending 차단 2회 초과 시 스테일로 간주해 pending 자동 정리 + exit 0
#   — 무관 서브에이전트가 스테일 verify-round 에 무한 차단되는 것을 방지한다.
#   오케스트레이터는 결과 처리 후 잔여 verify-round/{id} 정리 의무를 진다.
# 양 플러그인에 동일 내용으로 복제 등록 — $1 로 자기 플러그인 식별자(mvp|floop)를
# 받아 loop-active 의 "engine=" 줄이 타 엔진이면 개입하지 않는다(줄 없음 = 레거시 호환).
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"
SELF="${1:-}"

# stdin(JSON) 방어적 소비 — 어떤 필드(agent_id/agent_type 등)가 와도 안전핀이 우선
_stdin="$(cat 2>/dev/null || true)"; : "$_stdin"

# (a) 안전핀 1 — 루프 미가동 세션의 서브에이전트 종료는 절대 방해하지 않는다
[ -f "$PLAN/loop-active" ] || exit 0

# (a') engine 스코프 가드 — "engine=" 줄이 타 엔진 값이면 그 루프는 타 엔진 소유
eline="$(grep -m1 '^engine=' "$PLAN/loop-active" 2>/dev/null || true)"
if [ -n "$eline" ] && [ -n "$SELF" ] && [ "$(printf '%s' "${eline#engine=}" | tr -d '\r')" != "$SELF" ]; then
  exit 0
fi

# (b) 안전핀 2 — verify-round/ 부재 또는 비어있음(검증 디스패치 없음) → 개입 없음
VR="$PLAN/verify-round"
[ -d "$VR" ] || exit 0

blocked_ids=""
for f in "$VR"/*; do
  [ -f "$f" ] || continue   # 글롭 미매치(빈 디렉토리) 방어
  case "$f" in (*.tmp.*) continue;; esac   # 카운터 기록용 임시파일 잔재 방어
  id="$(basename "$f")"
  # 결과 기록 완료 — verified(반증 실패) 또는 refuted(반증 성공) 존재 시 pending 해소
  if [ -f "$PLAN/verified/$id" ] || [ -f "$PLAN/refuted/$id" ]; then
    rm -f "$f"
    continue
  fi
  # round 파싱 — "round=N" 1줄. 비정상 값은 1라운드로 간주(보수적 재주입)
  round="$(sed -n 's/^round=//p' "$f" 2>/dev/null | head -n 1 | tr -d '\r' || true)"
  case "$round" in (''|*[!0-9]*) round=1;; esac
  if [ "$round" -ge 2 ]; then
    rm -f "$f"   # 최대 2라운드 규약 — 더 붙잡지 않는다 (후속 처리는 오케스트레이터 몫)
    continue
  fi
  # 차단 횟수 자가치유 — 동일 pending 차단은 최대 2회. 2회 초과(3회째 종료 시도)면
  # 스테일 verify-round 로 간주해 자동 정리한다(무관 서브에이전트 무한 차단 방지).
  blocked="$(sed -n 's/^blocked=//p' "$f" 2>/dev/null | head -n 1 | tr -d '\r' || true)"
  case "$blocked" in (''|*[!0-9]*) blocked=0;; esac
  if [ "$blocked" -ge 2 ]; then
    rm -f "$f"
    echo "[${SELF:-loop}-verify] 스테일 verify-round/$id 자동 정리(차단 2회 초과) — verifier 재디스패치 필요" >&2
    continue
  fi
  # blocked 카운터 갱신 — 임시파일→mv 원자적 기록(부분 기록 방지)
  tmp="$f.tmp.$$"
  { printf 'round=%s\n' "$round"; printf 'blocked=%s\n' "$((blocked + 1))"; } > "$tmp"
  mv "$tmp" "$f"
  blocked_ids="${blocked_ids:+$blocked_ids, }$id"
done

# (c) 미기록 pending(round=1) 존재 → 종료 차단 + 마커 기록 지시 재주입 (지시 대상 = verifier 한정)
if [ -n "$blocked_ids" ]; then
  {
    echo "[${SELF:-loop}-verify] 검증 결과 미기록: $blocked_ids — 해당 id 의 verifier 는 종료 전에 반드시 결과를 남겨라:"
    echo "- 반증 실패(수용 기준 통과): .planning/verified/{id} 생성"
    echo "- 반증 성공(결함 발견): .planning/refuted/{id} 에 구체 근거(재현 절차·기대 vs 실제) 기록"
    echo "verified/{id}(반증 실패) 또는 refuted/{id}(구체 근거) 중 하나를 남겨라. 판단 회피·빈 파일 금지."
    echo "당신이 해당 id 의 verifier 가 아니라면 마커를 생성하지 말고 그대로 재종료하라 — 차단은 최대 2회로 제한되며, 초과 시 훅이 스테일 pending 을 자동 정리한다."
  } >&2
  exit 2
fi
exit 0
