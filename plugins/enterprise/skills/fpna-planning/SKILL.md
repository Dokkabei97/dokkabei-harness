---
name: fpna-planning
description: |
  전사 FP&A·경영계획 가이드 — 한국형 4Q 경영계획 시즌 캘린더, CEO 대원칙·수립지침 템플릿, 드라이버 트리(매출·비용 드라이버), 롤링 포캐스트와 variance/DERP 커멘터리 원칙, CLAP 5요소(형식주의 처방을 실질 요소로) 를 제공한다. budget-*.json·variance/*.json 의 전사 레벨 구조를 규정한다. **경계: 부서 배분·전사 손익 = fpna-planner(본 스킬), 유닛 레벨(CAC/LTV/번레이트) = startup:financial-modeler.** CLAP 5키 정본은 references/clap-keys.json, DERP 템플릿은 references/derp-template.md(게이트 참조). 재무제표·세무·실적 수치 검증은 finance 위임.
  Enterprise FP&A & annual-planning guide: the Korean 4Q planning-season calendar, CEO-principle/planning-guideline templates, driver trees, rolling forecasts with variance/DERP commentary, and the CLAP 5 elements; defines the enterprise-level structure of budget/variance JSON. Boundary: department allocation & company P&L = this skill; unit-level (CAC/LTV/burn) = startup:financial-modeler. Use when: building an annual plan, rolling forecast, or budget — financial-statement/tax figures delegated to finance.
metadata:
  version: 1.0.0
  category: enterprise
---

# FP&A Planning — 전사 계획·롤링 포캐스트

## 경계 (중요)
- **fpna-planner(본 스킬)** = 부서 배분·전사 손익·계획-실적 관리(전사 레벨).
- **startup:financial-modeler** = 유닛 이코노믹스(CAC/LTV/번레이트/런웨이 — 유닛 레벨).
- 재무제표·세무·K-SOX 숫자·실적 수치 검증 = **finance** 위임.

## When to Apply
- `/annual-plan`(경영계획+budget.json)·`/rolling-forecast`(variance/DERP) 설계 시
- 부서안을 전사 예산으로 합산·정합할 때(Σ부서=전사 ±0.5% — gate-budget)

## 한국형 4Q 경영계획 시즌 캘린더
| 분기 | 활동 |
|------|------|
| 3Q 말 | CEO 대원칙·경영방침 선포, 수립지침서 배포 |
| 4Q 초 | 부서안 작성·상향(bottom-up) |
| 4Q 중 | 전사 조정·시나리오(base/best/worst)·이사회 보고 |
| 4Q 말 | 확정 예산 → 익년 QBR·롤링 포캐스트 연계 |

## 수립지침 템플릿 (CEO 대원칙 → CLAP)
CLAP 5요소(정본: references/clap-keys.json) — **형식주의 처방을 실질 요소로 재정의**:
- **C challenge** 대원칙·도전 목표 / **L levers** 핵심 전략 레버 / **A allocation** 자원·부서 배분 원칙 /
  **A assumptions** 계획 가정(환율·성장률…) / **P plan** 실행 로드맵·점검 리듬.
- gate-budget 은 budget.clap 키 집합이 clap-keys.json 과 동일하고 값이 비공백인지 검사(하드코딩 금지).

## 드라이버 트리
- 매출 = 물량 × 단가 × (신규+기존×리텐션) / 비용 = 인건비 + 변동비 + 고정비.
- assumptions(≥3)를 드라이버에 연결 — 가정 없는 숫자 금지.

## 롤링 포캐스트 + variance/DERP
- 4~6분기 롤링, plan 대비 actual 의 variance = actual − plan(재계산 검증 — gate-variance).
- 임계(|variance_pct|>threshold_pct) 초과 라인은 **DERP 4키** 커멘터리 필수: [references/derp-template.md](references/derp-template.md).
- **포캐스트-보상 분리 원칙**: 포캐스트를 인센티브 목표와 분리(sandbagging 방지).

## References
- references/clap-keys.json (CLAP 5키 정본, gate-budget 참조)
- references/derp-template.md (DERP 4키 템플릿, gate-variance 계약)
- Wall Street Prep FP&A; Farseer DERP variance commentary
