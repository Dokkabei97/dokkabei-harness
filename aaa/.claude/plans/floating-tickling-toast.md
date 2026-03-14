# AA-MCP (Auto Agents MCP) 개발 계획

## Context

여러 AI CLI 에이전트(Claude Code, Codex, Gemini CLI, Copilot CLI)를 headless 모드로 호출하는 MCP 서버를 구축한다. 단순 호출뿐 아니라, 작업 위임, 협업 분석, 멀티모델 교차 검증, 특화 도구(코드리뷰/디버그/테스트생성 등)를 제공한다. 사용자가 특정 에이전트를 명시하면 해당 에이전트만 호출하고, 명시적으로 다중 호출을 요청한 경우에만 병렬 실행한다.

**레퍼런스:** codex-mcp-bridge (8개 스킬 + 서브에이전트), copilot-mcp-tool (9개 도구 + 세션 리소스 + copilot-flow)

---

## 기술 스택

| 항목 | 선택 | 이유 |
|------|------|------|
| **런타임** | Node.js 22+ | MCP 생태계 표준, `npx` 배포 용이 |
| **언어** | TypeScript 5.x (ESM) | 타입 안전성 + MCP SDK 참조 구현체 |
| **MCP SDK** | `@modelcontextprotocol/sdk` ^1.x | 프로덕션 안정 버전 |
| **검증** | Zod 3.x | MCP SDK 내장, 스키마 자동 변환 |
| **설정 파싱** | `yaml` 패키지 | 주석 지원 (사용자 편집용) |
| **CLI 감지** | `which` 패키지 | 크로스 플랫폼 바이너리 탐지 |
| **테스트** | Vitest | 빠르고 ESM 네이티브 지원 |
| **린팅** | Biome | 빠른 포매팅+린팅 통합 |

---

## 프로젝트 구조

```
aa-mcp/
├── src/
│   ├── index.ts                    # 진입점: 서버 생성 → transport 연결
│   ├── server.ts                   # McpServer 팩토리 + 도구/리소스 등록
│   │
│   ├── agents/                     # 에이전트 추상화 계층
│   │   ├── types.ts                # IAgent 인터페이스, AgentResponse 등
│   │   ├── registry.ts             # 에이전트 감지, 등록, 재귀 호출 방지
│   │   ├── base-agent.ts           # 공통 실행 로직 추상 클래스
│   │   ├── claude-agent.ts         # Claude Code CLI 어댑터
│   │   ├── codex-agent.ts          # Codex CLI 어댑터
│   │   ├── gemini-agent.ts         # Gemini CLI 어댑터
│   │   └── copilot-agent.ts        # Copilot CLI 어댑터
│   │
│   ├── tools/                      # MCP 도구 정의
│   │   ├── ask-agent.ts            # ask_agent: 특정 에이전트에 질문 (기본 도구)
│   │   ├── ask-all.ts              # ask_all: 명시적 요청 시 다중 에이전트 병렬 질문
│   │   ├── delegate.ts             # delegate_task: 작업 위임 (복잡도 분석 → 자동 병렬화)
│   │   ├── collaborate.ts          # collaborate: 다른 에이전트와 협업 분석
│   │   ├── verify.ts               # verify: 멀티모델 교차 검증 (copilot 멀티모델 등)
│   │   ├── review-code.ts          # review_code: 에이전트별 특화 코드 리뷰
│   │   ├── debug-with.ts           # debug_with: 에이전트로 디버그
│   │   ├── explain-with.ts         # explain_with: 에이전트로 코드 설명
│   │   ├── generate-test.ts        # generate_test: 에이전트로 테스트 생성
│   │   ├── refactor-with.ts        # refactor_with: 에이전트로 리팩터링
│   │   ├── list-agents.ts          # list_agents: 감지된 에이전트 목록
│   │   ├── list-models.ts          # list_models: 에이전트별 모델 목록
│   │   └── agent-health.ts         # agent_health: 에이전트 상태 확인
│   │
│   ├── orchestrator/               # 오케스트레이션 엔진
│   │   ├── executor.ts             # subprocess spawn 래퍼 (타임아웃/abort)
│   │   ├── parallel.ts             # Promise.allSettled 병렬 실행
│   │   ├── aggregator.ts           # 다중 응답 비교 포매팅
│   │   ├── complexity.ts           # 작업 복잡도 분석 (자동 병렬화 판단)
│   │   └── verifier.ts             # 교차 검증 파이프라인
│   │
│   ├── session/                    # 세션 관리
│   │   ├── store.ts                # 세션 저장소 (파일 기반)
│   │   └── types.ts                # 세션 타입 정의
│   │
│   ├── resources/                  # MCP 리소스 정의
│   │   ├── session-history.ts      # aa://session/{id}/history
│   │   ├── sessions-list.ts        # aa://sessions
│   │   └── agent-status.ts         # aa://agents/status
│   │
│   ├── config/                     # 설정 시스템
│   │   ├── loader.ts               # YAML 설정 로더
│   │   └── schema.ts               # Zod 검증 스키마
│   │
│   └── utils/                      # 유틸리티
│       ├── logger.ts               # stderr 전용 로거
│       └── detect.ts               # CLI 바이너리 감지 + 호출자 감지
│
├── config/
│   └── models.yaml                 # 외부 모델 설정 (사용자 편집 가능)
│
├── skills/                         # 커스텀 스킬 정의 (사용 예시)
│   ├── ask-agents.md               # /ask-agents 스킬
│   ├── delegate-task.md            # /delegate 스킬
│   ├── verify-with-all.md          # /verify 스킬
│   ├── code-review-multi.md        # /code-review-multi 스킬
│   └── debug-collaborate.md        # /debug-collaborate 스킬
│
├── agents/                         # 커스텀 서브에이전트 정의 (사용 예시)
│   ├── orchestrator.md             # 오케스트레이터 에이전트
│   └── reviewer.md                 # 멀티에이전트 리뷰어
│
├── commands/                       # 커스텀 커맨드 정의 (사용 예시)
│   └── aa.md                       # /aa 커맨드
│
├── package.json
├── tsconfig.json
├── biome.json
└── vitest.config.ts
```

