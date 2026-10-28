# 쿼리 · 집계 (ES-QRY / ES-AGG)

> 적용 전 확인: 실제 요청 JSON(Kotlin 빌더면 `toString()`/`JsonpUtils` 로 직렬화해 확인), ES 버전, 대상 인덱스 샤드 수. 성능 주장은 `_profile` 상대 비교로만.

### ES-QRY-01 · filter 컨텍스트는 노드 쿼리 캐시 대상이지만, 조건이 까다롭다
- 적용: 8.x/9.x. `indices.queries.cache.size` 기본 힙 10%, 최대 10,000 쿼리
- 신호: "filter 로 바꿨는데 캐시 히트가 0" — `GET _nodes/stats/indices/query_cache` hit_count 정체
- 메커니즘: filter 컨텍스트 쿼리만 대상이고 `term` 쿼리는 캐시 대상이 아니다(Lucene `UsageTrackingQueryCachingPolicy` 가 TermQuery 를 "충분히 싸다" 며 never-cache 로 분류). 세그먼트 단위로 캐시하며 세그먼트가 10,000 문서 이상이고 샤드 문서의 3% 이상일 때만. 쿼리 사용 이력을 추적해 반복된 것만 캐시. refresh 로 새 세그먼트가 생기면 그 세그먼트는 다시 채워야 한다
- 처방: 스코어 불필요 조건은 `filter`(스코어 계산 제거 효과는 캐시와 무관하게 유효). 캐시 효과를 기대한다면 같은 필터를 정규화된 형태로 재사용하고 시간 범위는 반올림(ES-QRY-02)
- 반례: 고유값 필터(사용자 ID 등)는 캐시 오염만 시킴
- 검증: `_nodes/stats/indices/query_cache` hit/miss/evictions, `_profile`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/node-query-cache-settings (세그먼트 조건), https://github.com/apache/lucene/blob/main/lucene/core/src/java/org/apache/lucene/search/UsageTrackingQueryCachingPolicy.java (TermQuery never-cache·사용 이력 기반 캐시)

### ES-QRY-02 · `now` range 의 반올림(`now-7d/d`)은 노드 쿼리 캐시만 살린다 — request cache 는 절대 시각으로
- 적용: 최근 N 시간/일 필터, 대시보드성 집계(`size=0`)
- 신호: `"gte": "now-7d"` 가 그대로 → query_cache hit 정체. `now-7d/d` 로 반올림했는데도 request_cache hit 0
- 메커니즘: 반올림 없는 `now` 는 매 요청 값이 달라 노드 쿼리 캐시(세그먼트 단위 필터 캐시)가 같은 필터로 인식하지 못한다 — `/d`·`/m` 반올림이면 같은 필터가 재사용된다. 반면 shard request cache 는 요청에 `now` 가 남아 있으면 반올림 여부와 무관하게 대부분 캐시 대상에서 제외된다("Most queries that use `now` cannot be cached")
- 처방: (a) 쿼리 캐시: `now-7d/d`·`now-1h/m` 반올림. 정밀 경계가 필요하면 `bool` 로 [반올림 범위 filter] ∩ [정밀 범위] 분리(과분할은 오히려 느림). (b) request cache 까지 노리는 집계: 클라이언트가 반올림한 절대 시각(`"gte": "2026-10-21T00:00:00Z"`)을 계산해 보내 요청에서 `now` 를 없앤다 — 같은 반올림 구간의 요청은 바디가 같아져 캐시 키가 일치(ES-QRY-03)
- 반례: 초 단위 정확성이 요구되는 경로. 클라이언트 반올림은 타임존 기준(UTC vs 로컬 일 경계)을 서버 쪽 `time_zone` 사용과 맞춰야 한다
- 검증: (a) `GET _nodes/stats/indices/query_cache` hit/miss, (b) 같은 집계를 반복 호출하며 `GET idx/_stats/request_cache` hit_count 증가 확인
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed, https://www.elastic.co/docs/reference/elasticsearch/rest-apis/shard-request-cache

