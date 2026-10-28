# Kafka 스페셜리스트 항목 (KFK)

영역: PRD 프로듀서 · CON 컨슈머 · TOP 토픽/브로커 · EOS 정확히 한 번.
**클라이언트 버전이 기본값을 바꾼다** — 먼저 빌드 파일에서 `kafka-clients`(Spring Kafka 가 끌어오는 버전 포함), Go 클라이언트(franz-go, segmentio/kafka-go, confluent-kafka-go/librdkafka) 종류와 버전을 확인한다. 아래 기본값은 Java 클라이언트 기준이며 Go 클라이언트(kafka-go·librdkafka·franz-go)는 기본값·파티셔너가 다르다(KFK-PRD-06).

---

## PRD

### KFK-PRD-01 · 3.0+ 프로듀서 기본은 `acks=all` + idempotence — 하지만 충돌 설정이 있으면 idempotence 는 조용히 꺼진다
- 적용: kafka-clients 3.0+ (3.0.0/3.1.0 에는 idempotence 기본값이 적용되지 않는 버그 KAFKA-13598, 3.0.1/3.1.1 에서 수정)
- 신호: 설정에 `acks=1`, `retries=0`, `max.in.flight.requests.per.connection > 5` 중 하나가 있고 `enable.idempotence` 는 명시 안 함
- 메커니즘: KIP-679 로 기본값이 `enable.idempotence=true`, `acks=all` 이 되었다. 이후 수정(KAFKA-13673)으로 idempotence 를 **명시하지 않은 상태에서** 충돌 설정이 있으면 idempotence 가 비활성화된다(명시적으로 true 면 ConfigException). 결과적으로 재시도 시 중복·재정렬이 생긴다.
- 처방: 의도가 "중복 없는 재시도" 면 `enable.idempotence=true` 를 **명시**해 충돌을 기동 시점에 실패로 드러낸다. `retries` 를 낮추지 말고 `delivery.timeout.ms` 로 상한을 잡는다(KFK-PRD-02).
- 반례: 지연 최소·유실 허용 텔레메트리는 `acks=1` 이 합리적일 수 있다(그때 idempotence 는 포기).
- 검증: 기동 로그의 `ProducerConfig values:` 에서 실제 `enable.idempotence`, `acks` 확인.
- 근거: https://cwiki.apache.org/confluence/display/KAFKA/KIP-679%3A+Producer+will+enable+the+strongest+delivery+guarantee+by+default , https://issues.apache.org/jira/browse/KAFKA-13673 , https://kafka.apache.org/documentation/#producerconfigs_enable.idempotence

### KFK-PRD-02 · 재시도 상한은 `retries` 가 아니라 `delivery.timeout.ms`(기본 120s)
- 적용: Java 클라이언트 2.1+
- 신호: `retries=3` 같은 설정으로 실패를 빨리 감지하려는 코드, 브로커 장애 시 `send()` 콜백이 2분 뒤에야 실패
- 메커니즘: `retries` 기본값은 사실상 무한(Integer.MAX_VALUE)이고 `send()` 부터 성공/실패 보고까지의 총 시간은 `delivery.timeout.ms` 가 제한한다(`>= linger.ms + request.timeout.ms` 여야 함). 버퍼가 차면 `send()` 자체가 `max.block.ms`(기본 60s) 동안 호출 스레드를 막는다 — 요청 처리 스레드/코루틴에서 동기 블로킹.
- 처방: SLO 에 맞춰 `delivery.timeout.ms`·`max.block.ms` 를 조정. 요청 경로에서는 `send()` 블로킹 가능성을 고려해 타임아웃 예산에 포함(DIST-TMO-01).
- 반례: 배치/백그라운드 프로듀서는 기본값이 안전.
- 검증: 브로커 차단(toxiproxy 등) 상태에서 send 실패까지 시간 측정.
- 근거: https://kafka.apache.org/documentation/#producerconfigs_delivery.timeout.ms , https://kafka.apache.org/documentation/#producerconfigs_max.block.ms

