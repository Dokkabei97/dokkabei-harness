---
name: enterprise-from-scaleup
description: |
  scaleup 산출물(.planning/scaleup/)을 enterprise 거버넌스 인테이크로 승계하는 브릿지 — headcount·OKR 이력·조직도·보드/투자자·파이프라인을 읽어 /grc-intake 프로파일과 /strategy-cascade 초안을 프리필한다. .planning/scaleup/ 부재 시 /grc-intake 풀 인터뷰로 폴백(독립 사용 보장). scaleup 없이도 enterprise 는 처음부터 동작.
  Bridge that carries scaleup outputs (.planning/scaleup/) into enterprise governance intake — reads headcount, OKR history, org chart, board/investor, and pipeline to pre-fill /grc-intake profile and /strategy-cascade draft, falling back to a full /grc-intake interview when scaleup is absent. Use when: an org graduating from scaleup starts enterprise GRC/planning.
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /enterprise-from-scaleup - scaleup → enterprise 브릿지

`scaleup` 하네스가 `.planning/scaleup/` 에 남긴 산출물을 **enterprise 거버넌스 인테이크로 승계**한다.
`/grc-intake` 프로파일과 `/strategy-cascade` 초안을 프리필해 인테이크 왕복을 줄인다. scaleup 산출물이
없으면 `/grc-intake` 풀 인터뷰로 폴백하므로 **enterprise 는 scaleup 없이도 독립 동작**한다.

> 파이프라인 로직 전체는 `enterprise-orchestrator` 가 수행한다. 이 커맨드는 **scaleup 산출물 → 인테이크
> 매핑**과 진입만 담당하며, GRC/계획 로직을 중복 기술하지 않는다.

## Triggers
- scaleup 단계를 지나 중견·대기업 거버넌스(GRC·경영계획)로 넘어갈 때
- "스케일업에서 이어서 GRC 구축", "조직·OKR 데이터로 거버넌스 시작" 요청

## Usage
```
/enterprise-from-scaleup [옵션]

Options:
  --interview   승계를 건너뛰고 /grc-intake 풀 인터뷰로 시작
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/scaleup/` 존재 확인. **부재 시** 중단 없이 `/grc-intake` 풀 인터뷰로 폴백(독립 사용 보장).
- 기존 `.planning/grc/grc-profile.json` 이 있으면 재개/갱신 안내.

### Phase 1: 승계 매핑
| scaleup 산출물 | → enterprise 인테이크/초안 |
|----------------|----------------------------|
| `org/headcount.json` | `/grc-intake` 상시근로자 → 자산구간·중대재해·산안위 의무 플래그 |
| OKR 이력 + `board/kpi-pack.json` | `/strategy-cascade` 초안 시드(대원칙·지표) |
| `org/org-chart.*` | risk/control owner **실재성 후보** |
| `board/`·`investor/` | `/annual-plan` CEO 대원칙·톤 참조 |
| `gtm/pipeline/*-audit.json` | `/rolling-forecast` 매출 드라이버 시드 |

- 매핑은 **컨텍스트(질문 사전 답변)**일 뿐 자동 확정이 아니다. 빈 칸만 인테이크 질문으로 남긴다.

### Phase 2: enterprise-orchestrator 진입
- 프리필된 프로파일로 `/grc-intake` 를 진입시키고, 이후 표준 GRC/계획 파이프라인을 안내한다.
- 승계한 항목과 여전히 물은 항목을 **1줄로 구분 보고**한다.

## Boundaries

**Will:**
- `.planning/scaleup/` 승계 프리필, 채운/물은 항목 투명 구분, 표준 파이프라인 적용

**Will Not:**
- scaleup 부재 시 중단 (→ `/grc-intake` 폴백)
- 승계 데이터를 확정 프로파일로 자동 승격 (사람 승인 전제)
- 법률·재무제표·인사 판단 → legal·finance·hr 위임
- scaleup 산출물 수정/재생성 (읽기 승계만)