---

## 핵심 설계

### 1. 에이전트 추상화 인터페이스 (`src/agents/types.ts`)

```typescript
interface IAgent {
  readonly id: 'claude' | 'codex' | 'gemini' | 'copilot';
  readonly displayName: string;
  readonly cliCommand: string;

  isAvailable(): Promise<boolean>;
  getModels(): string[];
  getDefaultModel(): string;
  execute(options: ExecutionOptions): Promise<AgentResponse>;
  healthCheck(): Promise<HealthStatus>;
}

interface ExecutionOptions {
  prompt: string;
  model?: string;
  timeout?: number;
  cwd?: string;
  context?: string;           // stdin으로 파이핑할 추가 컨텍스트
  analysisLevel?: 'low' | 'medium' | 'high' | 'xhigh';  // codex 전용
  sessionId?: string;         // 세션 추적용
}

interface AgentResponse {
  agent: string;
  model: string;
  content: string;
  durationMs: number;
  exitCode: number;
  error?: string;
}

interface HealthStatus {
  agent: string;
  available: boolean;
  authenticated: boolean;
  latencyMs?: number;
  error?: string;
}
```

### 2. 재귀 호출 방지 (`src/agents/registry.ts`)

```
1. 환경변수 기반 감지:
   - CLAUDECODE=1           → 호출자: claude
   - CODEX_SANDBOX_TYPE     → 호출자: codex
   - GEMINI_CLI             → 호출자: gemini
   - COPILOT_CLI            → 호출자: copilot

2. process.env._ (마지막 실행 명령) 체크 (보조)

3. CLI 인자 기반: npx aa-mcp --caller claude

→ 감지된 호출자는 getAvailableAgents()에서 완전히 제외
```

### 3. 각 에이전트 headless 실행 패턴

| 에이전트 | 명령어 패턴 | 출력 캡처 |
|---------|------------|----------|
| **Claude** | `claude -p "<prompt>" --output-format json --model <model>` | JSON stdout |
| **Codex** | `codex exec - --model <model> --sandbox read-only --output-last-message <tmpfile>` | 파일 → stdout 폴백 |
| **Gemini** | `gemini -p "<prompt>" -m <model> --output-format json` | JSON stdout |
| **Copilot** | `copilot -p "<prompt>" --model <model> --allow-all-tools` | 텍스트 stdout |

**Claude 특수 처리:** 호출 시 `CLAUDECODE` 환경변수 해제:
```typescript
env: { ...process.env, CLAUDECODE: '' }
```

