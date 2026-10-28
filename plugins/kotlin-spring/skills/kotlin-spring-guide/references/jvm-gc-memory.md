# JVM GC 선택·튜닝 / 메모리 풋프린트 (JVM-GC, JVM-MEM)

> 먼저 확인: 런타임 JDK 메이저 버전(Dockerfile 베이스 이미지, `java -version`), 배포판(Temurin/Corretto/Oracle),
> 컨테이너 리밋(requests/limits), 현재 JVM 플래그(`jcmd <pid> VM.flags`). 버전·배포판에 따라 항목의 적용 여부가 갈린다.
> GC 튜닝보다 할당 감소(JVM-OBS-02 alloc 프로파일)가 먼저다.

### JVM-GC-01 · 소형 컨테이너에서 JVM이 조용히 Serial GC를 고른다
- 적용: JDK 9 ~ 26, GC 플래그 미지정, CPU 1개 또는 메모리 1792MB 미만으로 보이는 환경(1 vCPU 파드). JDK 27+ 는 JEP 523 으로 항상 G1.
- 신호: `jcmd <pid> VM.flags` 에 `-XX:+UseSerialGC`, `-Xlog:gc` 첫 줄 `Using Serial`. p99 지연 스파이크가 힙 크기에 비례.
- 메커니즘: 서버급 머신이 아니라고 판정하면 ergonomics 가 Serial 을 고른다. Serial 은 단일 스레드 STW 수집이라 old 수집 pause 가 힙 크기에 비례한다.
- 처방: GC 를 명시한다(`-XX:+UseG1GC`, 지연 요건이 있으면 JVM-GC-06). 1 vCPU 에서는 G1 동시 스레드도 요청 처리와 경쟁하므로 CPU limit 2 이상을 검토.
- 반례: 힙 수백 MB 이하 배치/CLI/사이드카는 Serial 이 풋프린트·처리량 모두 유리할 수 있다.
- 검증: `java -XX:+PrintCommandLineFlags -version` 를 같은 리밋의 컨테이너에서 실행.
- 근거: https://openjdk.org/jeps/523 , https://docs.oracle.com/en/java/javase/21/gctuning/ergonomics.html

### JVM-GC-02 · 컨테이너 힙이 리밋의 25% 로 잡힌다 / 100% 로 잡으면 OOMKilled
- 적용: `-Xmx` 미지정, UseContainerSupport 기본 on(JDK 10+, 8u191+). cgroup v2 노드는 JDK 15+/11.0.16+/8u372+ 여야 리밋을 읽는다(그 미만은 호스트 메모리 기준).
- 신호: 2GiB 리밋 파드에서 `Runtime.maxMemory()` ≈ 512MiB 이고 힙 OOM 인데 RSS 는 여유. 반대로 `-Xmx` = 리밋으로 올린 뒤 exit 137(OOMKilled).
- 메커니즘: `MaxRAMPercentage` 기본 25. RSS 에는 힙 외에 메타스페이스, 코드캐시(티어드 기본 예약 240MB), 스레드 스택(Linux x64 기본 1MB × 스레드 수, 커밋은 사용분), 다이렉트 버퍼, GC 자료구조, malloc 아레나(JVM-MEM-01)가 더해진다.
- 처방: `-XX:MaxRAMPercentage=60~75`(+ 리사이즈 회피가 필요하면 `-XX:InitialRAMPercentage` 같은 값). 스레드·Netty·다이렉트 버퍼가 많은 앱일수록 낮게. limits 없이 requests 만 둔 파드는 퍼센트의 기준이 노드 메모리가 되므로 `-Xmx` 명시.
- 반례: 비힙이 매우 큰 앱(대형 오프힙 캐시)은 퍼센트가 아니라 절대값으로 예산을 짠다.
- 검증: `-XX:NativeMemoryTracking=summary` 후 `jcmd <pid> VM.native_memory summary` 합계 vs cgroup `memory.current`.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/specs/man/java.html (MaxRAMPercentage, UseContainerSupport), https://bugs.openjdk.org/browse/JDK-8230305

