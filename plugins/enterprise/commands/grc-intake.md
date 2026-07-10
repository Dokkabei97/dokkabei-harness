---
name: grc-intake
description: |
  회사 프로파일 인터뷰 → 자산구간·상시근로자 기준 법정 의무 룰 테이블 매핑. GRC 파이프라인 진입점.
  Interviews the company profile and maps statutory obligations by asset tier and headcount. Use when: starting the GRC pipeline, mapping which governance duties (audit committee, K-SOX, ISMS-P, serious-accidents) apply.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /grc-intake - GRC 프로파일 · 법정 의무 매핑

중견·대기업 GRC 파이프라인의 **진입점**. 회사 프로파일(자산총액·매출·상시근로자·상장 여부·업종)을
인터뷰로 수집해 `.planning/grc/grc-profile.json` 으로 물화하고, `k-grc-context` 스킬의
`references/obligation-triggers.json`(정본)과 대조해 적용되는 법정 의무 룰 테이블을 만든다.
전체 파이프라인·판정 기준은 `enterprise-orchestrator` 스킬과 `references/gate-policy.md` 를 따른다.

## Triggers
- "GRC 시작", "거버넌스 구축", "우리 회사에 어떤 법정 의무가 적용되나" 요청
- 리스크 레지스터·인증 갭·컴플라이언스 캘린더 작업 전 프로파일이 필요할 때
- `/enterprise-from-scaleup` 브릿지가 headcount 를 승계해 프리필로 호출할 때

## Usage
```
/grc-intake [옵션]

Options:
  --profile <file>   기존 프로파일 JSON 재사용(재인터뷰 생략)
```

## Behavioral Flow

### Phase 0: 프로파일 수집
- 자산총액·매출·부채·상시근로자·상장 여부·업종(정보통신서비스 여부)·개인정보 처리 규모를 묻는다.
- `.planning/scaleup/org/headcount.json` 이 있으면 상시근로자 후보로 승계(브릿지). 없으면 인터뷰.

### Phase 1: 의무 룰 매핑
- `k-grc-context/references/obligation-triggers.json` 의 각 트리거(감사위 2조·상근감사 1천억·준법지원인
  5천억·외감·K-SOX·ISMS·중대재해)를 프로파일 수치와 대조해 **적용/비적용/근접** 을 표기한다.
- 정본 수치는 JSON — 커맨드는 하드코딩하지 않고 파일을 읽는다.

### Phase 2: 산출 + 위임 안내
- `.planning/grc/grc-profile.json`(프로파일 + 적용 의무 목록) 생성.
- 적용 의무는 후속 커맨드로 안내: 리스크→`/risk-register`, 인증→`/cert-gap`, 정기의무→`/comp-calendar`.
- 각 의무의 **성립 여부·해석은 법적 판단** → legal 위임 문구를 명시한다.

## Boundaries

**Will:**
- 프로파일 인터뷰·물화, obligation-triggers.json 대조로 적용 의무 매핑, 후속 커맨드 안내

**Will Not:**
- 법정 의무 성립·적용 여부의 **확정 법적 판단** (상법·외감법·중대재해·개인정보) → legal 위임
- 재무제표·자산·매출 수치의 검증 → finance 위임
- 트리거 수치 하드코딩 (obligation-triggers.json 정본 우회 금지)
