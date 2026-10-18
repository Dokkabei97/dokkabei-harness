---
name: gov-audit
description: |
  거버넌스 감사 커맨드 — run-registered.sh로 등록 게이트를 일괄 실행하고 결과를 append-only audit-log.jsonl에 기록한 뒤, git 네이티브 증적을 감사 증적 문서(audit/YYYY-MM-DD.md)로 변환한다. 미등록(enabled:false) 게이트는 종수와 사유를 명시해 감사 투명성을 확보한다. SOC 2 CC8.1·ISO 27001:2022 Annex A 통제 매핑은 control-map 참조. audit-log.jsonl은 수기 편집 금지(/gov-audit만 append). /verify-flow의 거버넌스판. Use when 정기 감사·SOC 2/ISO 27001 심사 대비 증적을 생성하거나 등록 게이트 전체 실행 현황이 필요할 때.
  Governance audit command: runs all registered gates via run-registered.sh, appends results to the append-only audit-log.jsonl, then converts git-native evidence into an audit-evidence document (audit/YYYY-MM-DD.md) that names disabled gates and their reasons for transparency. Control mapping to SOC 2 CC8.1 · ISO 27001:2022 Annex A lives in control-map. audit-log.jsonl must not be hand-edited (only /gov-audit appends). The governance counterpart of /verify-flow. Use when: producing audit evidence for a SOC 2 / ISO 27001 review or checking overall registered-gate status.
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /gov-audit — 거버넌스 감사·증적

등록 게이트를 일괄 실행하고 결과를 감사 로그에 남긴 뒤 감사 증적 문서로 변환한다. `/verify-flow`의 거버넌스판 — 통제 매핑은 `governance-templates`(`references/control-map.md`)가 정본.

## Triggers
- 정기 감사(주기적 게이트 전수 실행)를 돌릴 때
- SOC 2·ISO 27001 심사 대비 증적 문서가 필요할 때
- "감사 돌려줘", "증적 만들어줘", "게이트 전체 현황" 요청

## Usage
```
/gov-audit [옵션]
Options:
  --doc-only     게이트 재실행 없이 최근 audit-log로 문서만 생성
  --no-doc       게이트 실행 + 로그 기록만(증적 문서 생략)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/gov/gates.json` 존재 확인(없으면 `/gov-init` 안내). `plugin_root` stale 감지 시 재초기화 안내.

### Phase 1: 등록 게이트 일괄 실행
1. `bash ${CLAUDE_PLUGIN_ROOT}/hooks/gates/run-registered.sh` — `enabled:true` 게이트만 순회 실행(disabled 무시).
2. 각 게이트의 `id`·`exit`를 수집. 하나라도 red면 run-registered는 exit 1(현황 보고).

### Phase 2: audit-log.jsonl append (수기 편집 금지)
1. 실행 결과를 `.planning/gov/audit-log.jsonl`에 **append-only**로 기록: 게이트별 `{"ts","gate","exit","sha"}` 1줄씩.
2. 이 파일은 **수기 편집 금지** — `/gov-audit`만 append한다.

### Phase 3: 감사 증적 문서 변환
1. `.planning/gov/audit/YYYY-MM-DD.md` 생성: 실행 게이트·결과·SHA, **미등록(enabled:false) 게이트의 종수와 사유**를 명시(감사 투명성).
2. `control-map`으로 각 게이트를 SOC 2 CC8.1·ISO 27001:2022 Annex A 통제에 매핑한 증적표를 포함.
3. 각 통제가 어떤 산출물·게이트로 증명되는지 서술한다. 프레임워크 개정 등 미확정 항목은 "갱신 필요" 스탬프.

### Phase 4: 보고
- 게이트 n종 실행(그린/레드), 미등록 m종(사유), 증적 문서 경로. red 게이트는 원인·해소 경로 제시.

## Tool Coordination
- **Bash**: `run-registered.sh` 실행, audit-log.jsonl append, 게이트별 exit·sha 수집
- **Skill**: `governance-templates`(control-map — 통제 매핑)
- **Write**: `.planning/gov/audit/YYYY-MM-DD.md`(감사 증적 문서). audit-log.jsonl은 append만
- **Read**: gates.json(등록 현황), 기존 audit-log(--doc-only)

## Boundaries

**Will:** 등록 게이트 일괄 실행, audit-log.jsonl append-only 기록, 감사 증적 문서 변환(미등록 게이트 사유 명시).
**Will Not:**
- audit-log.jsonl 수기 편집·과거 기록 개변(append-only 규율)
- 인증 취득·법 준수 여부 최종 판단(→ legal 위임 — 이 문서는 통제의 결정론 반쪽 증적)
- 미등록 게이트를 통과로 위장(사유를 명시해 skip을 투명화)
