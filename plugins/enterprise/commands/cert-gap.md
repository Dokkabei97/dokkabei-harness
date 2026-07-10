---
name: cert-gap
description: |
  ISMS-P 101항목 갭 분석(status n/a·planned·implemented·evidenced + 증적 경로) + ISO27001/SOC2 크로스맵 → 게이트.
  Runs an ISMS-P 101-item gap analysis (status + evidence paths) with an ISO27001/SOC2 crossmap, then enforces the readiness gate. Use when: preparing ISMS-P certification, tracking control evidence, or cross-mapping to SOC2/ISO27001.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /cert-gap - ISMS-P 인증 갭 분석

ISMS-P 101항목(16 관리체계+64 보호대책+21 개인정보)의 이행 상태를 갭 분석한다. 정본은
`k-grc-context/references/isms-p-items.json`("2026 개편 기준, 갱신 필요" 스탬프). 항목별 status
(`n/a→planned→implemented→evidenced`)와 증적 경로를 채우고, `gate-cert-readiness.sh` 가 무결성·
증적·핵심항목 이행을 검증한다. 2026 대개편은 증적 중심 전환·2027.7 의무화. 기준은 gate-policy.md.

## Triggers
- "ISMS-P 갭", "인증 준비", "정보보호 인증 항목", "SOC2/ISO27001 크로스맵" 요청
- `/grc-intake` 에서 ISMS 의무가 적용된 경우

## Usage
```
/cert-gap [옵션]

Options:
  --crossmap iso27001|soc2   크로스맵 컬럼 추가 생성
```

## Behavioral Flow

### Phase 0: 초기화
- `isms-p-items.json`(101항목) 을 정본으로 읽어 `.planning/grc/cert-gap.json` 골격을 만든다
  (id 집합은 정본과 정확히 일치해야 함 — 게이트 무결성 검사 대상).

### Phase 1: 갭 채우기 (maker: 메인)
- 각 항목 status 지정. status==evidenced 는 evidence_path 파일이 실재해야 한다.
- core==true 핵심 항목은 planned/n·a 로 남기지 않는다(implemented/evidenced 목표).
- `--crossmap` 시 ISO27001/SOC2 대응 컬럼을 추가(순서론: ISMS-P 우선).

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-cert-readiness.sh"`
- id 집합==정본(101)·status enum·evidenced 증적 존재·core 이행을 검증. 실패 항목 보완 후 재실행.

## Boundaries

**Will:**
- 101항목 갭 분석, status·증적 경로 관리, ISO27001/SOC2 크로스맵, 게이트 무결성 검증

**Will Not:**
- 개인정보보호법·정보통신망법 **적용·위반 판단** → legal 위임
- 인증 심사 통과 보증 (갭·증적 준비까지가 범위)
- 항목 id 를 정본 무시하고 임의 편집 (isms-p-items.json 우회 금지)