### ES-QRY-03 · shard request cache 는 기본 `size=0` 만, refresh 마다 무효화, 키는 JSON 바디 해시
- 적용: 집계 대시보드, 카운트 API, 자동완성 카테고리 집계
- 신호: 같은 집계인데 hit 없음 — 클라이언트가 JSON 키 순서를 매번 다르게 직렬화하거나 hits 를 함께 요청
- 메커니즘: 기본으로 `size=0` 요청의 hits.total·aggregations·suggest 만 캐시. 전체 JSON 바디 해시가 키라 키 순서만 달라도 미스. 샤드 refresh 시 무효화 → refresh 가 잦은 인덱스는 효과 낮음
- 처방: 집계용 요청은 `size: 0` 분리, 직렬화 순서 고정, 필요 시 `request_cache=true`. 갱신 잦은 인덱스는 `refresh_interval` 완화와 함께
- 반례: 비결정적 스크립트(`Math.random()`)·`now` 포함 요청은 캐시 불가
- 검증: `GET _nodes/stats/indices/request_cache`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/shard-request-cache

### ES-QRY-04 · `filter`/`must` 가 있는 bool 의 `should` 는 기본 선택 사항이 된다
- 적용: 모든 버전의 bool 쿼리
- 신호: "should 조건이 하나도 안 맞는 문서도 나온다" — filter 로 카테고리 제한 + should 로 키워드 매칭
- 메커니즘: `minimum_should_match` 기본은 `must`/`filter` 가 없으면 1, 있으면 0. 즉 should 는 점수 가산용으로만 동작
- 처방: should 중 최소 1개 매칭이 필요하면 `minimum_should_match: 1` 명시
- 반례: 순수 부스팅 목적이면 기본 동작이 의도와 맞다
- 검증: `_explain` 으로 매칭 근거 확인, `_validate/query?rewrite=true`
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-bool-query

### ES-QRY-05 · `track_total_hits` 기본 10,000 — `true` 로 바꾸면 WAND 조기 스킵이 꺼진다
- 적용: 7.0+ (기본 정확 카운트 상한 10,000)
- 신호: 프론트의 "총 N건" 표시 때문에 `track_total_hits: true` 상시 사용, 히트가 많은 쿼리에서 지연
- 메커니즘: 상위 K 만 필요하면 Lucene 은 block-max WAND 로 경쟁력 없는 문서를 건너뛴다. 정확한 총계를 요구하면 모든 매칭 문서를 방문해야 한다
- 처방: UI 는 "10,000+" 표기, 정확 카운트가 필요한 화면만 별도 `_count`/`size:0` 요청
- 반례: 정산·관리 화면처럼 정확 총계가 업무 요구
- 검증: 같은 쿼리 `track_total_hits` true/false `took` 비교
- 근거: https://www.elastic.co/docs/solutions/search/the-search-api (track_total_hits)

### ES-QRY-06 · PIT + `search_after` 의 숨은 비용 — 열린 PIT 는 세그먼트를 붙잡고, tiebreaker 는 `_shard_doc` 이 이미 있다
- 적용: PIT 7.10+. `index.max_result_window`(기본 10,000)를 넘는 순회·export
- 신호: 페이지마다 PIT/scroll 을 새로 열거나 `keep_alive` 를 수십 분으로 둠, 끝난 PIT 미삭제, tiebreaker 용 고유 필드를 별도로 추가해 정렬
- 메커니즘: PIT 를 쓰면 정렬 끝에 `_shard_doc` 이 암묵 tiebreaker 로 붙어 별도 고유 필드가 필요 없다. 열린 PIT/scroll 은 생성 시점 세그먼트를 참조해 머지된 구 세그먼트가 디스크에서 지워지지 않는다(LUC-SEG-03)
- 처방: PIT 하나로 순회하고 `keep_alive` 는 "다음 페이지 요청까지" 만큼 짧게(요청마다 연장), 완료 시 `DELETE _pit`. 사용자-facing 무한 스크롤은 깊이 제한(예: 100페이지)이 제품적으로 더 낫다
- 반례: 처음 몇 페이지만 보는 일반 검색은 from/size 가 단순하고 충분
- 검증: `GET _nodes/stats/indices/search?filter_path=**.open_contexts`, 디스크 사용량 추이
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/paginate-search-results

