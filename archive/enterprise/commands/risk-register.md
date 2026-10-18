---
name: risk-register
description: |
  리스크 성향 선언 → COSO/ISO31000 5x5 레지스터 → 대응계획 → grc-challenger 반증 → 결정론 게이트.
  Declares risk appetite, builds a COSO/ISO31000 5x5 risk register with response plans, runs grc-challenger falsification, and enforces the deterministic gate. Use when: creating or updating the enterprise risk register.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /risk-register - 전사 리스크 레지스터

리스크 성향(appetite)을 선언하고 COSO ERM·ISO 31000 기반 5x5 리스크 레지스터를 만든다.
`risk-assessor`(maker) 초안 → `grc-challenger`(checker, Edit 미보유) 반증 → `gate-risk-register.sh
--require-verdict` 결정론 판정의 3단 파이프라인. 스키마·판정 기준은 `enterprise-orchestrator/
references/gate-policy.md`, 프레임워크는 `grc-frameworks`(5x5 정본 risk-matrix.json).

## Triggers
- "리스크 레지스터", "전사 리스크 평가", "COSO/ISO31000 리스크" 요청
- `/grc-intake` 후 적용 의무·리스크를 구조화할 때

## Usage
```
/risk-register [옵션]

Options:
  --appetite <low|moderate|high>   리스크 성향 사전 지정
  --skip-verdict                   반증 없이 초안만 (게이트 --require-verdict 미충족 — 임시)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/grc/grc-profile.json` 권장(없으면 `/grc-intake` 안내). appetite 를 확정한다.

### Phase 1: risk-assessor 디스패치 (maker)
- likelihood·impact(1~5)·score(=l×i)·level(risk-matrix.json 5x5 매핑)·owner·response·next_review 작성.
- critical 은 actions 필수, high·critical 은 후속 `/control-matrix` 매핑 대상으로 표시.
- → `.planning/grc/risk-register.json`.

### Phase 2: grc-challenger 디스패치 (checker)
- 리스크 과소평가·의무 카테고리 누락·owner 실재성을 반증 → `.planning/grc/verdict.json`
  (ACCEPT/REMEDIATE/ESCALATE, coverage 비공백). ESCALATE 는 legal 위임 라우팅.

### Phase 3: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-risk-register.sh" --require-verdict`
- 필드·1..5·score·level·critical대응·next_review + verdict 커버리지·non-ACCEPT 를 검증. 실패 항목 해소 후 재실행.

## Boundaries

**Will:**
- appetite 선언, 5x5 레지스터 작성(maker), 반증(checker), 게이트 판정의 3단 실행

**Will Not:**
- 산출물을 checker 가 수정 (grc-challenger Edit 미보유)
- corporate law·M&A/규제·whistleblowing·data privacy 등 **법적 판단** → legal 위임
- 재무제표·세무 수치 검증 → finance 위임
- score·level 을 매트릭스 무시하고 임의 부여
