# 세그먼트 · 머지 · Lucene 실행 (LUC-SEG / LUC-EXE)

> 적용 전 확인: `GET _cat/segments/idx?v&h=index,shard,segment,docs.count,docs.deleted,size,committed,searchable`, 인덱스가 쓰기 중인지(read-only 인지), 샤드 크기.

### LUC-SEG-01 · force merge 는 더 이상 쓰지 않는 인덱스에만
- 적용: 모든 버전. 기본 `index.merge.policy.max_merged_segment` 5GB
- 신호: 쓰기 중인 인덱스에 야간 `_forcemerge?max_num_segments=1` 크론, 이후 docs.deleted 가 계속 쌓이고 디스크가 줄지 않음
- 메커니즘: force merge 로 만든 5GB 초과 세그먼트는 일반 머지 대상에서 사실상 빠진다 → 그 안에 생기는 삭제 문서는 오래 회수되지 않는다
- 처방: 롤오버된/읽기 전용 인덱스(ILM warm 단계)에서만. 쓰기 중 인덱스의 삭제 문서는 `_forcemerge?only_expunge_deletes=true` 를 신중히(이것도 큰 세그먼트 생성 가능)
- 반례: 이후 쓰기가 전혀 없는 정적 인덱스(사전, 아카이브)는 1 세그먼트가 검색·kNN 에 유리
- 검증: `_cat/segments` 크기·deleted 추이
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed, https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-forcemerge

### LUC-SEG-02 · 삭제 문서는 공짜가 아니다 — 스코어 통계와 디스크를 오염
- 적용: 갱신이 잦은 인덱스(ES-IDX-07)
- 신호: `docs.deleted / docs.count` 비율이 높게 유지, 같은 쿼리의 점수가 프라이머리/레플리카에서 다름
- 메커니즘: 삭제 표시 문서는 머지 전까지 postings·doc values 에 남아 순회되고, BM25 의 docCount/docFreq 통계에도 포함된다 → 레플리카 간 머지 시점 차이로 점수가 흔들린다
- 처방: 갱신 빈도 축소(외부 카운터), 점수 안정성이 필요하면 `preference`(ES-REL-02). 머지 정책 파라미터 조정은 측정 후
- 반례: 삭제 비율 자체보다 그로 인한 증상(디스크·점수 흔들림)이 있을 때만 대응
- 검증: `_cat/indices?h=index,docs.count,docs.deleted`, 같은 쿼리를 `preference=_primary` vs `_replica` 로 비교
- 근거: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/consistent-scoring.html

### LUC-SEG-03 · 열린 scroll/PIT 는 머지된 구 세그먼트를 붙잡아 디스크를 채운다
- 적용: 장시간 export, keep_alive 가 긴 PIT, 닫지 않는 scroll
- 신호: 머지 후에도 디스크 사용량이 줄지 않음, `open_contexts` 높음, disk watermark 경보(ES-OPS-03)
- 메커니즘: 검색 컨텍스트는 생성 시점의 세그먼트 집합을 참조 → 머지로 대체된 세그먼트 파일을 지울 수 없다
- 처방: keep_alive 최소화, 완료 시 `DELETE _pit`/`DELETE _search/scroll`, export 는 배치 크기를 키워 수명 단축
- 반례: 없음
- 검증: `GET _nodes/stats/indices/search?filter_path=**.open_contexts`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/paginate-search-results

### LUC-SEG-04 · 대량 적재 후 세그먼트를 크게 만들려면 force merge 대신 적재 설정으로
- 적용: 정적 재색인, 특히 벡터 인덱스(세그먼트 수 = HNSW 그래프 수)
- 신호: 적재 직후 세그먼트 수백 개 → 큰 force merge 를 습관적으로 실행
- 메커니즘: 처음부터 큰 세그먼트를 만들면 머지 비용 자체가 준다
- 처방: `refresh_interval: -1`, 인덱싱 버퍼 확대, `index.translog.flush_threshold_size` 상향. 벡터처럼 큰 문서는 `max_merged_segment` 를 10~20GB 로 검토
- 반례: 라이브 인덱스에는 부적합
- 검증: 적재 직후 `_cat/segments` 수·크기
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search

