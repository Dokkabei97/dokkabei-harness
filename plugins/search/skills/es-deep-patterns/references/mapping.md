# 매핑 설계 (ES-MAP)

> 적용 전 확인: 실제 매핑(`GET idx/_mapping`), 인덱스 템플릿/컴포넌트 템플릿, 어떤 필드가 검색·정렬·집계·표시 중 무엇에 쓰이는지(쿼리 코드 grep). 필드 용도표 없이 타입을 고르지 않는다.

### ES-MAP-01 · 숫자형 식별자는 `keyword` — 숫자 타입의 term 조회는 BKD 경로라 느리다
- 적용: 상품ID·회원ID·카테고리코드처럼 숫자처럼 생겼지만 range 조회를 하지 않는 필드
- 신호: `long`/`integer` 필드에 `term`/`terms` 필터만 사용, `_profile` 에서 `PointInSetQuery`/`PointRangeQuery`
- 메커니즘: 숫자 필드는 points(BKD) 로 색인되어 range 에 최적화. 정확 일치 조회는 inverted index(terms dict) 인 keyword 가 대체로 빠르고 필터 캐시 재사용도 좋다
- 처방: `keyword` 로 매핑. range 도 필요하면 multi-field(`id` keyword + `id.num` long)
- 반례: 범위 조회·수치 정렬·수치 집계가 주 용도면 숫자 타입 유지
- 검증: 같은 terms 필터 `_profile` 비교, Rally
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed

### ES-MAP-02 · keyword 의 Lucene term 상한은 32,766 바이트 — 한글은 약 1만 자에서 색인 실패
- 적용: `ignore_above` 없이 명시 매핑한 keyword(동적 매핑 기본은 `ignore_above: 256`)
- 신호: bulk item 에러 `Document contains at least one immense term`, 긴 URL/본문이 keyword 로 들어감
- 메커니즘: 상한은 UTF-8 **바이트**, `ignore_above` 는 **문자 수** 기준. 한글 1자 = 3바이트라 10,922자에서 터진다. `ignore_above` 를 넘는 값은 에러 없이 색인·doc_values 에서 빠진다(검색·집계 불가, `_source` 에만 남음)
- 처방: 용도에 맞는 `ignore_above`(예: 256~1024) 명시. 긴 문자열 정확 일치가 필요하면 해시 필드를 따로 둔다
- 반례: `ignore_above` 를 넘긴 문서가 "검색 안 됨" 이슈의 원인이 되기도 함 — 상한을 너무 낮게 잡지 말 것
- 검증: `_termvectors`/`terms` 집계로 긴 값 존재 확인, bulk 에러 로그
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/ignore-above

### ES-MAP-03 · 동적 매핑의 문자열 = `text` + `keyword` 이중 색인 — 프로덕션은 `dynamic_templates` 로 고정
- 적용: 명시 매핑 없이 문서를 넣는 인덱스, 로그성 필드
- 신호: 매핑에 `fields.keyword` 가 대량 자동 생성, 디스크가 예상의 1.5~2배
- 메커니즘: 동적 문자열은 기본으로 full-text 와 keyword(ignore_above 256) 를 모두 만든다
- 처방: `dynamic_templates` 에서 `match_mapping_type: string` → 용도별(keyword 기본, 특정 패턴만 text) 지정. 검색 인덱스는 `dynamic: strict`(오타 필드를 즉시 거부)
- 반례: 탐색적 로그 분석 인덱스에서는 기본 동작이 편할 수 있음
- 검증: `GET idx/_mapping` 필드 수, `POST idx/_disk_usage?run_expensive_tasks=true` 필드별 용량
- 근거: https://www.elastic.co/docs/manage-data/data-store/mapping/dynamic-templates

### ES-MAP-04 · 매핑 폭발 — 필드 1,000개 한도 상향 대신 `flattened` 나 key-value 구조로
- 적용: 사용자 정의 속성·상품 옵션처럼 키가 열린(open-ended) 객체. `index.mapping.total_fields.limit` 기본 1000
- 신호: `Limit of total fields [1000] has been exceeded`, 매핑 업데이트로 마스터 pending task 증가, 클러스터 상태 비대
- 메커니즘: 새 필드마다 마스터를 거치는 매핑 갱신이 일어나고 모든 노드에 전파. 필드 수는 힙·클러스터 상태 비용
- 처방: (a) `flattened` — 전체 객체를 키별 keyword 로 1 필드에 색인, (b) `[{key, value}]` nested 구조, (c) 검색 안 할 객체는 `enabled: false`. 한도 상향은 최후 수단. 동적 필드를 버리고 문서는 받으려면 `index.mapping.total_fields.ignore_dynamic_beyond_limit: true`(기본 false; 지원 버전 문서 확인)
- 반례: `flattened` 는 모든 값을 keyword 로 다룬다 — 숫자 range 가 사전식 비교, 분석·하이라이트 불가. 수치 필터가 필요한 키는 명시 필드로 승격
- 검증: `GET idx/_mapping` 필드 수 추이, `GET _cluster/pending_tasks`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/mapping-limit, https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/flattened