### ES-QRY-07 · 스크립트를 문자열 결합으로 만들면 컴파일 한도(기본 150/5m)에 걸린다
- 적용: painless `script_score`, script 필터/정렬/집계
- 신호: `[script] Too many dynamic script compilations within, max: [150/5m]` (circuit_breaking_exception), 코드에서 `"doc['x'].value * $weight"` 같은 문자열 보간
- 메커니즘: 소스 문자열이 다르면 별개 스크립트로 컴파일·캐시. 값이 바뀔 때마다 새 컴파일
- 처방: 값은 `params` 로 전달하고 소스는 고정(가능하면 stored script). `doc[...]`(doc values) 사용, `params._source` 접근 회피
- 반례: 한도 상향(`script.max_compilations_rate`)은 원인 은폐
- 검증: `GET _nodes/stats/script` 의 compilations, cache_evictions
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/circuit-breaker-settings, https://www.elastic.co/docs/explore-analyze/scripting/scripts-search-speed

### ES-QRY-08 · 정적 랭킹 신호는 `function_score` 대신 `rank_feature` — WAND 를 살린다
- 적용: 인기도·평점·판매량 부스트
- 신호: `function_score` + `field_value_factor` 가 모든 검색에 걸림, 매칭이 많은 쿼리에서 지연
- 메커니즘: function_score 는 매칭된 모든 문서의 점수를 계산해야 해 상위 K 조기 스킵이 어렵다. `rank_feature` 쿼리는 Lucene feature 필드로 색인되어 최대 점수 기반 스킵이 가능
- 처방: 매핑 `rank_feature`(값이 클수록 좋음이 기본, 반대면 `positive_score_impact: false`), 쿼리 `should` 에 `rank_feature`(saturation/log/sigmoid)
- 반례: 사용자별 개인화처럼 문서 고정값이 아닌 신호, 복잡한 결합식은 rescore 로(ES-RNK 참조)
- 검증: `took` p50/p99 비교, `_rank_eval` 로 품질 동등성 확인
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-rank-feature-query

### ES-QRY-09 · `field_value_factor` 의 `log` 는 값 0~1 에서 음수 점수 → 에러, `log1p` 를 쓴다
- 적용: 7.0+ (음수 점수 거부)
- 신호: 간헐적 `script_score/function_score ... negative score` 에러, 신규 상품(값 0)에서만 실패
- 메커니즘: log(0)=-∞, log(0.5)<0. ES 는 음수 점수를 허용하지 않는다. `missing` 미지정 시 필드 없는 문서도 에러
- 처방: `modifier: log1p`/`log2p`, `missing: 1` 명시, `boost_mode` 를 의도대로(기본 multiply 라 0 이면 원 점수 소멸)
- 반례: 없음
- 검증: 값 0·필드 없음 문서로 `_explain`
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-function-score-query

### ES-QRY-10 · terms 쿼리 65,536개 한도·regex 길이 1,000 — 큰 ID 목록은 terms lookup 또는 구조 변경
- 적용: `index.max_terms_count` 기본 65536, `index.max_regex_length` 기본 1000
- 신호: 블랙리스트/권한 ID 수만 개를 쿼리에 직접 삽입, 요청 바디 수 MB
- 메커니즘: 거대 terms 는 파싱·rewrite·네트워크 비용이 매 요청 발생하고 캐시 효율도 낮다
- 처방: 권한 집합은 문서 쪽에 그룹 키를 색인(역방향), 또는 `terms` lookup(다른 인덱스 문서의 배열 참조)
- 반례: 수백 개 수준은 문제없음
- 검증: `_profile` rewrite_time
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/index-modules

