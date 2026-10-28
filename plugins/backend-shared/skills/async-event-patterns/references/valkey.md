# Valkey/Redis 스페셜리스트 항목 (VK)

영역: KEY 키 설계 · EXP 만료 · MEM 메모리/축출 · CLI 클라이언트 · LOCK 분산락 · STR Streams/PubSub.
서버 종류·버전(Valkey 7.2/8.x, Redis OSS, ElastiCache)과 클라이언트(Lettuce, Redisson, go-redis, valkey-go, redis-py)를 먼저 확인한다 — 기본값이 다르다.

---

## KEY

### VK-KEY-01 · 패턴 키 순회: `SCAN` 은 중복을 반환하고 반복 중 변경을 보장하지 않으며, `MATCH` 는 훑은 뒤 거른다 — 클러스터는 노드별
- 적용: 패턴 기반 키 조회·삭제(캐시 무효화 등)
- 신호: 코드/스크립트의 `KEYS pattern`, `redisTemplate.keys(...)`, slowlog 상위
- 메커니즘: (`KEYS` 가 O(N) 으로 이벤트 루프를 막는다는 것은 전제.) `SCAN` 은 커서로 나눠 실행하지만 리해시 중 같은 키를 여러 번 반환할 수 있고, 반복 중 추가/삭제된 키는 포함이 보장되지 않는다. `MATCH` 는 `COUNT` 만큼 원소를 가져온 **뒤** 필터링하므로 희소 패턴이면 빈 배치가 연속으로 나온다 — 빈 결과는 종료 신호가 아니며 커서가 0 일 때만 끝이다. 클러스터에서는 `SCAN` 이 연결된 노드의 키만 보므로 각 primary 를 순회해야 한다(클라이언트의 cluster-scan 지원 여부 확인).
- 처방: `SCAN 0 MATCH p COUNT 1000` 반복 + 결과 중복 허용 로직 + `UNLINK`. 그보다 **패턴 삭제가 필요 없는 설계**: 키 버전 접두사 교체(→ team-conventions §캐시 키), 태그 Set 으로 키 목록 관리.
- 반례: 로컬 개발·키 수 수백 개의 테스트.
- 검증: `SLOWLOG GET`, `LATENCY LATEST`.
- 근거: https://valkey.io/commands/keys/ , https://valkey.io/commands/scan/

### VK-KEY-02 · 빅키: 수 MB 값·수십만 요소 컬렉션은 조회·삭제·만료·복제 모두를 막는다
- 적용: Hash/Set/ZSet/List 를 무한정 키우는 설계, 큰 JSON 직렬화 값
- 신호: `valkey-cli --bigkeys`/`--memkeys` 상위, `HGETALL`/`SMEMBERS` 지연, 키 만료 시점의 지연 스파이크
- 메커니즘: O(N) 명령과 큰 값 직렬화가 이벤트 루프를 점유한다. 큰 키 삭제도 메모리 해제가 O(N) 이다. Redis OSS·Valkey 7.x 는 `lazyfree-lazy-*` 기본 no 라 `DEL`/만료/축출이 동기 해제지만, **Valkey 8.0 은 `lazyfree-lazy-user-del`, `lazyfree-lazy-expire`, `lazyfree-lazy-eviction`, `lazyfree-lazy-server-del` 기본값이 yes** 로 바뀌었다.
- 처방: 컬렉션은 버킷으로 샤딩(`k:{id}:b{n}`), 전체 조회 대신 `HSCAN`/`ZRANGE` 페이지, 값은 압축 또는 분할. 삭제는 `UNLINK`(4.0+). 버전에 맞게 lazyfree 설정 확인.
- 반례: —
- 검증: `MEMORY USAGE key`, `--bigkeys`, `LATENCY HISTORY`.
- 근거: https://valkey.io/topics/memory-optimization/ , https://github.com/valkey-io/valkey/blob/8.0/valkey.conf (LAZY FREEING 섹션)

