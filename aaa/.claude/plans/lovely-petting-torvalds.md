# Copilot CLI 동시 모델 실행 문제 수정

## Context

`verify` 도구에서 Copilot을 여러 모델 배열로 호출하면 실패합니다.
`crossVerify()`가 `Promise.allSettled()`로 모든 모델을 **동시에** spawn하는데,
Copilot CLI는 세션 락/인증 토큰 경합으로 동시 인스턴스를 지원하지 않기 때문입니다.
단일 모델(`ask_agent`)로 호출하면 정상 동작합니다.

## 수정 방향

`IAgent` 인터페이스에 `supportsParallelExecution` 속성을 추가하고,
`crossVerify()`에서 이 플래그에 따라 병렬/순차 실행을 분기합니다.

> 왜 `agent.id === "copilot"` 하드코딩이 아닌가?
> - 향후 다른 에이전트도 동일 제약이 생길 수 있음 (1줄 override로 대응)
> - 인터페이스에 명시하면 자기 문서화(self-documenting)

## 변경 파일 (4개)

### 1. `src/agents/types.ts` — IAgent 인터페이스 확장
```typescript
// IAgent에 추가
readonly supportsParallelExecution: boolean;
```

### 2. `src/agents/base-agent.ts` — 기본값 true 설정
```typescript
// BaseAgent 클래스에 추가
readonly supportsParallelExecution: boolean = true;
```
- Claude, Codex, Gemini는 변경 없이 `true` 상속

### 3. `src/agents/copilot-agent.ts` — false로 override
```typescript
override readonly supportsParallelExecution = false;
```

### 4. `src/orchestrator/verifier.ts` — 병렬/순차 분기 로직
- 기존 `Promise.allSettled()` 로직을 `executeModelsParallel()` 헬퍼로 추출
- 새로운 `executeModelsSequential()` 헬퍼 추가 (for-of + try/catch)
- `crossVerify()`에서 `agent.supportsParallelExecution`으로 분기

```typescript
const responses = agent.supportsParallelExecution
    ? await executeModelsParallel(agent, models, params)
    : await executeModelsSequential(agent, models, params);
```

순차 실행에서도 한 모델 실패 시 나머지 계속 진행 (Promise.allSettled 동일 시맨틱).

## 변경하지 않는 파일

- `src/orchestrator/parallel.ts` — 서로 다른 에이전트 병렬 실행이므로 Copilot은 최대 1개. 수정 불필요
- `src/tools/verify.ts` — `crossVerify()` 호출만 하므로 수정 불필요

## 검증 방법

```bash
# 1. 빌드
npm run build

# 2. 단일 모델 테스트 (기존 동작 확인)
node -e "
const { CopilotAgent } = await import('./dist/agents/copilot-agent.js');
const agent = new CopilotAgent({ default: 'claude-sonnet-4.5', models: ['claude-sonnet-4.5'] });
const r = await agent.execute({ prompt: 'Reply with: OK', timeout: 60000 });
console.log('single:', r.exitCode, r.content.substring(0, 50));
"

# 3. 멀티 모델 순차 실행 테스트 (핵심 수정 검증)
node -e "
const { CopilotAgent } = await import('./dist/agents/copilot-agent.js');
const { crossVerify } = await import('./dist/orchestrator/verifier.js');
const agent = new CopilotAgent({ default: 'claude-sonnet-4.5', models: ['claude-sonnet-4.5', 'gpt-5.2-codex'] });
console.log('parallel support:', agent.supportsParallelExecution); // false
const result = await crossVerify(agent, { prompt: 'Reply with: OK', models: ['claude-sonnet-4.5', 'gpt-5.2-codex'], timeout: 60000 });
console.log('responses:', result.responses.length);
for (const r of result.responses) console.log(r.model, r.exitCode);
"

# 4. lint 확인
npm run lint
```
