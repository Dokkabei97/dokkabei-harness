---
name: retro
description: "Session retrospective router — extracts corrections, mistakes, and discoveries from the current session, then routes them by type: convention changes to sync-claude-md, recurring mistakes to tasks/lessons.md with guard-hook candidate tags, domain knowledge updates as skill-edit proposals. All routing requires user approval before apply."
category: workflow
complexity: intermediate
mcp-servers: []
personas: []
---

# /retro - 교훈 컴파운딩 라우터

## Triggers
- 작업·코드 리뷰·루프 하네스가 종료되어 이번 세션의 교훈을 회수하고 싶을 때
- 사용자가 세션 중 교정(잘못된 접근을 고쳐준 지시)을 여러 번 했을 때
- "회고", "레트로", "교훈 정리", "lessons 정리", "오늘 배운 것 기록" 요청 시
- 같은 실수가 반복되어 재발 방지 규칙이 필요하다고 판단될 때

## Usage
```
/retro [options]

Options:
  --dry-run        추출·품질 필터·라우팅 계획만 보고하고 어떤 파일도 수정하지 않음
  --lessons-only   (b) 반복 실수 기록만 수행 — sync-claude-md 위임과 스킬 수정 제안은 생략
```

## Behavioral Flow

전 과정의 판정 기준·기록 형식·방지 원칙은 `retro-compound` 스킬을 따른다.

### Phase 1: 회고 원료 수집
이번 세션에서 교훈의 원료가 되는 사건을 수집한다.

1. **교정(correction)**: 사용자가 결과물이나 접근을 고쳐준 지점 — 지시 번복, 재작업 요청, "그게 아니라 ~" 류 발화
2. **실수(mistake)**: 에러·실패한 시도·되돌린 변경 — 실패한 명령, revert된 편집, 검증 실패
3. **발견(discovery)**: 세션 중 새로 알게 된 프로젝트 사실 — 숨은 컨벤션, 도구 제약, 도메인 규칙
4. 보조 근거로 `git status --short`, `git log --oneline -10`을 확인해 실제 변경·되돌림 흔적과 대조

### Phase 2: 교훈 품질 필터
retro-compound 스킬의 품질 기준으로 각 후보를 판정한다.

- **재현 가능성**: 구체 사례(파일·명령·입력)가 있어 제3자가 상황을 재구성할 수 있는가
- **일반화 가능성**: 1회성 사건이 아니라 미래 작업에 적용되는 원리인가
- **판정 가능성**: 규칙 준수/위반을 객관적으로 판정할 수 있는 서술인가

기준 미달 후보는 **기록 보류** 목록으로 분리한다(버리지 않고 Phase 5 보고에 사유와 함께 표시).

### Phase 3: 유형별 라우팅 판정
통과한 교훈을 retro-compound 스킬의 라우팅 표에 따라 분류한다.

| 유형 | 판정 신호 | 라우팅 대상 | 적용 방식 |
|------|----------|------------|----------|
| **(a) 컨벤션 변화** | 프로젝트 규칙·구조·도구 사용법이 바뀌었거나 문서화 안 된 규칙 발견 | `workflow:sync-claude-md` 스킬 위임 | 승인 후 위임 실행 |
| **(b) 반복 실수 패턴** | 같은 유형의 교정·실수가 세션 내 2회 이상 또는 기존 lessons와 동일 패턴 | `tasks/lessons.md` 기록 (+조건 충족 시 `#가드-훅-후보` 태그) | 승인 후 직접 기록 |
| **(c) 도메인 지식 갱신** | 특정 플러그인 스킬의 내용이 낡았거나 트리거가 빗나감 | 해당 스킬 수정 **제안서** 산출 | 제안만 — 자동 수정 금지 |

- 하나의 교훈이 복수 유형에 해당하면 복수 라우팅한다(예: 컨벤션 변화이면서 반복 실수).
- (b)의 가드 훅 후보 태그는 표기까지만 한다 — 훅 스캐폴딩은 `harness:create-flow`의 몫이며, create-flow의 lessons 입력 모드는 별도 작업 예정이다.

### Phase 4: 중복·상충 검사
라우팅 결과를 적용하기 전에 기존 규칙과 대조한다.

1. `tasks/lessons.md` 기존 항목과 대조 — **중복**이면 신규 기록 대신 기존 항목의 발생 횟수 증가로 전환
2. 프로젝트 `CLAUDE.md`(및 `claude/CLAUDE.md`) 규칙과 대조 — 이미 명문화된 규칙이면 기록 생략, **상충**하면 양쪽을 병기해 사용자 판단 항목으로 표시
3. (c) 제안 대상 스킬의 현재 내용과 대조 — 이미 반영된 내용이면 제안 철회

