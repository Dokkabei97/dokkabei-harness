---
name: spec-driven-dev
description: |
  새 기능·프로젝트·큰 변경을 코드보다 스펙 먼저로 진행하는 게이트 워크플로(SPECIFY → PLAN → TASKS → IMPLEMENT) — 가정 명시, 측정 가능한 성공 기준, Always/Ask/Never 경계, 단계별 사람 검토로 범위 이탈과 재작업을 줄인다.
  Spec-before-code gated workflow for new features or significant changes: explicit assumptions, measurable success criteria, boundaries, and a human review between stages.
  Use when: "스펙 먼저", "기능 명세", "요구사항 정리", starting a new feature or project, a significant change with vague requirements. 단순 버그 수정·1~2줄 변경엔 불필요.
---

# Spec-Driven Development

코드 작성 전에 스펙을 정의하고, 단계마다 사람의 검토를 거쳐 진행하는 가이드다.
스펙이 길 필요는 없다 — 작은 작업은 2줄 스펙(목표 + 완료 기준)으로 충분하다.

## When it helps / When to skip

- 도움이 됨: 새 기능·프로젝트, 기존 시스템의 중요한 변경, 요구사항이 모호하거나 암묵적 가정이 많을 때, 여러 사람이 협업할 때
- 생략: 단순 버그 수정(증상 → 재현 테스트 → 수정), 1~2줄 설정 변경, 이미 명확한 스펙이 있는 작업

## The Gated Workflow

```
SPECIFY ──→ PLAN ──→ TASKS ──→ IMPLEMENT
  [검토]     [검토]    [검토]     [검증]
```

각 단계 산출물을 사용자에게 보여주고 승인 후 다음 단계로 넘어가는 것을 기본으로 한다.

### Phase 1: SPECIFY

1. **가정 먼저 적기** — 검증 안 된 전제를 목록으로 드러낸다.
   ```
   ASSUMPTIONS:
   - 이 API 는 인증된 사용자만 호출한다
   - 응답 시간 목표는 P95 < 200ms
   - 이벤트 발행은 MVP 범위 밖
   ```
2. **6개 영역** (각 1~5줄):

| 영역 | 내용 | 출처 |
|------|------|------|
| Objective | 무엇을 왜 만드는가 | 요구사항 |
| Commands | 빌드·테스트·실행·린트 명령 | **프로젝트 CLAUDE.md / 빌드 파일에서 확인** — 추측해 적지 않는다 |
| Structure | 소스·테스트 위치 | 기존 디렉터리 관례를 Glob 으로 확인 |
| Code Style | 기존 코드 스니펫 1개로 표현 | 같은 레이어의 기존 파일 |
| Testing | 단위/통합/E2E 범위와 도구 | 프로젝트가 이미 쓰는 프레임워크 |
| Boundaries | Always / Ask first / Never | 아래 표 |

   | Always | Ask first | Never |
   |--------|-----------|-------|
   | 입력 검증, 변경 로직에 테스트 | DB 스키마 변경, 새 외부 의존성, 보안 설정 변경 | 프로덕션 DB 직접 접속, 하드코딩된 시크릿 |

3. **성공 기준을 측정 가능하게** 재서술한다.
   ```
   ❌ "주문 조회를 빠르게"
   ✅ "주문 조회 API P95 < 200ms, 최근 30일, 커서 기반 페이지네이션"
   ```

스택 사실(버전·도구·검증 명령)이 CLAUDE.md 에 없다면 `workflow:project-rules` 로 먼저 정리하면 Commands/Structure 영역을 채우기 쉽다.

### Phase 2: PLAN
- 컴포넌트와 구현 순서(의존성 순), 리스크(외부 연동, 데이터 마이그레이션), 순차 필수 작업(스키마 마이그레이션 등), 검증 체크포인트
- 상세 분해는 `workflow:planning-guide`

### Phase 3: TASKS
- 수직 슬라이스(한 기능을 끝까지) 단위, 태스크당 ~5파일 이하, 각 태스크에 수용 기준 + 검증 명령

### Phase 4: IMPLEMENT
- 한 번에 한 태스크, 완료 시 검증 명령 실행 후 다음으로
- TDD 를 원하면 `test:tdd-workflow`

## Keeping the Spec Alive

- 구현 중 방향이 바뀌면 스펙을 먼저 고치고 사용자에게 확인한다
- 저장 위치는 프로젝트 관례를 따른다(없으면 `docs/specs/YYYY-MM-DD-<feature>.md` 제안)
- MR/PR 설명에 스펙 링크를 남기면 리뷰어가 의도를 대조할 수 있다

## Red Flags

- "done" 정의 없이 시작 / 스펙에 없는 기능 구현(스코프 크리프)
- 구현 중 방향 전환을 스펙에 반영하지 않음

## Related

- `workflow:planning-guide` — 아이디어 정제, 태스크 분해
- `workflow:doc-collab-guide` — 구현 전제가 아닌 기획서·제안서
- `/review-mr` — 구현 결과 리뷰(GitLab)
