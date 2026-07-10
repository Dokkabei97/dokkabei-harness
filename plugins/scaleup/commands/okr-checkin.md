---
name: okr-checkin
description: |
  주간 OKR 체크인 — KR별 confidence(0~1)·블로커·차주 커밋을 기록하고, 5~15개 지표 스코어카드를 갱신하며 이탈 지표를 이슈로 전환한다. EOS Scorecard·4DX 스코어보드를 하나로 통합(과잉 분리 방지).
  Weekly OKR check-in that records per-KR confidence (0-1), blockers, and next-week commitments, refreshes a 5-15 metric scorecard, and converts drifting metrics into issues — unifying EOS Scorecard and 4DX. Use when: running a weekly check-in, updating KR confidence, or refreshing the metrics scorecard.
category: scaleup
complexity: intermediate
---

# /okr-checkin — 주간 체크인

Doerr 주간 체크인 + EOS/4DX 스코어보드를 `.planning/scaleup/checkins/YYYY-Www.md` 로 통합 물화한다. 주간 리듬 유지가 목적 — 4DX 실측상 주간 세션 생략은 2사이클 내 케이던스 붕괴로 이어진다.

## Triggers
- 매주 정기 체크인(권장: 고정 요일)
- "이번 주 체크인", "KR confidence 갱신"

## Usage
```
/okr-checkin [주차(YYYY-Www)] [옵션]
Options:
  --date YYYY-MM-DD   체크인 기준일(frontmatter date:) 명시
```

## Behavioral Flow

### Phase 0: 사전 점검
- 최신 `okr/okr-*.json` 존재 확인(없으면 `/okr-plan` 선행 안내).
- 직전 체크인을 읽어 차주 커밋·블로커의 이월 상태를 파악.

### Phase 1: 체크인 작성 (메인 세션)
- frontmatter 에 `date: YYYY-MM-DD`(gate-cadence 계약 — 7일 이내여야 통과) 기록.
- 각 KR: confidence(0~1) 갱신, 블로커, 차주 커밋 1~2개.
- `## 스코어카드` 섹션에 5~15개 핵심 지표(EOS Scorecard/4DX)를 표로 갱신. 목표 이탈 지표는 `okr/issues.md` 로 이슈 전환.

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-cadence.sh"`:
  - frontmatter date 가 TODAY 기준 7일 이내
  - `## 스코어카드` 헤딩 존재
  - 지표 5~15개(범위 밖은 경고만).
- 판정 기준 정본: scaleup-orchestrator/references/gate-policy.md.

## Examples

```
/okr-checkin 2026-W28
/okr-checkin --date 2026-07-10   # 기준일 명시(주말 보정 등)
```

## Boundaries

**Will:** 주간 체크인·confidence·블로커·스코어카드 갱신, 이탈 지표 이슈 전환, gate-cadence 판정.
**Will Not:**
- 분기말 스코어링(→ `/okr-score`)
- OKR 트리 재설계(→ `/okr-plan`)
- 유닛이코노믹스 지표 정의 재작성 → **startup 위임**
- 재무 실적 수치 검증 → **finance 위임**
