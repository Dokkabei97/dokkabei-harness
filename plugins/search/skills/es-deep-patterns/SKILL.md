---
name: es-deep-patterns
description: |
  Elasticsearch·Lucene 스페셜리스트 트리아지 허브 — 느린 쿼리·타임아웃·p99 튐, 샤드 크기·개수, 대량 색인(refresh·replicas·bulk), 매핑 폭발·keyword/doc_values·nested, terms 집계 오차, 깊은 페이지네이션, force merge·세그먼트, JVM 힙·서킷 브레이커·429, Kotlin/Java·Go 클라이언트·BulkIngester/BulkIndexer, 샤드 부분 실패, Kafka→ES 색인. 증상에서 ID 붙은 함정 항목으로 안내한다.
  Specialist triage hub for Elasticsearch/Lucene performance, mapping, indexing, cluster ops and the Kotlin/Java and Go clients. Use when: an ES query is slow or times out, sizing shards, bulk indexing, reviewing mappings, heap/circuit breaker/429 errors, or ES client and Kafka-to-ES ingestion issues.
---

# Elasticsearch Deep Patterns (ES/Lucene 스페셜리스트 허브)

이 스킬은 **트리아지 인덱스**다. 본문은 증상 → 레퍼런스 경로와 항목 ID 목록만 담고, 실제 지식은 `references/` 의 항목에 있다.
항목은 "강한 시니어 제너럴리스트도 놓칠 법한" 함정만 모았다 — 각 항목은 `적용 / 신호 / 메커니즘 / 처방 / 반례 / 검증 / 근거` 를 가진다.
관련성·한국어 분석은 `search-relevance-engineering`, 벡터·하이브리드는 `vector-hybrid-search-patterns` 허브로.

## 0. 먼저 프로젝트 사실을 확인한다 (단정 금지)

항목을 적용하기 전에 아래를 **코드·설정에서 확인**하고, 확인 못 한 것은 가정이라고 밝힌다.

| 확인 대상 | 어디서 |
|---|---|
| ES 서버 버전(8.x/9.x), 배포 형태(self-managed/ECK/Cloud/Serverless) | 프로젝트 CLAUDE.md·`.claude/rules`, 인프라 코드, `GET /` |
| 클라이언트·버전·트랜스포트 | `build.gradle.kts`/`go.mod`, Spring Boot 관리 버전 |
| 인덱스 템플릿·매핑·alias 전략 | 저장소의 템플릿 JSON, 마이그레이션 스크립트 |
| 색인 소스(Kafka/CDC/배치) 와 커밋 방식 | 컨슈머 설정·리스너 코드 |
| 팀 컨벤션(리뷰 태그, 레이어 규칙) | 프로젝트 CLAUDE.md — 이 허브보다 우선 |

프로젝트별로 어떤 ID 가 유효한지는 `workflow:project-rules` 로 프로젝트 규칙 파일에 선별해 두는 것을 권장한다(이 허브는 범용 레이어).

## 1. 증상 → 레퍼런스

| 증상 / 질문 | 먼저 볼 곳 | 이어서 |
|---|---|---|
| 쿼리 느림·timeout·p99 튐 | `references/diagnostics.md` (증상→API 시퀀스) | query-aggregation, segments-lucene, jvm-cluster-ops |
| 검색 결과 누락·0건 | diagnostics.md "무결과" | ES-MAP-02, ES-MAP-13, (관련성 허브) KO-ANA-* |
| 순위·점수 이상, 레플리카마다 점수 다름 | diagnostics.md "오정렬" | LUC-SEG-02, (관련성 허브) ES-REL-* |
| 샤드 몇 개? 크기? 노드 쏠림 | `shards-indexing.md` ES-SHD-* | jvm-cluster-ops ES-OPS-* |
| 대량 색인·재색인이 느림 | shards-indexing.md ES-IDX-* | ingest-pipeline ES-ING-04/06, segments-lucene LUC-SEG-04 |
| 매핑 설계·리뷰, 필드 폭발 | `mapping.md` ES-MAP-* | — |
| 집계 결과가 샤드 수에 따라 다름 / 버킷 초과 | `query-aggregation.md` ES-AGG-* | — |
| 깊은 페이지네이션, scroll/PIT | ES-QRY-06 | LUC-SEG-03 |
| 결과·집계 수가 가끔 줄어듦(200 인데) | ES-QRY-13 | ES-CLI-03/11 |
| 디스크가 안 줄어듦, force merge 여부 | `segments-lucene.md` LUC-SEG-* | ES-OPS-03 |
| 힙·GC·`Data too large`·429 | `jvm-cluster-ops.md` ES-JVM-* | ES-CLI-04 |
| Kotlin/Java 클라이언트 설정·타임아웃·직렬화 | `client-kotlin.md` ES-CLI-01~09 | — |
| Go(go-elasticsearch) 커넥션·에러 처리·BulkIndexer·ctx | `client-go.md` ES-CLI-10~13 | ES-CLI-01/03/04 |
| Kafka/Spark → ES 유실·중복·순서 역전 | `ingest-pipeline.md` ES-ING-* | ES-CLI-04/05 |
| 업그레이드(8→9) | ES-OPS-04, ES-CLI-01 | — |

