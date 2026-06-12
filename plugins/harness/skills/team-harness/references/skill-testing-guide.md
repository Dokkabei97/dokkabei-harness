# Skill Testing & Iteration Guide

## Test Framework Overview

스킬 품질 검증 = 정성적 평가 + 정량적 평가

| 평가 유형 | 방법 | 적합한 스킬 |
|----------|------|-----------|
| **정성적** | 사용자 직접 리뷰 | 문체, 디자인, 창작물 |
| **정량적** | Assertion 기반 자동 채점 | 파일 생성, 데이터 추출, 코드 생성 |

핵심 루프: **작성 → 테스트 실행 → 평가 → 개선 → 재테스트**

---

## Test Prompt Design

### Principles
- 실제 사용자가 입력할 법한 구체적이고 자연스러운 문장
- 추상적/인공적 프롬프트는 테스트 가치 낮음

### Coverage (2~3 prompts)
1. 핵심 사용 사례 1개
2. 엣지 케이스 1개
3. (선택) 복합 작업 1개

### Diversity
- 공식적/캐주얼 톤 혼합
- 명시적/암시적 의도 혼합
- 단순/복잡 작업 혼합

---

## With-skill vs Baseline Comparison

각 테스트에 두 서브에이전트를 **동시** 스폰:

**With-skill**: 스킬 로딩 후 동일 프롬프트 실행
**Baseline**: 스킬 없이 동일 프롬프트 실행

### Timing Data
서브에이전트 완료 알림에서 `total_tokens`와 `duration_ms`를 **즉시** 저장.
이 데이터는 알림 시점에만 접근 가능, 이후 복구 불가.

---

## Assertion-Based Grading

### Good Assertions
- 객관적으로 참/거짓 판별 가능
- 서술적 이름 (결과만 봐도 무엇을 검사하는지 명확)
- 스킬의 핵심 가치를 검증

### Bad Assertions
- 스킬 유무와 무관하게 항상 통과 (Non-discriminating)
- 주관적 판단 필요 ("잘 작성되었다")

### Grading Schema
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

## Specialized Evaluation Agents

### Grader (채점자)
- Assertion별 통과/실패 판정 + 근거
- 산출물 사실적 주장 추출/교차검증
- Eval 자체 품질 피드백

### Comparator (블라인드 비교자)
- A/B 익명화, 어떤 것이 스킬 결과인지 모르는 상태에서 판정
- 활용: "새 버전이 정말 더 나은가?" 엄밀 확인 시

### Analyzer (분석자)
- Non-discriminating assertion 탐지
- 고분산 eval 식별
- 시간/토큰 트레이드오프 분석

---

## Iteration Loop

1. 스킬 수정
2. 새 `iteration-N+1/`에 모든 테스트 재실행
3. 이전 iteration과 비교 제시
4. 피드백 수집
5. 반복

### Improvement Principles
1. **일반화**: 테스트 예시에만 맞는 수정은 오버피팅
2. **무게 제거**: 비생산적 지시는 삭제
3. **Why 반영**: 피드백의 이유를 이해하고 반영
4. **번들링**: 반복 스크립트는 `scripts/`에 포함

### Exit Conditions
- 사용자 만족
- 빈 피드백 (모든 산출물 이상 없음)
- 의미 있는 개선 여지 소진

---

## Description Trigger Verification

### 20 Eval Queries
- Should-trigger 10개 + Should-NOT-trigger 10개

### Query Quality
- 실제 사용자 입력과 유사한 구체적 문장
- 경계 케이스(edge case)에 집중
- 길이/톤/형식 다양하게

### Conflict Check
새 스킬의 should-trigger 쿼리가 기존 스킬을 잘못 트리거하지 않는지 확인.

---

## Aggregate Harness Benchmark (하네스 전체 A/B)

개별 스킬 eval(위)이 "이 스킬이 동작하나"를 본다면, 집계 벤치마크는 **"하네스 전체가 결과를 개선하나"**를 통계적으로 본다.

### 측정 절차
1. 도메인 대표 작업 **N개**(권장 10~15개)를 난이도별로 구성 (Basic/Advanced/Expert)
2. 각 작업을 **with-harness**(오케스트레이터 경유) vs **without-harness**(단일 에이전트)로 실행
3. 블라인드 Comparator가 산출물 품질을 **1~100점** 채점 + 승/패 판정
4. 집계 지표 산출

### 집계 지표
| 지표 | 의미 |
|------|------|
| **품질 델타** | with − without 평균 점수 차 |
| **승률** | with가 이긴 작업 수 / N |
| **분산 감소** | 점수 표준편차 변화 (하네스가 *일관성*을 높이는가) |
| **난이도별 효과** | Basic/Advanced/Expert별 델타 (복잡할수록 효과 큰지) |

> 통상 하네스 효과는 작업이 복잡할수록 커진다. Basic에서 델타가 작다고 실패가 아니다 — 단순 작업은 단일 에이전트로 충분하기 때문. **분산 감소**가 종종 평균 향상보다 중요하다(예측 가능성).

### 결과 기록
`{harness}-benchmark/aggregate.json` 에 작업별 점수·승패·토큰·시간을 보존하고, CLAUDE.md 하네스 변경 이력에 핵심 수치(델타·승률·분산)를 1줄로 남긴다.

---

## Integration with verify-flow

팀 하네스로 생성된 스킬은 `/verify-flow --target team`으로 검증:
- SKL-001~018 규칙: 기본 스킬 구조 검증
- TEAM-001~008 규칙: 팀 구조 검증
- Health Score 산출

---

## Workspace Structure

```
{skill-name}-workspace/
├── iteration-1/
│   ├── eval-{descriptive-name}/
│   │   ├── eval_metadata.json
│   │   ├── with_skill/
│   │   │   ├── outputs/
│   │   │   ├── timing.json
│   │   │   └── grading.json
│   │   └── without_skill/
│   │       └── (same structure)
│   └── benchmark.json
├── iteration-2/
│   └── ...
└── evals/
    └── evals.json
```

**규칙**: 서술적 이름 사용, iteration 독립 보존, 삭제 금지.
