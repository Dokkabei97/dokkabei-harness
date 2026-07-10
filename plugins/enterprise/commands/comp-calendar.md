---
name: comp-calendar
description: |
  정기 법정 의무 캘린더(사업보고서 90일·운영실태보고·교육·위험성평가·중대재해 증적 주기) → 기한 게이트.
  Builds the recurring statutory-duty calendar (periodic reports, training, risk assessments, serious-accidents evidence cycles) with deadline/D-14 gating. Use when: tracking recurring compliance duties and their evidence.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /comp-calendar - 컴플라이언스 의무 캘린더

정기 법정 의무를 due·recurrence·증적 경로로 관리한다. 사업보고서 90일·정기공시·교육·위험성평가·
중대재해 증적 주기 등. `gate-calendar.sh` 가 기한 도과(open&due<TODAY)를 exit 1 로 막고 D-14 임박을
경고한다. 중대재해법은 **형식 문서가 아닌 실질 운영 증적**이 유·무죄를 가르므로 done→evidence_path 를
강제한다(`k-grc-context`). 기준은 `enterprise-orchestrator/references/gate-policy.md`.

## Triggers
- "컴플라이언스 캘린더", "정기 의무 기한", "사업보고서/공시 일정", "중대재해 증적 주기" 요청
- `/grc-intake` 적용 의무를 기한 관리로 전환할 때

## Usage
```
/comp-calendar [옵션]

Options:
  --today YYYY-MM-DD   기준일 지정(게이트 GATE_TODAY 주입 — 시뮬레이션)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/grc/grc-profile.json` 의 적용 의무를 duty 후보로 승계(없으면 인터뷰).

### Phase 1: 캘린더 작성 (maker: 메인)
- 각 duty: id·title·basis(근거 조문)·due(YYYY-MM-DD)·owner·recurrence·status(open/done/waived)·evidence_path.
- done 은 evidence_path 비공백(실질 증적). 중대재해·교육·위험성평가는 증적 주기 항목으로 포함.
- → `.planning/grc/compliance-calendar.json`.

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-calendar.sh"`
- 필드·status enum·done 증적·기한 도과를 검증하고, TODAY+14일 이내 open 의무를 D-14 경고한다.

## Boundaries

**Will:**
- 정기 의무 캘린더 작성, 증적 경로·기한 관리, 도과·D-14 게이트 판정

**Will Not:**
- 공시·보고 내용의 **법적 충족 여부 판단** → legal 위임
- 실적·재무 수치 검증 → finance 위임
- 증적 파일 자체 생성 대행 (경로·주기 관리까지가 범위)