### 4. 외부 모델 설정 (`config/models.yaml`)

```yaml
# Auto Agents MCP - 모델 설정
# 새 모델 추가/변경 시 이 파일만 수정하면 됩니다

agents:
  claude:
    default: claude-sonnet-4-5-20250929
    models:
      - claude-opus-4-6
      - claude-sonnet-4-5-20250929
      - claude-haiku-4-5-20251001
      - claude-sonnet-4-20250514
      - claude-opus-4-20250918

  codex:
    default: o3
    defaultAnalysisLevel: medium  # low | medium | high | xhigh
    models:
      - o3
      - o4-mini
      - gpt-5.3-codex-spark
      - gpt-5.2-codex
      - gpt-5.1-codex-mini
      - gpt-5.1-codex-max

  gemini:
    default: gemini-3-pro-preview
    models:
      - gemini-3-pro-preview
      - gemini-2.5-pro
      - gemini-2.5-flash
      - gemini-2.5-flash-lite

  copilot:
    default: claude-sonnet-4-5
    models:
      - claude-opus-4-6
      - claude-sonnet-4-5
      - claude-haiku-4-5
      - gpt-5
      - gpt-5.2-codex
      - gpt-5.1-codex-mini
      - gemini-3-pro-preview
      - o3
```

---

## MCP 도구 설계 (13개)

**기본 원칙: 사용자가 특정 에이전트를 명시하면 해당 에이전트만 호출. 명시적으로 다중 호출을 요청한 경우에만 병렬 실행.**

### 핵심 도구 (4개)

#### `ask_agent` — 특정 에이전트에 질문
- **용도:** 사용자가 "codex에게 물어봐", "gemini로 분석해줘" 등 단일 에이전트 지정
- **파라미터:** agent, prompt, model?, context?, timeout?, analysisLevel?
- Codex의 경우 `analysisLevel`(low/medium/high/xhigh)로 분석 깊이 제어

#### `ask_all` — 다중 에이전트 병렬 질문
- **용도:** "모든 에이전트에게 물어봐", "비교해서 보여줘" 등 명시적 다중 호출
- **파라미터:** prompt, agents?, context?, timeout?
- `Promise.allSettled`로 병렬 실행 → 비교 포맷팅

#### `delegate_task` — 작업 위임 (복잡도 기반 자동 라우팅)
- **용도:** 에이전트에게 작업을 맡기되, 대규모 작업이면 자동으로 여러 에이전트에 분할 위임
- **파라미터:** task, agent?, allowParallel?(default:true), context?
- **동작:**
  1. 작업 복잡도 분석 (프롬프트 길이, 키워드, 파일 수 등)
  2. 단순 작업 → 지정된 에이전트(또는 기본 에이전트)에 위임
  3. 대규모 작업 + allowParallel → 복수 에이전트에 분할 병렬 위임
  4. 결과 취합하여 반환

#### `collaborate` — 에이전트와 협업 분석
- **용도:** "Gemini와 상의하면서 진행해줘" 패턴 (CLAUDE.md의 기존 패턴을 MCP로 대체)
- **파라미터:** agent, prompt, context?
- **동작:**
  1. 에이전트에게 프롬프트 전달
  2. 에이전트 응답 + 호출 에이전트(자신)의 해설을 함께 반환
  3. 양쪽 결과 비교하여 최적안 제시 가이드

### 검증 도구 (1개)

#### `verify` — 멀티모델 교차 검증
- **용도:** 하나의 에이전트를 여러 모델로 호출하여 교차 검증
- **파라미터:** agent, prompt, models[]?, context?
- **동작 (copilot 예시 - CLAUDE.md 패턴 기반):**
  1. `copilot --model gpt-5.2-codex -p "$PROMPT"` 실행
  2. `copilot --model claude-sonnet-4-5 -p "$PROMPT"` 실행
  3. `copilot --model gemini-3-pro-preview -p "$PROMPT"` 실행
  4. 3개 모델 결과를 비교하여 합의/차이점 정리
- **다른 에이전트에도 동일 적용 가능** (claude를 opus/sonnet/haiku로 비교 등)

### 특화 도구 (5개) — 레퍼런스 패턴 차용

#### `review_code` — 에이전트로 코드 리뷰
- **파라미터:** agent, code(또는 filePath), focus?(bugs/security/performance/clarity)
- codex-mcp-bridge의 codex-review 스킬 + copilot-mcp-tool의 copilot-review 도구 패턴
- 4차원 분석: 버그, 보안, 성능, 가독성