### Phase 5: 사용자 승인 게이트
모든 라우팅 결과를 적용 **전에** 요약 표로 제시하고 항목별 승인을 받는다.

```
## 회고 라우팅 계획
| # | 교훈 요약 | 유형 | 라우팅 | 중복/상충 | 조치 |
|---|----------|------|--------|----------|------|
| 1 | ... | (a) 컨벤션 | sync-claude-md 위임 | 없음 | 승인 대기 |
| 2 | ... | (b) 반복 실수 | lessons.md 기록 #가드-훅-후보 | 기존 항목 재발(+1) | 승인 대기 |
| 3 | ... | (c) 도메인 지식 | {plugin}:{skill} 수정 제안 | 없음 | 제안서 첨부 |

기록 보류: {건수}건 — {사유 요약}
```

- 사용자는 전체 승인 / 항목별 선택 승인 / 전체 반려를 할 수 있다.
- 상충 항목은 승인 대상이 아니라 **판단 요청** 항목이다 — 어느 규칙이 맞는지 사용자가 결정할 때까지 적용하지 않는다.
- `--dry-run`이면 여기서 종료한다.

### Phase 6: 적용 및 보고
승인된 항목만 적용한다.

1. **(a)**: `workflow:sync-claude-md` 스킬을 발동해 CLAUDE.md 갱신을 위임 (수동 발동이므로 위임 결과가 보고됨)
2. **(b)**: `tasks/lessons.md`에 retro-compound 스킬의 기록 형식으로 추가/갱신 (파일 없으면 생성)
3. **(c)**: 수정 제안서를 출력 — 대상 스킬 경로, 현재 서술, 제안 서술, 근거. 파일은 건드리지 않는다
4. 적용 결과를 1~3줄로 요약 보고하고, 가드 훅 후보가 있으면 "추후 harness:create-flow로 훅 스캐폴딩 가능" 안내를 덧붙인다

## Tool Coordination
- **Bash**: `git status --short`, `git log --oneline -10` — 세션 변경·되돌림 흔적 확인 (병렬 실행)
- **Read**: `tasks/lessons.md`, 프로젝트 `CLAUDE.md`, (c) 제안 대상 스킬의 SKILL.md — 중복·상충 검사
- **Glob**: `**/CLAUDE.md`, `plugins/*/skills/*/SKILL.md` — 대조 대상 탐색
- **Write/Edit**: `tasks/lessons.md` 기록/갱신 (승인 후, 이 파일만)
- **Skill**: `workflow:sync-claude-md` 위임 발동 (승인 후)

## Examples

### 작업 종료 후 기본 회고
```
/retro
# 세션에서 교정 2건, 실수 1건, 발견 1건 추출
# 품질 필터 통과 3건 → (a) 1건, (b) 1건(#가드-훅-후보), (c) 1건 라우팅
# 승인 게이트에서 사용자가 (a),(b)만 승인 → sync-claude-md 위임 + lessons.md 기록
```

### 적용 없이 라우팅 계획만 확인
```
/retro --dry-run
# 추출·품질 필터·라우팅 계획 표만 출력
# 파일 수정, 스킬 위임 없이 종료
```

### 반복 실수 기록만 빠르게
```
/retro --lessons-only
# (b) 반복 실수 패턴만 추출해 승인 후 tasks/lessons.md에 기록
# 컨벤션 위임과 스킬 수정 제안은 생략
```

## Boundaries

**Will:**
- 이번 세션의 교정·실수·발견을 추출하고 품질 기준으로 필터링
- 유형별 라우팅: (a) sync-claude-md 위임, (b) tasks/lessons.md 기록 + 가드 훅 후보 태그, (c) 스킬 수정 제안
- 적용 전 기존 규칙과의 중복·상충 검사 및 사용자 승인 게이트 운영
- 저품질·1회성 교훈을 기록 보류로 분리해 규칙 인플레이션 방지

**Will Not:**
- 사용자 승인 없이 어떤 파일도 수정하거나 스킬을 위임 실행하지 않음
- (c) 유형의 플러그인 스킬을 직접 수정하지 않음 — 제안서 산출까지만
- 가드 훅을 직접 생성하지 않음 — `#가드-훅-후보` 태그 표기까지만 (스캐폴딩은 harness:create-flow 담당)
- CLAUDE.md를 직접 편집하지 않음 — 컨벤션 반영은 sync-claude-md에 위임
- 상충하는 규칙을 자동으로 해소하지 않음 — 사용자 판단 요청으로 승격
- git commit/push 등 형상 관리 작업 수행
