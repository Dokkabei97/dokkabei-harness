---
name: governance-templates
description: |
  eng-gov 하네스의 거버넌스 문서 템플릿·통제 매핑 스킬 — MADR 형식 ADR, SLO·에러버짓 정책, 블레임리스 포스트모템, 변경정책, 그리고 SOC 2 CC8.1·ISO 27001:2022 Annex A 통제 매핑표(references/)를 제공한다. 각 템플릿은 대응 결정론 게이트(gate-adr·gate-error-budget·gate-change-evidence)의 계약(status enum·thresholds.yaml 플랫 키·evidence.json 스키마)과 정확히 맞물리는 형식을 규정해, 문서를 쓰면 게이트가 초록이 되도록 한다. /gov-adr·/gov-slo·/gov-postmortem·/gov-change·/gov-audit가 산출물 표준으로 참조한다.
  Governance document templates and control-mapping skill for eng-gov: MADR ADRs, SLO/error-budget policy, blameless postmortems, change policy, and a SOC 2 CC8.1 · ISO 27001:2022 Annex A control map (in references/). Each template's format is aligned to its deterministic gate's contract (status enum, thresholds.yaml flat keys, evidence.json schema) so writing the doc turns the gate green. Use when: authoring an ADR, SLO, postmortem, or change-evidence bundle, or mapping controls for an audit.
metadata:
  version: 1.0.0
  category: governance
---

# Governance Templates

eng-gov 산출물의 **형식 단일 진실 원천**. 게이트(`hooks/gates/*.sh`)가 결정론으로 검사하는 형식을 이 템플릿들이 규정한다 — 템플릿대로 쓰면 게이트가 통과하고, 게이트가 잡지 못하는 의미 품질은 checker 에이전트가 반증한다.

## 언제 적용하나

- `/gov-adr` — 아키텍처 결정 기록/supersede → `references/madr-template.md`
- `/gov-slo` — SLO 문서·에러버짓 정책·임계값 분리 → `references/slo-template.md`
- `/gov-postmortem` — 블레임리스 포스트모템 → `references/postmortem-template.md`
- `/gov-change` — 변경 증적 정책·evidence.json → `references/change-policy-template.md`
- `/gov-audit` — 심사 증적·통제 매핑 → `references/control-map.md`

## 산출물 ↔ 게이트 ↔ 경로 계약

| 산출물 | 경로 | 게이트 | 게이트가 검사하는 형식 |
|--------|------|--------|----------------------|
| ADR | `docs/decisions/NNNN-<slug>.md` | `gate-adr.sh` | 파일명 `^NNNN-`, `status:` enum, `superseded-by: NNNN` 링크 실재 |
| SLO 임계값 | `.planning/gov/slo/thresholds.yaml` | `gate-error-budget.sh` | 플랫 `error_budget_min_pct: <숫자>` (yq 금지 — grep/sed) |
| 에러버짓 잔량 | `.planning/gov/slo/budget.json` | `gate-error-budget.sh` | `{"error_budget_remaining_pct": <숫자>}` |
| 변경 증적 | `.planning/gov/change/<sha>/evidence.json` | `gate-change-evidence.sh` | sha 매칭·author≠approver·risk_tier enum·gates[] 그린 |
| 포스트모템 | `.planning/gov/postmortems/YYYY-MM-DD-<slug>.md` | (게이트 없음) | postmortem-checker 반증만 |

> **경로 규약**: ADR만 업계 표준 `docs/decisions/`, 나머지 상태·증적은 `.planning/gov/`. 파일명 날짜는 `YYYY-MM-DD`, ADR 번호는 4자리 `NNNN`. 이 규약으로 게이트가 파일명만으로 판정 가능하다.

## 핵심 형식 원칙 (게이트 계약 요약)

1. **ADR status enum** — `proposed | accepted | superseded | deprecated` 중 하나를 `status:` 줄에 명시. superseded면 `superseded-by: NNNN`이 실재 ADR을 가리켜야 한다.
2. **thresholds.yaml는 플랫** — 중첩 YAML 금지. `key: value` 한 줄씩(게이트가 grep/sed로 파싱, yq 의존 없음).
3. **evidence.json은 실측만** — 실행하지 않은 게이트를 gates[]에 넣지 않는다. `author != approver`(4-eyes). risk_tier=high면 gate-secrets·gate-supply-chain 기록 필수.
4. **audit-log.jsonl는 append-only** — 수기 편집 금지. `/gov-audit`만 append한다.

## 통제 매핑 (감사 대응)

SOC 2 Type II·ISO 27001:2022 대응에서 "git 네이티브 증적 → 감사 증적"의 매핑은 `references/control-map.md` 참조. 핵심: `evidence.json`(변경통제) → SOC 2 CC8.1 / ISO 27001 A.8.32, `gate-secrets`+`gate-supply-chain`(공급망) → ISO 27001 A.8.8/A.8.24. `/gov-audit`가 이 매핑을 감사 증적 문서로 변환한다.

## 위임 경계

- **법적 판단**(개인정보 영향평가·규제 신고 의무·계약 조항) → **legal** 위임. 템플릿에는 "legal 확인" 플래그만 남긴다.
- **재무 수치**(가용성 SLA 위약금 산정 등) → **finance** 위임.
- 이 스킬은 **문서 형식과 게이트 계약**만 소유한다.

## References

| 문서 | 내용 |
|------|------|
| `references/madr-template.md` | MADR ADR 템플릿(status enum·supersede 링크·fitness 변환 후보 섹션) |
| `references/slo-template.md` | SLO 문서 + 에러버짓 정책 + thresholds.yaml·budget.json 형식(observe/infra-otel 연계 지점) |
| `references/postmortem-template.md` | 블레임리스 포스트모템(타임라인·5-why·owner/due 액션·에러버짓 소모) |
| `references/change-policy-template.md` | 변경정책 + evidence.json 스키마 + risk_tier 분류표 |
| `references/control-map.md` | SOC 2 CC8.1 · ISO 27001:2022 Annex A 통제 매핑표 |
