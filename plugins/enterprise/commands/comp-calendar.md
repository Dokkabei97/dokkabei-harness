---
name: comp-calendar
description: |
  정기 컴플라이언스 의무 캘린더(연례 신고·ISO 사후심사·SOC 2 감사 기간·보안 교육·접근권한 리뷰 등) → 기한 게이트.
  Builds the recurring compliance-duty calendar (annual filings, ISO surveillance audits, SOC 2 audit periods, security training, access reviews) with deadline/D-14 gating. Use when: tracking recurring compliance duties and their evidence.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /comp-calendar - 컴플라이언스 의무 캘린더

정기 컴플라이언스 의무를 due·recurrence·증적 경로로 관리한다. 예: 연례 규제 신고, ISO 27001 사후심사
(surveillance audit), SOC 2 Type II 감사 기간, 정기 보안 인식 교육, 분기 접근권한 리뷰. `gate-calendar.sh`
가 기한 도과(open&due<TODAY)를 exit 1 로 막고 D-14 임박을 경고한다. 감사·인증은 **형식 문서가 아닌
실질 운영 증적**이 통과를 가르므로 done→evidence_path 를 강제한다. 기준은 gate-policy.md.

## Triggers
- "컴플라이언스 캘린더", "정기 의무 기한", "감사 일정", "접근권한 리뷰 주기" 요청
- `/grc-intake` 채택 프레임워크의 정기 활동을 기한 관리로 전환할 때

## Usage
```
/comp-calendar [옵션]

Options:
  --today YYYY-MM-DD   기준일 지정(게이트 GATE_TODAY 주입 — 시뮬레이션)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/grc/grc-profile.json` 의 채택 프레임워크에서 정기 활동을 duty 후보로 승계(없으면 인터뷰).

### Phase 1: 캘린더 작성 (maker: 메인)
- 각 duty: id·title·basis(근거: 표준 조항·계약·규제)·due(YYYY-MM-DD)·owner·recurrence·status(open/done/waived)·evidence_path.
- done 은 evidence_path 비공백(실질 증적). 보안 교육·접근권한 리뷰·감사 준비는 증적 주기 항목으로 포함.
- → `.planning/grc/compliance-calendar.json`.

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-calendar.sh"`
- 필드·status enum·done 증적·기한 도과를 검증하고, TODAY+14일 이내 open 의무를 D-14 경고한다.

## Boundaries

**Will:**
- 정기 의무 캘린더 작성, 증적 경로·기한 관리, 도과·D-14 게이트 판정

**Will Not:**
- 규제 신고 내용의 **법적 충족 여부 판단** → legal 위임
- 실적·재무 수치 검증 → finance 위임
- 증적 파일 자체 생성 대행 (경로·주기 관리까지가 범위)
