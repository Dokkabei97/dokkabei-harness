---
name: post-merge
description: |
  MR 머지 완료 후 Plane 이슈 종료와 Outline 문서 업데이트를 자동으로 처리하는 오케스트레이터 스킬입니다.
  issue-tracker와 document-latest 스킬을 연계 실행하여 머지 후 후속 작업을 일괄 처리합니다.
metadata:
  version: 1.0.0
  category: workflow
  domain: post-merge-automation
  requires_mcp: [plane, outline]
  delegates_to: [issue-tracker, document-latest]
triggers:
  - "머지 완료"
  - "머지됐어"
  - "머지해줘"
  - "post merge"
  - "머지 후 처리"
auto_suggest:
  keywords:
    - "머지"
    - "merge"
    - "glab mr merge"
  action: "머지 후 Plane/Outline 처리를 진행할까요?"
  phase: 1
---

# Post-Merge - 머지 후 자동화 오케스트레이터

## Overview

MR(Merge Request) 머지 완료 후 후속 작업을 자동화합니다.
Plane 이슈 종료(코멘트 + 상태 변경)와 Outline 문서 업데이트를 하나의 흐름으로 연계 실행합니다.
기존 `issue-tracker`와 `document-latest` 스킬에 위임하여 각 스킬의 독립성을 유지합니다.

---

## 1. 활성화 규칙

| 트리거 유형 | 조건 | 동작 |
|-------------|------|------|
| **수동** | "머지 완료", "머지됐어", "post merge" 등 명시적 호출 | Phase 1~6 전체 실행 |
| **머지 요청** | "머지해줘" | Phase 1(경로 C)에서 `glab mr merge` 실행 후 Phase 2~6 진행 |
| **Hook 연동** | `glab mr merge` 성공 감지 (PostToolUse Hook) | "머지 후 Plane/Outline 처리를 진행할까요?" 제안 → 승인 시 Phase 1~6 실행 |
| **자동 제안** | "머지", "merge" 키워드 감지 | "머지 후 Plane/Outline 처리를 진행할까요?" 질문 → 승인 시 실행 |

---

## 2. Behavioral Flow

### Phase 1: 머지 감지 & MR 컨텍스트 수집

```
1. MR 정보 확보 (경로 분기):
   경로 A: Hook에서 호출됨 → MR ID가 이미 전달됨
   경로 B: "머지됐어" / "머지 완료"
     → git branch --show-current → 현재 브랜치명 확인
     → glab mr list --source-branch={branch} --state merged -F json
     → 최근 머지된 MR 선택
   경로 C: "머지해줘"
     → glab mr list --source-branch={branch} --state opened -F json
     → 열린 MR 확인 → glab mr merge {id} 실행
     → 머지 완료 후 계속

2. MR 상세 정보 수집:
   → glab mr view {id} -F json
   → 추출: MR 제목, 설명, 소스 브랜치, 타겟 브랜치, 변경 파일 수, 라벨

3. Plane 이슈 ID 파싱:
   → 소스 브랜치명에서 정규식 /([A-Z][A-Z0-9]+-\d+)/ 로 이슈 식별자 추출
   → 예: feature/PROJ-42-add-cart → PROJ-42
   → 미발견 시 사용자에게 이슈 번호 질문 (선택적)
```

### Phase 2: Plane 이슈 종료 (issue-tracker Phase 6 위임)

```
1. .plane-context.json 로드 → project_identifier, project_id 확인
   → 파일 미존재 시 사용자에게 안내 후 Phase 3으로 건너뜀

2. mcp__plane__retrieve_work_item_by_identifier({이슈 식별자})
   → 이슈 조회 → 이슈 제목, 현재 상태 확인

3. 머지 코멘트 작성:
   → merge-comment.html 템플릿 로드 (skills/post-merge/templates/merge-comment.html)
   → 변수 바인딩:
     - {{mr_url}} ← MR URL
     - {{mr_title}} ← MR 제목
     - {{merge_date}} ← 오늘 날짜 (YYYY-MM-DD)
     - {{branch_name}} ← 소스 브랜치
     - {{target_branch}} ← 타겟 브랜치
     - {{natural_language_summary}} ← MR 설명 기반 자연어 요약
     - {{files_changed}}, {{insertions}}, {{deletions}} ← MR 변경 통계
     - {{changed_files}} ← 변경 파일 목록
     - {{commits}} ← 커밋 이력
     - {{doc_url}}, {{doc_title}} ← Phase 4 완료 후 역바인딩 (있을 경우)
   → mcp__plane__create_work_item_comment(comment_html=바인딩된 HTML)

4. 이슈 상태 변경:
   → mcp__plane__list_states(project_id)
   → group이 "completed"인 상태 ID 조회
   → mcp__plane__update_work_item(
       state=completed_state_id,
       completed_at=오늘날짜
     )
   → 완료 알림: "PROJ-42 이슈가 종료되었습니다"
```