### KFK-PRD-03 · `linger.ms` 기본값이 4.0 에서 0 → 5ms 로 바뀌었다
- 적용: kafka-clients 4.0+ 로 업그레이드
- 신호: 업그레이드 후 저트래픽 경로의 publish 지연이 수 ms 증가
- 메커니즘: KIP-1030 이 작은 요청 남발을 줄이려고 기본 `linger.ms` 를 5ms 로 올렸다. 처리량은 개선되지만 저부하에서 지연이 늘 수 있다.
- 처방: 지연 민감 경로만 `linger.ms=0` 을 명시. 처리량 경로는 `batch.size`(기본 16384)와 함께 상향 검토.
- 반례: 대부분의 서비스는 새 기본값이 유리.
- 검증: 프로듀서 메트릭 `record-queue-time-avg`, `batch-size-avg`.
- 근거: https://cwiki.apache.org/confluence/display/KAFKA/KIP-1030:+Change+constraints+and+default+values+for+various+configurations

### KFK-PRD-04 · 파티션 키 스큐: 핫 키 하나가 파티션 하나와 컨슈머 하나를 포화시킨다
- 적용: 키 기반 순서 보장이 필요한 토픽
- 신호: 파티션별 lag 편차가 큼(한두 파티션만 lag), 특정 테넌트/상품 이벤트 폭주
- 메커니즘: 기본 파티셔너는 키 해시 mod 파티션 수다. 순서는 파티션 안에서만 보장되므로 같은 키는 항상 한 컨슈머 스레드에 묶인다. 파티션 수를 늘리면 키→파티션 매핑이 바뀌어 **전환 시점에 키 순서가 깨진다**.
- 처방: 순서가 실제로 필요한 최소 단위로 키 선택(주문 ID > 고객 ID > 테넌트 ID). 핫 키는 키에 버킷 접미사를 붙이고 소비 측에서 재조립하거나, 순서가 불필요하면 키 생략. 파티션 수는 처음부터 여유 있게 잡는다.
- 반례: 키 없이 보내면(sticky 파티셔너) 균등하지만 순서 보장이 없다.
- 검증: `kafka-consumer-groups --describe` 의 파티션별 LAG, 프로듀서 측 키 빈도 샘플링.
- 근거: https://kafka.apache.org/documentation/#design_partitioning , https://cwiki.apache.org/confluence/display/KAFKA/KIP-794%3A+Strictly+Uniform+Sticky+Partitioner

### KFK-PRD-05 · idempotence 는 "같은 프로듀서 세션의 브로커 재시도" 만 중복 제거한다
- 적용: "idempotent producer 를 켰으니 중복 없음" 이라는 가정이 있는 설계
- 신호: 앱이 send 타임아웃 후 직접 재전송, 프로듀서 재시작 후 재전송
- 메커니즘: idempotence 는 프로듀서 ID + 파티션별 시퀀스 번호로 **클라이언트 내부 재시도**만 중복 제거한다. 앱 레벨 재전송, 프로세스 재시작, 다른 인스턴스의 재처리는 다른 메시지다.
- 처방: 소비 측 멱등 처리(이벤트 ID 기반 dedupe 테이블 또는 upsert)를 기본으로(DIST-IDEM-01).
- 반례: —
- 검증: 프로듀서 강제 종료/재시작 카오스 테스트 후 컨슈머 측 중복 수.
- 근거: https://kafka.apache.org/documentation/#semantics