### ES-QRY-11 · 하이라이트는 `index.highlight.max_analyzed_offset`(기본 1,000,000자)에서 실패 — offsets 를 색인
- 적용: 긴 본문(약관·문서) 하이라이트
- 신호: `The length of [field] field ... has exceeded [1000000]` 에러, fetch phase 지연
- 메커니즘: offsets 가 없으면 unified highlighter 가 본문을 다시 분석
- 처방: `index_options: offsets` 또는 `term_vector: with_positions_offsets`(디스크 증가), 쿼리에 `max_analyzed_offset` 지정해 잘라서 하이라이트, `fragment_size`/`number_of_fragments` 제한
- 반례: 짧은 필드는 offsets 비용이 이득보다 큼
- 검증: `_profile` fetch breakdown
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/highlighting

### ES-QRY-12 · 인덱스가 많을 때 pre-filter(can_match) 라운드트립이 샤드를 건너뛴다 — 시간 필터를 필수로
- 적용: 다수 인덱스(시계열 alias/와일드카드) 검색. 샤드 128개 초과·읽기 전용 인덱스·인덱스된 필드 기반 1차 정렬이면 자동 실행(`pre_filter_shard_size`)
- 신호: 응답 `_shards.skipped` 가 0, 과거 인덱스 전부에 쿼리 전파
- 메커니즘: can_match 단계가 각 샤드의 min/max 값으로 매칭 불가능한 샤드를 건너뛴다 — 필터가 `filter` 컨텍스트의 range 일 때 효과가 크다
- 처방: 시간 범위를 항상 filter 로 포함, 오래된 인덱스는 read-only 로 전환
- 반례: 단일 인덱스 검색엔 무관
- 검증: 응답 `_shards.skipped`
- 근거: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-search (pre_filter_shard_size)

### ES-QRY-13 · 샤드 실패·타임아웃에도 200 — 부분 결과가 조용히 재현율·집계 카운트를 깎는다
- 적용: 모든 버전. `search.default_allow_partial_search_results` 기본 `true`
- 신호: 응답의 `_shards.failed > 0`·`_shards.failures[]`·`timed_out: true` 를 클라이언트가 읽지 않음, 특정 시점에만 집계 합계·검색 결과 수가 줄어듦
- 메커니즘: 일부 샤드가 실패하거나(노드 이탈·브레이커·쿼리 오류) timeout 에 걸려도 나머지 샤드 결과로 HTTP 200 을 돌려준다. hits·aggregations 는 빠진 샤드만큼 작아지지만 상태 코드로는 구분되지 않는다
- 처방: 클라이언트 공통 래퍼에서 `shards().failed() > 0`(Kotlin/Java) 또는 `_shards.failed`(Go 디코딩) 와 `timed_out` 을 검사해 메트릭·로그를 남긴다. 정합성이 필요한 경로(정산·카운트·export)는 요청에 `allow_partial_search_results=false` 를 줘 실패를 에러로 받는다
- 반례: 사용자-facing 검색은 저하된 결과가 무응답보다 낫다 — 허용하되 계측만
- 검증: 장애 주입(한 노드 정지·샤드 하나에만 실패하는 쿼리)으로 `_shards.failed` 와 앱 메트릭이 함께 오르는지 확인
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/search-settings, https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-search (allow_partial_search_results)

