# 색인 파이프라인 · 재색인 (ES-ING)

> 적용 전 확인: 소스 시스템(Kafka/CDC/배치 Spark·Iceberg), 이벤트에 단조 증가 버전(updated_at, 오프셋, CDC LSN)이 있는지, 삭제 이벤트 형태(tombstone), 소비자 커밋 방식. Kafka 일반 설정은 팀 컨벤션을 따르고 여기서는 ES 와 맞물리는 함정만 다룬다.

### ES-ING-01 · 순서 역전 방지는 `version_type: external` — 단, 삭제 tombstone 은 `gc_deletes`(기본 60s) 후 사라진다
- 적용: 파티션 재처리·재시도로 오래된 이벤트가 늦게 도착할 수 있는 CDC/Kafka 색인
- 신호: 가끔 이전 상태로 되돌아간 문서, 삭제했던 문서가 되살아남
- 메커니즘: external 버전은 "더 큰 버전만 반영"을 ES 가 보장(작으면 409). 그러나 삭제의 버전 기록은 `index.gc_deletes` 동안만 유지 — 그 뒤 도착한 더 오래된 index 연산은 새 문서로 받아들여져 부활
- 처방: `_id` = 비즈니스 키, `version` = 소스의 단조 증가 값, `version_type=external(_gte)`, 409 는 정상 스킵. 지연 재처리 창이 60s 를 넘으면 삭제를 soft delete(`deleted: true` + 필터) 로 바꾸거나 `gc_deletes` 를 재처리 창보다 길게
- 반례: 단일 파티션·단일 소비자로 순서가 보장되면 불필요
- 검증: 같은 키에 v2→v1 순서로 색인하는 테스트, 삭제 후 61s 뒤 구버전 색인 테스트
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/optimistic-concurrency-control, https://www.elastic.co/docs/reference/elasticsearch/index-settings/index-modules (gc_deletes)

### ES-ING-02 · auto-generated id + 재시도 = 중복 문서
- 적용: at-least-once 소비(재시도·리밸런스 재처리)
- 신호: 같은 이벤트 문서가 2건 이상, 리밸런스 직후 문서 수 증가
- 메커니즘: bulk 가 서버에서는 성공했지만 응답 유실/타임아웃이면 클라이언트가 재전송 → 새 id 로 또 생성
- 처방: 결정적 `_id`(비즈니스 키 또는 이벤트 키 해시) 사용. append-only 로그라도 중복이 문제면 이벤트 ID 기반 `_id` + `op_type: create`(이미 있으면 409 무시)
- 반례: 중복 허용 메트릭성 로그는 auto id 가 빠르다(ES-IDX-06)
- 검증: 강제 타임아웃 주입 후 문서 수 대조
- 근거: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-bulk

### ES-ING-03 · 오프셋 커밋은 bulk 아이템 결과 확인 후 — 비동기 ingester 와 auto commit 조합 금지
- 적용: Spring Kafka/Go 컨슈머 → ES
- 신호: `enable.auto.commit=true` + 비동기 BulkIngester, 장애 후 일부 이벤트 영구 누락
- 메커니즘: 커밋이 ES 반영보다 먼저 일어나면 그 사이 실패는 재처리되지 않는다
- 처방: poll 배치 → 동기 bulk → 아이템 분류(429 재시도, 4xx DLQ) → 수동 커밋(`AckMode.MANUAL`/배치 리스너). 재시도 지연 총합이 `max.poll.interval.ms` 를 넘으면 리밸런스가 나니 재시도 상한·pause 를 설계
- 반례: 유실 허용 로그성 데이터
- 검증: bulk 도중 프로세스 kill 후 재기동 → 소스 대비 문서 수 대조
- 근거: https://kafka.apache.org/documentation/#consumerconfigs_max.poll.interval.ms, https://www.elastic.co/docs/reference/elasticsearch/clients/java/usage/indexing-bulk

### ES-ING-04 · 무중단 재색인은 "alias 원자 스왑 + 스왑 구간 이중 쓰기/재생"
- 적용: 매핑·분석기 변경(ES-MAP-13), 샤드 수 변경
- 신호: 재색인 중 들어온 변경이 새 인덱스에 없음, alias 를 remove 와 add 두 번 호출
- 메커니즘: `_reindex` 는 시작 시점 스냅샷을 복사. 그 사이 변경은 별도로 반영해야 한다. alias 변경을 두 요청으로 나누면 순간적으로 대상 없음
- 처방: (1) 새 인덱스 생성(ES-IDX-02 설정) (2) 스트림 소비자를 새 인덱스에도 쓰게(또는 재색인 시작 시점 오프셋부터 재생 준비) (3) `_reindex?slices=auto&wait_for_completion=false` (4) 설정 복원·green (5) 단일 `POST _aliases` 에서 remove+add, `is_write_index` 지정 (6) 구 인덱스 보존 후 삭제. 외부 버전(ES-ING-01)을 쓰면 재생 순서 문제도 해결
- 반례: 소규모 인덱스는 소스(Iceberg/DB)에서 새로 적재하는 편이 단순
- 검증: 스왑 전후 문서 수·체크섬 샘플, 골든 쿼리 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/reindex-indices, https://www.elastic.co/docs/manage-data/data-store/aliases

### ES-ING-05 · `_source` 에서 필드를 `excludes` 로 빼면 `_reindex`·update 가 그 필드를 잃는다
- 적용: 디스크 절감용 `_source.excludes`(특히 벡터), `_source.enabled: false`
- 신호: 재색인 후 필드가 비어 있음, update API 실패
- 메커니즘: reindex/update/update_by_query 는 `_source` 를 원본으로 사용
- 처방: 벡터는 9.2+ `index.mapping.exclude_source_vectors`(재색인 시 재수화) 또는 synthetic `_source`(VEC-IDX-04). 그 외는 원본 재적재 경로(Iceberg 등)를 재색인 수단으로 확보
- 반례: 재색인을 항상 원본 소스에서 하는 아키텍처라면 수용 가능
- 검증: 테스트 인덱스에서 `_reindex` 후 필드 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/mapping-source-field, https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search

### ES-ING-06 · Spark(es-hadoop) 배치 색인의 실제 동시성 = 파티션 수 × 배치 — 클러스터를 쉽게 포화시킨다
- 적용: Spark/Iceberg → ES 대량 적재
- 신호: Spark 잡 시작 직후 ES write 스레드풀 거부·429 폭증, 잡 재시도로 악화
- 메커니즘: 각 태스크가 독립적으로 bulk 를 보낸다(`es.batch.size.entries`/`es.batch.size.bytes` 는 태스크당). executor·파티션이 많을수록 동시 bulk 가 선형 증가
- 처방: 쓰기 단계 직전 `coalesce` 로 동시 태스크를 ES 데이터 노드 처리량에 맞추고, 배치 바이트를 ES-IDX-03 범위로. 대상 인덱스는 ES-IDX-02 설정
- 반례: 소량 증분 배치
- 검증: `_cat/thread_pool/write` rejected, 잡 처리량
- 근거: https://www.elastic.co/docs/reference/elasticsearch-hadoop/configuration