### JVM-GC-03 · CPU limit 없는 파드에서 JVM 은 노드 전체 코어를 본다
- 적용: JDK 19+ (17.0.5, 11.0.17 백포트) — CPU shares(k8s requests)를 프로세서 수 계산에서 제외. requests 만 있고 limits 없는 파드.
- 신호: 64코어 노드에서 `availableProcessors()` = 64 → GC 스레드, `ForkJoinPool.commonPool`, `Dispatchers.Default`, Netty 이벤트 루프, 가상 스레드 캐리어가 64 기준으로 생성. 컨텍스트 스위칭·노이지 네이버.
- 메커니즘: JDK-8281181 이후 quota(limits)가 없으면 호스트 CPU 수를 쓴다. 이전 버전은 shares 1024 = 1 CPU 로 환산해 반대로 과소 산정.
- 처방: `-XX:ActiveProcessorCount=<requests 근사값>` 명시. 기동 로그에 `availableProcessors` 출력.
- 반례: limits 가 설정되어 quota 가 반영되면 불필요.
- 검증: `jcmd <pid> VM.flags`, 스레드 덤프에서 `GC Thread#` 개수.
- 근거: https://bugs.openjdk.org/browse/JDK-8281181

### JVM-GC-04 · 압축 OOP 32GB 경계 — 힙을 늘렸는데 담을 수 있는 객체가 줄어든다
- 적용: 64-bit HotSpot 의 G1/Parallel/Serial(ZGC 는 압축 OOP 를 쓰지 않음).
- 신호: `-Xmx32g` 이상, `-XX:+PrintFlagsFinal` 에서 `UseCompressedOops = false`. 힙을 키웠는데 GC 빈도·live set 비율 개선이 없다.
- 메커니즘: 8바이트 정렬에서 32-bit 압축 참조는 32GB 까지 주소 지정. 경계를 넘으면 모든 참조가 8바이트가 되어 참조 많은 힙은 수십 % 팽창, 캐시 효율 하락. 32GB 바로 아래에서도 zero-based 모드가 아니면 디코딩 비용이 붙는다.
- 처방: 약 31GB 이하로 유지하고 실제 모드를 확인. 경계를 넘길 거면 대폭(대략 40GB+) 넘겨야 손익이 맞는다. `-XX:ObjectAlignmentInBytes=16` 으로 64GB 까지 압축 가능하지만 패딩 낭비가 생긴다.
- 반례: 큰 프리미티브 배열 위주 힙은 영향이 작다.
- 검증: `java -Xmx31g -Xlog:gc+heap+coops=info -version` 출력의 `Compressed Oops mode`(Zero based 여부).
- 근거: https://docs.oracle.com/en/java/javase/21/vm/java-hotspot-virtual-machine-performance-enhancements.html , https://www.elastic.co/guide/en/elasticsearch/reference/current/advanced-configuration.html#set-jvm-heap-size

### JVM-GC-05 · G1 humongous 할당 — 큰 버퍼가 GC 원인이 된다
- 적용: G1. region 크기는 힙/2048 근처의 2의 거듭제곱, ergonomics 는 1~32MB(JDK 18+ 수동 지정 최대 512MB).
- 신호: GC 로그 원인 `G1 Humongous Allocation`, `Humongous regions: a->b` 증가. 큰 JSON 직렬화 `byte[]`, ES/Kafka bulk 요청 버퍼, 거대한 `ArrayList` 확장 배열.
- 메커니즘: region 의 절반 이상인 객체는 연속 humongous region 에 직접 할당되어 마지막 region 의 잔여가 낭비되고, 할당 자체가 concurrent cycle 을 트리거할 수 있다. 4GB 힙이면 region 2MB → 1MB 이상 객체가 humongous.
- 처방: 버퍼를 청크/스트리밍으로(Jackson streaming 쓰기, bulk 크기 상한). 어쩔 수 없으면 `-XX:G1HeapRegionSize=4m|8m|16m` 상향(region 수 감소 영향 측정).
- 반례: 드물게 생성되는 장수명 대형 배열(조회 테이블)은 문제가 아니다.
- 검증: `-Xlog:gc*` 의 humongous region 수 추이, JFR `jdk.ObjectAllocationOutsideTLAB` 스택.
- 근거: https://docs.oracle.com/en/java/javase/21/gctuning/garbage-first-g1-garbage-collector1.html , https://bugs.openjdk.org/browse/JDK-8275056

