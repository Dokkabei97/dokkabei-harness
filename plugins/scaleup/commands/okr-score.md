---
name: okr-score
description: |
  분기말 OKR 스코어링(0.0~1.0) + 회고 — 전 KR 에 score 를 부여하고(0.6~0.7 건강 구간), 무엇이 되고 안 됐는지 회고를 남겨 차기 /okr-plan 입력으로 연결한다.
  End-of-quarter OKR scoring (0.0-1.0, 0.6-0.7 healthy) plus a retro that assigns every KR a score and captures what worked, feeding the next /okr-plan. Use when: closing out a quarter, scoring OKRs, or writing an OKR retrospective.
category: scaleup
complexity: intermediate
---

# /okr-score — 분기말 스코어링·회고

Doerr 분기말 스코어링을 `okr/okr-*.json` 의 각 KR `score` 필드에 기록하고, 회고를 `.planning/scaleup/score/YYYYQn-retro.md` 로 남긴다. 0.6~0.7 이 건강 구간(1.0 은 목표가 너무 쉬웠다는 신호).

## Triggers
- 분기 종료 시점 OKR 마감
- "이번 분기 OKR 채점", "회고 작성"

## Usage
```
/okr-score [분기(YYYYQn)]
```

## Behavioral Flow

### Phase 0: 사전 점검
- 대상 분기 `okr/okr-*.json` 과 해당 분기 체크인 이력을 읽는다(없으면 안내).

### Phase 1: 스코어링 (메인 세션)
- 각 KR 에 `score`(0.0~1.0) 부여 — baseline→달성치 대비 선형 또는 마일스톤 기반.
- 근거는 체크인 confidence 추이·실적 데이터에서. 근거 없는 점수 금지.

### Phase 2: 회고 작성
- `score/YYYYQn-retro.md`: 달성/미달 KR, 원인(무엇이 통제 가능했나), 차기 분기 유지/조정 objective 후보.
- 회고는 차기 `/okr-plan --from-score` 입력이 된다.

### Phase 3: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-okr.sh" --scored`: 전 KR score 가 0.0~1.0 number 인지 검증(정본: gate-policy.md).

## Examples

```
/okr-score 2026Q2
```
- 산출: `okr/okr-2026Q2.json`(score 채움) + `score/2026Q2-retro.md`.
- 후속: `/okr-plan --from-score` 로 차기 분기 연결.

## Boundaries

**Will:** KR 스코어링·회고 작성, gate-okr --scored 판정, 차기 분기 입력 연결.
**Will Not:**
- 차기 OKR 트리 확정(→ `/okr-plan`)
- 실적 수치의 재무 검증 → **finance 위임**
- 근거 없는 임의 점수 부여
