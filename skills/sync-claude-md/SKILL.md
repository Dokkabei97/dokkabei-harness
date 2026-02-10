---
name: sync-claude-md
description: |
  커밋/PR 전 코드 변경사항을 분석하여 CLAUDE.md 업데이트 필요 여부를 판단합니다.
  아키텍처 변경, 새로운 통합, 컨벤션 변경, 환경/도구 변경 등을 감지하고,
  필요한 경우 CLAUDE.md 업데이트를 제안하고 실행합니다.
metadata:
  version: 1.0.0
  category: workflow
  domain: project-context
triggers:
  - "CLAUDE.md 동기화"
  - "CLAUDE.md 업데이트 확인"
  - "sync claude md"
  - "클로드 설정 업데이트"
auto_suggest:
  keywords:
    - "커밋할게"
    - "커밋"
    - "commit"
    - "push"
    - "PR 생성"
    - "MR 생성"
  action: "CLAUDE.md 업데이트 필요 여부를 확인할까요?"
  phase: 3
---

# Sync CLAUDE.md - 코드 변경 기반 CLAUDE.md 자동 동기화

## Overview

커밋/푸시 또는 PR/MR 전에 작업 내용이 CLAUDE.md에 반영되어야 하는지 자동으로 분석하고, 필요 시 업데이트를 수행합니다.
`monorepo-init` 스킬이 CLAUDE.md를 **생성**하는 역할이라면, 이 스킬은 작업 완료 후 CLAUDE.md를 **유지보수**하는 역할입니다.

---

## 1. 활성화 규칙

| 트리거 유형 | 조건 | 동작 |
|-------------|------|------|
| **수동** | "CLAUDE.md 동기화", "sync claude md" 등 명시적 호출 | Phase 1~5 전체 실행 |
| **자동 제안** | "커밋할게", "commit", "push", "PR 생성" 등 완료 신호 감지 | "CLAUDE.md 업데이트 필요 여부를 확인할까요?" 질문 → 승인 시 실행 |

---

## 2. Behavioral Flow

### Phase 1: CLAUDE.md 탐색 및 로드

```
1. 프로젝트 루트에서 CLAUDE.md 위치 탐색 (Glob: **/CLAUDE.md)
   - 우선순위: CLAUDE.md > claude/CLAUDE.md > .claude/CLAUDE.md
2. CLAUDE.md가 없으면:
   → "CLAUDE.md가 존재하지 않습니다. monorepo-init 또는 프로젝트 초기화를 먼저 진행해주세요." 출력 후 중단
3. 현재 CLAUDE.md 내용을 읽고 기존 섹션 목록 파악
4. CLAUDE.md에 이미 staged 변경이 있는지 확인:
   → git diff --cached -- "**/CLAUDE.md"
   → 이미 변경이 staged 되어 있으면 사용자에게 알림
```

### Phase 2: 변경 범위 수집

모드 자동 감지:

| 조건 | 분석 대상 | 설명 |
|------|-----------|------|
| staged 변경 존재 | `git diff --cached` | pre-commit 시나리오 |
| 사용자가 "PR", "MR" 언급 | `git diff main...HEAD` | pre-PR 시나리오 |
| fallback | `git diff HEAD` | 모든 미커밋 변경 |

수집 항목:
```
1. git diff --name-only → 변경 파일 목록
2. git diff --stat → 변경 통계 (파일 수, 추가/삭제 라인)
3. git diff → 실제 diff 내용 (변경 분류용)
```

### Phase 3: 변경 분류 (업데이트 필요 여부 판단)

수집된 diff를 분석하여 CLAUDE.md 업데이트 필요 여부를 판단합니다.

**업데이트 필요 (Yes):**

| 변경 카테고리 | 감지 신호 |
|---|---|
| 아키텍처 변경 | 새 디렉토리 구조 생성, 모듈 경계 변경, 레이어 추가 |
| 신규 통합/MCP | `mcp/` 파일 변경, 새 외부 서비스 클라이언트, API 연동 추가 |
| 컨벤션/패턴 변경 | 린터 설정 변경, 새 코딩 표준 파일, 새 공통 유틸/베이스 클래스 |
| 환경/도구 변경 | Dockerfile, docker-compose, CI/CD 설정, Makefile 변경 |
| 주요 의존성 추가 | 새 프레임워크/라이브러리 추가 (패치 업데이트 제외) |
| 워크플로우 변경 | 새 git hooks, 새 스크립트, 새 CI 스테이지 |
| 스킬/커맨드 추가 | `skills/`, `commands/`, `claude/commands/` 내 새 파일 |

**업데이트 불필요 (No):**

