---
name: biz-screen
description: |
  헌트존→롱리스트→5카테고리 스코어카드→딜 시시스(stop_rule·disqualifier 필수) → strategy-analyst maker → plan-challenger 반증 → 게이트. merger-control 규제 검토는 서술 안내로만, 법 판단 legal 위임.
  Screens M&A targets via hunt zone → long list → 5-category scorecard with mandatory stop rule and disqualifiers (strategy-analyst maker, plan-challenger falsification, screen gate); merger-control review is descriptive-only, legal judgment delegated. Use when: screening acquisition/partnership targets.
category: strategy
complexity: advanced
mcp-servers: []
personas: []
---

# /biz-screen - M&A · 사업 스크리닝

헌트존 정의 → 롱리스트 → 5카테고리 스코어카드로 딜을 스크리닝한다. `strategy-analyst`(maker) →
`plan-challenger`(checker, Edit 미보유) → `gate-screen.sh --require-verdict`. **disqualifier ≥1 +
stop_rule 필수**(무한 딜 추진 방지), synergy substitution 경계. merger-control(경쟁당국 신고) 검토는
**서술 안내로만** 다루고 게이트가 산술 플래그하지 않는다 — 성립·관할·절차의 **법 판단은 legal 위임**.
프레임워크·merger-control 참조는 `strategy-frameworks`.

## Triggers
- "M&A 스크리닝", "인수 후보 평가", "사업 스크리닝", "딜 스코어카드" 요청
- 포트폴리오 확장·인오가닉 성장을 검토할 때

## Usage
```
/biz-screen <target> [옵션]

Options:
  --weights a,b,c,d,e   5카테고리 가중치 사전 지정(Σ=1.0)
```

## Behavioral Flow

### Phase 0: 헌트존·롱리스트
- 전략 적합 기준으로 헌트존을 정의하고 후보 롱리스트를 만든다.

### Phase 1: strategy-analyst 디스패치 (maker)
- 5카테고리(전략적합·시장매력·재무·실행가능·리스크) 스코어카드: weight(Σ=1.0±0.001)×score(1~5).
- **disqualifiers ≥1 + stop_rule** 작성. annual_revenue 등 규모는 참고로만 기록(merger-control 검토 태그).
- → `.planning/enterprise/screen/<target>.json`.

### Phase 2: plan-challenger 디스패치 (checker)
- synergy substitution(시너지로 약한 카테고리 덮기)·disqualifier 실효성을 반증
  → `.planning/enterprise/screen/verdict.json`(APPROVE/REBASELINE/REJECT, coverage 비공백).

### Phase 3: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-screen.sh" --require-verdict`
- categories(5)·Σweight·score·disqualifier·stop_rule + verdict enum·non-APPROVE 를 검증.
  merger-control 규제 검토는 게이트가 산술 판정하지 않는다(legal 위임).

## Boundaries

**Will:**
- 5카테고리 스크리닝(maker), synergy substitution 반증(checker), 게이트 판정, merger-control 규제 검토 태그

**Will Not:**
- merger-control(경쟁당국 신고) 요건 성립·관할·절차의 **법적 판단** → legal 위임 (서술 안내만)
- 실적·세무·밸류에이션 확정 수치 → finance 위임
- PMI 실행 계획(인수 확정 후 영역 — v2 백로그)
- 스크리닝 결과를 checker 가 수정 (plan-challenger Edit 미보유)