### JVM-GC-06 · ZGC — 버전마다 같은 플래그의 의미가 다르다
- 적용: JDK 21(JEP 439, `-XX:+UseZGC -XX:+ZGenerational` 를 줘야 세대형), JDK 23(JEP 474, 세대형이 기본 모드), JDK 24+(JEP 490, 비세대 모드 제거). 기본 GC 는 여전히 G1.
- 신호: JDK 21 에서 `-XX:+UseZGC` 만 지정 → 비세대 ZGC 로 할당률 높은 서비스에서 `Allocation Stall`(JFR `jdk.ZAllocationStall`).
- 메커니즘: 비세대 ZGC 는 매 사이클 전체 힙을 마킹해 할당 속도를 따라잡지 못한다. ZGC 는 압축 OOP 를 쓰지 않고 동시 수집 여유 공간이 필요해 같은 데이터에 더 큰 힙이 든다.
- 처방: JDK 21 은 `ZGenerational` 명시. 힙 여유 확보, `-XX:SoftMaxHeapSize` 로 평시 목표 설정. GC pause 가 p99 를 지배한다는 측정이 있을 때만 선택.
- 반례: 작은 힙·처리량 우선 배치는 G1/Parallel 이 CPU 효율적.
- 검증: 동일 부하 A/B 로 p99 와 CPU 사용률을 함께 비교.
- 근거: https://openjdk.org/jeps/439 , https://openjdk.org/jeps/474 , https://openjdk.org/jeps/490

### JVM-GC-07 · Shenandoah — 배포판에 따라 아예 없다
- 적용: OpenJDK 계열 빌드(Temurin, Corretto, Red Hat 등)에 포함, Oracle JDK 빌드엔 없음. 세대형은 JDK 24 실험, JDK 25 정식(JEP 521), 기본은 단일 세대.
- 신호: Oracle JDK 이미지에서 `-XX:+UseShenandoahGC` → `Unrecognized VM option` 으로 기동 실패.
- 메커니즘: 동시 압축(concurrent compaction)으로 pause 가 힙 크기와 거의 무관.
- 처방: 베이스 이미지 배포판을 먼저 확인. JDK 25+ 세대형: `-XX:+UseShenandoahGC -XX:ShenandoahGCMode=generational`.
- 반례: 처리량 최우선이면 G1/Parallel.
- 검증: `java -XX:+UseShenandoahGC -version`.
- 근거: https://openjdk.org/jeps/521 , https://wiki.openjdk.org/display/shenandoah/Main

### JVM-GC-08 · MaxGCPauseMillis 를 낮추면 오히려 느려진다
- 적용: G1(기본 목표 200ms).
- 신호: `-XX:MaxGCPauseMillis=20` 같은 공격적인 값 이후 young GC 빈도 급증, 처리량 하락, `to-space exhausted`. `-Xmn`/`NewRatio` 를 함께 고정.
- 메커니즘: G1 은 목표를 맞추려 eden 을 줄여 GC 횟수와 조기 승격이 늘어난다. young 크기를 고정하면 pause 목표 제어 자체가 꺼진다.
- 처방: 기본값에서 시작해 측정 후 조정. G1 에서는 young 크기 고정 플래그를 쓰지 않는다.
- 반례: —
- 검증: GC 로그 pause 분포와 처리량을 함께 본다.
- 근거: https://docs.oracle.com/en/java/javase/21/gctuning/garbage-first-garbage-collector-tuning.html

### JVM-GC-09 · `-XX:+DisableExplicitGC` 가 다이렉트 메모리 OOM 을 만든다
- 적용: NIO DirectByteBuffer 를 쓰는 경로(Netty/WebClient, gRPC, Kafka·ES 클라이언트).
- 신호: `OutOfMemoryError: Cannot reserve ... bytes of direct buffer memory`(메시지는 JDK 버전별 상이), 힙은 여유.
- 메커니즘: 다이렉트 버퍼의 네이티브 메모리는 소유 객체가 GC 될 때 Cleaner 로 해제된다. 한도에 닿으면 `java.nio.Bits.reserveMemory` 가 `System.gc()` 로 회수를 시도하는데, 비활성화하면 그 기회가 없다. `MaxDirectMemorySize` 기본값 = 최대 힙.
- 처방: DisableExplicitGC 대신 `-XX:+ExplicitGCInvokesConcurrent`(G1). 다이렉트 한도를 명시해 RSS 예산에 포함.
- 반례: Netty 풀 버퍼는 자체 카운터(`io.netty.maxDirectMemory`)로 따로 관리되므로 별도 추적.
- 검증: `BufferPoolMXBean("direct")`, NMT 의 `Other` 카테고리.
- 근거: https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/nio/Bits.java

### JVM-MEM-01 · RSS 가 NMT 합계보다 계속 크다 — glibc malloc 아레나
- 적용: glibc 기반 이미지(Debian/Ubuntu 계열, Alpine musl 은 해당 없음), 스레드가 많은 앱.
- 신호: NMT committed 합계보다 RSS 가 수백 MB 크고 시간이 갈수록 증가하다 OOMKilled. `pmap -x` 에 64MB 단위 anon 블록 다수.
- 메커니즘: glibc 는 경합 시 64-bit 기준 코어 수 × 8 개까지 아레나를 만들고, 아레나별 단편화가 반환되지 않는다.
- 처방: 환경변수 `MALLOC_ARENA_MAX=2`(또는 4). 대안으로 jemalloc 프리로드. 환경변수를 못 바꾸고 JVM 옵션만 가능하면 `-XX:TrimNativeHeapInterval=<ms>`(주기적 malloc_trim, Linux glibc 전용 — JDK 22+ 정식, 21.0.3+/17.0.12+ 는 product 플래그로 백포트, 그 이전 업데이트는 실험 플래그일 수 있으니 `-XX:+PrintFlagsFinal` 로 확인). 진단은 `jcmd <pid> System.trim_native_heap` 전후 RSS 비교로 단편화 여부부터 확인.
- 반례: 네이티브 할당 집약 라이브러리(압축 등)는 경합이 늘 수 있으니 측정.
- 검증: 적용 전후 `/proc/<pid>/status` VmRSS 추이.
- 근거: https://man7.org/linux/man-pages/man3/mallopt.3.html (M_ARENA_MAX), https://bugs.openjdk.org/browse/JDK-8293114 , https://bugs.openjdk.org/browse/JDK-8325496

### JVM-MEM-02 · 한글 문자열은 Compact Strings 이득이 없다
- 적용: JDK 9+(JEP 254). 한국어 텍스트를 대량 상주시키는 서비스(상품명, 검색 문서, 사전).
- 신호: 힙 덤프에서 String 의 `byte[]` 비중이 크다. 메모리 추정을 "문자당 1바이트"로 했다.
- 메커니즘: 모든 문자가 Latin-1 일 때만 1바이트/문자. 한 글자라도 한글이 섞이면 그 문자열 전체가 UTF-16 2바이트/문자.
- 처방: 용량 산정은 2바이트/문자로. 대량 상주 데이터의 주 레버는 중복 제거와 사전 ID 화(반복 값 → int ID). 장수명 중복 문자열은 `-XX:+UseStringDeduplication`(JDK 18+ 는 Serial·Parallel·G1·Shenandoah·ZGC 모두 지원, 그 이전은 G1·Shenandoah). UTF-8 `byte[]` 보관은 ASCII 가 대부분인 텍스트(ID·URL·혼합 상품코드)에서만 이득.
- 반례: 요청 단위로 생성·폐기되는 문자열엔 무의미. 한글 위주 텍스트를 UTF-8 `byte[]` 로 바꾸면 오히려 커진다 — 한글 음절(U+AC00–D7A3)은 UTF-8 3바이트 vs UTF-16 2바이트.
- 검증: Eclipse MAT 의 String retained size, JOL.
- 근거: https://openjdk.org/jeps/254 , https://openjdk.org/jeps/192 , https://www.rfc-editor.org/rfc/rfc3629 , https://bugs.openjdk.org/browse/JDK-8267185

### JVM-MEM-03 · Compact Object Headers — 작은 객체가 많은 힙
- 적용: JDK 24 실험(JEP 450), JDK 25 정식(JEP 519, 기본 off).
- 신호: 박싱 숫자, 맵 노드, 작은 DTO 가 힙 대부분.
- 메커니즘: 64-bit 에서 객체 헤더가 12~16바이트에서 8바이트로 준다.
- 처방: `-XX:+UseCompactObjectHeaders` 를 A/B 로 적용(JDK 25+).
- 반례: 대형 배열 위주 힙은 효과가 작다.
- 검증: GC 로그의 live set, JOL.
- 근거: https://openjdk.org/jeps/519

### JVM-MEM-04 · OOM 힙 덤프가 재시작과 함께 사라진다
- 적용: 컨테이너 배포.
- 신호: OOM 재시작 후 원인을 알 수 없다. 덤프 중 liveness probe 실패로 kill.
- 메커니즘: `HeapDumpOnOutOfMemoryError` 의 기본 경로는 작업 디렉터리(컨테이너 임시 FS)이고 힙 크기만큼 디스크가 필요하다. OOM 이후 반쯤 살아있는 JVM 이 계속 트래픽을 받기도 한다.
- 처방: `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=<영속 볼륨> -XX:+ExitOnOutOfMemoryError`, probe 타임아웃 여유.
- 반례: 힙 덤프에는 개인정보가 들어간다 — 보관·접근 정책을 먼저 정한다.
- 검증: 스테이징에서 `jcmd <pid> GC.heap_dump <path>` 로 쓰기 시간과 용량 확인.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/specs/man/java.html