### VK-KEY-03 · 핫키는 샤드 하나에 몰린다 — 클러스터 확장으로 해결되지 않는다
- 적용: 인기 상품·설정·랭킹 같은 단일 키 고빈도 조회, 해시태그 `{}` 남용
- 신호: 클러스터 노드 하나만 CPU 100%, 네트워크 대역 편중
- 메커니즘: 키는 슬롯 하나(CRC16 mod 16384)에 고정된다. 해시태그로 여러 키를 같은 슬롯에 묶으면 그 슬롯이 핫스팟이 된다.
- 처방: 앱 로컬 캐시(Caffeine 등 짧은 TTL, 또는 서버 보조 클라이언트측 캐싱 `CLIENT TRACKING`), 키 복제(`k#0..k#n` 중 임의 읽기), 레플리카 읽기(`READONLY`, Lettuce `ReadFrom.REPLICA_PREFERRED`) — 단 레플리카 읽기는 복제 지연만큼 stale.
- 반례: 쓰기 핫키는 복제로 풀리지 않는다 — 쓰기 집계를 앱에서 배치.
- 검증: `valkey-cli --hotkeys`(`maxmemory-policy` 가 LFU 계열일 때만 동작), 노드별 `INFO commandstats`.
- 근거: https://valkey.io/topics/cluster-spec/ , https://valkey.io/topics/client-side-caching/

## EXP

### VK-EXP-01 · 만료 키스페이스 알림은 TTL 시각이 아니라 "실제로 지워질 때" 오고, 유실될 수 있다
- 적용: `__keyevent@0__:expired` 로 예약 작업·세션 만료 처리를 구현하려는 설계
- 신호: 만료 이벤트가 수 초~수 분 늦음, 앱 재시작 중 이벤트 누락
- 메커니즘: 키는 접근 시(passive) 또는 주기적 샘플링(active)으로 삭제되며, `expired` 이벤트는 삭제 시점에 발생한다. 키스페이스 알림은 Pub/Sub 이라 구독자가 연결되어 있지 않으면 사라지고, 클러스터에서는 키가 있는 노드에서만 발행된다. 기본 `notify-keyspace-events` 는 비어 있어 켜야 동작한다.
- 처방: 예약 작업은 ZSet(score=실행 시각) 폴링 또는 Streams/Kafka 지연 큐로. 만료 알림은 "최선 노력 힌트" 로만 사용.
- 반례: 유실·지연이 허용되는 캐시 통계 정도.
- 검증: TTL 1s 키 1만 개 생성 후 이벤트 도착 지연 분포 측정.
- 근거: https://valkey.io/topics/notifications/ (Timing of expired events), https://valkey.io/commands/expire/

## MEM

### VK-MEM-01 · `maxmemory` 기본 0(무제한)·`maxmemory-policy` 기본 `noeviction` — 미설정이면 컨테이너 OOMKill, 설정해도 정책을 안 바꾸면 쓰기 오류
- 적용: 캐시 용도 인스턴스
- 신호: `OOM command not allowed when used memory > 'maxmemory'`, 또는 (maxmemory 미설정 시) 오류 없이 컨테이너 OOMKilled·스왑
- 메커니즘: 64비트 빌드의 `maxmemory` 기본값은 0 = 제한 없음이라, 셀프호스트·컨테이너에서 설정하지 않으면 축출 정책이 **발동조차 하지 않고** OS/cgroup 한도에서 프로세스가 죽는다. 기본 noeviction 은 축출하지 않고 쓰기를 거부한다. `volatile-*` 정책은 TTL 이 있는 키만 축출하므로 TTL 없는 키만 있으면 noeviction 처럼 동작한다. LRU/LFU 는 `maxmemory-samples`(기본 5) 기반 근사다.
- 처방: `maxmemory` 를 컨테이너 메모리 한도의 일부로 명시(fork·버퍼 여유 — VK-MEM-02). 순수 캐시는 `allkeys-lru` 또는 접근 빈도 편중이 크면 `allkeys-lfu`. 캐시와 영속 데이터(세션·락·큐)를 한 인스턴스에 섞지 말 것 — 축출 정책을 하나만 고를 수 있다. 관리형 서비스는 파라미터 그룹 기본값을 확인.
- 반례: 큐/세션 저장소는 noeviction 이 맞다(조용히 지워지면 안 됨).
- 검증: `INFO memory`, `INFO stats` 의 `evicted_keys`.
- 근거: https://valkey.io/topics/lru-cache/