### LUC-SEG-05 · 머지 스레드는 기본 프로세서 절반(최소 1) — 회전 디스크면 1, 8.19+ 는 노드 공유 merge 풀
- 적용: self-managed, HDD 또는 IOPS 가 낮은 네트워크 디스크. 버전 확인 필수 — 8.18 이하는 샤드별 `ConcurrentMergeScheduler`, 8.19+/9.x 문서는 노드 단위 전용 `merge` 스레드 풀(노드의 모든 샤드가 공유, 작은 머지 우선)
- 신호: 머지가 I/O 를 포화시켜 검색 지연 상승, `hot_threads` 에 머지 스레드, `GET _cat/thread_pool/merge?v`(8.19+) 큐 적체
- 메커니즘: `index.merge.scheduler.max_thread_count` 기본 = max(1, JVM 이 보는 프로세서/2)(`node.processors` 와 무관), `max_merge_count` = thread+5. 8.19+ 에서 이 값은 "한 샤드에서 동시에 머지할 수 있는 스레드 상한"이고, 노드 전체 동시성은 노드 레벨 merge 풀 설정이 정한다. 순차 I/O 장치에선 동시 머지가 랜덤 I/O 화
- 처방: 회전 디스크는 `max_thread_count: 1`(두 모델 모두 문서 권고). 8.19+ 에서 노드 전체 머지 부하를 줄이려면 인덱스 설정이 아니라 노드 레벨 merge 풀/자원 한도 설정을 해당 버전 문서로 확인. SSD 에선 기본 유지
- 반례: 고성능 NVMe 에서 낮추면 머지 적체 → 세그먼트 폭증
- 검증: `GET _nodes/hot_threads`, `GET idx/_stats/merge` 의 current/throttled, (8.19+) `_cat/thread_pool/merge`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/merge, https://www.elastic.co/guide/en/elasticsearch/reference/8.18/index-modules-merge.html (구 모델), https://www.elastic.co/guide/en/elasticsearch/reference/8.19/index-modules-merge.html (merge 풀)

### LUC-EXE-01 · `_profile` 은 WAND 등 최적화를 끄고 shard 단계만 잰다 — 절대값 금지, 상대 비교 전용
- 적용: 모든 버전
- 신호: profile 의 nanos 로 SLA 판단, took 과 Σtime_in_nanos 의 큰 차이를 무시
- 메커니즘: 프로파일링은 계측 오버헤드가 크고 코디네이팅 머지·네트워크·global ordinals 빌드 일부·큐 대기는 포함되지 않는다. collector 시간은 query 시간과 겹쳐 합산하면 과대
- 처방: 단계 간 비율만 본다. took ≫ Σ 이면 "단계 밖"(hot_threads, `_tasks`, thread_pool, breaker)로 이동(diagnostics.md)
- 반례: 없음
- 검증: profile on/off took 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/search-profile

### LUC-EXE-02 · 스코어가 필요 없는 정렬 쿼리는 `_score` 계산을 하지 않게 — 필드 정렬 + 인덱스 정렬
- 적용: 최신순/가격순 정렬 목록
- 신호: `sort: [{created_at: desc}]` + `must` 매칭(스코어 계산), `track_scores: true`
- 메커니즘: 필드 정렬이면 점수는 버려지는데 must 는 계산을 강제. 정렬이 인덱스 정렬과 일치하면 세그먼트 조기 종료(ES-MAP-11)
- 처방: 매칭 조건을 `filter` 로, `track_scores` 제거, 필요 시 인덱스 정렬
- 반례: 정렬 tie-break 에 점수를 쓰면 유지
- 검증: `_profile` score 시간
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/sort-search-results

### LUC-EXE-03 · 파일시스템 캐시가 실제 검색 엔진 메모리 — 힙을 키우면 느려질 수 있다
- 적용: self-managed/ECK. 기본 힙 자동 산정은 RAM 의 절반 이하. 컨테이너는 컨테이너 memory limit 기준, 한 호스트 다중 노드는 합산 기준(구 ES-JVM-02 병합)
- 신호: 힙 사용률 낮은데 디스크 read IOPS 높음, 콜드 쿼리 지연, 64GB 노드에 힙 48GB 같은 수동 힙
- 메커니즘: postings·doc values·벡터는 mmap 으로 OS 페이지 캐시에서 읽힌다. 힙 증가 = 페이지 캐시 감소
- 처방: 자동 힙 산정을 유지하고, 수동이면 메모리의 최소 절반을 OS 에 남긴다(순수 마스터/코디네이팅 노드는 비율이 다를 수 있음 — 문서 확인). Linux 블록 디바이스 readahead 를 약 128KiB 로(과도한 readahead 는 캐시 오염). `index.store.preload` 는 RAM 에 확실히 들어갈 파일만
- 반례: preload 과다는 오히려 캐시 축출로 느려진다
- 검증: `blockdev --getra`, 노드 OS 메트릭(page cache, major faults)
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed, https://www.elastic.co/docs/reference/elasticsearch/jvm-settings
