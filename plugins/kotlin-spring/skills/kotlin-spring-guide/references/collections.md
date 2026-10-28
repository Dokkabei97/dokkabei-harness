# 컬렉션·자료구조 — O(1) 이 실제로 O(1) 인 조건 (JVM-COL, KT-COL)

> 먼저 확인: 컬렉션 크기(수십 vs 수십만), 수명(요청 단위 vs 상주), 동시 접근 여부, 키 타입(enum/숫자/문자열/복합 키).
> 작은 단명 컬렉션에서는 대부분 무의미하다 — 핫 경로나 상주 대형 컬렉션에서만 적용한다.

### JVM-COL-01 · `HashMap(n)` 은 n 개를 리사이즈 없이 담지 못한다
- 적용: 크기를 아는 대량 적재(쿼리 결과 → 맵, 배치 인덱싱 버퍼).
- 신호: `HashMap(list.size)`, `HashSet(ids.size)`. 프로파일 상위에 `HashMap.resize`.
- 메커니즘: 생성자 인자는 capacity(2의 거듭제곱으로 올림)이고 threshold = capacity × 0.75. n=1000 → capacity 1024, threshold 768 → 적재 도중 전체 rehash 1회와 배열 재할당.
- 처방: JDK 19+ `HashMap.newHashMap(n)`, `HashSet.newHashSet(n)`, `LinkedHashMap.newLinkedHashMap(n)`. Kotlin `associate*`/`toMap()` 은 내부에서 크기를 맞춰 잡는다. 직접 만들면 `(n / 0.75f).toInt() + 1`.
- 반례: loadFactor 를 1.0 으로 올려 메모리를 줄이려 하면 충돌 체인이 길어진다.
- 검증: JMH `-prof gc`, JFR 할당에서 `HashMap$Node[]`.
- 근거: https://bugs.openjdk.org/browse/JDK-8186958 , https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/HashMap.html

### JVM-COL-02 · 충돌 트리화는 Comparable 키일 때만 O(log n) 이다
- 적용: JDK 8+ `HashMap`/`ConcurrentHashMap`.
- 신호: 해시 품질이 낮은 키(일부 필드만 쓰는 hashCode, 상수 hashCode), 외부 입력을 키로 쓰는 맵(HashDoS).
- 메커니즘: bin 길이 ≥ 8(TREEIFY_THRESHOLD) **그리고** 테이블 용량 ≥ 64(MIN_TREEIFY_CAPACITY)일 때만 레드블랙 트리로 바뀌고(아니면 리사이즈), 6 이하로 줄면 리스트로 복귀. 트리는 hash → 같은 클래스의 Comparable → identityHashCode 순으로 정렬하므로, 해시가 같고 Comparable 이 아닌 키는 양쪽 서브트리를 뒤져 사실상 선형 탐색이 된다.
- 처방: hashCode 가 equals 의 모든 필드를 섞게 한다(Kotlin data class 는 **primary 생성자 프로퍼티만** 포함 — body 프로퍼티는 빠진다). 외부 입력 키 타입은 Comparable 구현.
- 반례: —
- 검증: 키 집합의 hashCode 분포 히스토그램, 충돌 키셋 JMH.
- 근거: https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/util/HashMap.java (구현 노트)

### JVM-COL-03 · enum 키는 EnumMap/EnumSet — 해시 없는 배열 인덱싱
- 적용: 키가 enum 인 맵/집합.
- 신호: `HashMap<Status, X>`, `mutableSetOf<Status>()`, 핫 루프의 `status in setOf(A, B)`(매 호출 Set 생성).
- 메커니즘: EnumMap 은 ordinal 인덱스 배열(해시·Node 없음), EnumSet 은 상수 64개 이하면 `long` 비트벡터 하나라 `contains` 가 비트 연산이다.
- 처방: `EnumMap<Status, X>(Status::class.java)`, `EnumSet.of(A, B)` 를 상수로 hoist. 상수 순회는 Kotlin 1.9+ `entries`(미리 할당된 리스트) — `values()` 는 호출마다 배열을 복제한다.
- 반례: —
- 검증: JMH.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/EnumMap.html , https://kotlinlang.org/docs/enum-classes.html#working-with-enum-constants

### JVM-COL-04 · IdentityHashMap — 그래프 순회의 방문 집합
- 적용: 객체 그래프 순회·사이클 탐지·직렬화 중복 방지처럼 "같은 인스턴스"를 묻는 경우.
- 신호: 방문 집합을 `HashSet` 으로 구현 → 깊은 data class equals/hashCode 비용, JPA 엔티티면 hashCode 가 lazy 연관을 초기화.
- 메커니즘: `System.identityHashCode` + `==`, 선형 탐사 오픈 어드레싱(키·값을 한 배열에 교대로 저장) → Node 객체가 없다.
- 처방: `Collections.newSetFromMap(IdentityHashMap<Any, Boolean>())`.
- 반례: 값 의미의 키(문자열, ID)에 쓰면 동등한 다른 인스턴스를 구분해 버그가 된다. Map 일반 계약을 어기므로 public API 로 반환하지 않는다.
- 검증: 단위 테스트.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/IdentityHashMap.html

