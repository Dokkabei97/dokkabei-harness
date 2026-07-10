---
name: okr-plan
description: |
  분기 OKR 트리(objectives 1~5·KR 1~4)를 owner·baseline·target·기한과 함께 작성하고, 의존성 로그·미결 이슈를 남긴다. 초안은 항상 okr-checker 반증 + 사람 승인 3단(무수정 자동 확정 금지).
  Authors the quarterly OKR tree (1-5 objectives, 1-4 KRs each) with owner/baseline/target/due plus a dependency log and open issues, always followed by okr-checker falsification and human approval. Use when: planning quarterly OKRs, starting a new OKR cycle, or rewriting objectives and key results.
category: scaleup
complexity: advanced
---

# /okr-plan — 분기 OKR 플래닝

Doerr 플래닝 워크숍 산출물을 `.planning/scaleup/okr/okr-YYYYQn.json` 으로 물화한다. **AI 초안 + okr-checker 반증 + 사람 정제** 3단이며, 무수정 자동 확정은 금지(prior-art 실측: 초안+정제가 유의하게 우수).

## Triggers
- 새 분기 시작 시 OKR 트리 수립
- `/okr-score` 회고 후 차기 분기 OKR 입력
- "이번 분기 OKR 짜줘", "objective/KR 세팅"

## Usage
```
/okr-plan [분기(YYYYQn)] [옵션]
Options:
  --from-score   직전 분기 score/YYYYQn-retro.md 를 입력으로 승계
  --auto         okr-checker REWRITE 를 자동 반영(실험용, 사람 승인 게이트는 유지)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/scaleup/scaleup-master.json` 로 현재 사이클 상태 확인(없으면 `/scaleup-from-startup` 또는 신규 생성 안내).
- `--from-score` 시 직전 회고를 읽어 유지/조정 objective 를 프리필.

### Phase 1: 초안 작성 (메인 + operating-cadence 스킬)
- operating-cadence 스킬의 OKR 규격을 참조해 objectives 1~5, 각 KR 1~4 를 작성.
- 각 KR 은 `X→Y by when` 형식: baseline·target(number)·unit·due(YYYY-MM-DD)·owner·confidence.
- 의존성 로그와 미결 이슈(validate-idea 리스크 가설 시드 포함)를 `okr/dependencies.md` 에 기록.

### Phase 2: okr-checker 반증
- `okr-checker` 를 디스패치(Edit 미보유 checker). KR 단위 ADOPT/REWRITE/DROP 판정을 `okr/verdict.json` 으로 물화.
- "반증 실패 시 통과, 반증에는 구체 근거" 원칙을 프롬프트에 포함. REWRITE 근거는 메인 세션이 초안에 반영(max 2라운드).

### Phase 3: 결정론 게이트 + 승인
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-okr.sh" --require-verdict` (판정 기준 정본: scaleup-orchestrator/references/gate-policy.md).
- 전 KR ADOPT 여야 통과. 통과 후 **사람 승인 게이트**(objective 목록 + riskiest KR 제시).

## Examples

```
/okr-plan 2026Q3
/okr-plan --from-score          # 직전 회고 승계
/okr-plan 2026Q3 --auto         # REWRITE 자동 반영(실험용)
```

## Boundaries

**Will:** OKR 트리·의존성·미결 이슈 작성, okr-checker 반증 라운드 관리, gate-okr 판정.
**Will Not:**
- okr-checker 없이 KR 자동 확정(3단 필수)
- 유닛이코노믹스·시장조사 재작성 → **startup 위임**(북극성 지표 근거는 unit-economics 참조)
- KR 개수·형식 상한 초과 자동 생성