### KFK-PRD-06 · Go 클라이언트는 기본값과 기본 파티셔너가 Java 와 다르다 — 같은 토픽을 함께 쓰면 키 순서가 깨진다
- 적용: Go 프로듀서(segmentio/kafka-go, confluent-kafka-go/librdkafka, franz-go), 특히 Java 와 Go 프로듀서가 같은 키 기반 토픽에 쓰는 경우
- 신호: `kafka.Writer{Addr: ..., Topic: ...}` 를 `Balancer`·`RequiredAcks`·`BatchTimeout` 없이 생성, 동기 `WriteMessages` 호출당 ~1s 지연, 같은 키의 이벤트가 여러 파티션에 흩어짐(언어별 프로듀서 혼재)
- 메커니즘: segmentio/kafka-go `Writer` 기본값은 `Balancer` = round-robin(키를 무시하므로 키별 순서 보장 없음), `RequiredAcks` = `RequireNone`(acks=0, fire-and-forget), `BatchSize` 100 · `BatchTimeout` 1s(배치가 차지 않으면 최대 1초 대기 후 flush — 저트래픽 동기 쓰기는 호출마다 ~1s). 키 해시도 언어별로 다르다: Java 기본은 murmur2, librdkafka(confluent-kafka-go) 기본 `partitioner=consistent_random`(CRC32), kafka-go `Hash` 밸런서는 Sarama 호환(FNV-1a). 같은 키가 프로듀서 언어에 따라 다른 파티션으로 간다.
- 처방: kafka-go 는 `Balancer: &kafka.Murmur2Balancer{}`(Java 호환), `RequiredAcks: kafka.RequireAll`, 지연 민감 경로는 `BatchTimeout` 을 ms 단위로. confluent-kafka-go 는 `"partitioner": "murmur2_random"`. franz-go 기본(sticky key 파티셔너, 키는 Kafka murmur2 해시)은 Java 와 호환되고 acks=all + idempotence 기본이라 그대로 두면 된다.
- 반례: 한 언어의 프로듀서만 쓰는 토픽이면 파티셔너 호환은 무관(acks·배치 기본값은 여전히 확인).
- 검증: 같은 키 집합을 Java·Go 프로듀서로 보내 `kafka-console-consumer --property print.partition=true` 로 파티션 일치 확인, 쓰기 지연 히스토그램.
- 근거: https://github.com/segmentio/kafka-go/blob/main/writer.go (Writer 필드 주석) , https://pkg.go.dev/github.com/segmentio/kafka-go#Murmur2Balancer , https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md (partitioner) , https://pkg.go.dev/github.com/twmb/franz-go/pkg/kgo#StickyKeyPartitioner

## CON

### KFK-CON-01 · 처리 시간 > `max.poll.interval.ms`(기본 5분)면 리밸런스 → 같은 배치 재처리 → 무한 반복
- 적용: 레코드당 외부 호출·DB 쓰기를 하는 컨슈머
- 신호: 로그 `Member ... sending LeaveGroup request ... since the consumer poll timeout has expired`, `CommitFailedException`, lag 은 그대로인데 처리량 0
- 메커니즘: `poll()` 사이 간격이 `max.poll.interval.ms` 를 넘으면 컨슈머가 그룹에서 제외되고 파티션이 재할당된다. 커밋되지 않은 배치(`max.poll.records` 기본 500)는 다른 컨슈머가 처음부터 다시 처리한다. 외부 API 가 느려지면 장애가 증폭된다.
- 처방: 배치당 최악 처리 시간 = `max.poll.records × 레코드당 최악 시간` 을 계산해 둘 중 하나를 조정. 레코드당 외부 호출에는 짧은 타임아웃(→ [team-conventions.md](team-conventions.md) §타임아웃)과 병렬화. 하트비트는 백그라운드 스레드라 `session.timeout.ms`(3.0+ 기본 45s)와는 별개 문제.
- 반례: `max.poll.interval.ms` 를 무작정 늘리면 진짜 멈춘 컨슈머의 감지가 늦어진다.
- 검증: 컨슈머 메트릭 `time-between-poll-max`, `last-poll-seconds-ago`.
- 근거: https://kafka.apache.org/documentation/#consumerconfigs_max.poll.interval.ms , https://cwiki.apache.org/confluence/display/KAFKA/KIP-735%3A+Increase+default+consumer+session+timeout