### Phase 3: 문서화 필요성 판단

```
1. MR 변경 규모 분석:
   → 변경 파일 수, 모듈 수 확인

2. 규모별 분기:
   a) 소규모 (≤5 파일):
      → "문서화를 건너뜁니다 (소규모 변경)" 알림
      → Phase 5로 이동
   b) 중규모 이상 (>5 파일):
      → "Outline 문서를 업데이트할까요?" 질문
      → 사용자 승인 시 Phase 4 진행
      → 사용자 거부 시 Phase 5로 이동

3. 사용자가 명시적으로 문서화를 요청한 경우:
   → 파일 수와 무관하게 Phase 4 진행
```

### Phase 4: Outline 문서 업데이트 (document-latest Phase 2~6 위임)

```
1. MR 컨텍스트를 추가 정보로 document-latest 스킬에 전달:
   → MR 제목 → 문서 요약의 시드 데이터
   → MR 설명 → 변경 내용 상세
   → MR 라벨 → 카테고리 힌트 (api, infrastructure 등)
   → 타겟 브랜치 → 문서화 우선순위 (main/master → 높음)

2. document-latest 스킬의 Phase 2~6 실행:
   → Phase 2: Change Analysis (MR 컨텍스트 활용)
   → Phase 3: Document Type Detection
   → Phase 4: Document Discovery
   → Phase 5: Content Generation & Security Filtering
   → Phase 6: Write to Outline

3. 문서 URL 수집 → Phase 2의 merge-comment에 역바인딩
   → doc_url, doc_title이 있으면 Plane 코멘트 업데이트 (선택적)
```

### Phase 5: 완료 요약 출력

```
처리 결과를 한눈에 표시:

┌─────────────────────────────────────────┐
│ Post-Merge 처리 완료                      │
├─────────────────────────────────────────┤
│ MR: !42 기능 추가 (머지됨)                │
│     https://labs.cowave.kr/.../merge_requests/42 │
│ 이슈: PROJ-42 → Completed ✓              │
│ 문서: [API] 결제 엔드포인트 (업데이트됨)     │
│     https://wiki.example.com/doc/...     │
└─────────────────────────────────────────┘
```

### Phase 6: 정리 (선택)

```
1. "로컬 브랜치를 삭제할까요?" 질문
   → 승인 시:
     → git checkout {target_branch} (main, master, develop 등)
     → git pull
     → git branch -d {source_branch}
     → "브랜치 {source_branch}가 삭제되었습니다"
   → 거부 시:
     → 건너뜀
```

---

## 3. Templates

머지 완료 시 Plane 이슈에 작성하는 코멘트 HTML 템플릿입니다.

| # | 템플릿 | 용도 | Plane API |
|---|--------|------|-----------|
| 1 | [merge-comment.html](templates/merge-comment.html) | 머지 완료 코멘트 | `create_work_item_comment(comment_html=...)` |

---

## 4. Tool Coordination

### Plane MCP 도구

| 단계 | MCP 도구 | 용도 |
|------|----------|------|
| 이슈 조회 | `mcp__plane__retrieve_work_item_by_identifier` | 식별자로 이슈 조회 |
| 상태 조회 | `mcp__plane__list_states` | completed 상태 ID 확인 |
| 코멘트 작성 | `mcp__plane__create_work_item_comment` | merge-comment.html 기반 코멘트 |
| 상태 변경 | `mcp__plane__update_work_item` | state → completed, completed_at 설정 |

### Outline MCP 도구

| 단계 | MCP 도구 | 용도 |
|------|----------|------|
| 문서 검색 | `mcp__outline__search_documents` | 기존 문서 탐색 |
| 문서 생성 | `mcp__outline__create_document` | 신규 문서 생성 |
| 문서 업데이트 | `mcp__outline__update_document` | 기존 문서 수정 |

### Git / GitLab CLI 도구 (Bash)

