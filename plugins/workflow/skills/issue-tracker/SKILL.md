---
name: issue-tracker
description: |
  plane-cli를 활용한 Plane 이슈 트래커 연동 스킬.
  브랜치명에서 이슈를 자동 감지하고, 작업 상태 추적, 변경 이력 기록,
  서브태스크 분할 제안까지 개발 전 과정에서 이슈를 관리합니다.
  Integrates with the Plane issue tracker via plane-cli: auto-detects the issue from the branch name, then manages it across the whole dev cycle — work status tracking, change history logging, and subtask split suggestions. Use when: linking or tracking issues, updating Plane tickets, recording work history, connecting a branch to its issue.
metadata:
  version: 2.0.0
  category: workflow
  domain: issue-tracking
  requires_cli: plane
triggers:
  - "이슈 연결"
  - "이슈 추적"
  - "plane 연동"
  - "이슈 트래커"
  - "작업 기록"
auto_suggest:
  keywords:
    - "작업 완료"
    - "다 했어"
    - "커밋할게"
    - "PR 생성"
    - "머지"
  action: "Plane에 작업 이력을 기록할까요?"
  phase: 5
---

# Issue Tracker - Plane CLI 기반 이슈 트래커 연동

## Overview

개발 워크플로우와 Plane 이슈 트래커를 `plane-cli`로 연동합니다.
브랜치명에서 이슈 번호를 파싱하고, 코드 변경 범위를 분석하여 서브태스크를 제안하며,
작업 완료 시 변경 요약을 코멘트에 기록합니다.

> **v2.0 변경사항:** Plane MCP 의존성 제거. 모든 API 호출을 `plane` CLI로 대체.
> `.plane-context.json` 제거 → `plane config`로 통합.

---

## 1. 사전 요구사항

### plane-cli 설정 확인

스킬 실행 전 `plane` CLI가 설정되어 있는지 확인합니다.

```bash
# 설정 확인
plane config list

# 미설정 시 초기화
plane config init
```

필수 설정값:
- `base_url`: Plane 인스턴스 URL
- `api_key`: API 인증 키
- `workspace`: 워크스페이스 slug
- `project`: 기본 프로젝트 ID (선택 — 브랜치에서 자동 감지 가능)

---

## 2. 활성화 규칙

| 트리거 유형 | 조건 | 동작 |
|-------------|------|------|
| **수동** | "이슈 연결", "이슈 추적", "plane 연동" 등 명시적 호출 | Phase 1~5 전체 실행 |
| **자동 제안** | "작업 완료", "다 했어", "커밋할게", "PR 생성" 등 완료 신호 감지 | "Plane에 기록할까요?" 질문 → 승인 시 Phase 5만 실행 |

---

## 3. Behavioral Flow

### Phase 1: CLI 환경 검증

```
1. `plane config list` 실행 → 설정 상태 확인
2. base_url, api_key, workspace가 설정되어 있는지 검증
3. 미설정 시 → 사용자에게 `plane config init` 실행 안내
4. `plane user me -f json` 실행 → API 연결 및 인증 검증
5. 검증 실패 시 → 오류 메시지 표시, 재설정 안내
```

### Phase 2: Issue Discovery

```
1. `git branch --show-current` → 현재 브랜치명 확인
2. 정규식으로 이슈 식별자 파싱: /([A-Z][A-Z0-9]+-\d+)/
   예: feature/PROJ-42-add-cart → PROJ-42
3. 식별자 발견 시:
   → `plane issue get PROJ-42 -f json` → 이슈 자동 연결
   → 이슈 제목, 상태, 담당자 표시
4. 식별자 미발견 시:
   → 사용자에게 이슈 지정 방식 질문:
     a) "이슈 번호 직접 입력" → 번호 입력 → `plane issue get <ID> -f json`
     b) "이슈 목록에서 선택" → `plane issue list -f json` → 결과에서 선택
     c) "새 이슈 생성" → issue.html 템플릿 변수 수집 →
        `plane issue create --name "제목" --description "<html>"`
     d) "이슈 없이 진행" → 이슈 미연결 (Phase 5 이력 기록 생략)
```

### Phase 3: Work Tracking

