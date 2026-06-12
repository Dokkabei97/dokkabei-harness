# Harness 플러그인 아키텍처 & upstream 마이그레이션 가이드

> 이 플러그인은 [revfactory/harness](https://github.com/revfactory/harness)(Apache-2.0)에서 출발해
> 사내 마켓플레이스에 맞게 **재구조화**한 fork다. upstream은 단일 `harness` 스킬(모놀리식)이지만,
> 이 fork는 책임을 3스킬 + 2커맨드로 분리했다.

## 1. 구조 개요

```
harness/
├── skills/
│   ├── team-harness/        # 설계: 도메인 분석 → 팀 아키텍처 → 오케스트레이터 설계 (메타스킬)
│   ├── flow-scaffolding/    # 생성: 컴포넌트 템플릿 (create-flow가 사용)
│   └── flow-validation/     # 검증: 9개 룰셋 (verify-flow가 사용)
├── commands/
│   ├── create-flow.md       # 컴포넌트 생성 진입점
│   └── verify-flow.md       # 컴포넌트 검증 진입점
└── docs/
    └── ARCHITECTURE.md      # (이 문서)
```

**설계 원칙 — 단일 책임 분리:**
- **설계(team-harness)**: "누가/어떻게 협업하나" — 패턴 선택, 에이전트 분리 기준, 오케스트레이터 설계
- **생성(create-flow + flow-scaffolding)**: 결정된 설계를 실제 파일로 스캐폴딩
- **검증(verify-flow + flow-validation)**: 생성물을 룰셋으로 기계 검증

## 2. upstream ↔ fork 개념 매핑

| upstream (단일 harness 스킬) | fork 대응 |
|------------------------------|-----------|
| Phase 0 감사 + Drift Detection | team-harness Phase 0 Audit |
| Phase 1 도메인 분석 | team-harness Phase 1 |
| Phase 2 팀 설계 (모드+패턴+4축) | team-harness Phase 2 |
| Phase 3·4 에이전트/스킬 생성 | team-harness Phase 3 → **create-flow 위임** |
| Phase 3-0/4-0 재사용 리뷰 | team-harness Phase 3 "재사용 우선 게이트" |
| Phase 5 통합·오케스트레이션 | team-harness Phase 4 등록 |
| Phase 6 검증(6단계) | team-harness Phase 5 → **verify-flow + flow-validation 9룰셋** |
| Phase 7 진화 | team-harness Phase 6 Feedback Loop |
| 6 아키텍처 패턴 / 3 실행모드 | 동일 보존 + 검증·루프 보강 패턴 4종 추가 |

## 3. fork 고유 확장 (upstream에 없음)

- **커맨드 분리**: `/create-flow`·`/verify-flow`로 생성/검증을 독립 호출
- **flow-validation 9룰셋**: agt/cmd/hk/orc/qua/sec/skl/team/**xrf**(교차참조) — upstream의 "6단계 검증" 서술보다 기계적
- **검증·루프 보강 패턴**: Adversarial Verify / Loop-until-dry / Verification Gate / Guardrails (2026 트렌드 반영)
- **실전 운용**: 이 메타스킬로 `search`·`legacy` 등 프로덕션 하네스를 실제 운용

## 4. upstream 동기화 시 주의

upstream을 추적할 때는 **버전 추종이 아니라 개념 선별 이식**이 원칙이다. fork가 구조적으로 분기했으므로:

1. upstream 신규 기능을 fork의 3책임(설계/생성/검증) 중 맞는 곳에 매핑한다.
2. upstream의 단일-스킬 전제(Phase 번호, 내부 생성 로직)는 그대로 옮기지 않는다.
3. 이식 후 CLAUDE.md `## Harness` 변경 이력에 출처(upstream 버전)와 매핑을 기록한다.

마지막 동기화: 2026-06-11 (upstream v1.2.1 + Unreleased 기준, U1~U4 이식).
