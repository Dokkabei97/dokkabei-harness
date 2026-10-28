# 샤드 설계 · 대량 색인 (ES-SHD / ES-IDX)

> 적용 전 확인: 클러스터 버전(`GET /`), 배포 형태(self-managed / ECK / Cloud / Serverless), 인덱스 성격(append-only 시계열 vs 갱신형 카탈로그).
> 수치는 Elastic 공식 문서 기준이며 "출발점"이다 — 최종 값은 실측(Rally, `_nodes/stats`)으로 정한다.

### ES-SHD-01 · 샤드 크기는 10–50GB, 샤드당 문서 2억 미만이 출발점
- 적용: 모든 버전. 검색 위주 인덱스, ILM rollover 를 쓰는 시계열 모두
- 신호: `GET _cat/shards?v&h=index,shard,prirep,store,docs&s=store:desc` 에서 1GB 미만 샤드가 다수(과샤딩) 또는 100GB+ 샤드(복구·재배치 수십 분)
- 메커니즘: 샤드마다 고정 오버헤드(세그먼트 메타, 매핑, 스레드 태스크)가 있고 검색은 샤드당 1 태스크 → 작은 샤드 다수는 fan-out·coordinating 머지 비용만 키운다. 큰 샤드는 복구/재배치/force merge 시간이 선형 증가
- 처방: 프라이머리 수 = ceil(예상 프라이머리 용량 / 30~50GB). 시계열은 rollover `max_primary_shard_size: 50gb`(+ `min_primary_shard_size: 10gb`)
- 반례: 검색 지연이 극도로 민감한 작은 카탈로그(수 GB)는 1 프라이머리 + 레플리카 다수가 더 빠를 수 있음. 50GB 는 상한 가이드지 목표치가 아니다
- 검증: Rally 로 프라이머리 1/2/4 비교, `_cat/shards` 크기 분포
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/size-shards

### ES-SHD-02 · Lucene 문서 상한 2,147,483,519 는 docs.count + docs.deleted 기준
- 적용: 대형 append 인덱스, nested 를 많이 쓰는 인덱스
- 신호: `_cat/indices` 의 docs.count 가 `_count` 보다 훨씬 큼(nested 숨은 문서 포함), 색인 시 `number of documents in the index cannot exceed` 에러
- 메커니즘: 상한은 Lucene 문서 기준이라 nested 객체 1개 = 숨은 문서 1개, 삭제되었지만 머지되지 않은 문서도 포함. `_count` API 는 이를 보여주지 않는다
- 처방: nested 배열이 큰 인덱스는 `_cat/indices`/`_cat/shards` 의 docs 로 용량 계획. rollover 조건에 `max_primary_shard_docs` 사용
- 반례: 없음(하드 리밋)
- 검증: `GET _cat/shards?h=index,shard,docs` vs `GET idx/_count`
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/size-shards

### ES-SHD-03 · 노드당 비-frozen 샤드 1,000 개 하드 리밋, 마스터는 인덱스 3,000개당 힙 1GB
- 적용: 8.x/9.x (`cluster.max_shards_per_node` 기본 1000)
- 신호: 인덱스 생성 실패 `this action would add [x] shards, but this cluster currently has [y]/[z] maximum normal shards open`; 일자별 인덱스 × 다수 샤드 구성
- 메커니즘: 샤드 수가 클러스터 상태 크기와 마스터 작업량을 키운다. 리밋을 올리는 것은 증상 억제일 뿐
- 처방: 일자 인덱스 → rollover/데이터 스트림, 소형 인덱스 병합, 프라이머리 수 축소(`_shrink`). 리밋 상향은 임시 조치로만
- 반례: frozen 티어는 별도 한도(노드당 3,000)
- 검증: `GET _cluster/stats?filter_path=indices.shards`, `GET _cat/allocation?v`
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/size-shards

