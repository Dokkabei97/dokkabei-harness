---
name: strategy-frameworks
description: |
  전사 전략·포트폴리오 프레임워크 가이드 — Lafley/Martin Playing to Win 5선택, McKinsey Three Horizons(3H) 포트폴리오, 9-box(GE/McKinsey) 매트릭스, 7S 진단, M&A 스크리닝 5카테고리(전략적합·시장매력·재무·실행가능·리스크)와 기업결합신고 임계값 참조표를 제공한다. strategy-cascade.md·biz-screen 산출물의 구조와 실패 패턴(one-box/three-box truncation·synergy substitution·hockey-stick)을 규정한다. 기업결합신고 요건의 법적 판단은 legal, 실적·세무 수치는 finance, 중견기업 세제 영향도 finance 위임.
  Corporate strategy & portfolio guide: Playing to Win's 5 choices, McKinsey Three Horizons, the 9-box matrix, 7S diagnosis, and an M&A screening 5-category scorecard with a merger-filing threshold reference table; defines the structure of strategy-cascade and biz-screen outputs and their failure patterns. Use when: writing a strategy cascade, screening M&A targets, tagging a 3H portfolio — merger-filing legal judgment delegated to legal.
metadata:
  version: 1.0.0
  category: enterprise
---

# Strategy Frameworks — 전사 전략·포트폴리오

## When to Apply
- `/strategy-cascade`(전략 1페이저)·`/biz-screen`(M&A 스크리닝) 설계 시
- 포트폴리오를 Three Horizons 로 태깅하거나 7S 정합을 진단할 때

## Playing to Win — 5선택 (연쇄)
1. **Winning Aspiration** — 이기는 것의 정의
2. **Where to Play** — 시장·세그먼트·지역·채널
3. **How to Win** — 차별적 우위(원가우위/차별화)
4. **Capabilities** — 이기기 위한 핵심 역량
5. **Management Systems** — 역량을 지탱하는 시스템·지표
> 5선택은 **논리 연쇄**여야 한다. 상하위가 단절되면(where↔how 불일치) plan-challenger 반증 대상.

## Three Horizons (3H) 포트폴리오
| Horizon | 성격 | 태그 |
|---------|------|------|
| H1 | 핵심사업 방어·개선 | core |
| H2 | 신흥사업 확장 | emerging |
| H3 | 미래 옵션·베팅 | option |
> **one-box/three-box truncation**: H1에만 자원 몰빵(미래 공백) 또는 H3 과다(현재 붕괴). portfolio.json 태그로 균형 점검.

## 9-box (GE/McKinsey)
축: 시장 매력도 × 사업 경쟁력 — 투자/유지/철수 구간. biz-screen 카테고리 가중치의 근거.

## 7S 진단
Strategy·Structure·Systems·Shared Values·Style·Staff·Skills — 전략 실행의 조직 정합 사전 진단.

## M&A 스크리닝 5카테고리 (screen/<target>.json)
1. 전략 적합성 2. 시장 매력도 3. 재무 건전성 4. 실행 가능성 5. 리스크
- 각 category: weight(Σ=1.0±0.001) × score(1~5). **disqualifier ≥1 + stop_rule 필수**(무한 딜 추진 방지).
- **synergy substitution 경계**: 시너지 수치를 근거로 약한 카테고리를 덮는 논리 — plan-challenger 반증 대상.

## 기업결합신고 임계값 참조표 (법 판단 legal 위임)
| 트리거 | 임계 |
|--------|------|
| 자산·매출 기준 | 신고회사 3천억 & 상대회사 300억 이상 |
| 사전신고 | 대규모회사(자산·매출 2조 이상) 관련 |
| 거래금액 기준 | 거래금액 6천억 이상 & 국내 상당활동 |
> gate-screen 은 annual_revenue_krw≥300억 교차 시 **경고만** 낸다. 신고 요건 성립·절차는 **legal** 위임.

## 실패 패턴 카탈로그 (plan-challenger 반증 관점)
- 캐스케이드 논리 단절(one-box/three-box) · hockey-stick 예산(산술은 gate 선행) · sandbagging · synergy substitution.

## References
- Lafley & Martin, "Playing to Win" (2013); McKinsey Three Horizons; GE/McKinsey 9-box; Waterman 7S