### KFK-CON-02 · 리밸런스 프로토콜: eager 는 전원 정지, cooperative-sticky 는 이동분만 — 3.0+ 기본 목록이면 롤링 1회, Range 단독이면 2회로 전환
- 적용: 컨슈머 수가 많거나 배포가 잦은 그룹, Kafka 4.0+ 에선 새 그룹 프로토콜(KIP-848)
- 신호: 배포/스케일 때마다 전 파티션 처리 정지(stop-the-world), lag 톱니 모양
- 메커니즘: 3.0+ 기본 `partition.assignment.strategy` 는 `[RangeAssignor, CooperativeStickyAssignor]` — 목록 첫 번째인 Range(eager)가 쓰인다. 전환 중에는 그룹 전 멤버가 공통으로 지원하는 프로토콜만 쓰이므로 출발점에 따라 절차가 다르다: **기본 목록이 적용 중**이면 모든 멤버가 이미 cooperative 를 지원하므로 Range 를 뺀 설정으로 **롤링 1회**면 된다(ConsumerConfig 문서 명시). **Range(또는 다른 eager 전략) 단독 설정이거나 2.x 클라이언트**면 ① 두 전략을 모두 넣고 롤링 → ② eager 제거 후 롤링, **2회**. Kafka 4.0 은 브로커 측 할당의 새 컨슈머 프로토콜(`group.protocol=consumer`)이 GA 다.
- 처방: 현재 실효 설정(기동 로그 `ConsumerConfig values:` 의 `partition.assignment.strategy`)으로 출발점을 확인한 뒤 위 절차로 cooperative-sticky 로 전환하거나(클라이언트 3.x), 브로커·클라이언트가 4.0+ 면 `group.protocol=consumer` 검토. 정적 멤버십(`group.instance.id`)으로 롤링 재시작 시 리밸런스 자체를 생략.
- 반례: 컨슈머 1~2개인 소규모 그룹은 체감 이득이 작다.
- 검증: 리밸런스 시간 메트릭 `rebalance-latency-avg`, 배포 중 lag 그래프.
- 근거: https://kafka.apache.org/documentation/#consumerconfigs_partition.assignment.strategy , https://github.com/apache/kafka/blob/trunk/clients/src/main/java/org/apache/kafka/clients/consumer/ConsumerConfig.java (PARTITION_ASSIGNMENT_STRATEGY_DOC: "single rolling bounce that removes the RangeAssignor") , https://cwiki.apache.org/confluence/display/KAFKA/KIP-429%3A+Kafka+Consumer+Incremental+Rebalance+Protocol , https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol

### KFK-CON-03 · Spring Kafka `DefaultErrorHandler` 기본은 0ms 간격 10회 시도 후 로그만 남기고 건너뛴다
- 적용: Spring Kafka 2.8+
- 신호: 장애 시 같은 레코드가 순식간에 10번 실패 후 사라짐(DLT 미구성), 또는 역직렬화 실패 레코드에서 무한 루프(ErrorHandlingDeserializer 미사용)
- 메커니즘: 기본 백오프는 `FixedBackOff(0L, 9)` — 지연 없이 9회 재시도 후 recoverer(기본 로그)로 넘기고 오프셋을 진행한다. `DeserializationException` 등 일부 예외는 재시도 없이 바로 recoverer. 역직렬화가 리스너 도달 전에 실패하면 `ErrorHandlingDeserializer` 로 감싸야 에러 핸들러가 처리할 수 있다.
- 처방: `DefaultErrorHandler(DeadLetterPublishingRecoverer(template), ExponentialBackOffWithMaxRetries(n))` 로 지수 백오프 + DLT 명시. 비즈니스 검증 실패는 `addNotRetryableExceptions`. 블로킹 재시도는 파티션을 막으므로 긴 재시도는 non-blocking retry 토픽(`@RetryableTopic`).
- 반례: 순서가 절대적인 토픽은 non-blocking retry 가 순서를 깨므로 블로킹 + 알람.
- 검증: 리스너에 실패 주입 테스트(EmbeddedKafka/Testcontainers)로 시도 횟수·DLT 도착 확인.
- 근거: https://docs.spring.io/spring-kafka/reference/kafka/annotation-error-handling.html