### ES-AGG-01 · terms 집계는 근사치 — `shard_size` 기본 `size*1.5+10`, `_count: asc` 는 오차 무한
- 적용: 멀티 샤드 인덱스의 상위 N 버킷
- 신호: 샤드 수를 바꾸면 Top N 순위가 달라짐, `doc_count_error_upper_bound` > 0
- 메커니즘: 각 샤드가 자기 상위 shard_size 만 보고 코디네이터가 합산 → 샤드별로 고르게 분포하지 않은 term 은 누락/과소집계. 오름차순 정렬은 오차를 정확히 보고할 수도 없다
- 처방: 정확도가 중요하면 `shard_size` 상향 + `show_term_doc_count_error: true` 로 모니터링, 희소 term 탐색은 `rare_terms`, 전체 버킷 순회는 `composite` 페이지네이션
- 반례: 단일 샤드 인덱스는 정확
- 검증: shard_size 를 크게 한 결과와 비교, `doc_count_error_upper_bound`
- 근거: https://www.elastic.co/docs/reference/aggregations/search-aggregations-bucket-terms-aggregation

### ES-AGG-02 · 고카디널리티 terms 집계의 "첫 쿼리만 느림" = global ordinals 지연 빌드 — eager 는 refresh 로 비용 이동
- 적용: keyword terms 집계, 갱신이 잦은 인덱스
- 신호: refresh 후 첫 집계만 수백 ms~수 초, `_profile` 에 안 보이고 took 만 큼
- 메커니즘: global ordinals 는 샤드 단위로 refresh 후 첫 사용 때 생성(기본 lazy). `eager_global_ordinals: true` 면 refresh 시점에 미리 생성
- 처방: 집계가 핫한 필드만 eager. 동시에 `refresh_interval` 을 늘려 재빌드 빈도를 줄인다. 매칭 문서가 매우 적은 쿼리엔 `execution_hint: map`
- 반례: eager 는 refresh 를 느리게 하고 힙을 쓴다 — 집계가 드문 필드엔 손해
- 검증: `GET _nodes/stats/indices/fielddata?fields=*`(global ordinals 메모리), refresh 시간
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/eager-global-ordinals

### ES-AGG-03 · `cardinality` 는 HyperLogLog++ — `precision_threshold` 기본 3,000, 최대 40,000, 메모리 ≈ 임계값×8바이트
- 적용: UV/고유 사용자 수 집계
- 신호: "정확한 고유 수"를 기대한 비교/정산 로직, 버킷 수 × precision_threshold 로 메모리 폭증
- 메커니즘: 임계값 이하에선 거의 정확, 이상에선 근사. 버킷마다 sketch 를 가짐
- 처방: 근사 허용 지표로만 사용, 중첩 버킷 아래에선 임계값을 낮춤. 정확값은 사전 집계(transform/배치)
- 반례: 소규모 데이터의 정확 카운트는 `terms` + 버킷 수로도 가능
- 검증: 샘플 구간 정확값과 오차 비교, `_nodes/stats/breaker` request
- 근거: https://www.elastic.co/docs/reference/aggregations/search-aggregations-metrics-cardinality-aggregation

### ES-AGG-04 · 버킷 상한 `search.max_buckets`(기본 65,536) 는 중첩 곱으로 터진다 — composite 로 순회
- 적용: 카테고리 × 브랜드 × 일자 같은 중첩 집계
- 신호: `too_many_buckets_exception`, request 브레이커(기본 힙 60%) 트립
- 메커니즘: 중첩 terms 의 버킷 수는 곱으로 증가하고 코디네이터에 전부 모인다
- 처방: `composite` + `after_key` 로 페이지 순회, 상위 수준만 terms, 나머지는 필요한 버킷에 대해 후속 쿼리. 범위 버킷이 자주 쓰이면 색인 시 미리 계산한 keyword(`price_range`)로 terms
- 반례: 한도 상향은 힙을 담보로 한 임시 조치
- 검증: `_profile` aggregation `debug.total_buckets`(존재 시), breaker 통계
- 근거: https://www.elastic.co/docs/reference/aggregations/search-aggregations-bucket-composite-aggregation, https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed
