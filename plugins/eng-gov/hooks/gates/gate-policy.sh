#!/usr/bin/env bash
# =============================================================================
# gate-policy.sh — 정책 as 코드 게이트 (conftest 로 Dockerfile/K8s/compose ↔ Rego deny)
# 정본: supply-chain-guide 스킬. 순수 로컬 CLI(네트워크 무의존).
# 정책: 등록된 게이트의 conftest 부재는 fail-closed(exit 1) — 단 검사 대상이 있을 때만.
# 검사 (순서: 대상 없으면 도구 요구 없이 공허 통과 — gate-fitness 와 동일한 '검사 대상 우선' 논리):
#   ① 대상 수집(Dockerfile*, k8s/*.yaml|yml, compose*.y*ml) 0건 → "대상 없음" 공허 통과 exit 0
#   ② command -v $CONFTEST_BIN (기본 conftest) 부재 → 설치 안내 exit 1 (대상 있을 때 fail-closed)
#   ③ .planning/gov/policy/ (Rego 정책 디렉토리) 부재 → /gov-init 안내 exit 1
#   ④ conftest test -p .planning/gov/policy/ <대상> 실행 exit 그대로 전파
# 인자 없이 동작(루프 gate-cmd 직결). 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
CONFTEST_BIN="${CONFTEST_BIN:-conftest}"
POLICY_DIR="$PROJ/.planning/gov/policy"

# ① 대상 수집 — 0건이면 검사할 것이 없으므로 도구 요구 없이 공허 통과
targets=()
for f in "$PROJ"/Dockerfile* "$PROJ"/k8s/*.yaml "$PROJ"/k8s/*.yml "$PROJ"/compose*.yml "$PROJ"/compose*.yaml; do
  [ -f "$f" ] && targets+=("$f")
done
if [ "${#targets[@]}" -eq 0 ]; then
  echo "[gate-policy] 통과: 정책 대상(Dockerfile/k8s/compose) 없음 — 검사 대상 없음(공허 통과)."
  exit 0
fi

# ② 도구 존재 (대상 있을 때 fail-closed)
if ! command -v "$CONFTEST_BIN" >/dev/null 2>&1; then
  echo "[gate-policy] 실패: '$CONFTEST_BIN' 미설치 — 설치: brew install conftest (또는 CONFTEST_BIN 오버라이드). 설치 불가 시 /gov-init 재실행으로 enabled:false 등록." >&2
  exit 1
fi

# ③ Rego 정책 디렉토리
if [ ! -d "$POLICY_DIR" ]; then
  echo "[gate-policy] 실패: $POLICY_DIR 없음 — /gov-init 으로 Rego 정책 디렉토리를 스캐폴딩하세요." >&2
  exit 1
fi

# ④ conftest 실행 — exit 전파
ct_exit=0
out="$( (cd "$PROJ" && "$CONFTEST_BIN" test -p "$POLICY_DIR" "${targets[@]}") 2>&1 )" || ct_exit=$?
if [ "$ct_exit" -ne 0 ]; then
  echo "[gate-policy] 실패: conftest 정책 위반 (${#targets[@]}개 대상, exit=$ct_exit)" >&2
  printf '%s\n' "$out" | tail -15 >&2
  exit "$ct_exit"
fi

echo "[gate-policy] 통과: conftest — ${#targets[@]}개 대상이 Rego deny 룰 위반 0건"
exit 0
