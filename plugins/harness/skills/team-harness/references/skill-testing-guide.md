# 스킬 테스트와 반복 개선 가이드

하네스로 만든 스킬의 품질을 검증하고 반복 개선하는 방법. `SKILL.md`의 검증(`/verify-flow` 위임)·피드백 루프 단계를 보충하는 레퍼런스다.

---

## 목차

1. [테스트 방식 개요](#1-overview)
2. [테스트 프롬프트 작성법](#2-prompts)
3. [With-skill vs Baseline 비교](#3-with-skill-vs-baseline)
4. [워크플로로 A/B 테스트 실행 (v2)](#4-workflow-ab)
5. [Assertion 기반 정량 평가](#5-assertions)
6. [전문 평가 에이전트](#6-eval-agents)
7. [반복 개선 루프](#7-iteration)
8. [`description` 트리거 검증](#8-trigger)
9. [하네스 전체 집계 벤치마크](#9-aggregate-benchmark)
10. [verify-flow 연동](#10-verify-flow)
11. [워크스페이스 구조](#11-workspace)

---

<a id="1-overview"></a>

## 1. 테스트 방식 개요

스킬 품질 = **정성 평가**(사람이 산출물을 판단) + **정량 평가**(assertion으로 자동 채점).

| 평가 방식 | 방법 | 적합한 스킬 |
|----------|------|-----------|
| **정성** | 사용자가 산출물을 직접 리뷰 | 문체, 디자인, 창작물 — 사람의 판단이 필요한 스킬 |
| **정량** | Assertion 기반 자동 채점 | 파일 생성, 데이터 추출, 코드 생성 — 결과를 객관적으로 확인 가능한 스킬 |

핵심 루프: **작성 → 테스트 실행 → 평가 → 개선 → 재테스트**

---

<a id="2-prompts"></a>

## 2. 테스트 프롬프트 작성법

### 원칙

**실제 사용자가 입력할 법한 구체적이고 자연스러운 문장**으로 쓴다. 추상적·인공적 프롬프트로는 실제 사용 상황의 동작을 알 수 없다.

- **좋지 않은 예:** `"PDF를 처리하라"`, `"데이터를 추출하라"`
- **좋은 예:** `"다운로드 폴더의 'Q4_매출_최종_v2.xlsx'에서 C열(매출)과 D열(비용)로 이익률(%) 열을 추가하고, 이익률 기준 내림차순 정렬해 줘."`

### 다양성

- 격식체와 캐주얼 톤을 섞는다.
- 명시적 의도와 문맥 추론이 필요한 암시적 의도를 섞는다(파일 형식을 말하는 경우/안 하는 경우).
- 단순·복잡 작업을 섞고, 일부에는 약어·오타·일상 표현을 넣는다.

### 커버리지 (2~3개로 시작)

1. 핵심 사용 사례 1개 (필수)
2. 엣지 케이스 1개 (필수)
3. (선택) 복합 작업 1개

---

<a id="3-with-skill-vs-baseline"></a>

## 3. With-skill vs Baseline 비교

### 3-1. 두 실행

테스트 프롬프트마다 서브에이전트 두 개를 **한 메시지에서 동시에** 실행한다(실행 모드 C — 병렬 `Agent` 호출).

- **With-skill**: 스킬을 읽은 뒤 작업, 결과를 `_workspace/iteration-N/eval-{id}/with_skill/outputs/`에 저장
- **Baseline**: 같은 프롬프트를 스킬 없이 처리, 결과를 `_workspace/iteration-N/eval-{id}/without_skill/outputs/`에 저장

### 3-2. Baseline 정하기

| 상황 | Baseline |
|------|----------|
| 새 스킬 생성 | 스킬 없이 같은 프롬프트 실행 |
| 기존 스킬 개선 | 수정 전 스킬을 별도 사본으로 보존해 실행 |

### 3-3. Timing 데이터

서브에이전트 완료 알림에서 `total_tokens`와 `duration_ms`를 **즉시** `timing.json`에 저장한다. 알림 시점에만 접근 가능하고 이후 복구할 수 없다.

---

<a id="4-workflow-ab"></a>

## 4. 워크플로로 A/B 테스트 실행 (v2)

테스트 사례가 세 건 이상이거나 여러 회차 반복 검증이 필요하면 A/B 테스트 자체를 `Workflow` 스크립트로 만든다(실행 모드 A). **사용자가 명시적으로 동의했을 때만** 사용하고, 첫 실행은 사례 수를 작게 잡는다.

```javascript
export const meta = {
  name: 'skill-ab-test',
  description: '스킬 적용 실행과 기준 실행을 마친 뒤 익명으로 채점한다',
  phases: [{ title: '실행' }, { title: '채점' }],
}
const RUN_RESULT = { type: 'object', required: ['saved', 'files'], properties: {
  saved: { type: 'boolean' },
  files: { type: 'array', minItems: 2, items: { type: 'string', minLength: 1 } } } }
const SLOT_GRADE = { type: 'object', required: ['expectations', 'summary'], properties: {
  expectations: { type: 'array', items: { type: 'object',
    required: ['text', 'passed', 'evidence'], properties: {
      text: { type: 'string' }, passed: { type: 'boolean' }, evidence: { type: 'string' } } } },
  summary: { type: 'object', required: ['passed', 'failed', 'total', 'pass_rate'], properties: {
    passed: { type: 'integer' }, failed: { type: 'integer' }, total: { type: 'integer' },
    pass_rate: { type: 'number' } } } } }
const GRADE = { type: 'object', required: ['A', 'B', 'comparison'], properties: {
  A: SLOT_GRADE,
  B: SLOT_GRADE,
  comparison: { type: 'object', required: ['preferred', 'reason'], properties: {
    preferred: { type: 'string', enum: ['A', 'B', 'tie'] },
    reason: { type: 'string' } } } } }

const results = await pipeline(
  args.evals,   // [{id, prompt, assertions, skillPath, withSkillSlot: 'A' | 'B'}]
  e => {
    const withSkillSlot = e.withSkillSlot === 'B' ? 'B' : 'A'
    const baselineSlot = withSkillSlot === 'A' ? 'B' : 'A'
    return parallel([
      () => agent(
        `${e.prompt}\n\n먼저 ${e.skillPath}를 읽고 따르라. 산출물은 ${args.ws}/${e.id}/with_skill/outputs/에 저장하고, 같은 파일을 ${args.ws}/${e.id}/blind/${withSkillSlot}/outputs/에도 저장하라. 저장한 파일 경로를 모두 반환하라.`,
        { label: `적용:${e.id}`, phase: '실행', schema: RUN_RESULT }),
      () => agent(
        `${e.prompt}\n\n산출물은 ${args.ws}/${e.id}/without_skill/outputs/에 저장하고, 같은 파일을 ${args.ws}/${e.id}/blind/${baselineSlot}/outputs/에도 저장하라. 저장한 파일 경로를 모두 반환하라.`,
        { label: `기준:${e.id}`, phase: '실행', schema: RUN_RESULT }),
    ])
  },
  (runs, e) => {
    const completed = (runs ?? []).filter(Boolean)
    if (completed.length !== 2 || completed.some(r => !r.saved || r.files.length < 2)) {
      log(`${e.id}: 스킬 적용 실행과 기준 실행의 산출물이 모두 준비되지 않아 채점을 건너뜁니다.`)
      return null
    }
    return agent(
      `${args.ws}/${e.id}/blind/A/outputs/와 ${args.ws}/${e.id}/blind/B/outputs/의 산출물이 모두 있는지 먼저 확인하라. 두 경로 중 하나라도 비어 있으면 채점하지 말고 실패 이유를 보고하라. 두 산출물이 모두 있으면 A와 B를 각각 채점하고 더 나은 쪽을 A, B, tie 가운데 하나로 판정하라. 익명성을 지키기 위해 eval_metadata.json, with_skill/, without_skill/은 열지 마라. 검증 조건: ${JSON.stringify(e.assertions)}`,
      { label: `채점:${e.id}`, phase: '채점', schema: GRADE })
      .then(grade => {
        if (!grade) log(`${e.id}: 익명 채점 결과를 받지 못해 이 사례를 건너뜁니다.`)
        return grade
      })
  }
)
const mapped = results.map((grade, index) => {
  if (!grade) return null
  const e = args.evals[index]
  const withSkillSlot = e.withSkillSlot === 'B' ? 'B' : 'A'
  const baselineSlot = withSkillSlot === 'A' ? 'B' : 'A'
  return {
    evalId: e.id,
    withSkill: grade[withSkillSlot],
    baseline: grade[baselineSlot],
    comparison: {
      preferred: grade.comparison.preferred === 'tie'
        ? 'tie'
        : grade.comparison.preferred === withSkillSlot ? 'with_skill' : 'baseline',
      reason: grade.comparison.reason,
    },
  }
}).filter(Boolean)
return { results: mapped }
```

- 메인 세션은 사례마다 `withSkillSlot`을 A/B로 **번갈아** 지정한다. 채점자는 중립 경로 `blind/A/`·`blind/B/`만 읽으므로 어느 쪽이 스킬 적용인지 모른다.
- 두 실행 산출물이 모두 준비된 사례만 채점한다. 채점 후 메인 세션이 A/B를 with-skill/baseline에 다시 대응시켜 각 실행 디렉토리의 `grading.json`에 저장한다.
- `pipeline`이라 사례 하나가 끝나는 즉시 채점이 시작된다 — 전 사례 완료를 기다릴 필요가 없다.
- 스킬 수정 후 `resumeFromRunId`로 재실행하면 변경되지 않은 사례는 캐시 결과로 건너뛴다.

---

<a id="5-assertions"></a>

## 5. Assertion 기반 정량 평가

### 5-1. 좋은 / 나쁜 assertion

- **좋은 assertion**: 객관적으로 참/거짓 판별 가능, 서술적 이름(문구만 봐도 무엇을 검사하는지 명확), 스킬 적용 시 개선되어야 할 결과를 측정
- **나쁜 assertion**: 스킬 유무와 무관하게 항상 통과("출력이 존재한다"), 주관적 판단 필요("잘 작성되었다")

### 5-2. 코드로 검사 가능한 조건은 스크립트로

눈으로 확인하는 것보다 빠르고 신뢰할 수 있으며, 반복 회차가 바뀌어도 재사용된다.

### 5-3. Non-discriminating assertion 주의

With-skill과 Baseline이 모두 100% 통과하는 assertion은 스킬의 차이를 측정하지 못한다. 삭제하거나 차이를 드러낼 만큼 까다롭게 바꾼다.

### 5-4. 채점 스키마

[skill-writing-guide.md §7](skill-writing-guide.md#7-schemas)의 `grading.json` 형식(`text`/`passed`/`evidence` + `summary`)을 따른다.

```json
{
  "expectations": [
    {"text": "이익률 열 추가됨", "passed": true, "evidence": "E열 확인"},
    {"text": "내림차순 정렬", "passed": false, "evidence": "원본 순서 유지"}
  ],
  "summary": {"passed": 1, "failed": 1, "total": 2, "pass_rate": 0.50}
}
```

---

<a id="6-eval-agents"></a>

## 6. 전문 평가 에이전트

| 역할 | 하는 일 | 사용 시점 |
|------|--------|------------|
| **Grader (채점자)** | assertion별 통과/실패 + 근거 기록, 산출물의 사실 주장 교차 검증, eval 자체 품질 피드백(너무 쉽거나 모호한 assertion 지적) | 매 반복 회차 |
| **Comparator (블라인드 비교자)** | 스킬 적용 여부를 가리고 A/B 순서를 섞어 품질 비교 | "새 버전이 정말 더 나은가?"를 엄밀히 확인할 때 |
| **Analyzer (분석자)** | non-discriminating assertion, 고분산 eval, 시간/토큰 트레이드오프 등 통계 패턴 분석 | 반복 결과가 3회 이상 쌓인 뒤 |

---

<a id="7-iteration"></a>

## 7. 반복 개선 루프

### 7-1. 개선 원칙

1. **일반화**: 테스트 사례 하나에만 맞춘 수정은 오버피팅이다. 원리 수준으로 고친다.
2. **무게 제거**: 트랜스크립트를 읽고 스킬이 비생산적 작업을 시키면 그 지시를 삭제한다.
3. **Why 반영**: 짧은 피드백이라도 왜 중요한지 파악해 그 이유가 드러나게 고친다.
4. **번들링**: 모든 테스트에서 같은 보조 스크립트를 만들면 `scripts/`에 미리 넣는다.

### 7-2. 반복 순서

```
1. 스킬을 수정한다.
2. 새 iteration-{N+1}/ 에서 모든 테스트 사례를 재실행한다.
3. 이전 회차와 비교한 결과를 사용자에게 제시한다.
4. 피드백을 받아 다시 수정 → 반복.
```

**종료 조건:** 사용자 만족 / 빈 피드백(모든 산출물 이상 없음) / 의미 있는 개선 여지 소진.

### 7-3. 초안 → 재검토

수정은 먼저 초안을 만들고, 처음 읽는 검토자의 시각으로 처음부터 다시 읽으며 고친다. 한 번에 완벽하게 쓰려 하지 않는다.

---

<a id="8-trigger"></a>

## 8. `description` 트리거 검증

### 8-1. 평가 쿼리 20개

`should-trigger` 10개 + `should-NOT-trigger` 10개.

**쿼리 품질:**
- 실제 사용자가 입력할 법한 구체적·자연스러운 문장 — 파일 경로, 상황, 열 이름, 회사명 등 디테일 포함
- 길이·톤·형식을 다양하게, 본 레포는 이중언어 description이므로 **한국어·영어 쿼리를 모두** 넣는다
- 뻔한 사례보다 **경계 케이스**에 집중

**`should-trigger`:** 같은 의도의 다양한 표현, 파일 유형을 말하지 않지만 분명히 필요한 요청, 비주류 사용 사례, 다른 스킬과 경쟁하지만 이 스킬이 이겨야 하는 요청.

**`should-NOT-trigger`:** **near-miss가 핵심** — 키워드는 비슷하지만 다른 도구·스킬이 적합한 요청. 명백히 무관한 요청("피보나치 함수 작성")은 테스트 가치가 없다.

### 8-2. 기존 스킬 충돌 검증

1. 기존 스킬의 `description`을 모두 수집한다(설치된 마켓플레이스 플러그인 포함).
2. 새 스킬의 `should-trigger` 쿼리가 기존 스킬을 잘못 트리거하지 않는지 확인한다.
3. 충돌 시 `description`에 적용 범위와 제외 조건을 더 분명히 적는다.

### 8-3. 자동 최적화 (선택·고급)

1. 20개 쿼리를 Train 60% / Test 40%로 분할한다.
2. 현재 `description`의 트리거 정확도를 측정한다.
3. 실패 사례를 분석해 `description`을 개선한다.
4. **Test set 기준**으로 best `description`을 고른다(Train 기준은 과적합).
5. 최대 5회 반복한다.

> headless `claude -p` 자동화 스크립트로 수행한다. 토큰 비용이 높으므로 스킬이 충분히 안정된 뒤 최종 단계에서 실행한다.

---

<a id="9-aggregate-benchmark"></a>

## 9. 하네스 전체 집계 벤치마크 (Aggregate Harness Benchmark)

개별 스킬 eval(위)이 "이 스킬이 동작하나"를 본다면, 집계 벤치마크는 **"하네스 전체가 결과를 개선하나"**를 통계적으로 본다.

### 측정 절차

1. 도메인 대표 작업 **N개**(권장 10~15개)를 난이도별로 구성 (Basic/Advanced/Expert)
2. 각 작업을 **with-harness**(오케스트레이터 경유) vs **without-harness**(단일 에이전트)로 실행
3. 블라인드 Comparator가 산출물 품질을 **1~100점** 채점 + 승/패 판정 (§4 워크플로 패턴을 그대로 확장 가능)
4. 집계 지표 산출

### 집계 지표

| 지표 | 의미 |
|------|------|
| **품질 델타** | with − without 평균 점수 차 |
| **승률** | with가 이긴 작업 수 / N |
| **분산 감소** | 점수 표준편차 변화 (하네스가 *일관성*을 높이는가) |
| **난이도별 효과** | Basic/Advanced/Expert별 델타 (복잡할수록 효과가 큰지) |

> 통상 하네스 효과는 작업이 복잡할수록 커진다. Basic에서 델타가 작다고 실패가 아니다 — 단순 작업은 단일 에이전트로 충분하기 때문이다. **분산 감소**가 종종 평균 향상보다 중요하다(예측 가능성).

### 결과 기록

`{harness}-benchmark/aggregate.json`에 작업별 점수·승패·토큰·시간을 보존하고, 핵심 수치(델타·승률·분산)는 해당 하네스 변경 **git 커밋 본문**에 1줄로 남긴다. 하네스의 이력 원장은 git이다 — 프로젝트 `CLAUDE.md`에는 하네스 트리거 포인터만 두고 수치·이력을 쓰지 않는다.

---

<a id="10-verify-flow"></a>

## 10. verify-flow 연동

팀 하네스로 생성된 컴포넌트는 `/verify-flow --target team`으로 구조를 검증한다. 위의 eval이 *동작 품질*을 본다면 verify-flow는 *구조 규약*을 본다.

- SKL-* 규칙: 스킬 구조·토큰 예산·description 트리거 품질
- TEAM-* 규칙: 팀 구조 (팀 정의 = 오케스트레이터 스킬의 `## Team Members` 표)
- Health Score 산출

---

<a id="11-workspace"></a>

## 11. 워크스페이스 구조

```
_workspace/
├── iteration-1/
│   ├── eval-{descriptive-name}/
│   │   ├── eval_metadata.json
│   │   ├── with_skill/    (outputs/ + timing.json + grading.json)
│   │   ├── without_skill/ (outputs/ + timing.json + grading.json)
│   │   └── blind/         (A/outputs/ + B/outputs/)
│   └── benchmark.json
├── iteration-2/
│   └── ...
└── evals/evals.json
```

**규칙:**
- eval 디렉토리는 숫자가 아닌 **서술적 이름**을 쓴다(예: `eval-multi-page-table-extraction`).
- 각 iteration은 독립 디렉토리로 보존하고 이전 회차를 덮어쓰지 않는다.
- `_workspace/`는 삭제하지 않는다 — 사후 검증·감사 추적용.
