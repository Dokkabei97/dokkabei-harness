---
name: mvp-eval
description: "제품 검증(평가) 실행 — '검증된 코드 ≠ 검증된 제품' 간극을 메운다. PRD 성공지표(분류 F1·정확도 등 모델 품질)를 골든셋 + 실제 LLM 호출로 실측하고, 결정론 회귀 게이트와 분리(@pytest.mark.eval)해 .planning/eval/report.json 에 기록한 뒤 gate-eval.sh 로 임계값 판정."
category: utility
complexity: advanced
mcp-servers: []
personas: []
---

# /mvp-eval - 제품 품질 실측 평가

회귀 게이트(`pytest`, Fake 주입·결정론)는 "코드가 명세대로 동작하는가"만 본다. 이 커맨드는
PRD 성공지표가 모델 품질(F1·정확도·관련성)에 의존할 때 **실제 데이터·실제 모델로 그 지표를 측정**해
"제품이 진짜 쓸 만한가"를 검증한다. `eval-engineer` 에이전트를 디스패치하고 `gate-eval.sh`로 판정한다.

> 정본: `mvp-eval-harness` 스킬. 평가는 회귀를 **대체하지 않고 추가**한다 — 결정론 회귀 스위트는 그대로 둔다.

## Triggers
- Stage 4 루프가 끝났는데 핵심 분류/생성/추천 품질이 미측정으로 남았을 때
- PRD `## 성공 지표`에 `macro F1 ≥ X` 같은 모델 품질 임계값이 있을 때
- "진짜 잘 분류해?", "정확도 재줘", "제품 품질 측정" 요청
- validation.md 최상위 리스크 가설(H1류: 정확도)을 실데이터로 닫고 싶을 때

## Usage
```
/mvp-eval [옵션]

Options:
  --dataset <path>      골든셋 경로 지정 (기본: data/golden/ 자동 탐색)
  --model <id>          평가에 사용할 모델 override
  --threshold <float>   임계값 override (MVP_EVAL_F1_MIN, 기본: PRD/report 정본)
  --build-golden        골든셋이 없으면 시드 구축(합성 포함 시 synthetic=true 표기)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/prd.md`의 `## 성공 지표`에서 모델 품질 지표·임계값을 읽는다. 없으면 평가 대상이 없으므로 중단·안내.
- 실제 모델 접근 가능 여부 확인(API 키 / 로컬 Ollama). 불가하면 골든셋·러너까지만 구축하고 측정은 보류 안내.

### Phase 1: eval-engineer 디스패치
`eval-engineer`(maker)를 호출:
1. 골든셋 구축/적재(`data/golden/*.jsonl`, 층화·held-out·현실성)
2. 평가 러너 작성 — **회귀와 분리**(`@pytest.mark.eval` + skipif, 기본 `pytest`에서 제외)
3. 실제 LLM 호출로 예측 수집 → `sklearn`으로 macro F1·per-class·혼동행렬 산출
4. `.planning/eval/report.json` + `report.md`(혼동행렬 + 실패 사례 5건) 기록

### Phase 2: gate-eval.sh 판정
- `gate-eval.sh` 실행: report 존재 + `value >= threshold` 검사.
  - exit 0 = 통과(임계값 충족) / exit 1 = 미달 / exit 2 = 미측정(report 부재)
- 결과 보고: 지표·실측값·임계값·n·model. 합성 데이터면 한계 명시.

### Phase 3: 미달 처리
- 임계값 미달 시 어느 클래스가 끌어내렸는지(per_class) 보고하고, PRD `## 가정/리스크` 또는
  validation 피벗 트리거(프롬프트 강화 → 분류 축소 → 파인튜닝)를 인용해 다음 행동 제안.
- **임계값은 PRD 정본 — 임의 하향 금지.**

## Boundaries

**Will:**
- 골든셋·평가 러너 구축, 실제 모델로 PRD 품질 지표 실측, report 기록·게이트 판정
- 회귀 게이트와 분리된 평가 경로만 추가

**Will Not:**
- 결정론 회귀 스위트 약화·대체, 회귀 게이트에 실제 LLM 호출 삽입
- PRD 임계값 임의 하향, 합성 데이터를 현실 데이터로 표기
