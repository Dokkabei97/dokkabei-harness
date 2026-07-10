---
name: cert-gap
description: |
  ISO/IEC 27001:2022 Annex A 93개 통제 갭 분석(status n/a·planned·implemented·evidenced + 증적 경로) + SOC 2 크로스맵 → 게이트.
  Runs an ISO/IEC 27001:2022 Annex A 93-control gap analysis (status + evidence paths) with a SOC 2 crossmap, then enforces the readiness gate. Use when: preparing ISO 27001 certification, tracking control evidence, or cross-mapping to SOC 2.
category: governance
complexity: advanced
mcp-servers: []
personas: []
---

# /cert-gap - ISO 27001 Annex A 인증 갭 분석

ISO/IEC 27001:2022 Annex A 93개 통제(A.5 Organizational 37 + A.6 People 8 + A.7 Physical 14 +
A.8 Technological 34)의 이행 상태를 갭 분석한다. 정본은 `compliance-context/references/
iso27001-annex-a.json`("갱신 필요" 스탬프). 항목별 status(`n/a→planned→implemented→evidenced`)와
증적 경로를 채우고, `gate-cert-readiness.sh` 가 무결성·framework·part·증적·핵심통제 이행을 검증한다.
SOC 2 Trust Services Criteria 크로스맵으로 증적을 재사용한다. 기준은 gate-policy.md.

## Triggers
- "ISO 27001 갭", "인증 준비", "Annex A 통제", "SOC 2 크로스맵" 요청
- `/grc-intake` 에서 ISO 27001·SOC 2 를 채택 프레임워크로 선언한 경우

## Usage
```
/cert-gap [옵션]

Options:
  --crossmap soc2   SOC 2 TSC 대응 컬럼 추가 생성
```

## Behavioral Flow

### Phase 0: 초기화
- `iso27001-annex-a.json`(93개 통제) 을 정본으로 읽어 `.planning/grc/cert-gap.json` 골격을 만든다
  (framework="ISO27001", id 집합·part 는 정본과 정확히 일치해야 함 — 게이트 무결성 검사 대상).

### Phase 1: 갭 채우기 (maker: 메인)
- 각 통제 status 지정. status==evidenced 는 evidence_path 파일이 실재해야 한다(로그·티켓·리뷰 이력 등 실질 증적).
- core==true 핵심 통제(정책·접근통제·사고대응·인식교육·특권접근·암호화·백업·로깅·변경관리 등)는 planned/n·a 로 남기지 않는다.
- `--crossmap soc2` 시 통제별 대응 SOC 2 TSC 컬럼을 추가(Security 공통 + 선택 기준).

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-cert-readiness.sh"`
- framework·id 집합==정본(93)·status/part enum·evidenced 증적 존재·core 이행을 검증. 실패 항목 보완 후 재실행.

## Boundaries

**Will:**
- Annex A 93개 통제 갭 분석, status·증적 경로 관리, SOC 2 크로스맵, 게이트 무결성 검증

**Will Not:**
- data privacy(GDPR 등) 규제 **적용·위반 판단** → legal 위임
- 인증 심사 통과 보증 (갭·증적 준비까지가 범위)
- 통제 id·part 를 정본 무시하고 임의 편집 (iso27001-annex-a.json 우회 금지)
