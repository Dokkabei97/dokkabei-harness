# Team Examples — 프로덕션 팀 구성 예시

## Example 1: 리서치 팀 (Fan-out/Fan-in, Agent Teams)

```
[리더/오케스트레이터]
    ├── TeamCreate(research-team)
    ├── TaskCreate(4개 조사 작업)
    ├── 팀원들이 자체 조율 (SendMessage)
    ├── 결과 수집 (Read)
    └── 종합 보고서 생성
```

### Agent Configuration
| 팀원 | 타입 | 역할 | 출력 |
|------|------|------|------|
| official-researcher | general-purpose | 공식 문서/블로그 | research_official.md |
| media-researcher | general-purpose | 미디어/투자 | research_media.md |
| community-researcher | general-purpose | 커뮤니티/SNS | research_community.md |
| background-researcher | general-purpose | 배경/경쟁/학술 | research_background.md |

> 리서치 에이전트는 빌트인 `general-purpose` 사용하되, `agents/{name}.md` 파일로 정의하여 역할/조사범위/팀 통신 프로토콜 명시.

### Communication Pattern
```
official ──SendMessage──→ background  (관련 공식 발표 공유)
media ────SendMessage──→ background  (투자/인수 정보 공유)
community ─SendMessage──→ media      (미디어 관련 커뮤니티 반응)
모든 팀원 ──TaskUpdate──→ 공유 작업 목록
리더 ←───── 유휴 알림 ──── 완료 팀원
```

---

## Example 2: SF 소설 집필 팀 (Pipeline + Fan-out, Hybrid)

```
Phase 1 (팀): worldbuilder + character-designer + plot-architect → 상호 조율
Phase 2 (서브): prose-stylist 단독 집필
Phase 3 (팀): science-consultant + continuity-manager → 리뷰 공유
Phase 4 (서브): prose-stylist 수정 반영
```

### Agent Configuration
| 팀원 | 역할 | 스킬 |
|------|------|------|
| worldbuilder | 세계관 구축 | world-setting |
| character-designer | 캐릭터 설계 | character-profile |
| plot-architect | 플롯 구조 | outline |
| prose-stylist | 집필/수정 | write-scene, review-chapter |
| science-consultant | 과학 검증 | science-check |
| continuity-manager | 일관성 검증 | consistency-check |

### Agent File Example: `agents/worldbuilder.md`
```yaml
---
name: worldbuilder
description: "SF 소설의 세계관을 구축하는 전문가. 물리 법칙, 사회 구조, 기술 수준, 역사를 설계한다."
tools: ["Read", "Write", "WebSearch"]
team: novel-team
teamRole: member
reportsTo: orchestrator
---
```

Required sections: 핵심 역할, 작업 원칙, I/O 프로토콜, Team Communication Protocol, 에러 핸들링

---

## Example 3: 코드 리뷰 팀 (Fan-out/Fan-in + Discussion, Agent Teams)

```
[리더] → TeamCreate(review-team)
    ├── security-reviewer: 보안 취약점
    ├── performance-reviewer: 성능 분석
    └── test-reviewer: 테스트 커버리지
    → 리뷰어 간 발견 공유 (SendMessage)
    → 리더 결과 종합
```

### Communication Pattern (핵심)
```
security ──SendMessage──→ performance  ("SQL 주입 가능, 성능도 확인 필요")
performance ──SendMessage──→ test      ("N+1 쿼리 발견, 관련 테스트 있나?")
test ────SendMessage──→ security      ("인증 테스트 없음, 보안 우선순위?")
```

리뷰어들이 **리더를 거치지 않고** 직접 소통 → 교차 영역 이슈 빠르게 포착.

---

## Example 4: 코드 마이그레이션 팀 (Supervisor, Agent Teams)

```
[supervisor] → 파일 분석 → 배치 할당
    ├→ [migrator-1] (batch A)
    ├→ [migrator-2] (batch B)
    └→ [migrator-3] (batch C)
    ← TaskUpdate → 추가 배치 할당/재할당
```

### Dynamic Distribution Logic
1. 전체 대상 파일 목록 수집
2. 복잡도 추정 (파일 크기, import 수, 의존성)
3. `TaskCreate`로 파일 배치를 작업 등록
4. 팀원들이 자체적으로 작업 claim
5. 완료 보고 시: 성공 → 다음 작업 / 실패 → 원인 확인 후 재할당
6. 모든 작업 완료 → 통합 테스트

---

## Example 5: 웹툰 제작 (Producer-Reviewer, Sub-agents)

> 2개 에이전트 + 결과 전달 중심 → 서브 에이전트 적합

```
Phase 1: Agent(webtoon-artist) → 패널 생성
Phase 2: Agent(webtoon-reviewer) → 검수 (PASS/FIX/REDO)
Phase 3: Agent(webtoon-artist) → 문제 패널 재생성 (최대 2회)
```

---

## Output Patterns Summary

### Agent Definition Files
- 위치: `agents/{agent-name}.md`
- 필수: 핵심 역할, 작업 원칙, I/O 프로토콜, 에러 핸들링
- 팀 추가: Team Communication Protocol

### Skill Files
- 위치: `skills/{name}/SKILL.md` (< 500줄)
- 초과 시 `references/` 분리

### Orchestrator Skills
- 위치: `skills/{team-name}-orchestrator/SKILL.md`
- 실행 모드 명시 필수
- 후속 작업 키워드 포함

### Workspace Artifacts
- 패턴: `_workspace/{phase}_{agent}_{artifact}.{ext}`
- 보존: 삭제하지 않음 (감사 추적용)
- 재실행 시: `_workspace_prev/`로 이동
