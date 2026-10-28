# kNN 쿼리 · 필터 · 하이브리드 · 임베딩 (VEC-QRY / VEC-HYB / VEC-EMB)

> 적용 전 확인: kNN 을 top-level `knn` 섹션으로 쓰는지 `knn` 쿼리로 쓰는지, retriever 사용 여부, 임베딩 모델과 그 사용 규약(접두어·정규화), 질의 임베딩 지연.

### VEC-QRY-01 · `num_candidates` 기본 1.5×k(최대 10,000), k 기본 = size — 재현율 노브는 num_candidates
- 적용: knn 쿼리/섹션(최신 문서 기준; 구버전은 필수 파라미터였음)
- 신호: `num_candidates == k` 로 고정, 재현율 불만을 k 를 키워 해결하려 함
- 메커니즘: 샤드마다 num_candidates 개 근사 후보를 탐색해 상위 k 를 고른다. 후보가 많을수록 재현율↑ 지연↑
- 처방: exact 결과 대비 recall@k 곡선을 그려 num_candidates 를 정한다(예: k 의 2~10배 구간 탐색). 양자화 인덱스는 oversample(VEC-IDX-02)과 함께
- 반례: 10,000 초과 불가 — 그 이상 필요하면 설계(필터·샤드) 재검토
- 검증: exact(script_score) 대비 recall@k, 지연
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-knn-query

### VEC-QRY-02 · bool `filter` 는 kNN 의 post-filter — 필터는 knn 의 `filter` 에 넣어야 k 개가 보장된다
- 적용: 카테고리·권한·지역 조건이 있는 벡터 검색
- 신호: 필터를 걸었더니 결과가 k 보다 적음(심하면 1~2건), 필터가 좁을수록 0건
- 메커니즘: knn 의 `filter` 는 근사 탐색 **중** 적용되는 pre-filter. 쿼리 트리의 다른 필터(bool filter 등)는 상위 k 를 뽑은 **뒤** 적용되는 post-filter. alias 필터도 pre-filter 로 적용된다
- 처방: 권한·카테고리 조건은 knn `filter` 로. 텍스트 쿼리와 함께라면 retriever/하이브리드 구조에서 각 하위 검색에 필터를 동일하게 적용
- 반례: 필터가 대부분의 문서를 통과시키는 경우 성능 특성이 다를 수 있다(버전별 post-filter 전환 설정 문서 확인)
- 검증: 필터 조합별 반환 건수·recall 테스트
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-knn-query

### VEC-QRY-03 · 아주 좁은 pre-filter 는 HNSW 를 비효율적으로 만든다 — 극단적 선택도는 exact 검색이 낫다
- 적용: 테넌트·사용자 단위로 필터되는 벡터 검색
- 신호: 필터가 좁을수록 kNN 지연이 오히려 증가
- 메커니즘: 그래프 탐색 중 필터를 통과하는 이웃이 적으면 더 많은 노드를 방문한다. Lucene 은 방문 비용이 필터 대상 수를 넘으면 exact 검색으로 전환하지만, 그 전까지 비용이 커질 수 있다
- 처방: 필터 결과가 작게 보장되는 쿼리는 `script_score` exact 검색(필터로 후보 축소 후)으로 명시 분기. 대형 테넌트는 별도 인덱스·routing
- 반례: 선택도가 중간 이상이면 근사 kNN pre-filter 가 맞다
- 검증: 필터 선택도 구간별 지연 곡선(approx vs exact)
- 근거: https://www.elastic.co/docs/solutions/search/vector/knn, https://lucene.apache.org/core/9_0_0/core/org/apache/lucene/search/KnnVectorQuery.html

### VEC-QRY-04 · `similarity` 파라미터는 점수가 아니라 원시 유사도 기준 — boost·정규화된 _score 로 임계값을 잡지 않는다
- 적용: kNN `similarity` 임계값으로 "충분히 비슷한 것만" 반환
- 신호: 임계값을 `_score` 분포를 보고 정했는데 결과가 비거나 너무 많음
- 메커니즘: similarity 는 벡터 원시 유사도(예: cosine 값)와 비교되고 boost 는 그 뒤에 적용된다. _score 는 similarity 함수별 변환(예: cosine 은 (1+cos)/2)이 들어간 값
- 처방: 임계값은 원시 유사도 스케일로, 모델·similarity 별로 검증셋에서 정한다
- 반례: 없음
- 검증: 검증셋의 원시 유사도 분포
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-knn-query, https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/dense-vector

### VEC-QRY-05 · nested 벡터(청크) kNN 은 `score_mode=max` 만 — 문서 점수 = 가장 비슷한 청크
- 적용: 문서를 청크로 나눠 nested `dense_vector` 로 색인
- 신호: "청크 평균 유사도" 를 기대한 설계
- 메커니즘: nested kNN 은 부모 문서별 최고 청크 점수만 사용. nested 메타데이터 필터의 pre-filter 지원은 9.2 GA
- 처방: 평균/합 같은 집계가 필요하면 애플리케이션 재정렬. 청크 수는 nested 비용(ES-MAP-07)과 함께 제한. `inner_hits` 로 매칭 청크 반환
- 반례: 없음
- 검증: 청크 매칭 결과 샘플 검토
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-knn-query