### ES-MAP-05 · `index: false` 와 `enabled: false` 는 다르다
- 적용: 표시 전용 필드, 원본 보관용 객체
- 신호: 표시용 필드가 기본 매핑으로 색인·doc_values 생성 → 디스크 낭비
- 메커니즘: `index: false` 는 inverted index/points 만 끔 — doc_values 는 남아 정렬·집계 가능하고, keyword/숫자/날짜는 doc_values 기반의 느린 조회도 가능. `enabled: false` 는 객체 필드에만 쓰며 파싱 자체를 건너뛰어 `_source` 에만 존재(검색·집계 불가)
- 처방: 표시만 → `enabled: false`(객체) 또는 `index: false, doc_values: false`(스칼라). 가끔 필터 → `index: false` 유지(doc_values 조회). copy_to 원천 필드는 `index: false` 로 색인 중복 제거
- 반례: 나중에 검색이 필요해지면 reindex 필요
- 검증: `_disk_usage` 필드별 inverted_index/doc_values 바이트
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/mapping-index, https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/enabled

### ES-MAP-06 · `text` 필드 `fielddata: true` 는 힙 폭탄 — 집계·정렬은 keyword 서브필드로
- 적용: text 필드를 정렬/terms 집계에 쓰려는 코드
- 신호: `Fielddata is disabled on [field]` 에러를 매핑 변경으로 "해결"한 이력, `GET _cat/fielddata?v` 에 큰 값, fielddata 브레이커(기본 힙 40%) 트립
- 메커니즘: fielddata 는 분석된 토큰 전체를 힙에 역색인 → 디스크 기반 doc_values 와 달리 힙 상주
- 처방: `fields.raw: keyword` 서브필드로 집계/정렬. 형태소 단위 키워드 통계가 필요하면 `significant_text`(샘플링) 또는 색인 시 별도 keyword 배열 생성
- 반례: 소규모·저카디널리티 텍스트의 일회성 분석은 허용 가능
- 검증: `GET _nodes/stats/indices/fielddata`, `_nodes/stats/breaker`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/text#fielddata-mapping-param, https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/circuit-breaker-settings

### ES-MAP-07 · nested 객체 1개 = Lucene 숨은 문서 1개, 부모 갱신 시 전부 재색인
- 적용: 옵션/SKU/리뷰 배열을 nested 로 둔 상품 문서
- 신호: SKU 수백 개 nested, 재고 1건 변경에 문서 전체 재색인, `nested` 쿼리 지연. 문서당 nested 객체 상한 `index.mapping.nested_objects.limit` 기본 10,000
- 메커니즘: nested 는 블록 조인(같은 세그먼트에 연속 저장). 하나만 바뀌어도 블록 전체 삭제+재색인. 쿼리는 부모-자식 비트셋 조인 비용
- 처방: 배열 요소 내 필드 간 상관(같은 옵션의 색상=빨강 AND 사이즈=L)이 필요할 때만 nested. 아니면 object(평탄화) 또는 조합 키(`color_size: "red_L"`) keyword. 자주 바뀌는 자식은 별도 인덱스
- 반례: 요소 간 상관 조건이 핵심이면 nested 가 정답 — 대신 요소 수를 제한
- 검증: `_cat/indices` docs.count vs `_count`, nested 쿼리 `_profile`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/nested, https://www.elastic.co/docs/reference/elasticsearch/index-settings/mapping-limit

### ES-MAP-08 · 비정규화 대비 nested 는 수 배, join(부모-자식)은 수백 배 느릴 수 있고 join 은 global ordinals 를 refresh 마다 만든다
- 적용: `join` 필드를 쓰는 인덱스
- 신호: `has_child`/`has_parent` 지연, refresh 시간 증가, 힙의 global ordinals 사용량
- 메커니즘: 자식과 부모가 같은 샤드에 있어야 해서 routing 강제. 조인에 global ordinals 를 쓰며 join 필드는 기본 eager 로딩 → refresh 마다 재구성
- 처방: 비정규화가 1순위, 그다음 nested, join 은 자식이 부모보다 훨씬 많고 자식 갱신이 매우 잦을 때만
- 반례: 자식 문서가 독립적으로 고빈도 갱신되는 구조(예: 재고)에서는 join 이 재색인 비용을 아껴 줌
- 검증: `GET _nodes/stats/indices/fielddata?fields=*` 의 global ordinals, `_profile`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/parent-join, https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed

