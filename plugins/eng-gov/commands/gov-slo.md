---
name: gov-slo
description: |
  SLO·에러버짓 정책 커맨드 — SLI 정의·SLO 목표·에러버짓 정책을 담은 slo.md와 게이트 입력 임계값(thresholds.yaml, 플랫 error_budget_min_pct)을 분리 작성하고(governance-templates 참조), gate-error-budget.sh를 시운전한다. SLI 실측 수집은 자체 구현하지 않고 observe 플러그인·infra/otel 스택 연계 또는 수동 폴백으로 budget.json을 채운다. 게이트는 잔량 ≥ 최소면 통과, 미만이면 소진(릴리즈 차단), budget.json 부재면 미측정(exit 2)로 3분기 판정한다. Use when 서비스의 SLO·에러버짓 정책을 정의하거나 릴리즈 차단 임계값을 설정할 때.
  SLO/error-budget command: authors slo.md (SLI definitions, SLO targets, error-budget policy) and, separately, the gate input thresholds.yaml (flat error_budget_min_pct) per governance-templates, then trial-runs gate-error-budget.sh. It does not build an SLI collector — budget.json is filled via the observe plugin / infra-otel stack or a manual fallback. The gate is three-way: pass (remaining ≥ min), exhausted (blocks releases), unmeasured (exit 2). Use when: defining SLO/error-budget policy or setting a release-blocking threshold.
category: workflow
complexity: intermediate
mcp-servers: []
personas: []
---

# /gov-slo — SLO·에러버짓 정책

SLO 문서와 게이트 입력 임계값을 분리 작성하고 에러버짓 게이트를 시운전한다. 형식은 `governance-templates`(`references/slo-template.md`)가 정본. **SLI 실측 수집기 자체 구현 금지** — observe/infra-otel 연계가 원칙.

## Triggers
- 서비스의 가용성·지연 SLO와 에러버짓 정책을 정의할 때
- 에러버짓 소진 시 릴리즈 동결 임계값을 설정할 때
- "SLO 정해줘", "에러버짓 정책", "가용성 목표" 요청

## Usage
```
/gov-slo "<서비스명>" [옵션]
Options:
  --min-budget <pct>   error_budget_min_pct 초기값(기본 20)
  --window <28d|30d>   측정 창(기본 28d 롤링)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/gov/slo/` 존재 확인(없으면 `/gov-init` 안내).

### Phase 1: SLO 문서 (slo.md)
1. `.planning/gov/slo/slo.md` 작성: SLI 정의(가용성·지연 등), SLO 목표표(목표·창), 에러버짓 정책(소진 시 동결 규칙).
2. SLI는 관측 가능한 것만 — 측정 불가한 SLI는 넣지 않는다.

### Phase 2: 임계값 분리 (thresholds.yaml — 플랫)
1. `.planning/gov/slo/thresholds.yaml`에 **플랫 형식**으로 기록: `error_budget_min_pct: <n>`, `availability_slo_pct:`, `latency_p99_ms:`.
2. 중첩 YAML 금지(게이트가 grep/sed로 파싱 — yq 미의존).

### Phase 3: 잔량 입력 경로 안내 (budget.json)
1. `budget.json`은 **자동 생성하지 않는다**. observe 플러그인/OTel/Grafana 쿼리 또는 수기 계산으로 `{"error_budget_remaining_pct":<n>,"source":"otel|manual"}`을 채우는 방법을 안내.
2. 초기엔 미측정 상태(파일 없음)가 정상 — 게이트가 exit 2로 구분한다.

### Phase 4: gate-error-budget 시운전
1. `bash ${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-error-budget.sh` 실행.
2. 3분기 보고: 통과(잔량 ≥ min) / 소진(< min, 릴리즈 차단) / 미측정(budget.json 없음 — 측정 먼저).

## Tool Coordination
- **Skill**: `governance-templates`(slo-template — 형식·게이트 계약)
- **Write**: `slo.md`, `thresholds.yaml`
- **Bash**: `gate-error-budget.sh` 시운전
- **연계**: observe 플러그인·infra/otel(budget.json 실측 입력원)

## Boundaries

**Will:** SLO 문서·thresholds.yaml 분리 작성, budget.json 입력 경로 안내, gate-error-budget 3분기 시운전.
**Will Not:**
- SLI 실측 수집기 자체 구현(→ observe/infra-otel 연계)
- SLA 위약금·계약 수치 산정(→ finance/legal 위임)
- budget.json 임의 값 조작(미측정을 통과로 위장 금지)
