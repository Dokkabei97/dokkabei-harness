# JVM · 서킷 브레이커 · 클러스터 운영 (ES-JVM / ES-OPS)

> 적용 전 확인: 배포 형태(Cloud/ECK 는 힙·OS 설정을 플랫폼이 관리), `GET _nodes/jvm,os?filter_path=**.mem,**.using_compressed_ordinary_object_pointers`, 컨테이너 메모리·CPU limit.

### ES-JVM-01 · 압축 OOP 경계는 "31GB" 가 아니라 26GB 안전, 일부 시스템 30GB — 로그로 확인
- 적용: self-managed / 수동 힙 지정
- 신호: `-Xmx31g` 관성 설정, 힙을 32GB 근처로 올렸는데 가용 객체 공간이 오히려 감소
- 메커니즘: 경계를 넘으면 객체 포인터가 64비트가 되어 같은 데이터가 더 많은 힙을 차지. zero-based compressed oops 경계는 OS/JVM 마다 다르다
- 처방: 기본 자동 힙 산정을 우선. 수동이면 26GB 이하에서 시작하고 시작 로그 `heap size [...], compressed ordinary object pointers [true]` 또는 nodes info `jvm.using_compressed_ordinary_object_pointers` 확인. Xms = Xmx
- 반례: 힙 30GB 대 대형 노드가 필요한 경우보다 노드 수평 확장이 대개 낫다
- 검증: `GET _nodes/jvm?filter_path=**.using_compressed_ordinary_object_pointers`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/jvm-settings

### ES-JVM-03 · 번들 JVM 의 G1 옵션을 일반 "GC 튜닝 글" 로 덮어쓰지 않는다
- 적용: `jvm.options.d/` 에 GC 플래그를 추가한 클러스터
- 신호: CMS/Parallel GC 플래그, `-XX:MaxGCPauseMillis` 등 임의 변경 후 브레이커 트립·긴 GC
- 메커니즘: ES 는 번들 JDK 와 G1 에 맞춘 기본 옵션을 제공하고, real-memory 부모 브레이커(ES-JVM-04)는 GC 가 힙 여유를 확보한다는 전제로 동작한다
- 처방: GC 플래그는 기본값 유지, 문제는 힙 소비자(fielddata, 대형 집계, bulk 크기)부터 줄인다. GC 로그로 원인 확인 후에만 조정
- 반례: Elastic 지원/릴리즈 노트가 특정 플래그를 권고하는 경우
- 검증: GC 로그(`logs/gc.log`), `GET _nodes/stats/jvm` 의 collection_time
- 근거: https://www.elastic.co/docs/reference/elasticsearch/jvm-settings

### ES-JVM-04 · 부모 브레이커 95%(real memory) — 429 `circuit_breaking_exception` 은 `durability` 를 보고 재시도 여부를 가른다
- 적용: 기본 `indices.breaker.total.use_real_memory: true`, total 95%(real memory 미사용 시 70%), fielddata 40%, request 60%, in-flight 100%
- 신호: 대형 집계/bulk 시 `[parent] Data too large`, 클라이언트가 이를 영구 실패로 처리해 데이터 유실 — 또는 반대로 같은 요청을 무한 재시도
- 메커니즘: 실제 힙 사용량 기준으로 새 요청을 거부해 OOM 을 예방. HTTP 상태는 항상 429 지만 에러 바디의 `durability` 가 성격을 알려준다 — request·in_flight 브레이커는 `TRANSIENT`, fielddata 는 `PERMANENT`, 부모 브레이커는 트립 시점에 transient 자식 사용량 ≥ permanent 자식 사용량이면 `TRANSIENT`, 아니면 `PERMANENT`
- 처방: `TRANSIENT` → 지수 백오프 재시도(ES-CLI-04). `PERMANENT` → 힙을 오래 점유한 구조(fielddata 등)가 원인이라 재시도로는 대개 회복되지 않는다 — 재시도 상한을 짧게 두고 알림, 서버 쪽에서 fielddata·global ordinals 소비를 줄인다. 어느 쪽이든 단일 요청이 너무 커서 트립되면(같은 요청이 매번 트립) bulk 분할·버킷 축소로 요청을 줄인다. 한도 상향은 OOM 위험을 키운다
- 반례: 재시도 무상한은 금지 — TRANSIENT 라도 같은 요청이 연속 트립하면 크기 문제다
- 검증: `GET _nodes/stats/breaker` 의 브레이커별 tripped 증가율, 에러 바디 `durability`·`bytes_wanted`·`bytes_limit` 로깅
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/circuit-breaker-settings, https://github.com/elastic/elasticsearch/blob/main/server/src/main/java/org/elasticsearch/common/breaker/CircuitBreakingException.java (status 는 항상 429, `durability` 필드), https://github.com/elastic/elasticsearch/blob/main/server/src/main/java/org/elasticsearch/indices/breaker/HierarchyCircuitBreakerService.java (브레이커별 durability·부모 판정)

