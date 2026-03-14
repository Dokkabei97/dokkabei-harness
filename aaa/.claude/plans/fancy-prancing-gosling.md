# Post-Merge 자동화 스킬 구현 계획

## Context

개발자가 Claude Code에서 작업 → MR → 머지까지 진행한 후, Plane 이슈 종료 + Outline 문서 업데이트를 **Claude Code 세션 내에서 자동으로** 처리하고 싶다. 현재 `/issue-tracker`(Phase 1~5)와 `/document-lastest`(Phase 1~6)가 각각 독립적으로 존재하지만, "머지 완료 후" 두 스킬을 연계 실행하는 오케스트레이터가 없다.

---

## 구현 내용

### 1. 신규: `skills/post-merge/SKILL.md` (오케스트레이터 스킬)

**트리거:**
- 수동: "머지 완료", "머지됐어", "머지해줘", "post merge"
- 자동: Hook이 `glab mr merge` 성공 감지 시 "머지 후 처리를 진행할까요?" 제안
- auto_suggest: "머지", "merge" 키워드 감지

**Phase 흐름:**

```
Phase 1: 머지 감지 & MR 컨텍스트 수집
  ├─ 경로 A: glab mr merge 후 Hook → MR ID 이미 알고 있음
  ├─ 경로 B: "머지됐어" → glab mr list --source-branch={branch} --state merged
  └─ 경로 C: "머지해줘" → glab mr merge 실행 → 완료 후 계속
  → glab mr view {id} -F json → MR 제목, 설명, 브랜치, 변경파일 추출
  → 브랜치에서 Plane ID 파싱: /([A-Z][A-Z0-9]+-\d+)/

Phase 2: Plane 이슈 종료 (issue-tracker Phase 6 위임)
  ├─ .plane-context.json 로드 → project_id 확인
  ├─ retrieve_work_item_by_identifier → 이슈 조회
  ├─ merge-comment.html 템플릿 바인딩 → create_work_item_comment
  ├─ list_states → completed 그룹 상태 ID 조회
  └─ update_work_item(state=completed_id, completed_at=오늘날짜)

Phase 3: 문서화 필요성 판단
  ├─ 변경 파일 수/모듈 수 분석
  ├─ 소규모(≤5파일) → 문서화 생략
  ├─ 중규모 이상 → "Outline 문서를 업데이트할까요?" 질문
  └─ 사용자 승인 시 Phase 4 진행

Phase 4: Outline 문서 업데이트 (document-lastest Phase 2~6 위임)
  └─ MR 컨텍스트(제목, 설명, 라벨)를 추가 정보로 전달

Phase 5: 완료 요약 출력
  └─ MR URL, 이슈 ID/상태, 문서 URL 표시

Phase 6: 정리 (선택)
  └─ "로컬 브랜치 삭제할까요?" → git branch -d + git checkout main
```

### 2. 신규: `skills/post-merge/templates/merge-comment.html`

기존 `comment.html`을 확장한 머지 전용 템플릿. MR URL, 머지 날짜, 대상 브랜치, 관련 문서 링크 포함.

변수: `{{mr_url}}`, `{{mr_title}}`, `{{merge_date}}`, `{{branch_name}}`, `{{target_branch}}`, `{{natural_language_summary}}`, `{{files_changed}}`, `{{insertions}}`, `{{deletions}}`, `{{changed_files}}`, `{{commits}}`, `{{doc_url}}`, `{{doc_title}}`

### 3. 수정: `claude/hooks/hooks.json`

PostToolUse 배열에 추가:
```
matcher: tool == "Bash" && tool_input.command matches "glab mr merge"
동작: 머지 성공 감지 시 stderr로 "머지 후 Plane/Outline 처리를 진행할까요?" 안내
```

### 4. 수정: `skills/issue-tracker/SKILL.md`

Phase 5 다음에 **Phase 6: Post-Merge Close** 추가:
- post-merge 스킬에 의해 호출됨 (독립 실행 아님)
- merge-comment.html 기반 코멘트 작성
- state → completed, completed_at 설정
- Tool Coordination 테이블에 항목 추가

### 5. 수정: `skills/document-lastest/SKILL.md`

Phase 2 (Change Analysis)에 MR 컨텍스트 활용 항목 추가:
- MR 제목/설명 → 문서 요약의 시드 데이터
- MR 라벨 → 카테고리 힌트
- 대상 브랜치 → 문서화 우선순위

### 6. 수정: `README.md`

Skills 테이블에 `post-merge` 추가, Hooks 테이블에 "머지 후 액션 제안" 추가

### 7. 수정: `setup.sh`

설치 완료 메시지에 `/post-merge` 항목 추가

---

## 파일 목록

| 작업 | 파일 | 유형 |
|---|---|---|
| 생성 | `skills/post-merge/SKILL.md` | 신규 |
| 생성 | `skills/post-merge/templates/merge-comment.html` | 신규 |
| 수정 | `claude/hooks/hooks.json` | PostToolUse 항목 추가 |
| 수정 | `skills/issue-tracker/SKILL.md` | Phase 6 추가 |
| 수정 | `skills/document-lastest/SKILL.md` | Phase 2 MR 컨텍스트 추가 |
| 수정 | `README.md` | 테이블 항목 추가 |
| 수정 | `setup.sh` | 출력 메시지 추가 |

---

## 검증 방법

1. `setup.sh` 실행 → hooks 정상 머지 확인
2. Claude Code 재시작 → `/post-merge` 스킬 인식 확인
3. 테스트 시나리오:
   - "머지됐어" 입력 → MR 자동 탐색 → Plane close → Outline 제안
   - `glab mr merge` 실행 → Hook 안내 메시지 출력 확인
   - "머지해줘" 입력 → MR merge 실행 → 후속 처리 확인
4. Plane MCP: `mcp__plane__retrieve_work_item_by_identifier` → 상태/코멘트 확인
5. Outline MCP: `mcp__outline__search_documents` → 문서 생성/업데이트 확인
