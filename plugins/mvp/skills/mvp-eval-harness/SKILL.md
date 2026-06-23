---
name: mvp-eval-harness
description: "MVP 제품 검증(평가) 하니스 표준 — '검증된 코드 ≠ 검증된 제품' 간극을 메우는 규약. PRD 성공지표가 모델 품질(F1·정확도·관련성)에 의존할 때, 결정론 회귀 게이트(Fake 주입)와 분리된 평가 경로를 두는 방법: 골든셋 구축 기준(층화·held-out·현실성), @pytest.mark.eval 분리(기본 skip), report.json 스키마, gate-eval.sh 소프트 게이트 계약, 임계값=PRD 정본 원칙. eval-engineer가 평가 하니스를 구축할 때, /mvp-eval 실행 시, gate-eval.sh 실패를 진단할 때 참조."
---

# MVP 제품 검증(평가) 하니스 표준

> **검증된 코드(verified code) ≠ 검증된 제품(validated product).**
> "7/7 passes·게이트 그린"은 코드가 명세대로 동작한다는 증명이지, 제품이 쓸 만하다는 증명이 아니다.
> LLM/모델 기반 제품에서 가장 리스크 높은 가설(분류 정확도·생성 품질·추천 적중)은
> Fake 주입 회귀 테스트로는 닿지 않는다 — 그래서 별도의 **평가 하니스**가 필요하다.

## When to Apply

- PRD `## 성공 지표`에 **모델 품질 지표**(macro F1, precision/recall, 관련성, 추천 적중률 등)가 임계값과 함께 있을 때
- 핵심 가치가 LLM/모델 출력 품질인 스토리(분류·요약·추출·생성·추천)를 완료했을 때
- Stage 4 루프 종료 후 "코드는 다 됐는데 진짜 잘 분류하나?"가 미검증으로 남았을 때
- validation.md의 최상위 리스크 가설(H1류)이 "데이터만 있으면 측정 가능"인데 아직 미측정일 때

## 핵심 원칙: 평가는 회귀와 분리한다

| | 회귀 게이트(`gate-cmd`) | 평가 하니스(eval) |
|---|---|---|
| 목적 | 코드가 명세대로 동작하는가 | 제품(모델)이 쓸 만한가 |
| 결정론 | **필수** (매 반복 그린) | 비결정 허용 |
| 비용 | 무료 (Fake/Mock 주입) | 유료 (실제 LLM 호출) |
| 빈도 | 매 스토리·매 커밋 | 온디맨드 (마일스톤) |
| 실행 | `pytest` (기본) | `pytest -m eval` / `scripts/eval.py` |

**절대 규칙**: 실제 LLM 호출을 회귀 게이트(`pytest` 기본)에 섞지 마라. 비결정·유료가 되어
루프 신뢰가 무너진다. 평가는 **추가**하는 것이지 회귀를 **대체**하는 게 아니다.

## 골든셋 기준

- **포맷**: JSONL `{"text": ..., "label": ...}`, `data/golden/` 또는 `tests/eval/fixtures/`.
- **층화(stratified)**: PRD가 지정한 클래스 분포를 따른다. 미지정 시 균형 표본.
- **현실성**: 합성만으로 채우지 말 것. 경계·애매 사례(미흡한 뒷광고 표기, 경계 욕설)를 포함해야
  지표가 의미를 갖는다. 합성 시드는 한계를 report에 명시하고 `synthetic: true` 플래그.
- **held-out**: 프롬프트 튜닝 예시 ≠ 평가셋(누수 금지).
- **크기**: PRD 명시값 우선(예: 200건). 미명시 시 클래스당 최소 20~30건.

## report.json 스키마 (gate-eval.sh 정본)

```json
{
  "metric": "macro_f1",        // PRD 주요 지표명
  "value": 0.91,                // 실측값
  "threshold": 0.88,            // PRD 임계값(정본 — 임의 하향 금지)
  "pass": true,                 // value >= threshold
  "n": 200,                     // 평가 건수
  "model": "claude-haiku-4-5",  // 실제 사용 모델
  "per_class": { "NORMAL": {"precision":0.95,"recall":0.92,"f1":0.93} },
  "confusion": [[...]],         // 혼동행렬(선택)
  "dataset": "data/golden/reviews.jsonl",
  "synthetic": false,           // 합성 데이터 여부
  "generated_at": "<stamp>",    // 스크립트가 기록
  "notes": "SPONSORED recall이 평균을 끌어내림"
}
```

`report.md`(사람용)에는 혼동행렬 + **대표 실패 사례 5건**을 함께 남긴다 — 숫자만으로는
어디를 고쳐야 할지 모른다.

## gate-eval.sh 소프트 게이트 계약

- 입력: `.planning/eval/report.json`.
- 검사: 필수 필드 존재 + `value >= threshold`(또는 `pass == true`).
- 임계값 override: `MVP_EVAL_F1_MIN` env(기본은 report의 threshold).
- **소프트 게이트**: 회귀 게이트(결정론)와 달리 평가 게이트는 데이터·모델 의존이라
  CI 차단보다 **마일스톤 판정·추적**에 쓴다. report가 아예 없으면 "미측정"으로 경고
  (= 가장 흔한 실패: 제품 가치를 한 번도 안 쟀음).

## 임계값 미달 처리

- 임계값은 **PRD 정본**이다. PASS를 만들려고 낮추지 마라.
- 미달 시 어느 클래스가 끌어내렸는지(per_class) 명시하고, PRD `## 가정/리스크` 또는
  validation의 피벗 트리거(프롬프트 강화 → 분류 축소(4→2) → 파인튜닝 검토)를 인용해 다음 행동을 제안.

## 안티패턴

- ❌ 회귀 게이트에 실제 LLM 호출 삽입 (비결정·유료화)
- ❌ 합성 데이터를 현실 데이터처럼 보고 (`synthetic` 누락)
- ❌ 임계값 임의 하향으로 PASS 조작
- ❌ "전체 정확도"만 보고하고 클래스 불균형 뒤 저조 클래스 은폐 (macro·per-class 필수)
- ❌ 프롬프트 튜닝에 쓴 예시를 평가셋에 포함 (누수)