### ES-SHD-04 · `total_shards_per_node` 로 핫 인덱스를 분산하면 노드 장애 시 미할당이 된다
- 적용: 핫 인덱스 쏠림을 막으려고 `index.routing.allocation.total_shards_per_node` 를 쓰는 경우
- 신호: 노드 1대 장애/롤링 재시작 후 클러스터 yellow/red 가 풀리지 않음, `_cluster/allocation/explain` 에 `shards_limit` decider
- 메커니즘: 하드 제약이라 (샤드 수 / 남은 노드 수) > 한도가 되는 순간 재할당 불가
- 처방: 한도 = ceil(총 샤드 / (노드 수 − 허용 장애 노드 수)) 로 여유를 둔다. 가능하면 샤드 수를 노드 수의 배수로 맞춰 자연 분산
- 반례: 노드 여유가 충분한 대형 클러스터에서는 유효한 도구
- 검증: 스테이징에서 노드 1대 제거 후 `GET _cluster/health`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/total-shards-per-node

### ES-SHD-05 · 레플리카는 검색 처리량을 "공짜로" 늘리지 않는다 — 색인 작업도 복제된다
- 적용: document replication(self-managed/ECK/Cloud Hosted). Serverless(stateless)는 별개
- 신호: 레플리카를 늘렸는데 p99 개선 없음 + 색인 처리량 하락, CPU 포화
- 메커니즘: 각 레플리카는 문서를 다시 분석·색인한다(세그먼트 복사가 아님). 노드 CPU/캐시가 이미 포화면 레플리카 추가는 파일시스템 캐시를 샤드 간에 나눠 오히려 느려질 수 있다
- 처방: 노드를 늘릴 때 레플리카를 늘린다. 레플리카 수 ≥ 1 은 가용성용, 그 이상은 측정 후
- 반례: 노드가 충분히 남고 검색 CPU 가 병목인 경우는 효과 있음
- 검증: `GET _nodes/stats/thread_pool/search,write`, Rally 로 replicas 1↔2 비교
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed

### ES-SHD-06 · 커스텀 routing 은 샤드 핫스팟을 만든다 — `routing_partition_size` 로 완화
- 적용: 테넌트/판매자 ID 로 `_routing` 하는 멀티테넌트 인덱스
- 신호: `_cat/shards` 크기 편차가 수 배, 특정 노드만 write/search 큐 상승
- 메커니즘: 동일 routing 값은 항상 1 샤드 → 대형 테넌트가 한 샤드에 몰림
- 처방: 인덱스 생성 시 `index.routing_partition_size`(기본 1, 생성 시에만 설정 가능)를 2 이상으로 → routing 값이 샤드 부분집합으로 퍼진다(대신 join 필드 불가, `_routing` required). 초대형 테넌트는 전용 인덱스로 분리
- 반례: 테넌트 크기가 균일하고 검색이 항상 단일 테넌트면 기본 routing 이 fan-out 절감 효과가 더 큼
- 검증: `_cat/shards` 크기 분산, 테넌트별 문서 수 상위 1% 비중
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/index-modules

### ES-IDX-01 · `refresh_interval` 을 명시하면 search-idle 최적화가 꺼진다
- 적용: Elastic Stack (기본 1s, Serverless 기본 5s). `index.search.idle.after` 기본 30s
- 신호: 템플릿에 `"refresh_interval": "1s"` 를 "기본값이니까" 명시. 검색이 드문 색인 전용 인덱스인데 세그먼트가 초당 생성
- 메커니즘: refresh_interval 이 **미설정**일 때만 30s 동안 검색이 없는 샤드는 백그라운드 refresh 를 건너뛴다. 기본값과 같은 값이라도 명시하면 opt-out
- 처방: 특별한 이유 없으면 템플릿에서 `refresh_interval` 키를 제거. 실시간성이 덜 중요하면 `30s` 등으로 늘림
- 반례: idle 샤드의 첫 검색은 refresh 를 기다리므로 지연이 생긴다 — "드문 검색이지만 즉시 응답" 요구면 명시가 맞다
- 검증: `GET idx/_settings?include_defaults=true&filter_path=**.refresh_interval`, `_cat/segments` 생성 속도
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/index-modules