```
1. 연결된 이슈의 현재 상태 확인 (Phase 2에서 조회한 JSON의 state 필드)
2. 상태가 "In Progress"가 아니면:
   → 사용자에게 "상태를 In Progress로 변경할까요?" 확인
   → 승인 시 `plane state list -f json` → group이 "started"인 상태 ID 조회
   → `plane issue update PROJ-42 --state <in_progress_state_id>`
3. 작업 유형 자동 분류 (Smart Categorization):
   a) 브랜치 prefix 분석:
      - feature/, feat/ → Feature
      - fix/, bugfix/, hotfix/ → Bug
      - refactor/ → Refactor
      - chore/, docs/ → Maintenance
   b) 커밋 메시지 패턴 (보조):
      - "fix", "resolve", "close" → Bug
      - "add", "implement" → Feature
      - "refactor", "clean" → Refactor
   c) diff 패턴 (보조):
      - 새 파일 추가 비율 높음 → Feature
      - 기존 파일 수정 위주 → Bug/Refactor
4. `git diff --stat`으로 변경 범위 추적 → 변경 파일 수, 추가/삭제 라인 수 기록
```

### Phase 4: Scope Analysis & Sub-task Suggestion

```
1. `git diff --name-only`로 변경 파일 목록 수집
2. 파일 경로 기반 모듈 그룹핑:
   - api/, controller/, route/ → API 모듈
   - service/, usecase/, domain/ → Service 모듈
   - component/, page/, view/ → UI 모듈
   - test/, spec/, __tests__/ → Test 모듈
   - config/, infra/, deploy/ → Infrastructure 모듈
   - migration/, schema/ → Database 모듈
3. Adaptive Depth (변경 규모별 분기):
   a) 소규모 (파일 5개 이하, 모듈 1~2개):
      → 서브태스크 제안 없음, Phase 5에서 간단 코멘트
   b) 중규모 (파일 6~15개, 모듈 2~3개):
      → 선택적 제안: "서브태스크로 분할하시겠습니까?"
   c) 대규모 (파일 16개 이상 또는 모듈 4개 이상):
      → 적극적 분할 제안, 모듈별 서브태스크 초안 제시
4. 사용자 승인 후에만 서브태스크 생성:
   → `plane issue create --name "서브태스크 제목" --parent <원본이슈ID>`
```

### Phase 5: Completion & History Writing

```
1. 변경 요약 데이터 수집:
   - `git log --oneline <base-branch>..HEAD` → 커밋 이력
   - `git diff --stat <base-branch>..HEAD` → 변경 통계
   - `git diff --name-only <base-branch>..HEAD` → 변경 파일 목록
2. 자연어 변경 요약 생성:
   - 작업 유형 (Feature/Bug/Refactor)
   - 주요 변경 내용 (커밋 메시지 기반)
   - 영향 범위 (모듈별 변경 파일 수)
3. comment.html 템플릿 변수 바인딩:
   - {{work_type}} ← Phase 3에서 분류한 작업 유형
   - {{branch_name}} ← 현재 브랜치명
   - {{natural_language_summary}} ← 커밋 메시지 기반 자연어 요약
   - {{files_changed}}, {{insertions}}, {{deletions}} ← git diff --stat 파싱
   - {{changed_files}} ← git diff --name-only 결과
   - {{commits}} ← git log --oneline (hash, message 쌍)
4. 바인딩된 HTML을 코멘트로 작성:
   → `plane comment create --issue PROJ-42 --body "<바인딩된 HTML>"`
5. 사용자 확인 후 상태 변경:
   → `plane state list -f json` → group이 "completed"인 상태 ID 조회
   → `plane issue update PROJ-42 --state <done_state_id>`
```

### Phase 6: Post-Merge Close (post-merge 스킬에서 위임)

> 이 Phase는 독립 실행되지 않으며, `post-merge` 스킬의 Phase 2에서 위임 호출됩니다.

