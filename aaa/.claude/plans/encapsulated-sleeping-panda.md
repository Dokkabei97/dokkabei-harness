# Outline 위키 '바이브 코딩' 문서 업데이트 계획

## Context

최근 4개 커밋(f9f396dd, a42be9c2, 1e7e5a4d, 9cbe5a9)에서 새로운 커맨드, 스킬, 기능이 다수 추가되었으나, Outline 위키의 '바이브 코딩' 문서에는 반영되지 않은 상태입니다. 문서를 최신 상태로 업데이트하여 팀원들이 새 기능을 쉽게 파악하고 활용할 수 있도록 합니다.

## 대상 문서

- **문서명**: 바이브 코딩
- **문서 ID**: `67aa8423-a3c4-4a9a-b0cf-e1bd32641c6b`
- **컬렉션**: VibeCode (`3376a27b-60ce-4bbe-a90d-fe80d7f8876c`)

## 업데이트 내용

### 1. CLAUDE.md 섹션 — Codex CLI 통합 추가

기존 Gemini/Copilot 통합 테이블에 Codex CLI 항목 추가:

| 통합 | 설명 |
|------|------|
| **Codex CLI** | "Codex와 상의하면서 진행해줘" 시 Codex Spark 호출하여 결과 비교 |

### 2. commands/ 섹션 — 신규 커맨드 3개 추가

기존 커맨드 테이블에 추가:

| 커맨드 | 설명 | 사용법 |
|--------|------|--------|
| `/obsidian` | Obsidian 기술 학습 노트 생성 (7종 템플릿) | `/obsidian` |
| `/create-flow` | 에이전트/커맨드/스킬/훅 컴포넌트 자동 생성 | `/create-flow` |
| `/verify-flow` | 컴포넌트 구조/품질/보안 검증 | `/verify-flow` |

### 3. skills/ 섹션 — 신규 스킬 3개 추가

기존 스킬 테이블에 추가:

| 스킬 | 설명 | 호출 |
|------|------|------|
| `obsidian-tech-note` | Obsidian 7종 템플릿 기반 기술 학습 노트 시스템 | `/obsidian` |
| `flow-scaffolding` | 에이전트/커맨드/스킬/훅 스캐폴딩 템플릿 | `/create-flow` |
| `flow-validation` | 46개 규칙 기반 컴포넌트 검증 시스템 | `/verify-flow` |

### 4. AI 협업 기능 강화 내용 반영

`/analyze`, `/arch-review`, `/perf-review` 커맨드에 Codex 협업 옵션이 추가된 점을 기존 설명에 보충:
- `--with codex` 옵션 추가됨

### 5. 변경 이력 추가

| 날짜 | 변경 내용 |
|------|----------|
| 2026-02-15 | Codex CLI 통합 추가, Obsidian 학습 노트 스킬 추가, Plane 이슈 트래커 개선, 컴포넌트 생성/검증 자동화(create-flow, verify-flow) 추가 |

## 실행 단계

1. 기존 문서 마크다운을 기반으로 위 5개 섹션을 병합한 전체 문서 작성
2. 민감정보 필터링 (API 키, 사설 IP 등 검사)
3. 사용자에게 미리보기 표시 및 확인 요청
4. `mcp__outline__update_document`로 문서 업데이트

## 검증

- 업데이트 후 Outline에서 문서 URL 확인
- 신규 커맨드/스킬 테이블이 정확히 반영되었는지 확인
