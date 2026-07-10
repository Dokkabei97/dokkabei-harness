---
name: stage-check
description: |
  Blitzscaling 5단계 진단 + 한국 상시근로자 임계값(10/30/50인) 산술 플래그. 메인 세션이 산술을 선계산하고 scale-checker 가 "이 전환은 아직 아니다"(조기 사업부제·창업자 직속 과밀)를 반증한다. 법·제도 대응은 legal/hr 위임.
  Blitzscaling 5-stage diagnosis plus Korean headcount-threshold (10/30/50) arithmetic flags: the main session pre-computes the arithmetic and scale-checker refutes premature transitions (early divisionalization, founder-direct overload). Use when: diagnosing scale stage, checking readiness to advance, or flagging labor-law thresholds. Labor-law response delegated to legal/hr.
category: scaleup
complexity: advanced
mcp-servers: []
personas: []
---

# /stage-check — 스케일 단계 진단

Hoffman & Yeh Blitzscaling 5단계 + 한국 노동법 인원 계단을 진단한다. 메인 세션이 인원·조직 산술을 선계산하고, `scale-checker`(Edit 미보유 checker)가 전환 준비도를 반증한다.

## Triggers
- 조직 규모·성장 단계 전환을 검토할 때
- 인원 임계값(10/30/50인) 도달 전후 점검
- "우리 지금 다음 단계 가도 돼?", "조직 스케일 진단"

## Usage
```
/stage-check [옵션]
Options:
  --headcount   headcount.json 기반 임계값 교차 분기만 산출
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/scaleup/org/headcount.json`·`scaleup-master.json` 을 읽어 현재 FTE·조직 형태 파악(없으면 `/org-plan` 안내).

### Phase 1: 산술 선계산 (메인 세션)
- Blitzscaling 5단계(Family/Tribe/Village/City/Nation) 대비 현 규모 매핑.
- 상시근로자 10/30/50인 도달 분기를 산술 표기(10인=취업규칙, 30인=노사협의회, 50인=산안위/장애인고용). **법적 대응 조치는 설계하지 않고 legal/hr 로 위임**.
- span-of-control(창업자 직속 리포트 수)·기능 리더십 갭을 수치화.

### Phase 2: scale-checker 반증
- `scale-checker` 디스패치 → ADVANCE/HOLD/NOT-YET 판정을 `org/stage-verdict.json` 으로 물화(조기 사업부제·직속 과밀·스페셜리스트 갭 반증).

### Phase 3: 보고
- 단계 진단 + 임계값 교차 분기 + 판정 + 선결 갭을 보고(게이트 없음 — 진단성 커맨드).

## Examples

```
/stage-check
/stage-check --headcount        # 임계값 교차 분기만
```

## Boundaries

**Will:** 단계 진단·임계값 산술 플래그, scale-checker 반증, 준비도 보고.
**Will Not:**
- 노동법·노사협의회·산안위 설치의 법적 이행 판단 → **legal 위임**
- JD·채용·온보딩 설계 → **hr 위임**
- 헤드카운트 플랜 작성(→ `/org-plan`)
- 근거 없는 ADVANCE 남발