| 명령어 | 용도 |
|--------|------|
| `git branch --show-current` | 현재 브랜치명 확인 |
| `glab mr list --source-branch={branch}` | 브랜치의 MR 조회 |
| `glab mr view {id} -F json` | MR 상세 정보 수집 |
| `glab mr merge {id}` | MR 머지 실행 (경로 C) |
| `git diff --stat` | 변경 통계 수집 |
| `git log --oneline` | 커밋 이력 수집 |
| `git branch -d {branch}` | 로컬 브랜치 삭제 (Phase 6) |

### 파일 도구

| 도구 | 용도 |
|------|------|
| **Glob** | `.plane-context.json`, `.outline-context.json` 파일 탐색 |
| **Read** | 설정 파일 및 merge-comment.html 템플릿 로드 |

---

## 5. 위임 규칙

이 스킬은 오케스트레이터로서 기존 스킬에 작업을 위임합니다.

| 위임 대상 | 위임 범위 | 조건 |
|-----------|-----------|------|
| `issue-tracker` Phase 6 | Plane 이슈 종료 (코멘트 + 상태 변경) | Plane 이슈 ID 파싱 성공 시 |
| `document-latest` Phase 2~6 | Outline 문서 업데이트 | 사용자 승인 시 |

### 위임 시 전달 컨텍스트

```
{
  "mr_id": "MR 번호",
  "mr_title": "MR 제목",
  "mr_description": "MR 설명",
  "mr_url": "MR URL",
  "source_branch": "소스 브랜치",
  "target_branch": "타겟 브랜치",
  "labels": ["라벨 목록"],
  "plane_issue_id": "PROJ-42",
  "files_changed": 15,
  "insertions": 320,
  "deletions": 45
}
```

---

## 6. Examples

### 예시 1: "머지됐어" → 자동 감지 후 전체 처리

```
사용자: "머지됐어"

[Phase 1] git branch → feature/SHOP-42-add-cart
          → glab mr list --source-branch=feature/SHOP-42-add-cart --state merged
          → MR !42 발견 → glab mr view 42 -F json
          → SHOP-42 파싱

[Phase 2] retrieve_work_item_by_identifier("SHOP-42")
          → "장바구니 기능 추가" 이슈 조회
          → merge-comment.html 바인딩 → create_work_item_comment
          → list_states → completed ID 조회
          → update_work_item(state=completed_id)

에이전트: SHOP-42 이슈를 종료했습니다.
          변경 파일이 12개입니다. Outline 문서를 업데이트할까요?

사용자: "응"

[Phase 4] document-latest Phase 2~6 실행
          → [API] 장바구니 엔드포인트 문서 업데이트

[Phase 5] 완료 요약 출력
[Phase 6] "로컬 브랜치를 삭제할까요?"
```

### 예시 2: "머지해줘" → 머지 실행 후 후속 처리

```
사용자: "머지해줘"

[Phase 1] git branch → fix/SHOP-99-login-bug
          → glab mr list --source-branch=fix/SHOP-99-login-bug --state opened
          → MR !99 발견 → glab mr merge 99
          → 머지 성공 → glab mr view 99 -F json
          → SHOP-99 파싱

[Phase 2] Plane 이슈 종료
[Phase 3] 변경 파일 3개 → 소규모 → 문서화 건너뜀
[Phase 5] 완료 요약 출력
[Phase 6] "로컬 브랜치를 삭제할까요?"
```

### 예시 3: Hook 연동 (glab mr merge 성공 후)

```
사용자: glab mr merge 42 (Bash 도구로 실행)

[Hook] 머지 성공 감지 → "[Hook] MR !42 머지 완료. 머지 후 Plane/Outline 처리를 진행할까요?"

사용자: "응"

[Phase 1~6] post-merge 스킬 전체 실행
```

---

## 7. Boundaries

**Will:**
- MR 정보 자동 수집 (브랜치명, glab CLI)
- 브랜치명에서 Plane 이슈 ID 자동 파싱
- Plane 이슈 종료 (코멘트 + 상태 변경)
- Outline 문서 업데이트 제안 및 실행
- 완료 요약 출력
- 로컬 브랜치 정리 제안

**Will Not:**
- 사용자 확인 없이 이슈 상태 변경
- 사용자 승인 없이 문서 생성/수정
- 사용자 확인 없이 브랜치 삭제
- 원격 브랜치 삭제 (git push origin --delete)
- MR 생성 (이 스킬은 머지 **후** 처리만 담당)
- Plane 워크스페이스/프로젝트 설정 변경