### VEC-HYB-01 · `query` + top-level `knn` 을 함께 주면 점수는 단순 합 — BM25 스케일이 벡터 점수를 압도한다
- 적용: retriever 없이 한 요청에 query 와 knn 을 함께 쓰는 하이브리드
- 신호: 하이브리드인데 사실상 BM25 순위, boost 숫자를 계속 조정
- 메커니즘: 두 점수가 합산되는데 BM25 는 상한이 없고 질의마다 스케일이 다르며 벡터 점수는 0~1 근처
- 처방: 순위 기반 융합(`rrf` retriever) 또는 정규화 후 가중합(linear 계열 retriever — 지원 버전 문서 확인). 융합 방식 변경은 `_rank_eval` 로 판단
- 반례: 벡터를 "보조 부스트" 로만 쓰는 의도적 설계는 합산도 가능 — 질의별 스케일 변동을 감수
- 검증: 질의셋에서 BM25 단독·kNN 단독·융합 nDCG 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/reciprocal-rank-fusion, https://www.elastic.co/docs/reference/elasticsearch/rest-apis/retrievers

### VEC-HYB-02 · RRF 의 `rank_window_size` 가 페이지 상한이자 융합 품질 노브
- 적용: `rrf` retriever(rank_constant 기본 60, rank_window_size 기본 size)
- 신호: 2페이지 빈 결과, 한쪽 리스트에만 있는 좋은 문서가 window 밖으로 잘림
- 메커니즘: 각 하위 retriever 에서 window 만큼만 가져와 융합 → window 밖 문서는 존재하지 않는 것과 같다
- 처방: window = 최대 페이지 깊이 이상, 하위 retriever 의 후보 수(num_candidates 포함)도 window 이상으로. sort/rescore/scroll 은 불가(ES-RNK-03)
- 반례: 너무 큰 window 는 하위 검색 비용 증가
- 검증: window 별 nDCG·지연
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/reciprocal-rank-fusion

### VEC-EMB-01 · ELSER 는 영어 전용 — 한국어 시맨틱 검색은 다국어 dense 모델
- 적용: 한국어 코퍼스에 semantic/sparse 검색 도입 검토
- 신호: ELSER 를 한국어 데이터에 적용 후 품질 미달
- 메커니즘: ELSER(학습 희소 표현)는 영어 어휘로 학습됨
- 처방: 다국어 dense 임베딩(예: Elastic 제공 multilingual E5 계열 또는 외부 모델)을 inference 엔드포인트/애플리케이션에서 사용, BM25(nori)와 하이브리드
- 반례: 영어 문서 비중이 높은 코퍼스
- 검증: 한국어 질의셋 nDCG 비교
- 근거: https://www.elastic.co/docs/explore-analyze/machine-learning/nlp/ml-nlp-elser

### VEC-EMB-02 · E5 계열 모델은 `query: ` / `passage: ` 접두어 규약 — 빠뜨리면 재현율이 조용히 떨어진다
- 적용: multilingual-e5 등 접두어 규약이 있는 모델
- 신호: 질의·문서 모두 접두어 없이 임베딩, 또는 한쪽만 적용
- 메커니즘: 모델이 비대칭 검색을 위해 접두어로 학습되어, 규약을 어기면 분포가 어긋난다. 에러는 나지 않는다
- 처방: 색인 파이프라인과 질의 임베딩 코드에 모델 카드 규약을 상수로 고정하고 테스트로 보장. 모델 교체 시 전체 재임베딩(차원·분포 변화) + 새 인덱스
- 반례: 접두어 규약이 없는 모델
- 검증: 접두어 유무 recall 비교
- 근거: https://huggingface.co/intfloat/multilingual-e5-large

### VEC-EMB-03 · 질의 임베딩 지연이 검색 지연의 대부분일 수 있다 — 헤드 질의 캐시와 타임아웃 폴백
- 적용: 검색 요청마다 외부/내부 추론으로 질의 벡터 생성
- 신호: ES `took` 은 20ms 인데 API 응답은 수백 ms, 추론 서버 장애 시 검색 전면 장애
- 메커니즘: 임베딩 호출이 동기 직렬 경로에 있다
- 처방: 정규화한 질의 문자열 기준 임베딩 캐시(헤드 질의 비중 큼), 짧은 타임아웃 후 BM25 단독 폴백, 차원 축소 모델 검토(검색 비용은 차원에 선형)
- 반례: 저 QPS 내부 도구
- 검증: 구간별 지연 분해(임베딩/ES/후처리)
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search (차원과 속도)