### KFK-CON-04 · 리스너가 처리를 다른 스레드/코루틴에 던지고 void 로 반환하면 커밋이 처리보다 앞서 유실된다
- 적용: 리스너 안에서 `launch {}`·`GlobalScope`·executor 제출·`subscribe()` 로 fire-and-forget 위임하고 반환 타입은 `Unit`/`void`
- 신호: 재시작 후 일부 메시지 미처리, 처리 실패가 커밋을 막지 못함
- 메커니즘: 동기 반환 리스너에서 오프셋 커밋(자동 커밋이든 Spring 의 BATCH/RECORD ack 든)은 리스너 메서드 **반환** 기준이다. 결과를 반환하지 않는 비동기 위임은 처리 완료 전에 커밋된다. 예외: **Spring Kafka 3.2+** 는 리스너 반환 타입이 `CompletableFuture<?>`·`Mono<?>`·Kotlin `suspend fun` 이면 AckMode 를 자동으로 `MANUAL` + out-of-order 커밋으로 바꾸고 비동기 완료 시점에 ack 한다.
- 처방: (a) Spring Kafka 3.2+ 면 `suspend fun` 리스너(또는 `CompletableFuture` 반환)로 완료까지 기다리게 한다 — 단 비동기 결과 객체를 만들기 **전에** 던져진 예외는 리스너가 잡아 실패 완료된 결과로 반환해야 한다(문서 명시). 비동기 결과의 실패는 컨테이너 에러 핸들러(KFK-CON-03)가 처리. (b) 그 이전 버전은 리스너 안에서 처리를 끝내고 반환(배치 리스너 + 내부 병렬 `awaitAll`, → team-conventions 예시). (c) 직접 수동 ack 를 할 때는 오프셋이 파티션 내 연속이어야 하므로 순서 밖 완료를 추적해야 한다.
- 반례: 유실 허용 이벤트(메트릭 등). (a) 의 비동기 반환은 이전 레코드 완료 전에 다음 레코드를 처리할 수 있어 **파티션 내 처리 순서가 보장되지 않는다** — 순서가 중요한 토픽은 (b) 처럼 리스너 안에서 완료까지 블로킹하고 처리량은 concurrency(파티션 수)로 얻는다.
- 검증: 처리 중 프로세스 kill 후 재기동해 처리 누락 수 확인.
- 근거: https://docs.spring.io/spring-kafka/reference/kafka/receiving-messages/message-listener-container.html#committing-offsets , https://docs.spring.io/spring-kafka/reference/kafka/receiving-messages/async-returns.html , https://kafka.apache.org/documentation/#consumerconfigs_enable.auto.commit

### KFK-CON-05 · 새 그룹은 `auto.offset.reset=latest`(기본)로 기존 메시지를 건너뛰고, 유휴 그룹의 오프셋은 7일 뒤 사라진다
- 적용: 신규 컨슈머 그룹 배포, 오래 멈춘 그룹 재가동
- 신호: 새 서비스가 배포 이전 이벤트를 못 받음 / 장기 중단 후 재가동 시 처음부터(earliest) 또는 최신부터(latest) 재시작
- 메커니즘: 커밋된 오프셋이 없으면 reset 정책을 따른다. 브로커는 그룹이 비어 있는 동안 `offsets.retention.minutes`(2.0+ 기본 7일) 이후 커밋 오프셋을 삭제한다.
- 처방: 신규 그룹의 시작 위치를 의도적으로 결정(`earliest` + 멱등 처리, 또는 배포 전 `kafka-consumer-groups --reset-offsets --to-datetime`). 장기 중단 예정 그룹은 오프셋을 외부에 기록.
- 반례: —
- 검증: 배포 체크리스트에 그룹 오프셋 확인 단계.
- 근거: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset , https://kafka.apache.org/documentation/#brokerconfigs_offsets.retention.minutes