| 변경 카테고리 | 설명 |
|---|---|
| 단순 버그 수정 | 기존 파일 소규모 수정, 새 패턴 없음 |
| 기존 패턴 내 기능 추가 | 기존 구조를 따르는 새 기능 파일 |
| 테스트 추가 | 기존 테스트 컨벤션을 따르는 테스트 파일 |
| 문서 수정 | README, docs, 주석 변경 |
| 리팩토링 | 기존 패턴 내 이름 변경, 이동 |

**감지 패턴 상세:**

```
# 아키텍처 변경 감지
- 새 디렉토리가 생성되었는가? (diff에 새 경로 패턴)
- src/, lib/, packages/ 등 핵심 디렉토리에 새 하위 모듈이 추가되었는가?

# 신규 통합/MCP 감지
- mcp/*.json 파일이 추가/수정되었는가?
- 새 API 클라이언트 파일이 추가되었는가?

# 컨벤션 변경 감지
- .eslintrc, .prettierrc, tsconfig.json, pyproject.toml 등 설정 파일 변경
- 새 base class, mixin, decorator 등 공통 패턴 파일 추가

# 환경/도구 변경 감지
- Dockerfile, docker-compose.yml 추가/수정
- .github/workflows/, .gitlab-ci.yml, Jenkinsfile 변경
- Makefile, justfile, taskfile.yml 변경

# 주요 의존성 감지
- package.json, requirements.txt, go.mod, build.gradle 등의 새 의존성 추가
  (버전 범프만 있는 경우는 제외)

# 스킬/커맨드 감지
- skills/*/SKILL.md 새 파일
- claude/commands/*.md 새 파일
- .claude/ 디렉토리 내 설정 변경
```

### Phase 4: 결정 및 제안

**업데이트 불필요 시:**

```
✅ CLAUDE.md 업데이트가 필요하지 않습니다.

분석 결과:
- 변경 유형: {버그 수정 / 기존 패턴 내 기능 추가 / 테스트 추가 / ...}
- 변경 파일: {N}개
- 영향 범위: 기존 아키텍처/규칙 내
```
→ 여기서 중단

**업데이트 필요 시:**

```
1. 어떤 섹션을 추가/수정해야 하는지 식별
   - 기존 CLAUDE.md 섹션 구조와 매칭
   - 새 섹션이 필요한지, 기존 섹션 업데이트로 충분한지 판단

2. 드래프트 업데이트 내용 제안:
   - 변경된 파일과 연결하여 근거 제시
   - 추가/수정할 구체적인 내용 미리보기

3. 사용자에게 "CLAUDE.md 업데이트를 진행합니다" 공유
   → 사용자 응답 대기 없이 Phase 5 진행
```

### Phase 5: CLAUDE.md 업데이트 실행

```
1. 현재 CLAUDE.md 내용 읽기 (Read)
2. 변경사항 적용:
   - 기존 섹션 업데이트: 해당 섹션 내용 수정 (Edit)
   - 새 섹션 추가: 적절한 위치에 삽입 (Edit)
   - 불필요해진 내용 제거: 더 이상 유효하지 않은 정보 삭제
3. CLAUDE.md 파일 쓰기 (Write/Edit)
4. agents-md-copy 스킬 연계 안내:
   → "AGENTS.md도 함께 업데이트하려면 agents-md-copy 스킬을 실행하세요."
5. 변경 diff 요약 표시:
   → 추가된 내용, 수정된 내용, 삭제된 내용 요약
6. git add 제안:
   → "git add {CLAUDE.md 경로}로 변경사항을 스테이징하세요."
```

---

## 3. 업데이트 섹션 매핑

변경 카테고리별로 CLAUDE.md의 어떤 섹션을 업데이트해야 하는지 가이드합니다.

| 변경 카테고리 | 대상 CLAUDE.md 섹션 | 업데이트 내용 |
|---|---|---|
| 아키텍처 변경 | Architecture / Structure | 새 모듈, 디렉토리 구조 반영 |
| 신규 통합/MCP | Integrations / MCP | 새 MCP 서버, 외부 연동 추가 |
| 컨벤션/패턴 변경 | Conventions / Coding Standards | 새 규칙, 패턴 문서화 |
| 환경/도구 변경 | Development Setup / Commands | 새 도구, 명령어 추가 |
| 주요 의존성 추가 | Tech Stack / Dependencies | 새 라이브러리 기록 |
| 워크플로우 변경 | Workflow / CI/CD | 새 워크플로우 단계 문서화 |
| 스킬/커맨드 추가 | Skills / Commands | 새 스킬, 커맨드 목록 업데이트 |

---

## 4. Tool Coordination

