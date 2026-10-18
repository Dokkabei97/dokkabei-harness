---
name: grc-intake
description: |
  회사 프로파일 인터뷰 → 채택할 컴플라이언스 프레임워크·규제 선언(ISO 27001·SOC 2·GDPR·기타)을 grc-profile.json 에 기록. GRC 파이프라인 진입점.
  Interviews the company profile and records which compliance frameworks/regulations to adopt (ISO 27001, SOC 2, GDPR, other) in grc-profile.json. Use when: starting the GRC pipeline and declaring the frameworks and regulations in scope.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /grc-intake - GRC 프로파일 · 프레임워크 선택

GRC 파이프라인의 **진입점**. 회사 프로파일(규모·업종·데이터 처리·고객 지역·계약 요구)을 인터뷰로
수집하고, **어떤 컴플라이언스 프레임워크·규제를 채택할지 사용자 선언 기반으로 선택**해
`.planning/grc/grc-profile.json` 의 `frameworks[]` 에 기록한다. 프레임워크 선택 지도는
`compliance-context` 스킬, 전체 파이프라인·기준은 `enterprise-orchestrator/references/gate-policy.md`.

## Triggers
- "GRC 시작", "거버넌스 구축", "어떤 인증·규제를 따라야 하나" 요청
- 리스크 레지스터·인증 갭·컴플라이언스 캘린더 작업 전 프로파일이 필요할 때
- `/enterprise-from-scaleup` 브릿지가 조직 데이터를 승계해 프리필로 호출할 때

## Usage
```
/grc-intake [옵션]

Options:
  --frameworks iso27001,soc2,gdpr   프레임워크 사전 지정(인터뷰 생략)
```

## Behavioral Flow

### Phase 0: 프로파일 수집
- 규모·업종·처리 데이터 유형·고객/데이터 주체 지역·계약상 보안 요구를 묻는다.
- `.planning/scaleup/` 산출물이 있으면 조직 규모 후보로 승계(브릿지). 없으면 인터뷰.

### Phase 1: 프레임워크·규제 선택 (사용자 선언 기반)
- 후보: **ISO 27001**(인증형 통제 세트), **SOC 2**(감사형 보증), **GDPR**(EU 데이터 규제), 기타(고객 요구 표준).
- `compliance-context` 의 선택 지도·순서론(ISO 우선 → SOC 2 확장)을 안내하되, 채택 결정은 사용자가 한다.
- 규제 **적용 여부의 법적 판단은 legal 위임** — intake 는 사용자 선언을 기록만 한다.

### Phase 2: 산출 + 후속 안내
- `.planning/grc/grc-profile.json`(프로파일 + `frameworks[]`) 생성.
- 후속 커맨드 안내: 리스크→`/risk-register`, 통제→`/control-matrix`, 인증→`/cert-gap`, 의무→`/comp-calendar`.

## Boundaries

**Will:**
- 프로파일 인터뷰·물화, 채택 프레임워크·규제 선언(frameworks[]) 기록, 후속 커맨드 안내

**Will Not:**
- 규제 **적용·성립 여부의 확정 법적 판단**(data privacy 등) → legal 위임
- 재무·규모 수치의 검증 → finance 위임
- 사용자가 선언하지 않은 프레임워크를 임의 강제
