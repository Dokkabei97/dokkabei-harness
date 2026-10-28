# 리랭킹 · 다단계 검색 · 결과 다양화 (ES-RNK)

> 적용 전 확인: ES 버전(Retriever API·`text_similarity_reranker`·LTR 지원 범위는 버전별로 다름 — 해당 버전 문서 확인), 라이선스, 추론 엔드포인트 유무, 지연 예산.

### ES-RNK-01 · "search pipeline" 은 OpenSearch 기능 — ES 에서는 retriever/rescore/애플리케이션 계층
- 적용: Elasticsearch(OpenSearch 아님)
- 신호: 설계 문서나 코드에 `PUT _search/pipeline`, request/response processor 가 등장
- 메커니즘: ES 에는 색인용 ingest pipeline 만 있고 검색 요청·응답 후처리 파이프라인 API 가 없다. 검색 후처리는 retriever 조합, rescore, 또는 애플리케이션에서
- 처방: 검색 시 변환은 Kotlin 서비스 계층(질의 재작성·결과 후처리)으로, 재정렬은 rescore/retriever 로 설계. 블로그·LLM 답변의 OpenSearch 예제를 ES 에 그대로 쓰지 않는다
- 반례: 실제로 OpenSearch 를 쓰는 프로젝트
- 검증: 대상 클러스터 `GET /` 의 distribution
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/retrievers, https://docs.opensearch.org/latest/search-plugins/search-pipelines/index/

### ES-RNK-02 · rescore `window_size`(기본 10) 는 샤드당 — 전체 후보 수는 window × 샤드 수
- 적용: query rescorer, LTR rescorer
- 신호: 샤드 수를 바꿨더니 rescore 비용·결과가 변함, `size` > `window_size` 라 하위 결과가 rescore 되지 않음
- 메커니즘: 각 샤드가 자기 상위 window_size 문서에만 2단계 점수를 적용. window 밖 문서는 1단계 점수 그대로라 순서가 섞일 수 있다
- 처방: `window_size ≥ from + size` 를 보장하고 페이지 깊이 제한. 비싼 2단계(phrase, 스크립트)는 여기로 옮긴다. 필드 정렬과 함께 쓸 수 없다(`_score` 정렬만)
- 반례: 샤드가 많으면 작은 window 도 비용이 커진다 — 샤드 수와 함께 결정
- 검증: `_profile`, 페이지 경계에서 순위 연속성 테스트
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/filter-search-results#rescore

### ES-RNK-03 · RRF 는 sort·rescore·scroll 불가, `from + size ≤ rank_window_size` 를 넘으면 결과가 비어 있다
- 적용: `rrf` retriever(`rank_constant` 기본 60, `rank_window_size` 기본 size). sub_searches 기반 RRF 는 retriever 로 대체됨
- 신호: 2페이지부터 빈 결과, RRF 에 정렬 옵션을 붙여 예외
- 메커니즘: 각 하위 retriever 에서 rank_window_size 개만 받아 순위 융합 — 그 밖의 페이지는 존재하지 않는다. 내부적으로 PIT 를 쓰므로 외부 PIT 사용도 피하라고 문서화
- 처방: 최대 페이지 깊이에 맞춰 `rank_window_size` 를 명시. 집계는 window 와 무관하게 전체 매칭 대상이라는 점을 UI 카운트와 구분
- 반례: 깊은 페이지가 필요한 목록형 화면은 RRF 대신 단일 랭킹 + search_after
- 검증: 페이지 경계 테스트
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/reciprocal-rank-fusion

### ES-RNK-04 · cross-encoder 재정렬(`text_similarity_reranker`)은 후보 수 × 추론 지연 — window 를 지연 예산에서 역산
- 적용: 추론 엔드포인트 기반 semantic rerank(지원 버전·라이선스 문서 확인)
- 신호: 리랭커 도입 후 p99 수백 ms 증가, 트래픽 피크 때 추론 엔드포인트 큐잉
- 메커니즘: 쿼리마다 후보 문서 텍스트를 모델에 넣어 점수 계산 — 비용이 후보 수와 문서 길이에 선형
- 처방: window 를 작게(수십), 입력 필드를 짧은 요약/제목으로, 헤드 쿼리 결과 캐시. 지연 예산을 1단계/2단계로 나눠 관리
- 반례: 오프라인 배치 평가나 저 QPS 내부 검색은 큰 window 허용
- 검증: window 별 지연·nDCG 곡선
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/retrievers/text-similarity-reranker-retriever

### ES-RNK-05 · `collapse` + `inner_hits` 는 그룹마다 추가 검색 — 그룹 수·동시성을 제한
- 적용: 브랜드/판매자 다양화를 collapse 로 구현
- 신호: collapse 도입 후 지연 증가, inner_hits 크기 큼
- 메커니즘: 상위 그룹마다 inner_hits 를 얻기 위해 별도 검색이 실행된다(`max_concurrent_group_searches` 로 동시성 제어)
- 처방: 그룹 대표 1건만 필요하면 inner_hits 생략, 필요 시 inner_hits size·필드 최소화. collapse 필드는 keyword/numeric + doc_values
- 반례: 그룹이 적은 페이지 크기에선 비용 미미
- 검증: `_profile`, took 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/collapse-search-results

### ES-RNK-06 · 개인화 신호를 1단계 쿼리에 넣으면 캐시·WAND 를 모두 잃는다 — 2단계로
- 적용: 사용자 선호 카테고리/브랜드 부스팅
- 신호: 모든 검색 요청 JSON 이 사용자마다 달라 request/query 캐시 hit 0, function_score 로 전체 매칭 문서 재점수
- 메커니즘: 사용자별 질의는 캐시 키가 매번 다르고, 문서별 함수 점수는 상위 K 조기 스킵을 막는다
- 처방: 1단계는 사용자 무관 랭킹(캐시 가능), 개인화는 rescore window 또는 애플리케이션 재정렬. 정적 품질 신호는 `rank_feature`(ES-QRY-08)
- 반례: 개인화가 매칭 자체를 바꿔야 하는 경우(권한·지역 필터)는 filter 로 1단계에 포함
- 검증: 캐시 hit, p99, A/B 지표
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/shard-request-cache, https://www.elastic.co/docs/reference/elasticsearch/rest-apis/filter-search-results#rescore
