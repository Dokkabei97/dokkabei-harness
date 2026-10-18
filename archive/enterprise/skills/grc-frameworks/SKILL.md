---
name: grc-frameworks
description: |
  GRC 프레임워크 정의 가이드 — COSO ERM 5요소·ISO 31000 리스크 프로세스·IIA Three Lines(2020) 방어선 모델·5x5 리스크 매트릭스 정의표를 제공한다. 리스크 레지스터·통제 매트릭스 산출물의 필드 의미(likelihood/impact/score/level, type preventive·detective, line 1·2·3)와 판정 기준을 규정하며, 5x5 level 매핑의 정본 수치는 references/risk-matrix.json(gate-risk-register.sh 가 재계산 참조)에 있다. 법적 의무·컴플라이언스 맥락은 compliance-context, 판정·스키마는 enterprise-orchestrator references/gate-policy.md.
  GRC frameworks guide covering COSO ERM's 5 components, the ISO 31000 risk process, the IIA Three Lines (2020) model, and a 5x5 risk-matrix definition table; the authoritative 5x5 level mapping lives in references/risk-matrix.json (recalculated by gate-risk-register.sh). Use when: building a risk register or control matrix, defining likelihood/impact/level, or applying COSO/ISO 31000/Three Lines.
metadata:
  version: 1.0.0
  category: enterprise
---

# GRC Frameworks — 리스크·통제 프레임워크 정의

## When to Apply
- 리스크 레지스터(`/risk-register`)·통제 매트릭스(`/control-matrix`)를 설계할 때
- likelihood·impact·level·통제 유형/방어선의 의미를 규정할 때
- COSO ERM / ISO 31000 / Three Lines 를 산출물 구조로 번역할 때

## COSO ERM (2017) 5요소
1. **거버넌스·문화** — 이사회 감독, 운영 구조, 윤리·행동강령
2. **전략·목표 설정** — 리스크 성향(appetite) 선언, 사업목표 정합
3. **성과** — 리스크 식별·평가(5x5)·우선순위·대응 선택
4. **검토·수정** — 변화·성과 대비 리스크 재평가(next_review 주기)
5. **정보·소통·보고** — 통제·증적·보고 라인

## ISO 31000 리스크 프로세스
`범위·맥락·기준 → 리스크 식별 → 분석(likelihood×impact) → 평가(level) → 대응(response) → 모니터링·검토`
- 대응 전략(response.strategy): mitigate / transfer / accept / avoid
- 각 리스크는 owner·actions·due·next_review 를 가진다(무주체·무기한 대응 금지).

## IIA Three Lines (2020)
| 방어선 | 역할 | line |
|--------|------|------|
| 1선 | 현업 — 리스크를 소유·관리하는 운영 통제 | 1 |
| 2선 | 관리 — 리스크·컴플라이언스 기능의 감독·지원 | 2 |
| 3선 | 내부감사 — 독립적 보증 | 3 |
> 통제가 1선에만 몰리면(2·3선 0건) 방어선 공백 — gate-control-matrix 경고 대상.

## 통제 유형
- **preventive(예방)**: 사건 발생 전 차단 (예: 접근권한 승인)
- **detective(적발)**: 사건 후 탐지 (예: 로그 리뷰·내부감사)

## 5x5 리스크 매트릭스
- score = likelihood(1~5) × impact(1~5)
- level ∈ {low, medium, high, critical} — **셀별 매핑**은 [references/risk-matrix.json](references/risk-matrix.json)이 정본.
- gate-risk-register.sh 가 이 파일을 slurp 해 `matrix[likelihood][impact]` 로 level 을 재계산·대조한다. 하드코딩 금지.
- critical 리스크는 반드시 actions 를 가져야 하고(무대응 실패), high·critical 은 매핑 통제가 있어야 한다.

## References
- references/risk-matrix.json — 5x5 level 매핑 정본 (게이트 참조)
- COSO ERM Integrated Framework (2017), ISO 31000:2018, IIA Three Lines Model (2020)
