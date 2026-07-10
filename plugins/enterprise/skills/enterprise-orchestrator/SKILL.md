---
name: enterprise-orchestrator
description: |
  중견·대기업 거버넌스 OS 오케스트레이터 — GRC(리스크·통제·인증·컴플라이언스)와 전사 계획(전략 캐스케이드·경영계획·롤링 포캐스트·M&A 스크리닝) 2개 파이프라인을 라우팅하는 마스터. 커맨드 요청을 트랙별로 분류해 maker(risk-assessor·strategy-analyst·fpna-planner) 초안 → checker(grc-challenger·plan-challenger, Edit 미보유) 반증 → 결정론 게이트(exit 0/1) 순서로 흐르게 하고, 판정 기준·산출물 스키마 정본은 references/gate-policy.md 단일 원천을 따른다. 법률·재무제표·인사·유닛이코노믹스는 legal·finance·hr·startup 위임.
  Master orchestrator of the enterprise governance OS routing two pipelines — GRC (risk/control/certification/compliance) and corporate planning (strategy cascade, annual plan, rolling forecast, M&A screening) — through maker draft, checker (no Edit) falsification, and deterministic gates, with judgment criteria and output schemas canonicalized in references/gate-policy.md. Use when: running enterprise GRC or corporate-planning commands, or coordinating governance deliverables end to end.
metadata:
  version: 1.0.0
  category: enterprise
---

# Enterprise Orchestrator

중견·대기업 거버넌스를 2개 파이프라인(GRC / 전략·계획)의 게이트 기반 상태로 관리하는 오케스트레이터.
자유 대화형 임원 회의는 배제하고, **maker 초안 → checker 반증(Edit 미보유) → 결정론 게이트**의
파일 계약으로만 움직인다. 핵심 명제: **"완료 판정은 모델이 아니라 게이트가 한다."**

## When to Apply

- `/grc-intake`·`/risk-register`·`/control-matrix`·`/policy-suite`·`/cert-gap`·`/comp-calendar` (GRC)
- `/strategy-cascade`·`/annual-plan`·`/rolling-forecast`·`/biz-screen` (전략·계획)
- `/enterprise-from-scaleup` (scaleup 승계 브릿지)
- "GRC 구축", "경영계획 수립", "리스크 레지스터", "ISO 27001 갭", "M&A 스크리닝" 요청

**미발동 (위임 경계):** 유닛 레벨 재무·시장조사(startup) / 재무제표·세무·실적 수치(finance) /
corporate law·M&A 및 규제 신고·whistleblowing·data privacy 법적 판단(legal) / JD·온보딩·징계(hr).

## Architecture

- **패턴**: Dual Pipeline + Producer-Reviewer(단계 내부 maker/checker) + 결정론 게이트
- **실행 모드**: Sub-agents — 메인 세션이 오케스트레이터, maker/checker 를 `Agent` 도구로 디스패치
- **메모리**: `.planning/grc/` + `.planning/enterprise/` 파일 + git = 상태 (compaction 의존 금지)
- **정본**: 판정 기준·스키마·결선표는 [references/gate-policy.md](references/gate-policy.md)

## Team Roster

| ID | 에이전트 | 구분 | 트랙 | 산출물 |
|----|---------|------|------|--------|
| RA | `risk-assessor` | maker | GRC | risk-register.json / control-matrix.json |
| SA | `strategy-analyst` | maker | 전략 | strategy-cascade.md / screen/<target>.json |
| FP | `fpna-planner` | maker | 계획 | budget-*.json / variance/*.json (전사 레벨) |
| GC | `grc-challenger` | checker(Edit✗) | GRC | grc/verdict.json (ACCEPT/REMEDIATE/ESCALATE) |
| PC | `plan-challenger` | checker(Edit✗) | 전략·계획 | verdict.json (APPROVE/REBASELINE/REJECT) |

## Routing — 두 파이프라인

### GRC 파이프라인 (①→⑥ 순차 후 분기 갱신)
`/grc-intake`(프로파일+의무 트리거) → `/risk-register`(RA→GC→gate-risk-register --require-verdict)
→ `/control-matrix`(RA→gate-control-matrix) → `/policy-suite`(메인→GC→gate-policy-suite)
→ `/cert-gap`(메인+iso27001-annex-a→gate-cert-readiness) → `/comp-calendar`(메인→gate-calendar).

### 전략·계획 파이프라인 (⑦→⑧→⑨ 반복, ⑩ 수시)
`/strategy-cascade`(SA→PC, 게이트 없음) → `/annual-plan`(FP→PC→gate-budget)
→ `/rolling-forecast`(FP→gate-variance) → `/biz-screen`(SA→PC→gate-screen --require-verdict).

## Dispatch Rules

- maker 는 초안만 만든다. checker 는 maker 와 분리(Edit 미보유) — 산출물을 고쳐 통과시키지 못한다.
- checker 는 표면 체크(섹션 존재 등) 금지 — 그건 게이트 몫. verdict.json `coverage` 에 반증 질문 기록.
- 게이트가 결정론으로 잡는 것(숫자·enum·산술·기한)은 전부 게이트 선처리, checker 는 의미 판단 잔여분만.
- `--require-verdict` 게이트는 checker 판정이 물화(verdict.json)돼야 통과 — maker/checker/게이트 3단.

## Escalation & Delegation

| 신호 | 위임 |
|------|------|
| corporate/company law·M&A 및 규제 신고·whistleblowing·data privacy 법적 판단 | **legal** |
| 재무제표·세무·ICFR 숫자·실적 수치 검증 | **finance** |
| JD·온보딩·징계 조항 | **hr** |
| 시장조사·유닛이코노믹스·콘텐츠·브랜드보이스 | **startup** |

- verdict 가 ESCALATE(GRC) 인 항목과 merger-control 등 규제 검토는 legal 로 라우팅한다.
- 모든 대외 산출물은 사람 승인 게이트 전제 — 자율 확정 금지.

## Skill References

| 영역 | 스킬 |
|------|------|
| 판정 기준·스키마·결선표 정본 | enterprise-orchestrator/references/gate-policy.md |
| COSO·ISO31000·Three Lines·5x5 | grc-frameworks (+risk-matrix.json) |
| 프레임워크 선택·ISO 27001 Annex A 93·SOC 2·증적 규율 | compliance-context (+iso27001-annex-a.json) |
| Playing to Win·3H·9box·M&A 5카테고리·merger-control 참조 | strategy-frameworks |
| 4Q 캘린더·CLAP·드라이버 트리·DERP | fpna-planning (+clap-keys.json, derp-template.md) |

## Boundaries

**Will:** 트랙 분류·maker/checker/게이트 3단 라우팅, 크로스파일 정합 관리, 위임 신호 식별.
**Will Not:** 법률·재무제표·인사 확정 판단, 게이트 우회, checker 없는 산출물 확정, 자유 대화형 임원 회의.
