---
name: handoff
description: "세션 컨텍스트를 HANDOFF.md로 저장하여 다음 세션에서 이어받기"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /handoff - Session Context Transfer

## Triggers
- 대화가 길어져 컨텍스트 윈도우 한계에 근접할 때
- 세션을 종료하고 나중에 이어서 작업해야 할 때
- 작업 진행 상황을 다른 세션/에이전트에 인계할 때

## Usage
```
/handoff
```

## Behavioral Flow

### Phase 1: 변경 상태 수집
Git 상태를 수집하여 현재 작업 환경을 파악한다.

**실행 명령:**
```bash
git branch --show-current     # 현재 브랜치
git status --short            # 미커밋 변경 파일 목록
git diff --stat               # 변경 통계
git log --oneline -10         # 최근 커밋 이력
```

모든 git 명령은 **병렬로** 실행한다.

### Phase 2: 대화 컨텍스트 분석
현재 세션의 대화 내용을 분석하여 핵심 정보를 추출한다.

1. **세션 목표 식별**: 사용자의 최초 요청에서 핵심 목표를 1줄로 요약
2. **시도한 접근법 분류**: 각 접근/작업을 성공/실패로 분류
   - 성공: 완료된 작업, 생성/수정된 파일과 간단한 설명
   - 실패: 실패한 접근과 그 이유
3. **미해결 이슈 식별**: 아직 완료되지 않은 작업이나 발견된 문제점

### Phase 3: HANDOFF.md 생성
프로젝트 루트에 `HANDOFF.md` 파일을 **Write 도구**로 작성한다.
다음 에이전트가 이 파일 하나만 읽고 작업을 이어갈 수 있도록 자족적(self-contained) 구조로 작성한다.

**출력 템플릿:**
```markdown
# HANDOFF - Session Context Transfer

> 이 파일은 이전 세션의 작업 컨텍스트입니다.
> 새 세션에서 이 파일을 읽고 작업을 이어가세요.

## Session Info
- Date: {YYYY-MM-DD}
- Branch: {현재 브랜치}
- Goal: {세션의 핵심 목표 1줄 요약}

## What Was Tried
- {시도한 접근/작업 목록 - 각 항목에 결과 표시}

## What Succeeded
- {성공 항목}
- {수정/생성된 파일 목록 with 간단 설명}

## What Failed
- {실패한 접근: 이유}

## Current State
- Branch: {브랜치명}
- Uncommitted: {미커밋 파일 목록}
- Build/Test: {빌드/테스트 상태 if applicable}

## Next Steps
1. {다음 우선 작업}
2. {후속 작업}

## Key Files
- `path/to/file` - {역할 설명}
```

### Phase 4: 다음 단계 안내
HANDOFF.md 생성 후 사용자에게 다음 워크플로우를 안내한다:

```
HANDOFF.md가 생성되었습니다.

다음 세션에서 작업을 이어가려면:
1. /clear 로 현재 세션을 정리하세요
2. 새 세션에서 다음과 같이 입력하세요:
   @HANDOFF.md 이 파일을 읽고 작업을 이어가줘
```

## Tool Coordination
- **Bash**: `git status`, `git diff`, `git log`, `git branch` (병렬 실행)
- **Read**: 관련 파일 확인 (필요시)
- **Write**: `HANDOFF.md` 파일 생성

## Examples

### 기본 사용
```
/handoff
# 현재 세션의 작업 컨텍스트를 HANDOFF.md로 저장
# git 상태 + 대화 요약 + 다음 단계를 포함
```

## Boundaries

**Will:**
- Git 상태 수집 (branch, status, diff, log)
- 세션 대화 컨텍스트 분석 및 요약
- 프로젝트 루트에 자족적 HANDOFF.md 생성
- 다음 세션 워크플로우 안내

**Will Not:**
- 코드를 수정하거나 커밋하지 않음
- Git push 등 원격 작업 수행하지 않음
- 기존 HANDOFF.md가 있을 경우 백업 없이 덮어쓰지 않음 (경고 후 진행)
