---
name: stage-check
description: |
  Blitzscaling 5단계 진단 + 조직 스케일 준비도 점검. 메인 세션이 span-of-control·기능 리더십 갭·프로세스 부채를 산술로 선계산하고 scale-checker 가 "이 전환은 아직 아니다"(조기 사업부제·창업자 직속 과밀)를 반증한다. 노동·고용 규제 대응은 legal/hr 위임.
  Blitzscaling 5-stage diagnosis plus scale-readiness check: the main session pre-computes span-of-control, functional-leadership gaps, and process debt, and scale-checker refutes premature transitions (early divisionalization, founder-direct overload). Use when: diagnosing scale stage or checking readiness to advance. Labor/employment-regulation response delegated to legal/hr.
category: scaleup
complexity: advanced
mcp-servers: []
personas: []
---

# /stage-check — 스케일 단계 진단

Hoffman & Yeh Blitzscaling 5단계를 기준으로 조직 스케일 준비도를 진단한다. 메인 세션이 조직 산술을 선계산하고, `scale-checker`(Edit 미보유 checker)가 전환 준비도를 반증한다.

## Triggers
- 조직 규모·성장 단계 전환을 검토할 때
- 리더십 밀도·span-of-control 점검
- "우리 지금 다음 단계 가도 돼?", "조직 스케일 진단"

## Usage
```
/stage-check [옵션]
Options:
  --headcount   headcount.json 기반 조직 규모·span-of-control 지표만 산출
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/scaleup/org/headcount.json`·`scaleup-master.json` 을 읽어 현재 FTE·조직 형태 파악(없으면 `/org-plan` 안내).

### Phase 1: 산술 선계산 (메인 세션)
- Blitzscaling 5단계(Family/Tribe/Village/City/Nation) 대비 현 규모 매핑.
- span-of-control(창업자·리더 직속 리포트 수)·기능 리더십 갭·프로세스 부채를 수치화.
- 관리 계층 대비 인원 비율, 스페셜리스트 vs 제너럴리스트 구성을 산출.

### Phase 2: scale-checker 반증
- `scale-checker` 디스패치 → ADVANCE/HOLD/NOT-YET 판정을 `org/stage-verdict.json` 으로 물화(조기 사업부제·직속 과밀·스페셜리스트 갭 반증).

### Phase 3: 보고
- 단계 진단 + 조직 지표 + 판정 + 선결 갭을 보고(게이트 없음 — 진단성 커맨드).

## Examples

```
/stage-check
/stage-check --headcount        # 조직 규모·span-of-control 지표만
```

## Boundaries

**Will:** 단계 진단·조직 스케일 지표 산출, scale-checker 반증, 준비도 보고.
**Will Not:**
- 노동·고용 규제의 법적 이행 판단 → **legal 위임**
- JD·채용·온보딩 설계 → **hr 위임**
- 헤드카운트 플랜 작성(→ `/org-plan`)
- 근거 없는 ADVANCE 남발