#### `debug_with` — 에이전트로 디버그
- **파라미터:** agent, error, code?, context?
- copilot-mcp-tool의 copilot-debug 도구 패턴
- 에러 메시지 + 코드 컨텍스트를 에이전트에 전달

#### `explain_with` — 에이전트로 코드 설명
- **파라미터:** agent, code, detail?(brief/detailed)
- codex-mcp-bridge의 codex-explain + copilot-mcp-tool의 copilot-explain 패턴

#### `generate_test` — 에이전트로 테스트 생성
- **파라미터:** agent, code, framework?(jest/vitest/pytest/kotest)
- codex-mcp-bridge의 codex-test (workspace-write 권한) 패턴
- 프레임워크 자동 감지 + 테스트 코드 생성

#### `refactor_with` — 에이전트로 리팩터링
- **파라미터:** agent, code, goal?(performance/readability/modularity)
- codex-mcp-bridge의 codex-refactor 패턴

### 정보 도구 (3개)

#### `list_agents` — 감지된 에이전트 목록 + 가용 상태
#### `list_models` — 에이전트별 사용 가능 모델 목록 (agent?)
#### `agent_health` — 에이전트 상태 확인 (인증, 응답 속도 등)

---

## MCP 리소스 (3개) — copilot-mcp-tool 패턴

세션 기반 히스토리와 에이전트 상태를 MCP 리소스로 노출:

| 리소스 URI | 설명 |
|-----------|------|
| `aa://sessions` | 활성 세션 목록 |
| `aa://session/{id}/history` | 특정 세션의 에이전트 호출 히스토리 |
| `aa://agents/status` | 모든 에이전트의 현재 상태 (가용성, 인증, 지연시간) |

### 세션 관리 (`src/session/`)

- 파일 기반 세션 저장: `~/.aa-mcp/sessions/`
- 각 에이전트 호출마다 세션에 기록 (prompt, response, agent, model, duration)
- 리소스를 통해 히스토리 조회 가능

---

## 커스텀 스킬/에이전트/커맨드 예시

### 커스텀 스킬 (`skills/`)

Claude Code에서 `/ask-agents`, `/delegate`, `/verify` 등의 슬래시 커맨드로 사용 가능한 스킬 정의:

#### `skills/ask-agents.md`
```markdown
---
name: ask-agents
description: AI 에이전트에게 질문합니다
user-invocable: true
allowed-tools: [mcp__aa-mcp__ask_agent, mcp__aa-mcp__list_agents]
---
사용자의 질문을 적절한 에이전트에 전달합니다.
1. list_agents로 가용 에이전트 확인
2. 사용자가 지정한 에이전트로 ask_agent 호출
3. 응답 포맷팅하여 반환
```

#### `skills/delegate-task.md`
```markdown
---
name: delegate
description: 에이전트에게 작업을 위임합니다 (대규모 작업 자동 분할)
user-invocable: true
allowed-tools: [mcp__aa-mcp__delegate_task, mcp__aa-mcp__list_agents]
---
작업을 분석하여 적절한 에이전트에 위임합니다.
복잡한 작업은 자동으로 분할하여 병렬 처리합니다.
```

#### `skills/verify-with-all.md`
```markdown
---
name: verify
description: 멀티모델로 교차 검증합니다
user-invocable: true
allowed-tools: [mcp__aa-mcp__verify, mcp__aa-mcp__list_models]
---
하나의 에이전트를 여러 모델로 호출하여 결과를 교차 검증합니다.
ex) copilot을 gpt/claude/gemini 모델로 각각 호출 후 비교
```

#### `skills/code-review-multi.md`
```markdown
---
name: code-review-multi
description: 여러 에이전트로 코드 리뷰
user-invocable: true
allowed-tools: [mcp__aa-mcp__review_code, mcp__aa-mcp__ask_all]
---
복수 에이전트로 코드를 리뷰하고 결과를 종합합니다.
각 에이전트의 강점 분야별 리뷰 (보안, 성능, 가독성 등)
```

#### `skills/debug-collaborate.md`
```markdown
---
name: debug-collaborate
description: 에이전트와 협력하여 디버깅
user-invocable: true
allowed-tools: [mcp__aa-mcp__debug_with, mcp__aa-mcp__collaborate]
---
에러를 분석하고 에이전트와 협력하여 해결합니다.
```