### ES-JVM-05 · 스레드풀 거부(429 `es_rejected_execution_exception`)는 큐를 늘려 숨기지 않는다
- 적용: write/search 스레드풀
- 신호: `GET _cat/thread_pool/write,search?v&h=node_name,name,active,queue,rejected` 의 rejected 증가, 특정 노드만
- 메커니즘: 큐는 지연을 흡수할 뿐 처리 능력을 늘리지 않는다. 큐 확대 = 힙 사용과 꼬리 지연 증가. 특정 노드만 거부면 샤드 쏠림(ES-SHD-06)·느린 디스크
- 처방: 클라이언트 동시성 제한 + 백오프, 샤드 분산 점검, 노드 증설
- 반례: 순간 버스트가 명확하고 측정상 큐만으로 흡수 가능한 경우
- 검증: rejected 와 노드별 샤드 분포 상관
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/thread-pool-settings

### ES-JVM-06 · 컨테이너 CPU limit 과 `node.processors` — 스레드풀 크기가 프로세서 수에서 나온다
- 적용: ECK/쿠버네티스, CPU quota 가 걸린 컨테이너
- 신호: CPU throttling 이 높은데 search 스레드가 많음, 또는 반대로 limit 보다 적게 잡힘
- 메커니즘: search 풀 = int(프로세서×3/2)+1, write 풀 = 프로세서 수. 감지된 프로세서 수가 실제 할당과 다르면 과/소 병렬
- 처방: `GET _nodes/os?filter_path=**.allocated_processors` 확인, 필요 시 `node.processors` 를 컨테이너 CPU 와 일치
- 반례: 플랫폼이 이미 맞춰 주는 Cloud Hosted
- 검증: allocated_processors vs 컨테이너 CPU limit, throttling 메트릭
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/thread-pool-settings

### ES-OPS-01 · ECK 에서 `vm.max_map_count` 를 못 올리면 `node.store.allow_mmap: false` 로 기동은 되지만 검색 I/O 가 느려진다
- 적용: ECK/쿠버네티스(노드 sysctl 권한이 없는 클러스터). self-managed 프로덕션 모드는 부트스트랩 체크가 이미 강제하므로 대상 아님
- 신호: ECK 매니페스트에 `node.store.allow_mmap: false`, 또는 privileged init container 없이 배포
- 메커니즘: 기본 store 는 세그먼트 파일을 mmap 으로 읽어 커널 페이지 캐시를 직접 쓴다(LUC-EXE-03). mmap 을 끄면 기동 요건(262,144)은 피하지만 파일 읽기가 mmap 이 아닌 경로로 바뀐다
- 처방: 가능하면 privileged init container 나 DaemonSet 으로 노드에 `vm.max_map_count=1048576` 을 설정하고 `allow_mmap` 은 기본(true) 유지. 불가하면 성능 차이를 측정한 뒤 수용
- 반례: 소규모·개발 클러스터에선 `allow_mmap: false` 가 간단한 선택
- 검증: 노드에서 `sysctl vm.max_map_count`, `GET _nodes/settings?filter_path=**.allow_mmap`, 동일 쿼리 지연 비교
- 근거: https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/virtual-memory, https://www.elastic.co/docs/deploy-manage/deploy/self-managed/bootstrap-checks

