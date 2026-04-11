# Skill Writing Guide

## Description의 역할

Claude는 스킬명과 설명만으로 호출 여부를 결정한다. "복잡하고 다단계이며 전문적인 작업일수록 스킬 트리거 확률이 높다."

### 적극적(Pushy) Description 작성

나쁜 예: `"PDF 처리 도구"` (모호, 언제 쓰는지 불명확)

좋은 예: `"PDF: read/extract/merge/split/rotate/OCR all operations. Use whenever .pdf mentioned or PDF outputs requested. Handles multi-page tables, encrypted files, form extraction."`

**원칙:**
- 트리거 조건을 명시적으로 나열
- 유사 스킬과의 차별점을 기술
- "Use when..." 패턴으로 시작
- 지원 범위를 구체적으로 열거

---

## Content Writing Principles

### 1. Why-First (이유 우선)
규칙을 강제하기보다 이유를 설명한다.

나쁜 예: `"PyPDF2를 사용하지 마라"`
좋은 예: `"PyPDF2는 텍스트 추출에 특화되어 테이블 구조를 보존하지 못한다. pdfplumber를 사용하면 테이블 레이아웃을 유지할 수 있다."`

### 2. Lean (간결)
컨텍스트 윈도우는 공유 자원이다. 불필요한 내용은 제거.

### 3. Generalize (일반화)
특정 예시에만 맞는 좁은 수정 대신 원리 수준에서 일반화.

나쁜 예: `"test_login.py에서 assert True를 제거하라"`
좋은 예: `"Tautological assertion(항상 참인 단언)은 테스트 가치가 없으므로, 구체적인 조건을 검증하는 assertion으로 교체한다."`

### 4. Bundle Repetition (반복 번들링)
3개 테스트에서 동일한 헬퍼 스크립트가 반복 생성되면 `scripts/`에 번들.

---

## Progressive Disclosure

| 레벨 | 위치 | 내용 | 크기 제한 |
|------|------|------|----------|
| 1 | `SKILL.md` | 개요, 핵심 규칙, 참조 안내 | < 500줄 |
| 2 | `references/` | 상세 규칙, 패턴, 예시 | 제한 없음 (300줄 초과 시 목차) |
| 3 | `templates/` | 재사용 템플릿 | 필요에 따라 |
| 4 | `scripts/` | 공통 유틸리티 스크립트 | 3회 이상 반복 시 |

---

## Size Discipline

- `SKILL.md` < 500줄 (초과 시 `references/`로 분리)
- 초과 시 상세 내용을 `references/`로 분리
- `references/` 파일: `{prefix}-{topic}.md` 네이밍
- 5개 이상 레퍼런스 시 `_sections.md` 인덱스 파일 추가 권장

---

## Output Format

산출물 형식이 중요한 스킬은 명확한 템플릿과 예시를 포함한다.

---

## Excluded Content

스킬에 포함하지 않는 것:
- README, CHANGELOG
- 메타정보, 사용자 설명서
- 일반 프로그래밍 지식 (Claude가 이미 아는 것)
- 특정 프로젝트의 일시적 상태

---

## Integration with flow-scaffolding

agent-utils의 `skills/flow-scaffolding/` 스킬이 제공하는 템플릿을 활용:
- `templates/skill.md` — 스킬 기본 템플릿
- `templates/agent.md` — 에이전트 기본 템플릿
- `templates/team-agent.md` — 팀 에이전트 템플릿

`/create-flow` 커맨드로 컴포넌트 생성 시 이 템플릿이 자동 적용된다.
