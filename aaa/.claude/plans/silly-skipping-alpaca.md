# Plan: Issue Tracker 스킬에 Templates 디렉토리 추가

## Context

issue-tracker 스킬에 `templates/` 디렉토리를 만들어 **공용 이슈 템플릿 1개** + **공용 코멘트 템플릿 1개**를 추가합니다.
어떤 작업 유형(Feature/Bug/Refactor/Chore)이든 대응 가능한 범용 템플릿으로, SKILL.md에서 마크다운 링크로 참조합니다.

---

## 디렉토리 구조

```
skills/issue-tracker/
├── SKILL.md                          (수정 - 템플릿 참조 추가)
├── plane-context.template.json       (기존 유지)
└── templates/                        (신규)
    ├── issue.html                    # 공용 이슈 생성 템플릿
    └── comment.html                  # 공용 작업 이력 코멘트 템플릿
```

---

## 생성할 파일 (2개)

### 1. `templates/issue.html` - 공용 이슈 템플릿

`mcp__plane__create_work_item(description_html=...)` 용.
사용자가 제시한 구조를 기반으로, 어떤 이슈든 대응 가능한 범용 포맷:

```html
<h3>작업 개요 (Task Overview)</h3>
<p>{{task_overview}}</p>

<h3>상세 할 일 (To-Do List)</h3>
<ul>
{{#each todo_items}}
  <li>{{this}}</li>
{{/each}}
</ul>

<h3>일정 및 마감일 (Schedule & Due Date)</h3>
<p><strong>목표 완료일:</strong> {{due_date}}</p>

<h3>참고 사항 (Notes)</h3>
<p>{{notes}}</p>
```

### 2. `templates/comment.html` - 공용 코멘트 템플릿

`mcp__plane__create_work_item_comment(comment_html=...)` 용.
기존 SKILL.md L172-199의 인라인 템플릿을 추출 + 정리:

```html
<h3>작업 이력</h3>
<p><strong>작업 유형:</strong> {{work_type}}</p>
<p><strong>브랜치:</strong> <code>{{branch_name}}</code></p>

<h4>변경 요약</h4>
<p>{{natural_language_summary}}</p>

<h4>변경 통계</h4>
<ul>
  <li>변경 파일: {{files_changed}}개</li>
  <li>추가: +{{insertions}} / 삭제: -{{deletions}}</li>
</ul>

<h4>변경 파일</h4>
<ul>
{{#each changed_files}}
  <li><code>{{this}}</code></li>
{{/each}}
</ul>

<h4>커밋 이력</h4>
<ul>
{{#each commits}}
  <li><code>{{hash}}</code> {{message}}</li>
{{/each}}
</ul>
```

---

## SKILL.md 수정 (3곳)

### 1. 섹션 2와 3 사이에 "2.5 Templates" 섹션 추가 (L78)

```markdown
## 2.5. Templates

이슈 생성 및 작업 이력 기록에 사용하는 공용 HTML 템플릿입니다.

| # | 템플릿 | 용도 | Plane API |
|---|--------|------|-----------|
| 1 | [issue.html](templates/issue.html) | 이슈 생성 시 description | `create_work_item(description_html=...)` |
| 2 | [comment.html](templates/comment.html) | 작업 이력 코멘트 | `create_work_item_comment(comment_html=...)` |
```

### 2. Phase 5 인라인 템플릿을 파일 참조로 교체 (L171-199)

기존 인라인 HTML 코드 블록 → `[comment.html](templates/comment.html)` 링크 + 변수 바인딩 설명

### 3. Phase 2 새 이슈 생성 시 템플릿 참조 추가 (L106)

`c) "새 이슈 생성"` 옵션에 `[issue.html](templates/issue.html)` 템플릿 로드 흐름 추가

---

## 수정 대상 파일

- `skills/issue-tracker/SKILL.md` (수정)
- `skills/issue-tracker/templates/issue.html` (신규)
- `skills/issue-tracker/templates/comment.html` (신규)

## 구현 순서

1. `templates/` 디렉토리 생성
2. `templates/issue.html` 생성
3. `templates/comment.html` 생성 (SKILL.md에서 추출)
4. SKILL.md 수정 (섹션 2.5 추가, Phase 5 교체, Phase 2 업데이트)

## 검증

- 마크다운 링크가 실제 파일을 가리키는지 확인
- `comment.html`이 기존 인라인 템플릿 내용을 완전히 보존하는지 확인