### ES-OPS-02 · 노드 이탈 후 `delayed_timeout`(기본 1m) — 롤링 재시작이 재배치 폭풍을 만든다
- 적용: 롤링 재시작/패치, 노드 재부팅 시간이 1분을 넘는 환경
- 신호: 재시작마다 대량 샤드 복구로 네트워크·디스크 포화
- 메커니즘: `index.unassigned.node_left.delayed_timeout` 이 지나면 레플리카를 다른 노드에 새로 만든다
- 처방: 롤링 재시작 전 `cluster.routing.allocation.enable: primaries` 후 재시작·복구 완료 시 `all` 복원, 또는 delayed_timeout 을 재부팅 시간보다 길게
- 반례: 실제 노드 장애 시 너무 긴 지연은 가용성(레플리카 부족) 기간을 늘린다
- 검증: `GET _cat/recovery?active_only=true&v`
- 근거: https://www.elastic.co/docs/deploy-manage/maintenance/start-stop-services/full-cluster-restart-rolling-restart-procedures, https://www.elastic.co/docs/reference/elasticsearch/index-settings/index-modules

### ES-OPS-03 · 디스크 워터마크 85/90/95% — flood stage 에서 인덱스가 쓰기 차단된다
- 적용: 기본 low 85%, high 90%, flood_stage 95%
- 신호: bulk 응답 `index ... blocked by: [TOO_MANY_REQUESTS/12/disk usage exceeded flood-stage watermark, index has read-only-allow-delete block]`
- 메커니즘: high 이상이면 샤드를 다른 노드로 이동, flood stage 이면 해당 노드에 샤드가 있는 인덱스에 read_only_allow_delete 블록. 디스크가 내려가면 자동 해제
- 처방: 디스크 경보는 low 이전에. PIT/scroll 정리(LUC-SEG-03), 오래된 인덱스 삭제/스냅샷, 노드 증설. 클라이언트는 이 429 를 재시도해도 풀리지 않으니 별도 알림
- 반례: 대용량 디스크에서는 퍼센트 대신 `max_headroom` 이 실효 기준이 될 수 있음(문서 확인)
- 검증: `GET _cat/allocation?v`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/cluster-level-shard-allocation-routing-settings

### ES-OPS-04 · 메이저 업그레이드는 직전 메이저에서 만든 인덱스만 읽는다 — 9.x 전 7.x 인덱스 처리
- 적용: 8.x → 9.x 업그레이드 계획
- 신호: 7.x 시절 생성된 인덱스가 아직 존재(`GET _cat/indices?h=index,creation.date.string` + `index.version.created`)
- 메커니즘: N 메이저는 N-1 메이저에서 생성된 인덱스까지 지원. 그 이전 인덱스는 재색인하거나(지원 범위에서) 읽기 전용 아카이브 처리 필요
- 처방: Upgrade Assistant 로 사전 점검, 7.x 인덱스는 8.x 에서 reindex. 클라이언트는 서버 먼저 올린 뒤(클라이언트는 같거나 높은 마이너 서버와 호환되는 forward-compatible) 업그레이드
- 반례: 없음
- 검증: `GET _migration/deprecations`
- 근거: https://www.elastic.co/docs/deploy-manage/upgrade/prepare-to-upgrade, https://www.elastic.co/docs/reference/elasticsearch/clients/java

### ES-OPS-05 · slow log 는 기본 꺼져 있다 — 임계값을 "평소 p99 의 2~3배" 로 켠다
- 적용: 인덱스 단위 search/indexing slowlog
- 신호: 느린 쿼리 원인 추적 불가, 또는 임계값 0 으로 켜서 로그 폭증
- 메커니즘: 샤드 단위 query/fetch 단계 시간을 기록 — 코디네이터 단계는 포함 안 됨
- 처방: `index.search.slowlog.threshold.query.warn` 등을 서비스 SLO 기반으로 설정, 애플리케이션 측에서는 `X-Opaque-Id` 헤더로 요청 출처를 slowlog/`_tasks` 에 남긴다
- 반례: 임계값이 너무 낮으면 I/O 부담
- 검증: slowlog 파일/데이터 스트림, `_tasks` 의 headers
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/slow-log
