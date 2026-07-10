---
name: gov-postmortem
description: |
  블레임리스 포스트모템 커맨드 — 타임라인·5-why 루트코즈·owner/due 액션 아이템을 담은 포스트모템을 postmortems/YYYY-MM-DD-<slug>.md에 작성하고(governance-templates 참조), 소모한 에러버짓을 slo/budget.json과 연결한 뒤 postmortem-checker(Edit 미보유)로 블레임 언어·얕은 루트코즈·소유자 없는 액션을 반증한다. 게이트는 없다(포스트모템은 릴리즈 비차단) — 품질 보증은 checker 반증에만 의존한다. Use when 인시던트 후 사후분석을 작성하거나 재발 방지 액션을 정리할 때.
  Blameless postmortem command: writes a postmortem (timeline, 5-why root cause, owner/due action items) to postmortems/YYYY-MM-DD-<slug>.md per governance-templates, links the error budget consumed to slo/budget.json, then falsifies blame language / shallow root cause / ownerless actions with postmortem-checker (no Edit). There is no gate (postmortems don't block releases) — quality relies on the checker's falsification. Use when: writing a post-incident analysis or organizing prevention actions.
category: workflow
complexity: intermediate
mcp-servers: []
personas: []
---

# /gov-postmortem — 블레임리스 포스트모템

SRE Workbook 형식의 블레임리스 포스트모템을 작성한다. 형식·규범은 `governance-templates`(`references/postmortem-template.md`)가 정본. 이 영역은 결정론 게이트가 없으므로 `postmortem-checker` 반증이 유일한 품질선이다.

## Triggers
- SEV 인시던트 후 사후분석(post-incident review)을 남길 때
- 반복 사고의 근본 원인·재발 방지 액션을 정리할 때
- "포스트모템 써줘", "사후분석", "왜 장애 났는지 정리" 요청

## Usage
```
/gov-postmortem "<사고 요약>" [옵션]
Options:
  --sev <1|2|3>       심각도(기본 2)
  --budget-impact <pct>   소모한 에러버짓 %p (slo/budget.json 연결)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/gov/postmortems/` 존재 확인(없으면 `/gov-init` 안내). 파일명 `YYYY-MM-DD-<slug>.md`.

### Phase 1: 사실 수집 → 타임라인
1. 사고 타임라인을 탐지→대응→복구 순으로 구성(시각 명기 → MTTR 재구성).
2. 영향(사용자 규모·기간)과 에러버짓 소모를 정량화.

### Phase 2: 루트코즈 (5-why, 시스템 수준)
1. 직접 원인에서 멈추지 않고 5-why로 조직/프로세스 근본 원인까지 파고든다.
2. "부주의"·"실수"는 루트코즈가 아니다 — 그 실수가 **가능한 시스템**을 묻는다. 기여 요인(contributing factors)도 별도 기록.

### Phase 3: 액션 아이템 (owner·due 필수)
1. 각 액션에 유형(예방/탐지/완화)·**owner**·**due**를 반드시 부여. 무주공산 액션 금지.
2. 에러버짓 소모를 `slo/budget.json`·`/gov-dora` 원장과 연결(추세 조인용).

### Phase 4: postmortem-checker 반증
`postmortem-checker` 디스패치 — 블레임 언어·5-why 미달·소유자 없는 액션·타임라인 공백을 반증(verdict는 `.planning/gov/postmortems/verdict.json`). BLOCK(블레임 지향·루트코즈 부재)이면 재작성 유도. 게이트가 없으므로 checker 판정을 사용자에게 명확히 보고한다.

## Tool Coordination
- **Skill**: `governance-templates`(postmortem-template — 형식·블레임리스 규범)
- **Task**: `postmortem-checker` 디스패치
- **Write**: 포스트모템 문서
- **Read**: `slo/budget.json`(에러버짓 소모 연결), 관련 로그·커밋

## Boundaries

**Will:** 타임라인·5-why·owner/due 액션 포스트모템 작성, 에러버짓 연결, postmortem-checker 반증 보고.
**Will Not:**
- 개인 책임 귀속·징계 판단(→ hr/legal 위임 — 블레임리스 규범 정면 위배)
- 사고 자체의 기술적 원인 실시간 조사(사고대응 몫 — 이 커맨드는 사후 문서화)
- 없는 게이트를 통과로 위장(품질은 checker 반증으로만 보증)