### ES-IDX-02 · 초기 적재는 `refresh_interval: -1` + `number_of_replicas: 0`, 끝나면 반드시 복원
- 적용: 신규 인덱스 풀 적재, 재색인(alias 스왑 전)
- 신호: 풀 리인덱스가 몇 시간, 적재 중 세그먼트 수천 개
- 메커니즘: refresh 마다 작은 세그먼트 생성 + 머지 비용, 레플리카는 동일 색인 작업을 반복
- 처방: 적재 전 두 설정 변경 → 적재 → `refresh_interval` 원복(키 제거 권장, ES-IDX-01) → replicas 원복 → green 대기 후 alias 스왑. 레플리카 0 동안 노드 장애 = 데이터 손실이므로 소스(Kafka 오프셋/Iceberg 스냅샷)를 재처리 가능하게 유지
- 반례: 라이브 트래픽을 받는 인덱스에 적용 금지
- 검증: 적재 처리량(docs/s), `_cat/segments` 수
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/indexing-speed

### ES-IDX-03 · bulk 크기는 문서 수가 아니라 바이트로, "수십 MB" 를 넘기지 않는다
- 적용: 모든 bulk 경로(BulkIngester, Spark es-hadoop, Logstash)
- 신호: 10만 건 단위 bulk, 요청당 100MB 근접(`http.max_content_length` 기본 100mb), 코디네이팅 노드 힙 스파이크, `circuit_breaking_exception`
- 메커니즘: bulk 는 코디네이팅 노드에서 메모리에 올라가 샤드별로 쪼개진다. 너무 크면 in-flight/parent 브레이커, 너무 작으면 요청 오버헤드
- 처방: 100 → 200 → 400 … 으로 두 배씩 늘리며 처리량 정체 지점 탐색, 바이트 상한은 수 MB~수십 MB. 클라이언트에서 바이트 기준 flush(BulkIngester `maxSize`)
- 반례: 문서가 매우 큰(수백 KB) 경우 건수 기준은 무의미 — 바이트만 본다
- 검증: 동시성 고정 후 크기만 바꾼 처리량 곡선, `_nodes/stats/breaker`
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/indexing-speed

### ES-IDX-04 · bulk 는 샤드별로 쪼개진다 — 많은 샤드에 흩어진 bulk 는 샤드당 배치가 작다
- 적용: 다수 인덱스/샤드로 보내는 혼합 bulk(멀티테넌트, 다수 alias)
- 신호: bulk 크기를 늘려도 처리량이 안 오름, write 스레드풀 태스크 수가 bulk 요청 수의 수십 배
- 메커니즘: 코디네이팅 노드가 bulk 를 대상 샤드별 하위 요청으로 분할 → 샤드당 실질 배치 = bulk 크기 / 대상 샤드 수
- 처방: 대상 인덱스(가능하면 routing)별로 버퍼를 나눠 bulk 를 구성. 샤드 수가 과도하면 ES-SHD-01 로 축소
- 반례: 샤드 수가 적으면 무의미
- 검증: `GET _nodes/stats/thread_pool/write` completed 증가량 / bulk 요청 수
- 근거: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-bulk (Bulk API 동작), https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/indexing-speed

### ES-IDX-05 · 요청마다 `refresh=true` 는 초소형 세그먼트 공장 — `wait_for` 를 쓴다
- 적용: 저장 직후 조회해야 하는 API(관리자 화면 등), 통합 테스트 코드가 프로덕션으로 새는 경우
- 신호: 코드의 `Refresh.True`/`refresh=true`, `_cat/segments` 에 수 KB 세그먼트 다수, 머지 스레드 상시 바쁨
- 메커니즘: `true` 는 요청마다 즉시 refresh 를 강제. `wait_for` 는 다음 정기 refresh 까지 응답만 대기해 세그먼트를 늘리지 않는다
- 처방: 프로덕션 경로는 `Refresh.WaitFor` 또는 read-your-write 가 필요 없도록 설계. 테스트는 `indices().refresh()` 를 테스트 코드에서만
- 반례: `wait_for` 는 `refresh_interval: -1` 인 인덱스에서 사실상 무한 대기가 될 수 있음(대기 요청이 `index.max_refresh_listeners` 를 넘으면 강제 refresh)
- 검증: `GET idx/_stats/refresh` 의 total 증가율
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/refresh-parameter