### 커스텀 서브에이전트 (`agents/`)

#### `agents/orchestrator.md`
```markdown
---
name: orchestrator
description: 멀티에이전트 오케스트레이터
tools: [mcp__aa-mcp__*, Read, Glob, Grep]
---
복잡한 작업을 분석하여 여러 에이전트에 분배하고 결과를 종합합니다.
1. 작업 분석 → 하위 작업 분할
2. 각 하위 작업에 최적 에이전트 매칭
3. 병렬/순차 실행 결정
4. 결과 취합 및 품질 검증
```

#### `agents/reviewer.md`
```markdown
---
name: reviewer
description: 멀티에이전트 코드 리뷰어
tools: [mcp__aa-mcp__review_code, mcp__aa-mcp__ask_all, Read, Glob]
---
여러 에이전트의 코드 리뷰 결과를 종합하여 통합 리뷰 리포트를 생성합니다.
- 보안 관점 (에이전트 A)
- 성능 관점 (에이전트 B)
- 가독성 관점 (에이전트 C)
→ 통합 리포트
```

### 커스텀 커맨드 (`commands/`)

#### `commands/aa.md`
```markdown
---
name: aa
description: Auto Agents 통합 커맨드
allowed-tools: [mcp__aa-mcp__*]
---
Auto Agents MCP의 모든 기능에 접근하는 통합 커맨드입니다.
- /aa ask <agent> <prompt> - 에이전트에 질문
- /aa delegate <task> - 작업 위임
- /aa verify <prompt> - 교차 검증
- /aa review <file> - 멀티에이전트 리뷰
- /aa status - 에이전트 상태 확인
```

---

## 오케스트레이션 설계

### 작업 복잡도 분석 (`src/orchestrator/complexity.ts`)

`delegate_task` 도구에서 사용. 작업을 자동으로 분석하여 단일/병렬 실행 결정:

```
분석 기준:
- 프롬프트 길이 (긴 프롬프트 → 복잡한 작업 가능성)
- 키워드 감지 ("전체", "모든 파일", "리팩터링", "마이그레이션" 등)
- 파일/디렉토리 참조 수
- 명시적 다중 작업 구조 (번호 목록, "그리고", "또한" 등)

결과:
- simple → 단일 에이전트 실행
- complex → 에이전트에게 위임 (타임아웃 늘림)
- large → 여러 에이전트에 분할 병렬 위임 (allowParallel=true일 때)
```

### 교차 검증 파이프라인 (`src/orchestrator/verifier.ts`)

`verify` 도구에서 사용. 하나의 에이전트를 여러 모델로 호출:

```
입력: agent=copilot, prompt="코드 분석", models=[gpt-5.2-codex, claude-sonnet-4-5, gemini-3-pro-preview]
  ↓
1. copilot --model gpt-5.2-codex -p "코드 분석" → 결과 A
2. copilot --model claude-sonnet-4-5 -p "코드 분석" → 결과 B
3. copilot --model gemini-3-pro-preview -p "코드 분석" → 결과 C
  ↓ (병렬 실행)
비교 분석:
- 합의 사항 (모든 모델이 동의)
- 차이점 (모델별 다른 의견)
- 각 모델 응답 원문
```

### 에이전트 헬스체크 (`src/tools/agent-health.ts`)

```
각 에이전트에 간단한 프롬프트 전송 → 응답 확인:
- CLI 존재 여부 (which)
- 인증 상태 (간단한 호출 → 인증 에러 감지)
- 응답 지연시간 측정
- 에러 시 failover 가능 에이전트 제안
```

---

## subprocess 실행 패턴

`child_process.spawn` 사용:
- `AbortController`로 타임아웃 관리
- stdin 파이핑으로 컨텍스트 전달
- 에이전트별 환경변수 커스터마이징
- stdout/stderr 수집 후 에이전트별 파싱
- Codex: `--output-last-message <tmpfile>`로 파일 기반 출력 캡처 (codex-mcp-bridge 패턴)

---

## 구현 단계 (팀 병렬 개발)

