---
name: with
description: Routes tasks to external AI CLI agents (Codex, Gemini, Copilot) with automatic complexity-based model routing. Supports collaboration, delegation, and parallel execution modes.
argument-hint: <agent|all> <task description>
disable-model-invocation: true
context: fork
allowed-tools: Bash(codex *), Bash(gemini *), Bash(copilot *), Bash(mktemp *), Bash(cat *), Bash(rm *), Bash(wait *), Bash(which *), Read, Grep, Glob
---

# Agent Orchestration

외부 AI CLI 에이전트에 작업을 전달합니다. 복잡도를 자동 분석하여 최적의 모델/설정을 선택합니다.

## When to Use

- 외부 AI 에이전트의 의견이나 분석이 필요할 때
- 특정 에이전트의 강점을 활용하고 싶을 때 (Codex: 코드 실행, Gemini: 웹 검색, Copilot: GitHub)
- 여러 에이전트의 응답을 비교하여 최적안을 도출하고 싶을 때
- 작업을 외부 에이전트에 위임하고 싶을 때

## Agent Availability

- Codex: !`which codex 2>/dev/null && echo "available" || echo "not installed"`
- Gemini: !`which gemini 2>/dev/null && echo "available" || echo "not installed"`
- Copilot: !`which copilot 2>/dev/null && echo "available" || echo "not installed"`

## Supported Agents

| Agent   | CLI       | 강점                            | 기본 모델                  |
|---------|-----------|---------------------------------|------------------------|
| Codex   | `codex`   | 코드 생성/실행, 디버깅, 샌드박스   | gpt-5.4                |
| Gemini  | `gemini`  | 웹 검색, 리서치, 멀티모달         | gemini-3.1-pro-preview |
| Copilot | `copilot` | GitHub 연동, 멀티모델 지원        | claude-sonnet-4.6      |

## Instructions

### 1. Parse Arguments

`$ARGUMENTS`에서 다음을 파싱합니다:

- **에이전트**: 첫 번째 단어가 `codex`, `gemini`, `copilot`, `all` 중 하나인지 확인
  - 매칭되면 해당 에이전트 사용
  - `all` 또는 매칭 안 되면 → 모드 판별로 이동
- **모드 감지** (프롬프트 내 키워드):
  - 협업: "같이", "상의", "물어봐", "의견" → Claude 주도 + 에이전트 참고
  - 위임: "맡겨", "시켜", "처리해" → 에이전트 주도
  - 병렬: "비교", "전부", "다 같이", "all" → 모든 에이전트 병렬
  - 기본값: 위 키워드가 없으면 **협업 모드**로 동작
- **에이전트 미지정 시**: 작업 유형으로 자동 선택
  - 코드 생성/실행/디버깅 → Codex
  - 리서치/설명/웹 관련 → Gemini
  - GitHub/PR/리뷰 관련 → Copilot

### 2. Complexity Analysis

작업 내용에서 복잡도를 분석합니다 (각 1점):

1. 키워드: refactor, migrate, architecture, system, optimize, redesign, 리팩토링, 마이그레이션, 아키텍처, 최적화
2. 멀티파일/모듈 변경 필요
3. 의존성/관계 이해 필요
4. 테스트 전략 포함
5. 횡단 관심사 (보안, 성능, 동시성)
6. 외부 시스템/API 연동

### 3. Model Routing

복잡도 점수에 따라 모델/effort를 자동 선택합니다:

| 복잡도   | 점수 | Codex effort | Copilot model     | Gemini model             |
|----------|------|--------------|-------------------|--------------------------|
| Simple   | 0-2  | low          | claude-sonnet-4.6 | gemini-3.1-flash-preview |
| Medium   | 3-4  | high         | claude-opus-4.6   | gemini-3.1-pro-preview   |
| Complex  | 5+   | xhigh        | gpt-5.4           | gemini-3.1-pro-preview   |

### 4. Execute

**단일 에이전트:**

```bash
PROMPT='<task, shell-escaped>'

# Codex
codex --model gpt-5.4 <effort> exec "$PROMPT" 

# Gemini
gemini -m <model> -p "$PROMPT" 

# Copilot
copilot --model <model> -p "$PROMPT" 
```

**병렬 실행 (all 또는 Complex 위임):**

```bash
PROMPT='<task, shell-escaped>'
TMPDIR=$(mktemp -d)

# 설치된 에이전트만 실행
(codex --model gpt-5.4 xhigh exec "$PROMPT" > "$TMPDIR/codex.txt" 2>/dev/null; echo $? > "$TMPDIR/codex.exit") &
(gemini -m gemini-3.1-pro-preview -p "$PROMPT" > "$TMPDIR/gemini.txt" 2>/dev/null; echo $? > "$TMPDIR/gemini.exit") &
(copilot --model gpt-5.4 -p "$PROMPT" > "$TMPDIR/copilot.txt" 2>/dev/null; echo $? > "$TMPDIR/copilot.exit") &

wait
```

### 5. Present Results

**단일 에이전트:**
```markdown
## <Agent> (<model>) — Complexity: <level> (score: <N>)
<response>
```

**협업 모드 (단일):** 에이전트 응답 표시 후, Claude가 해설과 최적안을 종합합니다.

**위임 모드 (단일):** 에이전트 응답을 그대로 전달합니다.

**병렬 모드:**
```markdown
## Agent Comparison — Complexity: <level> (score: <N>)

### Codex (gpt-5.4)
<response>

### Gemini (<model>)
<response>

### Copilot (<model>)
<response>

---

## Synthesis
- **Agreements**: 합의점
- **Differences**: 차이점
- **Recommendation**: 추천안
```

### 6. Cleanup

병렬 실행 후:
```bash
rm -r "$TMPDIR"
```

## Timeout

| 복잡도  | 단일  | 병렬 (각) |
|---------|-----|--------|
| Simple  | 5m  | 5m     |
| Medium  | 10m | 10m    |
| Complex | 20m | 20m    |

## Error Handling

- CLI 미설치: 설치 명령 안내 (`npm i -g @openai/codex` 등)
- 타임아웃: 보고 후 더 간단한 프롬프트 제안
- exit code 비정상: stderr 표시
- 병렬 시 일부 실패: 성공한 에이전트 결과만 표시

## Examples

- `/with codex 이 함수 리팩토링해줘` → Simple, Codex 단일
- `/with gemini 맡겨 - REST API 설계` → Medium 위임, Gemini
- `/with copilot 같이 - 인증 모듈 보안 검토` → 협업, Copilot
- `/with all 이 아키텍처 접근법 비교해줘` → Complex 병렬
- `/with 이 에러 디버깅해줘` → 에이전트 자동 선택 (Codex)