### JVM-COL-05 · LinkedHashMap LRU 에서는 `get` 도 쓰기 연산이다
- 적용: `LinkedHashMap(cap, 0.75f, true)` + `removeEldestEntry` 로 만든 캐시.
- 신호: 멀티스레드에서 동기화 없이 사용하거나, ReadWriteLock 의 read lock 으로 `get` 을 보호 → `ConcurrentModificationException`, 링크 손상.
- 메커니즘: access-order 모드에서는 `get` 이 엔트리를 꼬리로 옮기는 구조 변경이다(javadoc 명시).
- 처방: 단일 스레드 전용으로만 쓴다. 동시성이 필요하면 Caffeine(W-TinyLFU, 크기·시간 기반 만료) 또는 Spring Cache + Caffeine.
- 반례: —
- 검증: 동시성 스트레스 테스트, Caffeine `recordStats()` 적중률.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/LinkedHashMap.html , https://github.com/ben-manes/caffeine

### JVM-COL-06 · `ConcurrentHashMap.computeIfAbsent` — 재귀 갱신 예외와 bin 락
- 적용: 메모이제이션 캐시, 레지스트리.
- 신호: `IllegalStateException: Recursive update`(JDK 9+, JDK 8 은 무한 루프/행). 매핑 함수 안에서 원격 호출·DB 조회. JFR `jdk.JavaMonitorEnter` 스택에 `ConcurrentHashMap`.
- 메커니즘: 매핑 함수가 도는 동안 해당 bin 의 첫 노드에 `synchronized` 를 잡는다 → 같은 bin 의 다른 키 갱신까지 대기. 함수 안에서 같은 맵을 수정하면 안 된다(javadoc). `synchronized` 이므로 JDK 21~23 가상 스레드에선 pinning(JVM-CONC-01)까지 겹친다. JDK 8 은 키가 이미 있어도 락을 잡는 경로가 있었다(JDK-8161372).
- 처방: 매핑 함수는 짧고 순수하게. 비싼 로딩은 Caffeine `cache.get(key) { load(it) }`/`AsyncLoadingCache`. 중복 계산을 허용하면 `map[key] ?: compute(key).let { map.putIfAbsent(key, it) ?: it }`.
- 반례: 계산이 싸면 그대로가 가장 단순하고 빠르다.
- 검증: async-profiler `-e lock`, JFR 모니터 이벤트.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/ConcurrentHashMap.html , https://bugs.openjdk.org/browse/JDK-8161372

### KT-COL-01 · `mutableMapOf`/`mutableSetOf`/`toSet()` 은 Linked 구현이다
- 적용: Kotlin/JVM 의 상주 대형 컬렉션.
- 신호: 수십만~수백만 엔트리 캐시를 기본 팩토리로 생성, 순서는 필요 없음.
- 메커니즘: `mutableMapOf()` = `LinkedHashMap`, `mutableSetOf()`/`toSet()`/`toMutableSet()` = `LinkedHashSet`. 엔트리에 before/after 참조가 붙어 압축 OOP 기준 엔트리당 32 → 40바이트.
- 처방: 순서가 필요 없는 대형 컬렉션은 `HashMap()`/`hashMapOf()`/`HashSet()`/`toHashSet()`. 반환 타입은 `Map`/`Set` 로 유지.
- 반례: 직렬화 출력·스냅샷 테스트·API 응답이 삽입 순서에 의존하고 있으면(사실상의 계약) 바꾸면 회귀다.
- 검증: JOL `GraphLayout.parseInstance(map).totalSize()`.
- 근거: https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/mutable-map-of.html

### KT-COL-02 · `List<Int>`·`Map<Long, V>` 박싱 — 원시 배열·원시 맵
- 적용: 수십만+ 원소의 숫자 컬렉션 상주, 핫 루프.
- 신호: `List<Int>`, `Array<Int>`, `Set<Long>`, `Map<Long, X>` 대형. 힙 덤프 상위에 `java.lang.Long`/`Integer`.
- 메커니즘: `List<Int>`/`Array<Int>` 는 `Integer` 참조 배열 — 원소당 객체 16바이트 + 참조 4바이트 vs `IntArray` 4바이트(약 5배). Integer 캐시는 -128..127 뿐. `Int?`, 제네릭 위치, `Any` 전달도 박싱.
- 처방: `IntArray`/`LongArray`. 원시 키 맵은 fastutil `Long2ObjectOpenHashMap`, Eclipse Collections, HPPC(의존성 추가는 프로젝트 결정). 키 공간이 작고 조밀하면 배열 인덱싱이 가장 빠른 O(1).
- 반례: 작은 컬렉션·API 경계에서는 `List<Int>` 의 가독성이 우선.
- 검증: JOL, JMH `-prof gc`(`gc.alloc.rate.norm`).
- 근거: https://kotlinlang.org/docs/arrays.html#primitive-type-arrays , https://fastutil.di.unimi.it/

