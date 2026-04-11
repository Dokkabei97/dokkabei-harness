# JPA Patterns — Entity 설계, N+1, 연관 관계, 영속성 컨텍스트

Kotlin + Spring Data JPA에서 성능과 정합성을 위한 모범 사례.

---

## Entity 설계

### 기본 Entity 구조

```kotlin
@Entity
@Table(name = "orders")
class OrderEntity(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L,

    @Column(nullable = false, length = 100)
    var name: String,

    @Column(nullable = false, precision = 12, scale = 2)
    var amount: BigDecimal,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    var status: OrderStatus = OrderStatus.CREATED,

    @Column(nullable = false, updatable = false)
    val createdAt: LocalDateTime = LocalDateTime.now(),

    @Column(nullable = false)
    var updatedAt: LocalDateTime = LocalDateTime.now(),
) {
    // 도메인 로직은 Entity 내부에
    fun validateStatusTransition(target: OrderStatus) {
        val allowed = VALID_TRANSITIONS[status]
            ?: error("현재 상태에서 전이 불가: $status")
        require(target in allowed) {
            "$status → $target 전이는 허용되지 않습니다"
        }
    }

    companion object {
        private val VALID_TRANSITIONS = mapOf(
            OrderStatus.CREATED to setOf(OrderStatus.CONFIRMED, OrderStatus.CANCELLED),
            OrderStatus.CONFIRMED to setOf(OrderStatus.SHIPPED, OrderStatus.CANCELLED),
            OrderStatus.SHIPPED to setOf(OrderStatus.DELIVERED),
        )
    }
}
```

### data class vs class

```kotlin
// ❌ BAD: data class Entity — equals/hashCode가 모든 필드 비교
// JPA 프록시, 지연 로딩, 변경 감지와 충돌
@Entity
data class OrderEntity(
    @Id val id: Long = 0L,
    var name: String,
)

// ✅ GOOD: 일반 class + 필요시 수동 equals/hashCode
@Entity
class OrderEntity(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L,
    var name: String,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is OrderEntity) return false
        return id != 0L && id == other.id
    }

    override fun hashCode(): Int = javaClass.hashCode()
}
```

**결론:** JPA Entity에는 `data class`를 사용하지 않는다. `data class`의 `equals`, `hashCode`, `copy`가 JPA 영속성 컨텍스트와 충돌한다.

### BaseEntity — 공통 Audit 필드

```kotlin
@MappedSuperclass
@EntityListeners(AuditingEntityListener::class)
abstract class BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L

    @CreatedDate
    @Column(nullable = false, updatable = false)
    var createdAt: LocalDateTime = LocalDateTime.now()
        protected set

    @LastModifiedDate
    @Column(nullable = false)
    var updatedAt: LocalDateTime = LocalDateTime.now()
        protected set
}

// 사용
@Entity
@Table(name = "orders")
class OrderEntity(
    var name: String,
    var status: OrderStatus = OrderStatus.CREATED,
) : BaseEntity()
```

**주의:** `@EnableJpaAuditing`을 Config 클래스에 추가해야 동작한다.

```kotlin
@Configuration
@EnableJpaAuditing
class JpaConfig
```

### Soft Delete

```kotlin
@Entity
@Table(name = "members")
@Where(clause = "deleted_at IS NULL")
@SQLDelete(sql = "UPDATE members SET deleted_at = NOW() WHERE id = ?")
class MemberEntity(
    var name: String,

    @Column(name = "deleted_at")
    var deletedAt: LocalDateTime? = null,
) : BaseEntity() {

    fun softDelete() {
        deletedAt = LocalDateTime.now()
    }
}
```

---

## N+1 문제

### 문제 상황

```kotlin
// Entity 정의
@Entity
class OrderEntity(
    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
    val items: MutableList<OrderItemEntity> = mutableListOf(),
) : BaseEntity()

// ❌ BAD: N+1 발생
val orders = orderRepository.findAll()      // 1번 쿼리
orders.forEach { order ->
    println(order.items.size)                // 주문 수(N)만큼 추가 쿼리
}
// 총 N+1 번 쿼리 실행
```

### 해결 방법

#### 1. Fetch Join (가장 흔한 해결)

