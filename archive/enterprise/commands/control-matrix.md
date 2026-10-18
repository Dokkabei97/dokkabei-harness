---
name: control-matrix
description: |
  리스크별 통제 매핑(예방/적발·1/2/3선·증적 경로) + ICFR(SOX-style) RCM 골격 → 결정론 게이트.
  Maps controls to risks (preventive/detective, three lines, evidence paths) with an ICFR (SOX-style) RCM skeleton, then enforces the gate. Use when: building the control matrix / RCM after a risk register exists.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /control-matrix - 리스크 통제 매트릭스 (RCM)

리스크 레지스터의 리스크별로 통제를 매핑한다. `risk-assessor`(maker)가 예방/적발·1/2/3선 방어선·
증적 경로를 작성하고, 재무보고 통제가 필요하면 ICFR(SOX-style) RCM 골격(설계→운영→평가)을 포함한다.
`gate-control-matrix.sh` 가 크로스파일 정합을 결정론 검증한다. 스키마·기준은 `enterprise-orchestrator/
references/gate-policy.md`, 방어선 모델은 `grc-frameworks`(IIA Three Lines 2020).

## Triggers
- "통제 매트릭스", "RCM", "리스크별 통제 매핑", "ICFR 통제" 요청
- `/risk-register` 후 high·critical 리스크에 통제를 붙일 때

## Usage
```
/control-matrix [옵션]

Options:
  --icfr   ICFR(SOX-style) RCM 골격(재무보고 통제) 우선 생성
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/grc/risk-register.json` 필요(없으면 `/risk-register` 안내 — 크로스 검증 대상).

### Phase 1: risk-assessor 디스패치 (maker)
- 통제 작성: type(preventive/detective)·line(1/2/3)·owner·frequency·status·evidence_path·risk_ids.
- high·critical 리스크는 최소 1개 통제로 매핑. 2·3선(관리·감사) 통제도 배치(1선 편중 방지).
- status==implemented 통제는 evidence_path 파일이 실재해야 한다. → `.planning/grc/control-matrix.json`.

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-control-matrix.sh"`
- type/line enum·risk_ids 실재·high·critical 무통제 0·implemented 증적 존재를 검증(2/3선 0건은 경고).

## Boundaries

**Will:**
- 리스크별 통제 매핑(maker), ICFR(SOX-style) RCM 골격, 방어선 배치, 게이트 정합 검증

**Will Not:**
- 재무보고 **숫자·정확성 검증**(ICFR 수치) → finance 위임 (여기선 통제 구조만)
- 규제 의무 성립·적용 판단 → legal 위임
- risk-register 부재 시 크로스 검증 강행 (경고+skip)