### KT-COL-03 · Sequence vs Iterable — 손익분기
- 적용: Kotlin 컬렉션 연산 체인.
- 신호: 대형 리스트에 `.map{}.filter{}.map{}.first()`(중간 리스트 3개), 반대로 원소 수십 개에 `asSequence()` 남용.
- 메커니즘: Iterable 연산은 `inline` 이라 람다 객체·가상 호출이 없지만 단계마다 중간 `ArrayList` 를 만든다. Sequence 는 원소 단위 지연 평가로 중간 컬렉션이 없고 단락(`first`/`take`/`any`)이 되지만, 연산자가 inline 이 아니어서 람다 객체 + 이터레이터 체인 + 공유 콜사이트의 메가모픽화(JVM-JIT-02)가 붙는다.
- 처방: 단계가 2개 이상이면서 원소가 많거나 단락 종결 연산이 있으면 Sequence. 단일 단계·소형·결과 전체가 필요하면 Iterable. `sorted()`/`groupBy` 같은 상태 연산은 Sequence 의 이점을 상쇄한다.
- 반례: 고정 임계값을 믿지 말고 측정한다 — 손익분기는 원소 크기·람다 비용·박싱 여부에 따라 움직인다.
- 검증: JMH(시간 + `gc.alloc.rate.norm`).
- 근거: https://kotlinlang.org/docs/sequences.html

### KT-COL-05 · Kotlin 1.6+ `list - list`·`removeAll(list)` 는 더 이상 내부에서 HashSet 으로 바꾸지 않는다
- 적용: Kotlin 1.6+ (1.5 이하에서 업그레이드한 코드 포함). 일반적인 루프 안 `x in list` 의 O(n·m) 은 다루지 않는다(상식).
- 신호: `bigList - otherList`, `bigList.minus(otherList)`, `mutable.removeAll(otherList)`/`retainAll(otherList)`, `subtract` 를 큰 인자 컬렉션과 함께 사용. Kotlin 업그레이드 후 해당 구간만 느려짐.
- 메커니즘: 1.6 전에는 stdlib 가 인자 컬렉션을 내부적으로 HashSet 으로 변환해 O(n) 에 가까웠다. 불안정한 `hashCode` 원소에서 결과가 틀릴 수 있어 1.6 에서 변환을 없앴고, 이제 인자가 `List` 면 원소마다 선형 `contains` → O(n·m). 1.6 에 한해 JVM 시스템 프로퍼티 `kotlin.collections.convert_arg_to_set_in_removeAll=true` 로 임시 복원할 수 있었으나 **1.7 부터는 효과가 없다** — 처방으로 쓰지 말 것.
- 처방: 인자를 명시적으로 `toHashSet()`(또는 처음부터 `Set`)으로 넘긴다 — `bigList - otherList.toHashSet()`.
- 반례: 인자가 작으면(수십 개 이하) 변환 비용이 더 크다. 원소의 `hashCode`/`equals` 가 불안정·불일치하면 Set 변환이 결과를 바꾼다(변경의 이유).
- 검증: 입력 크기 2배 시 시간 4배 여부, JMH.
- 근거: https://kotlinlang.org/docs/compatibility-guide-16.html , https://kotlinlang.org/api/core/1.6/kotlin-stdlib/kotlin.collections/minus.html , https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/minus.html

### KT-COL-06 · value class 는 제네릭·nullable·인터페이스 위치에서 박싱된다
- 적용: `@JvmInline value class UserId(val value: Long)` 로 ID 를 감싼 코드.
- 신호: `List<UserId>`, `Map<UserId, X>`, `UserId?` 대량 사용. 프레임워크 리플렉션(파생 쿼리, 목 라이브러리)에서 메서드를 못 찾음.
- 메커니즘: 제네릭 인자·nullable·인터페이스 타입으로 쓰이면 래퍼 객체가 생긴다. value class 를 파라미터로 받는 함수는 JVM 이름이 맹글링(`foo-<hash>`)되어 Java/리플렉션 기반 도구와 어긋날 수 있다.
- 처방: 대량 컬렉션은 기저 타입으로 보관. 프레임워크 경계(Spring Data, Jackson, MockK)는 사용 버전의 value class 지원을 문서로 확인한 뒤 적용.
- 반례: 타입 안전성이 주목적이고 컬렉션 규모가 작으면 그대로 쓴다.
- 검증: 바이트코드(`javap`), JMH 할당량.
- 근거: https://kotlinlang.org/docs/inline-classes.html#representation , https://kotlinlang.org/docs/inline-classes.html#mangling

> 결번: JVM-COL-07(BigDecimal equals/scale), KT-COL-04(data class 배열 프로퍼티) — 범용 지식이라 제거(IDE·정적 분석이 잡는다). ID 는 재사용하지 않는다.
