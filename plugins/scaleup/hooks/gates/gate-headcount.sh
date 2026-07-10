#!/usr/bin/env bash
# =============================================================================
# gate-headcount.sh — 헤드카운트 플랜 결정론 게이트 (훅 미등록)
# 대상: .planning/scaleup/org/headcount.json
# 검사(정본: gate-policy.md):
#   ① rows[] 각 항목 필수 6필드(role,dept,level,start_quarter,fte,annual_cost_krw)
#   ② fte > 0, annual_cost_krw > 0, start_quarter 형식 YYYYQn
#   ③ 분기 누적 FTE(current_fte 기반)가 10/30/50인 교차 → 경고(취업규칙/노사협의회/
#      산안위 — 대응은 legal/hr 위임)
#   ④ 크로스파일: .planning/enterprise/budget-*.json 존재 + personnel_total_krw 존재 시
#      |Σannual_cost − personnel_total| / personnel_total > 0.05 → 실패
#      (둘 중 하나라도 부재 시 경고 후 skip)
# 규약: jq 부재=사유 exit 1. 통과 0 / 실패 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
HC="$PROJ/.planning/scaleup/org/headcount.json"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-headcount] 실패: jq 미설치 — headcount 스키마 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$HC" ]; then
  echo "[gate-headcount] 실패: $HC 없음 (/org-plan 로 헤드카운트 플랜 생성 필요)" >&2
  exit 1
fi
if ! jq -e . "$HC" >/dev/null 2>&1; then
  echo "[gate-headcount] 실패: headcount.json JSON 파싱 불가" >&2
  exit 1
fi

# ① 필수 6필드
if ! jq -e '.rows | type == "array" and length > 0' "$HC" >/dev/null 2>&1; then
  echo "[gate-headcount] 실패: rows 는 1개 이상 배열이어야 함" >&2; fail=1
elif ! jq -e '[.rows[] | has("role") and has("dept") and has("level") and has("start_quarter") and has("fte") and has("annual_cost_krw")] | all' "$HC" >/dev/null 2>&1; then
  echo "[gate-headcount] 실패: role/dept/level/start_quarter/fte/annual_cost_krw 필드가 누락된 row 존재" >&2; fail=1
else
  # ② 값 규격 — fte>0, annual_cost_krw>0, start_quarter 형식
  if ! jq -e '[.rows[] | (.fte | type == "number" and . > 0)] | all' "$HC" >/dev/null 2>&1; then
    echo "[gate-headcount] 실패: fte 가 0 이하이거나 number 가 아닌 row 존재" >&2; fail=1
  fi
  if ! jq -e '[.rows[] | (.annual_cost_krw | type == "number" and . > 0)] | all' "$HC" >/dev/null 2>&1; then
    echo "[gate-headcount] 실패: annual_cost_krw 가 0 이하이거나 number 가 아닌 row 존재" >&2; fail=1
  fi
  if ! jq -e '[.rows[] | (.start_quarter | type == "string" and test("^[0-9]{4}Q[1-4]$"))] | all' "$HC" >/dev/null 2>&1; then
    echo "[gate-headcount] 실패: start_quarter 형식(YYYYQn, 예: 2027Q1) 위반 row 존재" >&2; fail=1
  fi
fi

# ③ 인원 임계값(10/30/50) 교차 분기 경고 — current_fte 기반 분기 누적(awk: 소수 fte 안전)
if [ "$fail" -eq 0 ]; then
  base_fte="$(jq -r '.current_fte // 0' "$HC" 2>/dev/null || echo 0)"
  jq -r '.rows | group_by(.start_quarter)[] | "\(.[0].start_quarter)\t\([.[].fte] | add)"' "$HC" 2>/dev/null | sort | \
    awk -F'\t' -v base="$base_fte" '
      BEGIN { n = split("10 30 50", TH, " ") }
      {
        prev = base + 0; base = base + $2
        for (i = 1; i <= n; i++) {
          t = TH[i] + 0
          if (prev < t && base >= t) {
            law = (t==10) ? "취업규칙 신고 의무" : (t==30) ? "노사협의회 설치 의무" : "산업안전보건위원회·장애인 고용"
            printf "[gate-headcount] 경고: %s 에 상시근로자 %d인 교차 → %s (대응은 legal/hr 위임)\n", $1, t, law > "/dev/stderr"
          }
        }
      }' || true
fi

# ④ 크로스파일 — budget-*.json 의 personnel_total_krw 대비 ±5%
budget=""
for b in "$PROJ"/.planning/enterprise/budget-*.json; do
  [ -e "$b" ] || continue
  if [ -z "$budget" ] || [[ "$b" > "$budget" ]]; then budget="$b"; fi
done
if [ -z "$budget" ]; then
  echo "[gate-headcount] 경고: .planning/enterprise/budget-*.json 부재 — 인건비-예산 정합 검사 skip (enterprise 플러그인 소유)" >&2
elif ! jq -e 'has("personnel_total_krw") and (.personnel_total_krw | type == "number")' "$budget" >/dev/null 2>&1; then
  echo "[gate-headcount] 경고: $(basename "$budget") 에 personnel_total_krw 없음 — 정합 검사 skip" >&2
elif [ "$fail" -eq 0 ]; then
  pt="$(jq -r '.personnel_total_krw' "$budget")"
  if jq -e -n --slurpfile hc "$HC" --argjson pt "$pt" \
      '([$hc[0].rows[].annual_cost_krw] | add) as $sum | (($sum - $pt) | fabs) / $pt > 0.05' >/dev/null 2>&1; then
    sum="$(jq -r '[.rows[].annual_cost_krw] | add' "$HC")"
    echo "[gate-headcount] 실패: Σannual_cost($sum) 와 예산 personnel_total_krw($pt) 편차 > 5% (AOP 정합 위반)" >&2; fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-headcount] 통과: rows 필수 필드·값 규격 검증 완료 + 인건비-예산 정합(존재 시)"
fi
exit "$fail"
