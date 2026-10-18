> [English](ARCHITECTURE.md) · **한국어**

# Harness 플러그인 아키텍처 & upstream 마이그레이션 가이드

> 이 플러그인은 [revfactory/harness](https://github.com/revfactory/harness)(Apache-2.0)에서 출발해
> 사내 마켓플레이스에 맞게 **재구조화**한 fork다. upstream은 `harness` + `evolve` 2스킬이지만,
> 이 fork는 책임을 4스킬 + 4커맨드(설계 / 진화 / 생성 / 검증 + 경량 루프)로 분리했다.

## 1. 구조 개요

```
harness/
├── skills/
│   ├── team-harness/        # 설계: 점검 → 도메인 분석 → 실행 모드·팀 패턴 → 에이전트/스킬/오케스트레이터 (메타 스킬, v2)
│   ├── evolve/              # 진화: 피드백 → 일반화 → 1건씩 반영 → git에 델타 기록
│   ├── flow-scaffolding/    # 생성: 컴포넌트 템플릿 (create-flow가 사용)
│   └── flow-validation/     # 검증: 10개 룰셋 (verify-flow가 사용)
├── commands/
│   ├── create-flow.md       # 컴포넌트 생성 진입점
│   ├── verify-flow.md       # 컴포넌트 검증 진입점
│   ├── loop-run.md          # 경량 범용 루프 시작
│   └── loop-stop.md         # 경량 범용 루프 킬스위치
├── hooks/                   # generic-loop-stop-hook.sh (engine=generic)
└── docs/
    └── ARCHITECTURE_KO.md   # (이 문서)
```

**설계 원칙 — 단일 책임 분리:**
- **설계(team-harness)**: "누가/어떻게 협업하는가" — 실행 모드, 패턴 선택, 에이전트 분리 기준, 모델 티어, 오케스트레이터 설계
- **진화(evolve)**: 실행 피드백으로 기존 하네스를 조정. 구조 재설계는 team-harness로 되돌림
- **생성(create-flow + flow-scaffolding)**: 결정된 설계를 실제 파일로 스캐폴딩
- **검증(verify-flow + flow-validation)**: 생성 산출물을 룰셋으로 기계 검증

## 2. upstream ↔ fork 개념 매핑 (upstream v2.1.0)

| upstream | fork 대응 |
|----------|----------|
| harness 0단계 상태 점검(구축/확장/운영) + v1 감지 | team-harness Phase 0 Audit (+ 3자 대조 Drift Detection) |
| 1단계 분야·작업 분석 | team-harness Phase 1 |
| 2단계 실행 모드 + 팀 구성 + 검증 방식 | team-harness Execution Modes / 6 Patterns / 검증·루프 보강 패턴, Phase 2 |
| 3단계 에이전트 정의(중복 확인, 모델 티어, tools) | team-harness Phase 3 (재사용 우선 게이트) → **생성은 create-flow 위임** |
| 4단계 스킬 작성 | team-harness Phase 4 |
| 5단계 통합(모드별 오케스트레이터, 데이터 전달, 오류, 규모, 후속 요청) | team-harness Phase 5 |
| 5-4 CLAUDE.md 호출 조건 + 변경 이력 표 | team-harness Phase 6 — 트리거만, **변경 이력 = git 커밋 본문** |
| 6단계 검증과 테스트 | team-harness Phase 7 → **verify-flow + flow-validation 룰셋** |
| 7단계 운영 / `harness:evolve` | team-harness Phase 7 운영 / **evolve** 스킬 |
| references 9종 | 동일 구성. `team-patterns.md`가 기존 `agent-design-patterns.md`를 대체, fork 전용 `loop-harness-guide.md` 추가 |

## 3. fork 고유 확장 (upstream에 없음)

- **커맨드 분리**: `/create-flow`·`/verify-flow`로 생성/검증을 독립 호출
- **flow-validation 10개 룰셋**: agt/cmd/hk/loop/orc/qua/sec/skl/team/**xrf**(교차참조) — v1 유물 감지·워크플로 스크립트 함정까지 기계 검사
- **검증·루프 보강 패턴**: upstream 품질 패턴 위에 Verification Gate / Guardrails, Stop훅 엔진 기반 Loop Harness Design(4요소)
- **하네스 간 협업**: 협업 호출 규약 표, 위임 경계, 루프 엔진 재사용 vs 복제 규칙
- **git을 변경 원장으로**: evolve는 CLAUDE.md 표 대신 델타 1건을 Conventional Commit 1건으로, 본문에 사유를 기록
- **프로덕션 운영**: `search`·`mvp`·`feature-loop` 등 실제 운영 하네스를 이 메타 스킬로 운용

## 4. upstream 동기화 시 주의사항

upstream을 추적할 때는 **버전 추종이 아니라 개념 선별 이식**이 원칙이다. fork가 구조적으로 갈라졌으므로:

1. upstream 신규 기능을 fork의 책임(설계/진화/생성/검증) 중 맞는 곳에 매핑한다.
2. upstream의 단일 스킬 전제(단계 번호, CLAUDE.md 변경 이력 표, `.claude/commands/` 금지)를 그대로 옮기지 않는다.
3. 3-way로 병합한다: upstream 직전 동기화 시점 → fork → upstream 신버전. fork 고유 추가분이 살아남게 한다.
4. 이식 후 출처(upstream 버전·커밋)와 매핑을 커밋 본문에 기록하고 `NOTICE`를 갱신한다.

최종 동기화: 2026-10-18 (upstream v2.1.0, 커밋 928de2c — v2 재구축 + evolve).
