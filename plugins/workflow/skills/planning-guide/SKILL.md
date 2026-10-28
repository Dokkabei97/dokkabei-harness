---
name: planning-guide
description: |
  모호한 아이디어를 원페이저 계획과 실행 가능한 태스크로 바꾸는 가이드 — 문제 재진술, 가정 명시, 의존성 순서, 수직 슬라이싱, 태스크 크기(XS~XL)와 분해 기준, 태스크 템플릿.
  Turns vague ideas into a one-page plan and implementable tasks: problem restatement, explicit assumptions, dependency order, vertical slicing, task sizing.
  Use when: "계획 세워줘", "태스크로 쪼개줘", "작업 분해", "범위 정리", breaking down a feature, planning a vague request.
---

# Planning Guide — 아이디어 정제부터 태스크 분해까지

## 1. 정제 (원페이저)

모호한 요청은 측정 가능한 문제로 재진술하고, 아래 원페이저를 채워 사용자와 맞춘다.

```markdown
## [기능명] 계획
### Problem — "How might we …" 형식, 측정 가능한 목표 포함
### Direction — 2~3개 접근 중 선택과 이유(사용자 가치·실현 가능성·유지보수성)
### Assumptions to validate
- [ ] [가정] — 검증 방법: [프로파일링/쿼리/로그 확인 등]
### MVP scope
### Not doing (and why)
### Open questions
```

막히면 다섯 질문: 누구를 위한가 / 성공 기준은 / 제약은 / 이전에 무엇을 시도했나 / 왜 지금인가.

## 2. 의존성 순서

코드를 쓰기 전에 읽기 전용으로 기존 패턴과 의존성을 파악한다. 일반적으로 하위 계층부터:
스키마/마이그레이션 → 영속 계층 → 도메인/서비스 → 핸들러/컨트롤러 → 통합 테스트 → API 문서.
마이그레이션 도구·영속 방식(ORM/원시 SQL)은 프로젝트마다 다르므로 빌드 파일과 기존 코드로 확인한다.

## 3. 태스크 분해

**수직 슬라이스**: "모든 엔티티 → 모든 서비스" 대신 "주문 생성(저장소+서비스+핸들러+테스트)"처럼
독립적으로 테스트 가능한 기능 단위로 자른다.

| 크기 | 파일 수 | 예시 |
|------|---------|------|
| XS | 1 | 검증 규칙 추가 |
| S | 1~2 | 엔드포인트 1개 |
| M | 3~5 | 한 기능 슬라이스 |
| L | 5~8 | 필터+페이징 검색 |
| XL | 8+ | **더 쪼갠다** |

더 쪼갤 신호: 수용 기준 3개 초과, 독립 서브시스템 2개 이상 접촉, 제목에 "그리고/and".

```markdown
### Task N: [제목]
- Description: [무엇을 왜]
- Acceptance: - [ ] … - [ ] …
- Verify: [프로젝트 검증 명령 — CLAUDE.md 의 Commands 에서]
- Depends on: Task N-1
- Files: […]  · Size: M
```

2~3개 태스크마다 체크포인트: 테스트·빌드 통과, CI 통과, 필요 시 사람 리뷰.

## Related

- `workflow:spec-driven-dev` — 계획을 게이트 스펙으로 발전시킬 때
- `workflow:project-rules` — 검증 명령·스택 사실이 CLAUDE.md 에 없을 때
- `/handoff` — 계획과 진행 상황을 다음 세션에 넘길 때
