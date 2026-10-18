# DERP 편차 커멘터리 템플릿 (정본)

> variance/*.json 의 각 라인 중 **|variance_pct| > threshold_pct** 인 항목은 아래 4키를 모두 채워야 한다.
> 빈 문자열이면 gate-variance.sh 실패. (Farseer DERP 방법론)

| 키 | 질문 | 예시 |
|----|------|------|
| **describe** | 무엇이 얼마나 벗어났나 (사실) | "인건비 계획 600 → 실적 720, +20%" |
| **explain** | 왜 벗어났나 (근본 원인) | "엔지니어 채용 가속 + 상여 선지급" |
| **respond** | 지금 무엇을 하나 (대응) | "4Q 채용 동결, 상여 이연" |
| **prevent** | 재발 방지 (구조) | "헤드카운트 게이트를 예산 승인에 연결" |

## 원칙
- describe 는 숫자, explain 은 원인, respond 는 액션, prevent 는 구조 — 4개가 서로 다른 층위여야 한다.
- "환경 탓"으로 끝나는 explain(통제 불가 귀인만)은 respond/prevent 를 공허하게 만든다 — 지양.
- variance = actual − plan 재계산은 게이트가 선처리하므로, 커멘터리는 **의미**에 집중한다.