## 2. 사용법

1. 증상으로 레퍼런스 파일을 고르고 해당 ID 항목만 읽는다(파일 전체를 다 읽을 필요 없음).
2. 항목의 **적용** 조건이 이 프로젝트에 맞는지 0절 사실로 확인한다. 맞지 않으면 버린다.
3. 제안할 때는 **ID + 신호(근거가 된 코드/메트릭) + 처방 + 검증 방법**을 함께 제시한다. 수치·기본값은 항목의 근거 링크 기준이며, 서버 버전에 따라 다르면 그렇게 말한다.
4. **반례**를 확인해 과최적화를 피한다 — 측정 없이 설정을 바꾸자고 하지 않는다.

## 3. 항목 인덱스

| ID | 함정 | 파일 |
|---|---|---|
| ES-SHD-01 | 샤드 크기는 10–50GB, 샤드당 문서 2억 미만이 출발점 | shards-indexing |
| ES-SHD-02 | Lucene 문서 상한 2,147,483,519 는 docs.count + docs.deleted 기준 | shards-indexing |
| ES-SHD-03 | 노드당 비-frozen 샤드 1,000 개 하드 리밋, 마스터는 인덱스 3,000개당 힙 1GB | shards-indexing |
| ES-SHD-04 | `total_shards_per_node` 로 핫 인덱스를 분산하면 노드 장애 시 미할당이 된다 | shards-indexing |
| ES-SHD-05 | 레플리카는 검색 처리량을 "공짜로" 늘리지 않는다 — 색인 작업도 복제된다 | shards-indexing |
| ES-SHD-06 | 커스텀 routing 은 샤드 핫스팟을 만든다 — `routing_partition_size` 로 완화 | shards-indexing |
| ES-IDX-01 | `refresh_interval` 을 명시하면 search-idle 최적화가 꺼진다 | shards-indexing |
| ES-IDX-02 | 초기 적재는 `refresh_interval: -1` + `number_of_replicas: 0`, 끝나면 반드시 복원 | shards-indexing |
| ES-IDX-03 | bulk 크기는 문서 수가 아니라 바이트로, "수십 MB" 를 넘기지 않는다 | shards-indexing |
| ES-IDX-04 | bulk 는 샤드별로 쪼개진다 — 많은 샤드에 흩어진 bulk 는 샤드당 배치가 작다 | shards-indexing |
| ES-IDX-05 | 요청마다 `refresh=true` 는 초소형 세그먼트 공장 — `wait_for` 를 쓴다 | shards-indexing |
| ES-IDX-06 | 자체 `_id` 는 색인마다 존재 확인 비용 — auto id 와 트레이드오프 | shards-indexing |
| ES-IDX-07 | 같은 문서를 자주 update 하는 카운터 패턴은 삭제 문서·머지 비용으로 돌아온다 | shards-indexing |
| ES-IDX-08 | 대량 적재 중 인덱싱 버퍼는 샤드당 512MB 이상 줘도 효과 없음 | shards-indexing |
| ES-IDX-09 | `translog.durability: async` 는 마지막 `sync_interval`(기본 5s) 만큼의 확인된 쓰기를 잃을 수 있다 | shards-indexing |
| ES-MAP-01 | 숫자형 식별자는 `keyword` — 숫자 타입의 term 조회는 BKD 경로라 느리다 | mapping |
| ES-MAP-02 | keyword 의 Lucene term 상한은 32,766 바이트 — 한글은 약 1만 자에서 색인 실패 | mapping |
| ES-MAP-03 | 동적 매핑의 문자열 = `text` + `keyword` 이중 색인 — 프로덕션은 `dynamic_templates` 로 고정 | mapping |
| ES-MAP-04 | 매핑 폭발 — 필드 1,000개 한도 상향 대신 `flattened` 나 key-value 구조로 | mapping |
| ES-MAP-05 | `index: false` 와 `enabled: false` 는 다르다 | mapping |
| ES-MAP-06 | `text` 필드 `fielddata: true` 는 힙 폭탄 — 집계·정렬은 keyword 서브필드로 | mapping |
| ES-MAP-07 | nested 객체 1개 = Lucene 숨은 문서 1개, 부모 갱신 시 전부 재색인 | mapping |
| ES-MAP-08 | 비정규화 대비 nested 는 수 배, join(부모-자식)은 수백 배 느릴 수 있고 join 은 global ordinals 를 refresh 마다 만든다 | mapping |
| ES-MAP-09 | 필터 전용 text 는 `norms: false`, 스코어 불필요 필드는 `index_options: docs` | mapping |
| ES-MAP-10 | 부분 일치(`*abc*`) 요구는 `wildcard` 필드 타입이나 n-gram 으로 — keyword 에 leading wildcard 금지 | mapping |
| ES-MAP-11 | index sorting 은 생성 시에만 — 정렬이 지배적인 쿼리의 조기 종료·결합 쿼리 가속 | mapping |
| ES-MAP-12 | 고정값 필터는 인덱스 분리 + `constant_keyword` 로 필터 자체를 제거 | mapping |
| ES-MAP-13 | 분석기 변경은 기존 문서를 다시 분석하지 않는다 — 새 인덱스 + alias 스왑 | mapping |
| ES-QRY-01 | filter 컨텍스트는 노드 쿼리 캐시 대상이지만, 조건이 까다롭다 | query-aggregation |
| ES-QRY-02 | `now` range 의 반올림(`now-7d/d`)은 노드 쿼리 캐시만 살린다 — request cache 는 절대 시각으로 | query-aggregation |
| ES-QRY-03 | shard request cache 는 기본 `size=0` 만, refresh 마다 무효화, 키는 JSON 바디 해시 | query-aggregation |
| ES-QRY-04 | `filter`/`must` 가 있는 bool 의 `should` 는 기본 선택 사항이 된다 | query-aggregation |
| ES-QRY-05 | `track_total_hits` 기본 10,000 — `true` 로 바꾸면 WAND 조기 스킵이 꺼진다 | query-aggregation |
| ES-QRY-06 | PIT + `search_after` 의 숨은 비용 — 열린 PIT 는 세그먼트를 붙잡고, tiebreaker 는 `_shard_doc` 이 이미 있다 | query-aggregation |
| ES-QRY-07 | 스크립트를 문자열 결합으로 만들면 컴파일 한도(기본 150/5m)에 걸린다 | query-aggregation |
| ES-QRY-08 | 정적 랭킹 신호는 `function_score` 대신 `rank_feature` — WAND 를 살린다 | query-aggregation |
| ES-QRY-09 | `field_value_factor` 의 `log` 는 값 0~1 에서 음수 점수 → 에러, `log1p` 를 쓴다 | query-aggregation |
| ES-QRY-10 | terms 쿼리 65,536개 한도·regex 길이 1,000 — 큰 ID 목록은 terms lookup 또는 구조 변경 | query-aggregation |
| ES-QRY-11 | 하이라이트는 `index.highlight.max_analyzed_offset`(기본 1,000,000자)에서 실패 — offsets 를 색인 | query-aggregation |
| ES-QRY-12 | 인덱스가 많을 때 pre-filter(can_match) 라운드트립이 샤드를 건너뛴다 — 시간 필터를 필수로 | query-aggregation |
| ES-QRY-13 | 샤드 실패·타임아웃에도 200 — 부분 결과가 조용히 재현율·집계 카운트를 깎는다 | query-aggregation |
| ES-AGG-01 | terms 집계는 근사치 — `shard_size` 기본 `size*1.5+10`, `_count: asc` 는 오차 무한 | query-aggregation |
| ES-AGG-02 | 고카디널리티 terms 집계의 "첫 쿼리만 느림" = global ordinals 지연 빌드 — eager 는 refresh 로 비용 이동 | query-aggregation |
| ES-AGG-03 | `cardinality` 는 HyperLogLog++ — `precision_threshold` 기본 3,000, 최대 40,000, 메모리 ≈ 임계값×8바이트 | query-aggregation |
| ES-AGG-04 | 버킷 상한 `search.max_buckets`(기본 65,536) 는 중첩 곱으로 터진다 — composite 로 순회 | query-aggregation |
| LUC-SEG-01 | force merge 는 더 이상 쓰지 않는 인덱스에만 | segments-lucene |
| LUC-SEG-02 | 삭제 문서는 공짜가 아니다 — 스코어 통계와 디스크를 오염 | segments-lucene |
| LUC-SEG-03 | 열린 scroll/PIT 는 머지된 구 세그먼트를 붙잡아 디스크를 채운다 | segments-lucene |
| LUC-SEG-04 | 대량 적재 후 세그먼트를 크게 만들려면 force merge 대신 적재 설정으로 | segments-lucene |
| LUC-SEG-05 | 머지 스레드는 기본 프로세서 절반(최소 1) — 회전 디스크면 1, 8.19+ 는 노드 공유 merge 풀 | segments-lucene |
| LUC-EXE-01 | `_profile` 은 WAND 등 최적화를 끄고 shard 단계만 잰다 — 절대값 금지, 상대 비교 전용 | segments-lucene |
| LUC-EXE-02 | 스코어가 필요 없는 정렬 쿼리는 `_score` 계산을 하지 않게 — 필드 정렬 + 인덱스 정렬 | segments-lucene |
| LUC-EXE-03 | 파일시스템 캐시가 실제 검색 엔진 메모리 — 힙은 노드(컨테이너) 메모리 절반 이하(구 ES-JVM-02 병합) | segments-lucene |
| ES-JVM-01 | 압축 OOP 경계는 "31GB" 가 아니라 26GB 안전, 일부 시스템 30GB — 로그로 확인 | jvm-cluster-ops |
| ES-JVM-03 | 번들 JVM 의 G1 옵션을 일반 "GC 튜닝 글" 로 덮어쓰지 않는다 | jvm-cluster-ops |
| ES-JVM-04 | 부모 브레이커 95%(real memory) — 429 `circuit_breaking_exception` 은 `durability` 를 보고 재시도 여부를 가른다 | jvm-cluster-ops |
| ES-JVM-05 | 스레드풀 거부(429 `es_rejected_execution_exception`)는 큐를 늘려 숨기지 않는다 | jvm-cluster-ops |
| ES-JVM-06 | 컨테이너 CPU limit 과 `node.processors` — 스레드풀 크기가 프로세서 수에서 나온다 | jvm-cluster-ops |
| ES-OPS-01 | ECK 에서 `vm.max_map_count` 를 못 올리면 `node.store.allow_mmap: false` 로 기동은 되지만 검색 I/O 가 느려진다 | jvm-cluster-ops |
| ES-OPS-02 | 노드 이탈 후 `delayed_timeout`(기본 1m) — 롤링 재시작이 재배치 폭풍을 만든다 | jvm-cluster-ops |
| ES-OPS-03 | 디스크 워터마크 85/90/95% — flood stage 에서 인덱스가 쓰기 차단된다 | jvm-cluster-ops |
| ES-OPS-04 | 메이저 업그레이드는 직전 메이저에서 만든 인덱스만 읽는다 — 9.x 전 7.x 인덱스 처리 | jvm-cluster-ops |
| ES-OPS-05 | slow log 는 기본 꺼져 있다 — 임계값을 "평소 p99 의 2~3배" 로 켠다 | jvm-cluster-ops |
| ES-CLI-01 | 클라이언트는 forward-compatible — 서버 먼저 올리고 클라이언트는 같거나 낮은 마이너로 | client-kotlin |
| ES-CLI-02 | 레거시 RestClient 기본 커넥션 풀은 노드당 10, 전체 30 — 고동시성 서비스의 숨은 큐 | client-kotlin |
| ES-CLI-03 | 클라이언트 socket timeout < 서버 `timeout` 이면 서버는 계속 일한다 | client-kotlin |
| ES-CLI-04 | bulk 응답은 200 이어도 아이템 실패가 있다 — 실패를 상태 코드로 분류 | client-kotlin |
| ES-CLI-05 | BulkIngester 기본값: 1,000 ops / 5MiB / 동시 요청 1 — `add()` 가 블록된다 | client-kotlin |
| ES-CLI-06 | 동기 클라이언트를 코루틴에서 쓰면 `withTimeout` 이 호출을 끊지 못한다 | client-kotlin |
| ES-CLI-07 | 커스텀 ObjectMapper 를 `JacksonJsonpMapper` 에 넘기면 기본 `NON_NULL` 이 사라진다 — Kotlin 모듈과 함께 직접 설정 | client-kotlin |
| ES-CLI-08 | Spring Data Elasticsearch 의 자동 인덱스 생성은 운영 매핑을 오염시킨다 | client-kotlin |
| ES-CLI-09 | 쿠버네티스/클라우드 환경에서 sniffing 은 끈다 | client-kotlin |
| ES-CLI-10 | Go `Config.Transport` 미지정 = `http.DefaultTransport` 복제 — 호스트당 유휴 커넥션 2개 | client-go |
| ES-CLI-11 | esapi 응답은 4xx/5xx 에도 `err == nil` — `res.IsError()` 확인과 Body 소진·Close | client-go |
| ES-CLI-12 | `esutil.BulkIndexer` 기본값: 워커 `runtime.NumCPU()`·5MB·30s — 아이템 실패는 콜백과 `Stats()` 에서만 | client-go |
| ES-CLI-13 | Go `context` 데드라인은 HTTP 를 끊는다 — 기본 재시도(502/503/504 ×3)·429 미재시도를 알고 계층화 | client-go |
| ES-ING-01 | 순서 역전 방지는 `version_type: external` — 단, 삭제 tombstone 은 `gc_deletes`(기본 60s) 후 사라진다 | ingest-pipeline |
| ES-ING-02 | auto-generated id + 재시도 = 중복 문서 | ingest-pipeline |
| ES-ING-03 | 오프셋 커밋은 bulk 아이템 결과 확인 후 — 비동기 ingester 와 auto commit 조합 금지 | ingest-pipeline |
| ES-ING-04 | 무중단 재색인은 "alias 원자 스왑 + 스왑 구간 이중 쓰기/재생" | ingest-pipeline |
| ES-ING-05 | `_source` 에서 필드를 `excludes` 로 빼면 `_reindex`·update 가 그 필드를 잃는다 | ingest-pipeline |
| ES-ING-06 | Spark(es-hadoop) 배치 색인의 실제 동시성 = 파티션 수 × 배치 — 클러스터를 쉽게 포화시킨다 | ingest-pipeline |

진단 API 시퀀스(`_profile`·`_explain`·`_validate`·`_termvectors`·`_tasks`·hot_threads) 는 `references/diagnostics.md`.

## 4. 관련 컴포넌트

- 커맨드(사용자 호출): `/es-query-review`, `/es-mapping-review`, `/index-lifecycle` — 모두 이 레퍼런스의 ID 로 판정한다.
- 에이전트: `es-query-optimizer`(쿼리·매핑·클러스터 성능), `search-service-architect`(Kotlin·Go 클라이언트·색인 파이프라인). 이 스킬을 사전 로드한다.
- 다른 허브: `search-relevance-engineering`(ES-REL/ES-RNK/KO), `vector-hybrid-search-patterns`(VEC).