### VK-MEM-02 · RDB/AOF 재작성 fork 는 copy-on-write 로 메모리를 최대 2배까지 쓰고 지연을 만든다
- 적용: 영속성 켠 대용량 인스턴스, 쓰기량이 큰 시간대의 BGSAVE
- 신호: 저장 시점마다 지연 스파이크, `latest_fork_usec` 큼, 컨테이너 OOMKill
- 메커니즘: fork 는 페이지 테이블 복사 시간만큼 메인 스레드를 멈추고, 이후 변경된 페이지마다 복사가 일어난다. Transparent Huge Pages 가 켜져 있으면 복사 단위가 커져 악화된다.
- 처방: maxmemory 를 컨테이너 메모리의 일부(쓰기량에 따라 여유)로, THP 비활성화, 순수 캐시는 영속성 끄기 검토.
- 반례: —
- 검증: `INFO persistence`/`INFO stats` 의 `latest_fork_usec`, `LATENCY DOCTOR`.
- 근거: https://valkey.io/topics/latency/ , https://valkey.io/topics/persistence/

## CLI

### VK-CLI-01 · Lettuce 는 연결 하나를 공유한다 — 블로킹 명령·큰 응답이 모든 요청을 막는다
- 적용: Spring Data Redis(Lettuce 기본), 공유 연결에서 `BLPOP`/`XREAD BLOCK`/큰 `MGET`
- 신호: 한 기능의 지연이 무관한 모든 Redis 호출 지연으로 전파
- 메커니즘: Lettuce 는 스레드 안전한 단일 연결에 명령을 파이프라이닝한다. 블로킹 명령이나 큰 응답은 그 연결 뒤의 모든 명령을 기다리게 한다.
- 처방: 블로킹 명령·Streams 소비는 전용 연결(풀 또는 별도 커넥션 팩토리). 큰 응답은 분할. 명령 타임아웃(`spring.data.redis.timeout`) 명시 — 캐시는 짧게(→ team-conventions §타임아웃).
- 반례: 짧은 명령만 쓰면 단일 연결이 오히려 효율적이다(풀링 불필요).
- 검증: 부하 테스트에서 블로킹 명령 유무에 따른 p99 비교.
- 근거: https://redis.github.io/lettuce/advanced-usage/#connection-pooling , https://docs.spring.io/spring-data/redis/reference/redis/connection-modes.html

### VK-CLI-02 · 클러스터 장애 조치 후 Lettuce 가 옛 토폴로지를 계속 쓴다 — 적응형 리프레시는 명시적으로 켜야 한다
- 적용: Valkey/Redis Cluster + Lettuce
- 신호: 페일오버 후 수십 초~수 분간 `MOVED`/연결 오류 지속
- 메커니즘: Lettuce 클러스터 토폴로지 리프레시(주기적·적응형)는 기본 비활성이며, Spring Boot 에서도 `spring.data.redis.lettuce.cluster.refresh.adaptive`/`.period` 를 설정해야 켜진다.
- 처방: `refresh.adaptive=true` + `refresh.period=30s` 정도. 사용하는 Spring Boot/Lettuce 버전의 기본값을 확인.
- 반례: 단일 노드/센티널은 해당 없음(센티널은 별도 메커니즘).
- 검증: 스테이징 클러스터에서 마스터 강제 페일오버 후 오류 지속 시간 측정.
- 근거: https://redis.github.io/lettuce/ha-sharding/#redis-cluster , https://docs.spring.io/spring-boot/appendix/application-properties/index.html (spring.data.redis.lettuce.cluster.refresh)

### VK-CLI-03 · 왕복 지연이 지배적이면 파이프라이닝 — 단 클러스터에서 다중 키 명령은 같은 슬롯만
- 적용: 루프 안의 개별 GET/SET, 대량 적재
- 신호: N 건 처리 시간 ≈ N × RTT
- 메커니즘: 명령 실행은 μs 단위인데 왕복은 수백 μs~ms 다. 파이프라인은 왕복을 묶는다. `MGET`/`MSET`/트랜잭션/Lua 는 클러스터에서 모든 키가 같은 슬롯이어야 하며(`CROSSSLOT`), 해시태그로 묶으면 VK-KEY-03 핫스팟 위험.
- 처방: 클라이언트 파이프라인(Lettuce 비동기 + `flushCommands`, go-redis `Pipelined`, redis-py `pipeline(transaction=False)`) 을 수백~수천 단위 배치로. 원자성이 필요할 때만 MULTI/Lua.
- 반례: 파이프라인 응답을 모두 메모리에 모으므로 초대형 배치는 분할.
- 검증: 배치 크기별 처리량 벤치마크.
- 근거: https://valkey.io/topics/pipelining/ , https://valkey.io/topics/cluster-spec/#hash-tags