```
1. post-merge 스킬로부터 MR 컨텍스트 수신:
   → mr_url, mr_title, merge_date, target_branch, 변경 통계 등
2. `plane issue get {이슈 식별자} -f json` → 이슈 조회, 현재 상태 확인
3. merge-comment.html 템플릿 바인딩:
   → skills/post-merge/templates/merge-comment.html 로드
   → MR 컨텍스트 변수 바인딩
   → `plane comment create --issue {이슈 식별자} --body "<바인딩된 HTML>"`
4. 이슈 상태 변경:
   → `plane state list -f json` → group이 "completed"인 상태 ID 조회
   → `plane issue update {이슈 식별자} --state <completed_state_id>`
```

---

## 4. Smart Categorization (작업 유형 자동 분류)

3중 신호를 분석하여 작업 유형을 자동 분류합니다.

| 신호 | 우선순위 | 소스 | 분류 규칙 |
|------|----------|------|-----------|
| 브랜치 prefix | 1 (최고) | `git branch --show-current` | `feature/`→Feature, `fix/`→Bug, `refactor/`→Refactor |
| 커밋 메시지 | 2 | `git log --oneline` | 키워드 빈도 분석 |
| diff 패턴 | 3 (최저) | `git diff --stat` | 신규 파일 비율, 수정 패턴 |

**우선순위 규칙:**
- 브랜치 prefix가 명확하면 최우선 적용
- 브랜치 prefix가 모호하면 (예: `dev/`) 커밋 메시지 + diff 패턴으로 결정
- 모든 신호가 모호하면 사용자에게 직접 질문

---

## 5. Adaptive Depth (변경 규모별 워크플로우 깊이)

| 규모 | 파일 수 | 모듈 수 | 코멘트 | 서브태스크 제안 | 상태 변경 |
|------|---------|---------|--------|----------------|-----------|
| 소규모 | ≤5 | 1~2 | 간단 요약 (3줄 이내) | 안함 | 사용자 확인 |
| 중규모 | 6~15 | 2~3 | 상세 요약 (모듈별 변경) | 선택적 제안 | 사용자 확인 |
| 대규모 | ≥16 | ≥4 | 전체 이력 (템플릿 사용) | 적극적 제안 | 사용자 확인 |

---

## 6. Tool Coordination

### plane-cli 명령어

| 단계 | CLI 명령어 | 용도 |
|------|-----------|------|
| 환경 검증 | `plane config list` | 설정 상태 확인 |
| 인증 확인 | `plane user me -f json` | API 연결 및 인증 검증 |
| 프로젝트 목록 | `plane project list -f json` | 워크스페이스 내 프로젝트 조회 |
| 이슈 조회 | `plane issue get <ID\|PROJ-123> -f json` | 식별자로 이슈 조회 |
| 이슈 목록 | `plane issue list -f json [--state <id>] [--priority <p>]` | 필터링된 이슈 목록 |
| 이슈 생성 | `plane issue create --name "..." [--parent <id>]` | 새 이슈 또는 서브태스크 생성 |
| 이슈 수정 | `plane issue update <ID> --state <id>` | 상태 변경, 필드 업데이트 |
| 상태 조회 | `plane state list -f json` | 상태 목록 및 ID 조회 |
| 레이블 조회 | `plane label list -f json` | 레이블 목록 조회 |
| 멤버 조회 | `plane member list-project -f json` | 프로젝트 멤버 조회 |
| 코멘트 작성 | `plane comment create --issue <ID> --body "..."` | 변경 요약 코멘트 |
| 코멘트 조회 | `plane comment list --issue <ID> -f json` | 기존 코멘트 확인 |
| 활동 조회 | `plane activity list --issue <ID> -f json` | 이슈 변경 이력 확인 |

### Git 도구 (Bash)

| 명령어 | 용도 |
|--------|------|
| `git branch --show-current` | 브랜치명에서 이슈 식별자 파싱 |
| `git diff --stat` | 변경 통계 (파일 수, 라인 수) |
| `git diff --name-only` | 변경 파일 목록 (모듈 그룹핑) |
| `git log --oneline` | 커밋 이력 수집 |

### 파일 도구

| 도구 | 용도 |
|------|------|
| **Read** | 템플릿 파일 로드 (comment.html, issue.html) |

---

## 7. 브랜치명 파싱 규칙

### 지원 패턴

