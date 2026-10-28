---
name: search-relevance-engineering
description: |
  검색 관련성·한국어 분석 허브 — 순위가 이상함·엉뚱한 결과·0건, nori 형태소(decompound_mode·사용자 사전·품사 필터), 동의어(synonym_graph·Synonyms API), 자동완성(edge_ngram·자모), BM25·multi_match·minimum_should_match, 점수 흔들림(샤드 IDF·preference), rescore·RRF·리랭커, _rank_eval·CTR 평가. 증상에서 ID 붙은 함정 항목(KO-*/ES-REL/ES-RNK/ES-EVL)으로 안내한다.
  Hub for search relevance and Korean (nori) text analysis. Use when: ranking looks wrong or unstable, designing analyzers or synonyms, Korean autocomplete, tuning BM25/multi_match, reranking with rescore/RRF/cross-encoder, or evaluating search quality.
---

# Search Relevance Engineering (관련성·한국어 분석 허브)

이 스킬은 **트리아지 인덱스**다. 증상 → 레퍼런스 경로와 항목 ID 만 담고, 지식은 `references/` 항목(적용/신호/메커니즘/처방/반례/검증/근거)에 있다.
성능·매핑·클러스터는 `es-deep-patterns`, 벡터·하이브리드는 `vector-hybrid-search-patterns` 허브로.

## 0. 먼저 확인할 사실 (단정 금지)

- 실제 분석기 정의: `GET idx/_settings?filter_path=**.analysis` 와 매핑의 `analyzer`/`search_analyzer` — 저장소의 템플릿 JSON 이 원본이다.
- 사용자 사전·동의어의 위치(파일/inline/Synonyms API)와 배포 방식.
- 품질 판단 근거: 골든셋(`_rank_eval` 요청 파일), 클릭 로그, A/B 체계가 있는지. 없으면 "측정 없는 튜닝" 임을 먼저 밝힌다.
- 프로젝트 CLAUDE.md·`.claude/rules` 의 도메인 규칙(브랜드 사전, 금칙어 등)이 이 허브보다 우선.

## 1. 증상 → 레퍼런스

| 증상 / 질문 | 먼저 볼 곳 | 이어서 |
|---|---|---|
| 특정 문서가 안 나옴(0건) | `_analyze` × `_termvectors` 비교 (es-deep-patterns 의 diagnostics.md "무결과") | KO-ANA-01/03, ES-MAP-13 |
| 복합어·브랜드명 검색 품질 | `korean-analysis.md` KO-ANA-01/03 | KO-SYN-02 |
| 구문(phrase) 검색이 한국어에서 안 맞음 | KO-ANA-02 | ES-REL-06 |
| 동의어 추가·갱신 | KO-SYN-01~03 | — |
| 자동완성·초성·입력 중 자모 | KO-AC-01/02 | ES-MAP-10 |
| 무관 결과가 너무 많음 | `scoring-relevance.md` ES-REL-05 | ES-QRY-04 (es-deep-patterns) |
| 순위가 환경·새로고침마다 다름 | ES-REL-01/02 | LUC-SEG-02 |
| 짧은 제목·태그가 과대평가 | ES-REL-04 | — |
| 여러 필드에 걸친 질의 | ES-REL-03 | — |
| 인기도·평점 부스트 | ES-QRY-08/09 (es-deep-patterns) | ES-RNK-06 |
| 2단계 재정렬·리랭커·RRF | `reranking.md` ES-RNK-* | VEC-HYB-* (벡터 허브) |
| 품질 측정·A/B | ES-EVL-01/02 | — |

## 2. 분석기 변경의 기본 루프

1. 대표 질의 20~50개(헤드/토르소/테일, 한영 혼용·모델명·오타 포함)를 고정하고 현재 결과를 `_rank_eval` 로 기록한다.
2. 후보 분석기를 **새 인덱스**에 정의하고 `_analyze`(`explain: true`)로 색인/검색 토큰을 비교한다.
3. 샘플 재색인 → 같은 질의셋으로 `_rank_eval` 비교, unrated 문서 추가 판정(ES-EVL-01).
4. 운영 반영은 재색인 + alias 원자 스왑(es-deep-patterns ES-MAP-13, ES-ING-04). search-time 동의어만이면 `updateable` 리로드.

## 3. 사용법

- 증상으로 파일을 고르고 해당 ID 만 읽는다. 항목의 **적용** 조건을 0절 사실과 대조한다.
- 제안은 **ID + 근거가 된 `_analyze`/`_explain` 출력 + 처방 + 검증 지표**로. 품질 개선 주장은 측정(골든셋/A/B) 없이는 "가설"로 표기한다.
- 프로젝트별로 유효한 ID 는 `workflow:project-rules` 로 규칙 파일에 선별해 두는 것을 권장한다.

