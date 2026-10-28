---
name: search-quality
description: |
  검색 품질 평가 설계 — 골든 질의셋, 판정 기준, _rank_eval 요청, 위치 편향을 고려한 온라인 지표.
  Designs golden sets, _rank_eval requests, and online metrics. Use when: running /search-quality.
disable-model-invocation: true
---

# /search-quality

## Usage
```
/search-quality [path] [--design-test-cases] [--rank-eval] [--online]
```
- `--design-test-cases`: 질의셋과 판정 가이드 초안 (판정 등급 0~3 또는 0~4, 등급별 예시를 도메인 데이터로)
- `--rank-eval`: `_rank_eval` 요청 JSON 생성(metric: dcg normalize / mrr / precision `ignore_unlabeled` 검토)과 unrated 문서 추가 판정 루프(ES-EVL-01)
- `--online`: 온라인 지표·실험 설계 — CTR 을 순위 비교에 직접 쓰지 않는 이유와 대안(ES-EVL-02), 질의 그룹별 보고

## Flow
1. **사실 확인** — 검색 로그/클릭 로그 존재 여부, 기존 골든셋, 대상 인덱스·쿼리 코드, 실험 플랫폼 유무. 없는 것은 "측정 공백"으로 보고.
2. **질의셋** — 로그가 있으면 빈도 구간 층화 샘플링, 없으면 도메인 시나리오 기반 + 무결과 질의 수집 계획. 한국어 특이 케이스(복합어, 조사 포함 구문, 한자, 영문 브랜드, 자모 입력) 포함.
3. **오프라인 평가** — `_rank_eval` 요청과 변경 전후 비교표. 변경이 분석기라면 `search-relevance-engineering` 의 "분석기 변경의 기본 루프" 를 따른다.
4. **온라인 평가** — 지표 정의, 최소 표본·기간은 트래픽 수치를 받아 계산(근거 없는 기본값 제시 금지).

## Output
```
## Search Quality Plan — [대상]
측정 공백: [...]
### 질의셋 (층/예시/판정 기준)
### _rank_eval 요청 JSON
### 온라인 지표·실험 설계
```

## Boundaries
- 판정 라벨을 임의로 만들어 "정답"으로 쓰지 않는다 — 라벨은 사람 판정 또는 명시된 규칙에서 나온다.