```
{prefix}/{IDENTIFIER}-{number}-{description}
{prefix}/{IDENTIFIER}-{number}
{IDENTIFIER}-{number}-{description}
{IDENTIFIER}-{number}
```

### 파싱 정규식

```
/([A-Z][A-Z0-9]+-\d+)/
```

### 예시

| 브랜치명 | 파싱 결과 |
|----------|-----------|
| `feature/PROJ-42-add-cart` | `PROJ-42` |
| `fix/PROJ-123-login-bug` | `PROJ-123` |
| `PROJ-7-quick-fix` | `PROJ-7` |
| `refactor/cleanup-utils` | 미발견 → 사용자에게 질문 |

---

## 8. Templates

이슈 생성 및 작업 이력 기록에 사용하는 HTML 템플릿입니다.

| # | 템플릿 | 용도 | CLI 명령어 |
|---|--------|------|-----------|
| 1 | [issue.html](templates/issue.html) | 이슈 생성 시 description | `plane issue create --description "..."` |
| 2 | [comment.html](templates/comment.html) | 작업 이력 코멘트 | `plane comment create --issue <ID> --body "..."` |

---

## 9. Examples

### 예시 1: 브랜치에서 이슈 자동 감지

```
사용자: "이슈 연결해줘"

[Phase 1] plane config list → workspace, project 설정 확인
[Phase 2] git branch → feature/SHOP-42-add-cart
          → SHOP-42 파싱 → plane issue get SHOP-42 -f json
          → "장바구니 기능 추가" 이슈 연결됨

에이전트: SHOP-42 "장바구니 기능 추가" 이슈에 연결했습니다.
         현재 상태: Backlog
         상태를 In Progress로 변경할까요?
```

### 예시 2: 이슈 목록에서 선택

```
사용자: "이슈 추적 시작"

[Phase 1] plane config list → 설정 확인
[Phase 2] git branch → dev/payment-refactor (이슈 번호 없음)
          → 사용자에게 이슈 지정 방식 질문

사용자: "이슈 목록 보여줘"

[Phase 2] plane issue list -f json --priority high → 우선순위 높은 이슈 표시
          1. SHOP-38 "결제 모듈 리팩토링"
          2. SHOP-41 "결제 오류 수정"
          3. SHOP-45 "결제 수단 추가"

사용자: "1번"
          → SHOP-38 연결
```

### 예시 3: 작업 완료 시 자동 제안

```
사용자: "다 했어, 커밋할게"

에이전트: Plane에 작업 이력을 기록할까요? (연결된 이슈: SHOP-42)

사용자: "응"

[Phase 5] git log + git diff → 변경 요약 생성
          → plane comment create --issue SHOP-42 --body "<HTML 코멘트>"
          → 상태를 Done으로 변경할까요?
```

### 예시 4: 대규모 변경 시 서브태스크 제안

```
[Phase 4] git diff --name-only → 22개 파일 변경
          모듈 분석:
          - API: 5개 파일
          - Service: 8개 파일
          - UI: 6개 파일
          - Test: 3개 파일

에이전트: 4개 모듈에 걸쳐 22개 파일이 변경되었습니다.
         서브태스크로 분할하시겠습니까?

사용자: "응"

→ plane issue create --name "API 엔드포인트 구현" --parent <SHOP-42-UUID>
→ plane issue create --name "비즈니스 로직 구현" --parent <SHOP-42-UUID>
→ plane issue create --name "UI 컴포넌트 구현" --parent <SHOP-42-UUID>
→ plane issue create --name "테스트 코드 작성" --parent <SHOP-42-UUID>
```

---

## 10. Boundaries

**Will:**
- 브랜치명에서 이슈 번호 자동 파싱
- `plane-cli`로 이슈 연결, 상태 변경, 코멘트 작성
- 변경 범위 분석 및 서브태스크 분할 제안
- 작업 완료 시 자동 이력 기록 제안
- post-merge 스킬과 연계하여 머지 후 이슈 종료

**Will Not:**
- 사용자 확인 없이 이슈 상태 변경
- 사용자 승인 없이 서브태스크 생성
- Plane 이슈/프로젝트 삭제
- 코드 자동 수정 또는 커밋
- Plane 워크스페이스 설정 변경