```kotlin
interface OrderRepository : JpaRepository<OrderEntity, Long> {
    @Query("""
        SELECT DISTINCT o FROM OrderEntity o
        JOIN FETCH o.items
        WHERE o.status = :status
    """)
    fun findByStatusWithItems(@Param("status") status: OrderStatus): List<OrderEntity>
}
```

**주의:** Fetch Join + Pageable은 메모리에서 페이지네이션 → 대량 데이터 시 OOM

#### 2. @EntityGraph

```kotlin
interface OrderRepository : JpaRepository<OrderEntity, Long> {
    @EntityGraph(attributePaths = ["items"])
    fun findByStatus(status: OrderStatus): List<OrderEntity>
}
```

#### 3. @BatchSize (글로벌 전략)

```kotlin
@Entity
class OrderEntity(
    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
    @BatchSize(size = 100)  // IN 쿼리로 100개씩 배치 로딩
    val items: MutableList<OrderItemEntity> = mutableListOf(),
)

// 또는 application.yml에서 글로벌 설정
// spring.jpa.properties.hibernate.default_batch_fetch_size: 100
```

#### 4. DTO Projection (읽기 전용 최적화)

```kotlin
// 필요한 필드만 조회 — Entity 프록시 자체를 생성하지 않음
@Query("""
    SELECT new com.example.dto.OrderSummary(o.id, o.name, o.status, SIZE(o.items))
    FROM OrderEntity o
    WHERE o.status = :status
""")
fun findSummaryByStatus(@Param("status") status: OrderStatus): List<OrderSummary>
```

### N+1 해결 전략 선택 가이드

| 상황 | 전략 | 이유 |
|------|------|------|
| 단건 조회 + 연관 엔티티 필요 | Fetch Join | 쿼리 1번으로 해결 |
| 목록 조회 + 연관 엔티티 필요 (소량) | @EntityGraph | 선언적, 간결 |
| 목록 조회 + 연관 엔티티 필요 (대량) | @BatchSize | 페이지네이션 호환 |
| 읽기 전용 + 일부 필드만 필요 | DTO Projection | 최고 성능 |
| 페이지네이션 + Fetch Join 필요 | @BatchSize + Pageable | OOM 방지 |

---

## 연관 관계 매핑

### @ManyToOne (가장 흔한 관계)

```kotlin
@Entity
@Table(name = "order_items")
class OrderItemEntity(
    @ManyToOne(fetch = FetchType.LAZY)  // 항상 LAZY
    @JoinColumn(name = "order_id", nullable = false)
    val order: OrderEntity,

    @Column(nullable = false)
    var productName: String,

    @Column(nullable = false)
    var quantity: Int,

    @Column(nullable = false)
    var price: BigDecimal,
) : BaseEntity()
```

**핵심 규칙:** `@ManyToOne`은 **항상 `FetchType.LAZY`**로 설정한다. 기본값이 `EAGER`이므로 명시적으로 지정해야 한다.

### @OneToMany (양방향)

```kotlin
@Entity
class OrderEntity(
    @OneToMany(mappedBy = "order", cascade = [CascadeType.ALL], orphanRemoval = true)
    val items: MutableList<OrderItemEntity> = mutableListOf(),
) : BaseEntity() {

    // 연관 관계 편의 메서드 — 양쪽 참조를 동기화
    fun addItem(item: OrderItemEntity) {
        items.add(item)
    }

    fun removeItem(item: OrderItemEntity) {
        items.remove(item)
    }
}
```

### 안티패턴: 양방향 의존 과다

```kotlin
// ❌ BAD: 모든 관계를 양방향으로 만듦
@Entity
class UserEntity(
    @OneToMany(mappedBy = "user") val orders: MutableList<OrderEntity>,
    @OneToMany(mappedBy = "author") val reviews: MutableList<ReviewEntity>,
    @OneToMany(mappedBy = "sender") val messages: MutableList<MessageEntity>,
    // ... 수많은 컬렉션
)

// ✅ GOOD: 필요한 경우만 양방향, 나머지는 단방향 @ManyToOne
// 조회가 필요하면 Repository 쿼리로 해결
interface OrderRepository : JpaRepository<OrderEntity, Long> {
    fun findByUserId(userId: Long): List<OrderEntity>
}
```

---

## 영속성 컨텍스트

### 변경 감지 (Dirty Checking)