### Phase 1: 프로젝트 초기화 + 설정 시스템
**담당: 개발자 A**
- [ ] `package.json`, `tsconfig.json`, `biome.json` 초기화
- [ ] 의존성 설치: `@modelcontextprotocol/sdk`, `zod`, `yaml`, `which`
- [ ] `src/agents/types.ts` - 핵심 인터페이스 정의
- [ ] `src/config/schema.ts` - Zod 검증 스키마
- [ ] `src/config/loader.ts` - YAML 설정 로더
- [ ] `config/models.yaml` - 외부 모델 설정 파일
- [ ] `src/utils/logger.ts` - stderr 전용 로거
- [ ] `src/utils/detect.ts` - CLI 감지 + 호출자 감지

### Phase 2: 에이전트 계층 (Phase 1 완료 후)
**담당: 개발자 B, C 병렬**
- [ ] `src/agents/base-agent.ts` - 추상 베이스 클래스 (spawn 로직)
- [ ] `src/orchestrator/executor.ts` - subprocess spawn 래퍼
- [ ] `src/agents/claude-agent.ts` - CLAUDECODE 환경변수 해제 포함
- [ ] `src/agents/codex-agent.ts` - stdin 파이핑 + output-last-message + analysisLevel
- [ ] `src/agents/gemini-agent.ts` - -p + --output-format json
- [ ] `src/agents/copilot-agent.ts` - -p + --allow-all-tools
- [ ] `src/agents/registry.ts` - 감지 + 등록 + 재귀 방지

### Phase 3: 오케스트레이션 (Phase 2 완료 후)
**담당: 개발자 D**
- [ ] `src/orchestrator/parallel.ts` - 병렬 실행
- [ ] `src/orchestrator/aggregator.ts` - 응답 비교 포매팅
- [ ] `src/orchestrator/complexity.ts` - 작업 복잡도 분석
- [ ] `src/orchestrator/verifier.ts` - 교차 검증 파이프라인

### Phase 4: MCP 도구 + 리소스 + 서버 (Phase 2, 3 완료 후)
**담당: 개발자 E, F 병렬**
- [ ] `src/tools/ask-agent.ts`, `ask-all.ts` - 기본 도구
- [ ] `src/tools/delegate.ts` - 작업 위임
- [ ] `src/tools/collaborate.ts` - 협업 분석
- [ ] `src/tools/verify.ts` - 멀티모델 교차 검증
- [ ] `src/tools/review-code.ts`, `debug-with.ts`, `explain-with.ts`, `generate-test.ts`, `refactor-with.ts` - 특화 도구
- [ ] `src/tools/list-agents.ts`, `list-models.ts`, `agent-health.ts` - 정보 도구
- [ ] `src/session/store.ts`, `src/session/types.ts` - 세션 관리
- [ ] `src/resources/*.ts` - MCP 리소스 (3개)
- [ ] `src/server.ts` - McpServer 팩토리
- [ ] `src/index.ts` - 진입점 (stdio transport)

### Phase 5: 스킬/에이전트/커맨드 + 테스트
- [ ] `skills/*.md` - 5개 커스텀 스킬
- [ ] `agents/*.md` - 2개 커스텀 서브에이전트
- [ ] `commands/aa.md` - 통합 커맨드
- [ ] Vitest 단위 테스트
- [ ] `claude mcp add` → 실제 도구 호출 통합 테스트

---

## 검증 방법

1. **빌드:** `npm run build` 성공 확인
2. **CLI 감지:** `list_agents` → 설치된 에이전트 목록 확인
3. **단일 호출:** `ask_agent` → 각 에이전트 개별 테스트
4. **다중 호출:** `ask_all` → 모든 에이전트 동시 호출 + 비교 결과
5. **작업 위임:** `delegate_task` → 단순/복잡 작업 자동 라우팅 확인
6. **협업:** `collaborate` → 에이전트 응답 + 해설 포함 확인
7. **교차 검증:** `verify` → copilot 3개 모델 비교 결과 확인
8. **특화 도구:** `review_code`, `debug_with` 등 각각 테스트
9. **재귀 방지:** Claude Code에서 MCP 연결 후 claude 제외 확인
10. **모델 설정:** `models.yaml` 수정 후 `list_models` 반영 확인
11. **세션:** 호출 히스토리가 `aa://session/{id}/history`에 기록되는지 확인
12. **헬스체크:** `agent_health` → 에이전트 인증/가용성 상태 확인
13. **스킬:** Claude Code에서 `/ask-agents`, `/delegate` 등 슬래시 커맨드 동작 확인