### KFK-CON-06 · 컨슈머 랙은 오프셋 수가 아니라 "시간" 으로 알람을 건다
- 적용: 컨슈머 모니터링
- 신호: 트래픽 변동에 따라 오탐/미탐이 잦은 lag 알람
- 메커니즘: 오프셋 lag 1만은 초당 10만 건 토픽에선 0.1초, 초당 10건 토픽에선 17분이다.
- 처방: 시간 기반 지연(가장 오래된 미처리 레코드 타임스탬프와 현재의 차, 또는 Burrow/kafka-lag-exporter 의 시간 추정)으로 알람. 파티션별로 본다(KFK-PRD-04 스큐 탐지).
- 반례: —
- 검증: 컨슈머 정지 실험에서 알람 발생 시간.
- 근거: https://kafka.apache.org/documentation/#consumer_monitoring

## TOP

### KFK-TOP-01 · `acks=all` 은 `min.insync.replicas`(기본 1)와 함께여야 내구성이 생긴다
- 적용: 유실 불가 토픽
- 신호: RF=3, `acks=all` 인데 브로커 장애 후 확인된 메시지 유실
- 메커니즘: `acks=all` 은 "현재 ISR 전원" 의 확인이다. ISR 이 리더 하나로 줄어도 min.insync.replicas=1 이면 쓰기가 성공하고, 그 리더를 잃으면 유실된다. `unclean.leader.election.enable` 기본은 false.
- 처방: RF=3 + `min.insync.replicas=2`(토픽 또는 브로커) + `acks=all`. ISR 부족 시 프로듀서는 `NotEnoughReplicas` 로 실패하므로 알람.
- 반례: RF=1 개발 클러스터.
- 검증: `kafka-topics --describe` 의 설정, 메트릭 `UnderMinIsrPartitionCount`.
- 근거: https://kafka.apache.org/documentation/#topicconfigs_min.insync.replicas

### KFK-TOP-02 · 컴팩션 토픽의 tombstone 은 `delete.retention.ms`(기본 24h) 뒤 사라진다 — 상태 재구성 컨슈머는 그 안에 읽어야 한다
- 적용: 컴팩션 토픽으로 상태(KTable, 캐시 재구성)를 유지
- 신호: 장기 중단 컨슈머가 재구성 후 삭제된 키를 살아 있다고 판단
- 메커니즘: null 값(tombstone)은 컴팩션 후 `delete.retention.ms` 동안만 남는다. 그보다 늦게 읽은 컨슈머는 삭제 사실을 보지 못한다.
- 처방: 재구성 컨슈머의 최대 중단 허용 시간 < delete.retention.ms 로 설정하거나, 재구성 시 전체 스냅샷과 대조.
- 반례: —
- 검증: 토픽 설정 확인, 재구성 테스트.
- 근거: https://kafka.apache.org/documentation/#topicconfigs_delete.retention.ms , https://kafka.apache.org/documentation/#compaction

## EOS

### KFK-EOS-01 · 정확히 한 번(EOS)의 범위는 "Kafka 읽기 → 처리 → Kafka 쓰기" 뿐이다
- 적용: `transactional.id`, `isolation.level=read_committed`, Kafka Streams `exactly_once_v2`
- 신호: "EOS 를 켰으니 DB 쓰기/HTTP 호출도 한 번" 이라는 가정
- 메커니즘: 트랜잭션은 출력 토픽 쓰기와 입력 오프셋 커밋을 원자적으로 묶을 뿐, 외부 시스템 부작용은 재시도 시 반복된다. 또한 컨슈머 기본 `isolation.level=read_uncommitted` 라 abort 된 메시지도 읽는다. read_committed 컨슈머는 열린 트랜잭션의 LSO 에서 멈추므로 오래 열린 트랜잭션이 하위 lag 을 만든다.
- 처방: 외부 부작용은 멱등 키 + upsert 또는 outbox(DIST-MSG-01). 트랜잭션 프로듀서를 쓰면 하위 컨슈머를 read_committed 로 맞추고 `transaction.timeout.ms` 를 짧게.
- 반례: 순수 Kafka→Kafka 변환(Streams)은 EOS 가 그대로 유효.
- 검증: 처리 중 강제 종료 카오스 테스트 후 외부 시스템 중복 수.
- 근거: https://kafka.apache.org/documentation/#semantics , https://kafka.apache.org/documentation/#consumerconfigs_isolation.level