## 4. 항목 인덱스

| ID | 함정 | 파일 |
|---|---|---|
| KO-ANA-01 | nori `decompound_mode` 기본은 `discard` — 원형이 사라진다 | korean-analysis |
| KO-ANA-02 | 품사 필터(`nori_part_of_speech`)로 조사를 지우면 위치 간격이 남는다 — phrase 에는 slop 필요 | korean-analysis |
| KO-ANA-03 | nori 사용자 사전은 리로드되지 않는다 — 색인 분석기에 쓰면 재색인까지 | korean-analysis |
| KO-ANA-04 | `discard_punctuation` 기본 true — 모델명·버전 문자열이 쪼개진다 | korean-analysis |
| KO-ANA-05 | 커스텀 analyzer 로 `nori_tokenizer` 를 쓰면 `nori_readingform`·`lowercase` 를 직접 넣어야 한다 | korean-analysis |
| KO-SYN-01 | `synonym_graph` 는 검색 분석기 전용 — 다중어 동의어를 색인 시점에 쓰면 위치가 깨진다 | korean-analysis |
| KO-SYN-02 | 동의어 규칙 자체가 앞단 토크나이저로 분석된다 — nori 가 규칙 문자열을 쪼갠다 | korean-analysis |
| KO-SYN-03 | Synonyms API 세트는 인덱스보다 먼저 존재해야 하고, `lenient: false` 의 잘못된 규칙은 인덱스를 못 열게 한다 | korean-analysis |
| KO-AC-01 | 한글 자동완성은 음절 edge_ngram 만으로 부족 — 입력 중 자모("검ㅅ")를 처리하려면 자모 분해 필드 | korean-analysis |
| KO-AC-02 | edge_ngram 은 색인 분석기에만 — 검색 분석기까지 n-gram 하면 무관 결과 폭증 | korean-analysis |
| ES-REL-01 | IDF 는 샤드 로컬 — 작은 인덱스·테스트 인덱스에서 순위가 샤드 배치에 좌우된다 | scoring-relevance |
| ES-REL-02 | 같은 쿼리라도 프라이머리/레플리카에서 점수가 다르다 — 사용자별 `preference` 로 고정 | scoring-relevance |
| ES-REL-03 | `cross_fields`/`combined_fields` 는 analyzer 가 같은 필드끼리만 하나로 묶인다 | scoring-relevance |
| ES-REL-04 | 짧은 필드(상품명·태그)는 길이 정규화가 노이즈 — 필드별 `b` 조정 또는 norms 제거 | scoring-relevance |
| ES-REL-05 | `minimum_should_match` 없는 한국어 `match` 는 OR — 분해된 형태소 하나만 맞아도 나온다 | scoring-relevance |
| ES-REL-06 | 다중값 필드 phrase 는 `position_increment_gap`(기본 100) 때문에 값 경계를 넘지 못한다 | scoring-relevance |
| ES-EVL-01 | `_rank_eval` 에서 라벨 없는 문서는 기본으로 무관 처리 — 골든셋 커버리지를 함께 본다 | scoring-relevance |
| ES-EVL-02 | 클릭률은 위치 편향의 함수 — 순위 변경 효과를 CTR 로 직접 비교하지 않는다 | scoring-relevance |
| ES-RNK-01 | "search pipeline" 은 OpenSearch 기능 — ES 에서는 retriever/rescore/애플리케이션 계층 | reranking |
| ES-RNK-02 | rescore `window_size`(기본 10) 는 샤드당 — 전체 후보 수는 window × 샤드 수 | reranking |
| ES-RNK-03 | RRF 는 sort·rescore·scroll 불가, `from + size ≤ rank_window_size` 를 넘으면 결과가 비어 있다 | reranking |
| ES-RNK-04 | cross-encoder 재정렬(`text_similarity_reranker`)은 후보 수 × 추론 지연 — window 를 지연 예산에서 역산 | reranking |
| ES-RNK-05 | `collapse` + `inner_hits` 는 그룹마다 추가 검색 — 그룹 수·동시성을 제한 | reranking |
| ES-RNK-06 | 개인화 신호를 1단계 쿼리에 넣으면 캐시·WAND 를 모두 잃는다 — 2단계로 | reranking |

## 5. 관련 컴포넌트

- 커맨드(사용자 호출): `/search-quality`(골든셋·지표 설계), `/es-mapping-review`(분석기 점검 포함).
- 에이전트: `search-relevance-engineer` — 이 스킬과 벡터 허브를 사전 로드한다.