### ES-MAP-09 · 필터 전용 text 는 `norms: false`, 스코어 불필요 필드는 `index_options: docs`
- 적용: 매칭만 하고 BM25 길이 정규화가 의미 없는 필드(태그 텍스트, 내부 코드 설명)
- 신호: 필드 수가 많은 인덱스의 디스크/힙에서 norms 비중
- 메커니즘: norms 는 필드×문서당 1바이트(디스크·캐시). positions 는 phrase 쿼리용이라 phrase 를 안 쓰면 낭비
- 처방: 스코어링 안 하면 `norms: false`; phrase/하이라이트 안 쓰면 `index_options: freqs` 또는 `docs`
- 반례: positions 를 지우면 `match_phrase` 가 에러. 나중에 phrase 가 필요해지면 reindex
- 검증: `_disk_usage` 의 norms/postings
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/norms, https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/index-options

### ES-MAP-10 · 부분 일치(`*abc*`) 요구는 `wildcard` 필드 타입이나 n-gram 으로 — keyword 에 leading wildcard 금지
- 적용: 코드·URL·로그 문자열의 중간 일치 검색
- 신호: `wildcard`/`query_string` 에 `*abc` 패턴, keyword 필드 `_profile` 에서 rewrite 비용 폭증
- 메커니즘: keyword 의 leading wildcard 는 terms dict 전체를 automaton 으로 훑는다. `wildcard` 필드는 n-gram 색인 + 바이너리 doc values 검증으로 설계됨
- 처방: 중간 일치 → `wildcard` 타입. 접두 일치 → keyword `prefix` 또는 text `index_prefixes`. 자동완성 → `search_as_you_type`/edge_ngram. `search.allow_expensive_queries: false` 로 실수 차단 검토
- 반례: `wildcard` 타입은 고카디널리티·짧은 값에서 keyword 보다 디스크·정확 일치가 불리할 수 있음
- 검증: 같은 패턴 `_profile` 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/keyword#wildcard-field-type, https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-wildcard-query

### ES-MAP-11 · index sorting 은 생성 시에만 — 정렬이 지배적인 쿼리의 조기 종료·결합 쿼리 가속
- 적용: 대부분의 쿼리가 같은 필드 정렬(최신순 등)이거나 저카디널리티 필터 결합이 많은 인덱스
- 신호: 최신순 정렬 + 큰 매칭 집합에서 query phase 지연
- 메커니즘: 세그먼트 내 문서를 정렬 순서로 저장 → 요청 정렬이 인덱스 정렬과 같고 `track_total_hits: false` 면 세그먼트당 상위 N 이후 수집 중단. 결합(conjunction) 쿼리도 빨라진다
- 처방: `index.sort.field`/`index.sort.order` 를 생성 시 지정, 쿼리에 `track_total_hits: false`
- 반례: 색인 처리량이 떨어지고(정렬 비용) 사후 변경 불가. 정렬이 다양하면 효과 없음
- 검증: 동일 쿼리 `took`, `_profile` collector
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/sorting, https://www.elastic.co/docs/reference/elasticsearch/index-settings/sorting-conjunctions

### ES-MAP-12 · 고정값 필터는 인덱스 분리 + `constant_keyword` 로 필터 자체를 제거
- 적용: 문서 타입/국가/채널 등 소수 값으로 인덱스를 나눌 수 있는 경우
- 신호: 모든 쿼리에 `term: {doc_type: "x"}` 필터
- 메커니즘: `constant_keyword` 는 인덱스 내 모든 문서가 같은 값 → 일치하면 match_all, 불일치면 샤드를 건너뜀(can_match)
- 처방: 값별 인덱스 + `constant_keyword` 매핑, alias 로 묶어 조회
- 반례: 값이 많으면 인덱스 수 폭증(ES-SHD-03)
- 검증: `_profile`, `_shards.skipped`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/keyword (constant_keyword)

### ES-MAP-13 · 분석기 변경은 기존 문서를 다시 분석하지 않는다 — 새 인덱스 + alias 스왑
- 적용: analyzer/tokenizer/사용자 사전/필드 타입 변경
- 신호: 매핑 변경 후 "새 문서만 검색됨", 테스트 문서와 운영 문서 결과 상이
- 메커니즘: 색인 시점 분석 결과가 세그먼트에 고정. search_analyzer 만 바꾼 경우 색인 토큰과 어긋나 무결과
- 처방: 새 인덱스 생성 → `_reindex`(slices=auto, ES-IDX-02 설정) → 검증 → 단일 `_aliases` 호출에서 remove+add 원자 스왑. 애플리케이션은 항상 alias 로 접근
- 반례: search-time 전용 필터(동의어 `updateable`)만 바뀌면 `_reload_search_analyzers` 로 충분(KO-SYN 참조)
- 검증: `_analyze` 로 신/구 토큰 비교, 골든 쿼리 `_rank_eval`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/reindex-indices, https://www.elastic.co/docs/manage-data/data-store/aliases