```kotlin
@Transactional
fun updateName(id: Long, newName: String) {
    val entity = orderRepository.findByIdOrNull(id)
        ?: throw OrderNotFoundException(id)

    entity.name = newName  // setter만 호출하면 자동 UPDATE
    // ✅ save() 호출 불필요 — 트랜잭션 커밋 시 변경 감지가 UPDATE 쿼리 실행
}
```

### save() vs 변경 감지

| 상황 | 방법 | 이유 |
|------|------|------|
| 새 엔티티 생성 | `repository.save(entity)` | 영속 상태로 전환 필요 |
| 기존 엔티티 수정 | 필드 수정만 (save 불필요) | 변경 감지가 자동 처리 |
| 명시적 flush 필요 | `repository.saveAndFlush(entity)` | 즉시 DB 반영 |

### 주의사항

```kotlin
// ❌ BAD: @Transactional 없이 변경 — 변경 감지 불가
fun updateName(id: Long, newName: String) {
    val entity = orderRepository.findByIdOrNull(id) ?: return
    entity.name = newName  // 변경 감지 불가, DB에 반영 안 됨
}

// ❌ BAD: @Transactional(readOnly = true)에서 변경 — 경고 없이 무시됨
@Transactional(readOnly = true)
fun updateName(id: Long, newName: String) {
    val entity = orderRepository.findByIdOrNull(id) ?: return
    entity.name = newName  // flush 생략됨, DB에 반영 안 됨
}
```

---

## ID 전략

| 전략 | 장점 | 단점 | 적합한 경우 |
|------|------|------|------------|
| `IDENTITY` | 단순, auto_increment | 배치 INSERT 최적화 불가 | 일반적인 CRUD |
| `SEQUENCE` | 배치 INSERT 가능, 사전 할당 | 시퀀스 테이블 관리 | 대량 데이터 INSERT |
| `UUID` | 분산 시스템, 외부 노출 안전 | 인덱스 성능, 크기(16 bytes) | MSA, 외부 공개 ID |

```kotlin
// IDENTITY (가장 흔한)
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
val id: Long = 0L

// UUID
@Id
@Column(columnDefinition = "BINARY(16)")
val id: UUID = UUID.randomUUID()

// SEQUENCE (배치 최적화)
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
@SequenceGenerator(name = "order_seq", sequenceName = "order_sequence", allocationSize = 50)
val id: Long = 0L
```

---

## Enum 매핑

```kotlin
// ✅ GOOD: EnumType.STRING — DB에 문자열로 저장
@Enumerated(EnumType.STRING)
@Column(nullable = false, length = 20)
var status: OrderStatus = OrderStatus.CREATED

// ❌ BAD: EnumType.ORDINAL — 순서 변경 시 데이터 깨짐
@Enumerated(EnumType.ORDINAL)
var status: OrderStatus = OrderStatus.CREATED
```

**핵심:** `EnumType.STRING`만 사용한다. `ORDINAL`은 Enum 순서가 바뀌면 기존 데이터가 깨진다.

---

## 쿼리 최적화 팁

### exists 대신 count 사용 금지

```kotlin
// ❌ BAD: count — 전체 행 카운트 후 비교
val exists = orderRepository.count() > 0

// ✅ GOOD: exists — 첫 번째 행만 확인
val exists = orderRepository.existsByStatus(OrderStatus.CREATED)
```

### Slice vs Page

```kotlin
// Page — COUNT 쿼리 추가 실행 (전체 개수 필요할 때)
fun findByStatus(status: OrderStatus, pageable: Pageable): Page<OrderEntity>

// Slice — COUNT 쿼리 없음 (더보기/무한스크롤에 적합)
fun findByStatus(status: OrderStatus, pageable: Pageable): Slice<OrderEntity>
```

### 벌크 업데이트

```kotlin
// 대량 상태 변경 — 변경 감지 대신 벌크 쿼리
@Modifying(clearAutomatically = true)
@Query("UPDATE OrderEntity o SET o.status = :status WHERE o.createdAt < :before")
fun bulkUpdateStatus(
    @Param("status") status: OrderStatus,
    @Param("before") before: LocalDateTime,
): Int
```

**주의:** `@Modifying`은 영속성 컨텍스트를 우회하므로 `clearAutomatically = true`로 캐시를 초기화해야 한다.