| 도구 | 용도 |
|------|------|
| **Glob** | `**/CLAUDE.md` 파일 위치 탐색 |
| **Read** | CLAUDE.md 현재 내용 읽기, 설정 파일 분석 |
| **Bash** | `git diff`, `git diff --cached`, `git diff main...HEAD` 등 변경 범위 수집 |
| **Grep** | diff 내용에서 패턴 감지 (새 import, 설정 파일, MCP 설정 등) |
| **Edit** | CLAUDE.md 기존 섹션 수정 |
| **Write** | CLAUDE.md에 새 섹션 추가 (필요시) |

---

## 5. Examples

### 예시 1: MCP 서버 추가 후 동기화

```
사용자: "CLAUDE.md 동기화해줘"

[Phase 1] CLAUDE.md 탐색 → ./CLAUDE.md 발견, 내용 로드
[Phase 2] git diff --cached → mcp/grafana.json 추가됨
[Phase 3] 분류: 신규 통합/MCP → 업데이트 필요
[Phase 4] 제안:
  - "Integrations" 또는 "MCP" 섹션에 Grafana MCP 서버 추가
  - 근거: mcp/grafana.json 신규 파일

에이전트: CLAUDE.md에 Grafana MCP 연동 정보를 추가합니다.
[Phase 5] CLAUDE.md 업데이트 실행 → diff 요약 표시
```

### 예시 2: 새 스킬 추가 후 동기화

```
사용자: "커밋할게"
에이전트: CLAUDE.md 업데이트 필요 여부를 확인할까요?
사용자: "응"

[Phase 1] CLAUDE.md 탐색 → ./CLAUDE.md 발견
[Phase 2] git diff --cached → skills/sync-claude-md/SKILL.md 추가됨
[Phase 3] 분류: 스킬/커맨드 추가 → 업데이트 필요
[Phase 4] 제안:
  - "Skills" 섹션에 sync-claude-md 스킬 추가
  - 근거: skills/sync-claude-md/SKILL.md 신규 파일

에이전트: CLAUDE.md에 sync-claude-md 스킬 정보를 추가합니다.
[Phase 5] CLAUDE.md 업데이트 실행 → diff 요약 표시
         → agents-md-copy 스킬로 AGENTS.md도 동기화하세요.
```

### 예시 3: 단순 버그 수정 (업데이트 불필요)

```
사용자: "CLAUDE.md 동기화"

[Phase 1] CLAUDE.md 탐색 → ./CLAUDE.md 발견
[Phase 2] git diff HEAD → src/utils/format.ts 1개 파일, 3줄 수정
[Phase 3] 분류: 단순 버그 수정 → 업데이트 불필요

에이전트:
✅ CLAUDE.md 업데이트가 필요하지 않습니다.

분석 결과:
- 변경 유형: 버그 수정
- 변경 파일: 1개
- 영향 범위: 기존 아키텍처/규칙 내
```

### 예시 4: PR 전 전체 변경 분석

```
사용자: "PR 생성 전에 CLAUDE.md 확인해줘"

[Phase 1] CLAUDE.md 탐색 → ./CLAUDE.md 발견
[Phase 2] "PR" 언급 감지 → git diff main...HEAD 분석
          → 12개 파일 변경, docker-compose.yml 추가, .github/workflows/ci.yml 수정
[Phase 3] 분류:
  - 환경/도구 변경 (docker-compose.yml) → 업데이트 필요
  - 워크플로우 변경 (CI 설정) → 업데이트 필요
[Phase 4] 제안:
  - "Development Setup" 섹션에 Docker 환경 추가
  - "CI/CD" 섹션에 새 CI 파이프라인 단계 추가
  - 근거: docker-compose.yml 신규, ci.yml 수정

에이전트: CLAUDE.md에 Docker 환경 및 CI 파이프라인 변경사항을 반영합니다.
[Phase 5] CLAUDE.md 업데이트 실행
```

---

## 6. Boundaries

**Will:**
- 변경사항 자동 분석 및 CLAUDE.md 업데이트 필요 여부 판단
- 업데이트 필요 시 구체적 변경 내용 제안
- 사용자 확인 후 CLAUDE.md 업데이트 실행
- agents-md-copy 스킬 연계 안내

**Will Not:**
- 사용자 확인 없이 CLAUDE.md 수정
- `~/.claude/CLAUDE.md` (글로벌 설정) 수정 — 프로젝트 레벨만 대상
- CLAUDE.md가 없을 때 처음부터 생성 (monorepo-init 역할)
- 코드 수정 또는 git commit 직접 실행
- CLAUDE.md 외 다른 프로젝트 파일 수정

---

## 7. Related Skills

| 스킬 | 관계 |
|------|------|
| `monorepo-init` | CLAUDE.md 초기 생성 → 이 스킬은 이후 유지보수 담당 |
| `agents-md-copy` | CLAUDE.md 업데이트 후 AGENTS.md 동기화 연계 |
| `issue-tracker` | 커밋/PR 시점에 함께 동작할 수 있는 워크플로우 스킬 |