### VK-CLI-04 · `RedisTemplate` 기본 직렬화(JDK)·`@class` 타입 정보 JSON 은 배포 간 호환성과 보안을 해친다
- 적용: Spring Data Redis 캐시/세션 (클래스명은 Jackson 2 계열 기준 — Spring Boot 4/Spring Data Redis 4 의 Jackson 3 계열은 직렬화기 이름이 다를 수 있으니 해당 버전 레퍼런스로 확인)
- 신호: 키 값이 `\xac\xed` 로 시작(JDK 직렬화), JSON 값에 `"@class"` 필드, 클래스 이동·이름 변경 후 역직렬화 오류
- 메커니즘: `RedisTemplate` 기본 값 직렬화기는 `JdkSerializationRedisSerializer` 다. `GenericJackson2JsonRedisSerializer` 는 다형 타입 정보를 저장해 클래스명이 저장 형식에 결합되고, 기본 타이핑 범위가 넓으면 역직렬화 가젯 위험이 있다. 롤링 배포 중 구/신 버전이 같은 키를 읽는다.
- 처방: 캐시별 구체 타입 `Jackson2JsonRedisSerializer<T>`(또는 Kotlin/kotlinx 직렬화) + 키 버전 접두사로 스키마 변경 분리(→ team-conventions §캐시 키).
- 반례: —
- 검증: 구버전 앱이 쓴 값을 신버전 앱이 읽는 테스트.
- 근거: https://docs.spring.io/spring-data/redis/reference/redis/template.html#redis:serializer

## LOCK

### VK-LOCK-01 · 분산락은 lease 다 — GC 정지·네트워크 지연 동안 만료되면 두 소유자가 생긴다
- 적용: `SET key token NX PX`, Redisson `RLock`, Redlock 으로 상호 배제를 보장하려는 설계
- 신호: 락 획득 후 장시간 작업(외부 호출·대량 DB 쓰기), 락 해제가 토큰 비교 없이 `DEL`
- 메커니즘: 소유자가 멈춘 사이 TTL 이 지나면 다른 프로세스가 획득한다. 깨어난 원래 소유자는 자신이 아직 소유자라고 믿고 쓴다. 비동기 복제라 마스터 장애 조치 시 락 자체가 사라질 수 있다. Redisson 의 watchdog(`lockWatchdogTimeout` 기본 30s 갱신)은 **leaseTime 을 지정하지 않은 경우에만** 동작한다.
- 처방: 해제는 토큰 비교 Lua(또는 Redisson). 정합성이 중요하면 락에 의존하지 말고 **보호 대상 저장소에서 펜싱**: 단조 증가 토큰/버전 컬럼으로 조건부 쓰기(`UPDATE ... WHERE version = ?`). 효율 목적(중복 작업 줄이기)의 락만 Valkey 로.
- 반례: 중복 실행이 무해한(멱등) 작업은 단순 `SET NX PX` 로 충분.
- 검증: 락 보유 중 프로세스 정지(SIGSTOP)로 TTL 초과를 재현.
- 근거: https://valkey.io/topics/distlock/ , https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html , https://redisson.pro/docs/data-and-services/locks-and-synchronizers/

## STR

### VK-STR-01 · Pub/Sub 은 연결된 구독자에게만, Streams 는 ACK 하지 않으면 PEL 이 무한히 자란다
- 적용: 캐시 무효화 브로드캐스트(Pub/Sub), 작업 큐(Streams consumer group)
- 신호: 재시작 중 무효화 누락으로 stale 캐시 / `XPENDING` 수 증가, 메모리 증가
- 메커니즘: Pub/Sub 은 저장하지 않는다. Streams 그룹에서 읽고 `XACK` 하지 않은 항목은 Pending Entries List 에 남고, 죽은 컨슈머의 항목은 누군가 `XAUTOCLAIM`(6.2+)/`XCLAIM` 하기 전까지 처리되지 않는다. `XADD` 에 `MAXLEN`/`MINID` 를 주지 않으면 스트림은 계속 자란다.
- 처방: 무효화는 Pub/Sub + 짧은 TTL(유실 대비). Streams 는 처리 후 XACK, 주기적 XAUTOCLAIM(min-idle-time), `XADD ... MAXLEN ~ n` 근사 트리밍. 영속·재생·대량 팬아웃이 필요하면 Kafka.
- 반례: —
- 검증: `XINFO GROUPS`, `XPENDING` 모니터링.
- 근거: https://valkey.io/topics/streams-intro/ , https://valkey.io/topics/pubsub/