### ES-IDX-06 · 자체 `_id` 는 색인마다 존재 확인 비용 — auto id 와 트레이드오프
- 적용: append-only(로그·이벤트) vs 갱신형(상품) 판단
- 신호: append-only 인데 UUID v4 를 `_id` 로 지정, 색인 처리량 정체
- 메커니즘: 명시 `_id` 는 같은 샤드에 동일 id 가 있는지 조회해야 한다(버전 맵/terms 조회). auto-generated id 는 이 확인을 건너뛴다. 무작위 UUID 는 terms 사전 지역성도 나쁘다
- 처방: append-only 는 auto id. 갱신·멱등이 필요하면 비즈니스 키를 `_id` 로(ES-ING-01), 가능하면 순차성 있는 키
- 반례: 재시도 시 중복이 치명적인 경로에서 auto id 는 중복 문서를 만든다(ES-ING-02)
- 검증: 동일 데이터 auto id vs 명시 id Rally 비교
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/indexing-speed

### ES-IDX-07 · 같은 문서를 자주 update 하는 카운터 패턴은 삭제 문서·머지 비용으로 돌아온다
- 적용: 조회수/재고/좋아요 같은 고빈도 부분 갱신
- 신호: `_cat/indices?h=index,docs.count,docs.deleted` 에서 deleted 비율이 상시 높음, 머지 I/O 지속, update 지연
- 메커니즘: Lucene 은 in-place 갱신이 없다. partial update 도 `_source` 전체를 읽어 재색인 = 기존 문서 삭제 표시 + 새 문서 추가
- 처방: 고빈도 수치는 외부 저장소(Redis 등)에 두고 주기 배치로 반영하거나, 랭킹 신호면 별도 인덱스/`rank_feature` 로 분리해 갱신 빈도를 낮춘다
- 반례: 갱신 빈도가 분 단위 이하로 낮으면 문제없음
- 검증: `GET idx/_stats/indexing,merge` 의 merge total_time, docs.deleted 추이
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/update-document (update = reindex)

### ES-IDX-08 · 대량 적재 중 인덱싱 버퍼는 샤드당 512MB 이상 줘도 효과 없음
- 적용: `indices.memory.index_buffer_size`(기본 힙 10%, 노드의 활성 샤드가 공유)
- 신호: 적재 노드에 활성 샤드가 많아 샤드당 버퍼가 작음 → 작은 세그먼트 flush 빈발
- 메커니즘: 버퍼는 노드 단위로 활성 색인 샤드에 분배. 샤드당 512MB 를 넘으면 일반적으로 개선 없음
- 처방: 적재 노드의 동시 활성 샤드 수를 줄이거나 버퍼 비율 상향(정적 설정, 재시작 필요)
- 반례: 검색과 함께 쓰는 노드에서 버퍼 상향은 힙 압박
- 검증: `GET _nodes/stats/indices/segments` 의 index_writer_memory, flush 빈도
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/indexing-speed

### ES-IDX-09 · `translog.durability: async` 는 마지막 `sync_interval`(기본 5s) 만큼의 확인된 쓰기를 잃을 수 있다
- 적용: 적재 속도를 위해 async 로 바꾼 인덱스
- 신호: 설정에 `index.translog.durability: async` 가 상시 유지
- 메커니즘: 기본 `request` 는 요청 응답 전에 translog fsync. async 는 주기 fsync 라 크래시 시 이미 200 을 받은 쓰기가 사라질 수 있다
- 처방: 재처리 가능한 일회성 적재에서만 사용하고 완료 후 `request` 로 복원
- 반례: 소스에서 언제든 재생 가능한(Kafka 오프셋 보존) 파이프라인이면 수용 가능
- 검증: `GET idx/_settings?include_defaults=true&filter_path=**.translog`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/translog
