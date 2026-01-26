---
name: kotlin-spring-patterns
description: Spring Boot 4.x + Kotlin 2.x + JDK 21 architecture patterns, including coroutines, virtual threads, and modern Spring conventions.
---

# Kotlin + Spring Boot 4.x Development Patterns

Modern backend patterns for Spring Boot 4.x with Kotlin 2.x on JDK 21. Covers Spring Framework 7 conventions, Kotlin idioms, and production-ready architecture.

## Technology Stack

- **Spring Boot**: 4.x (Spring Framework 7)
- **Kotlin**: 2.x (K2 compiler)
- **JDK**: 21+ (LTS with Virtual Threads)
- **Build Tool**: Gradle Kotlin DSL

## Project Structure

```
src/
├── main/
│   ├── kotlin/
│   │   └── com/example/app/
│   │       ├── Application.kt           # Main entry point
│   │       ├── config/                   # Configuration classes
│   │       │   ├── SecurityConfig.kt
│   │       │   └── WebConfig.kt
│   │       ├── domain/                   # Domain models & entities
│   │       │   ├── User.kt
│   │       │   └── Order.kt
│   │       ├── repository/               # Data access layer
│   │       │   ├── UserRepository.kt
│   │       │   └── OrderRepository.kt
│   │       ├── service/                  # Business logic
│   │       │   ├── UserService.kt
│   │       │   └── OrderService.kt
│   │       ├── controller/               # REST controllers
│   │       │   ├── UserController.kt
│   │       │   └── OrderController.kt
│   │       └── dto/                      # Data transfer objects
│   │           ├── UserDto.kt
│   │           └── OrderDto.kt
│   └── resources/
│       ├── application.yaml
│       └── db/migration/                 # Flyway migrations
└── test/
    └── kotlin/
        └── com/example/app/
            ├── integration/              # Integration tests
            └── unit/                     # Unit tests
```

## Gradle Configuration (build.gradle.kts)

```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.springframework.boot") version "4.0.0"
    id("io.spring.dependency-management") version "1.1.7"
    kotlin("jvm") version "2.1.0"
    kotlin("plugin.spring") version "2.1.0"
    kotlin("plugin.jpa") version "2.1.0"
}

group = "com.example"
version = "0.0.1-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    // Spring Boot Starters
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-actuator")

    // Kotlin
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")
    implementation("org.jetbrains.kotlin:kotlin-reflect")

    // Coroutines (optional, for reactive)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-reactor")

    // Database
    runtimeOnly("org.postgresql:postgresql")
    implementation("org.flywaydb:flyway-core")
    implementation("org.flywaydb:flyway-database-postgresql")

    // Testing - Kotest
    val kotestVersion = "5.9.1"
    testImplementation("io.kotest:kotest-runner-junit5:$kotestVersion")
    testImplementation("io.kotest:kotest-assertions-core:$kotestVersion")
    testImplementation("io.kotest:kotest-property:$kotestVersion")
    testImplementation("io.kotest.extensions:kotest-extensions-spring:1.3.0")

    // MockK & Testcontainers
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("org.testcontainers:postgresql")
    testImplementation("org.testcontainers:testcontainers")

    // Spring Boot Test (exclude JUnit 4)
    testImplementation("org.springframework.boot:spring-boot-starter-test") {
        exclude(group = "org.junit.vintage", module = "junit-vintage-engine")
    }
    testImplementation("org.springframework.security:spring-security-test")
}

kotlin {
    compilerOptions {
        freeCompilerArgs.addAll("-Xjsr305=strict")
        jvmTarget.set(JvmTarget.JVM_21)
    }
}

tasks.withType<Test> {
    useJUnitPlatform()
}
```

## Domain Models (Kotlin Data Classes)

### Entity with JPA

```kotlin
package com.example.app.domain

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "users")
data class User(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(nullable = false, unique = true)
    val email: String,

    @Column(nullable = false)
    val name: String,

    @Enumerated(EnumType.STRING)
    val status: UserStatus = UserStatus.ACTIVE,

    @Column(name = "created_at", nullable = false, updatable = false)
    val createdAt: Instant = Instant.now(),

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now()
) {
    @PreUpdate
    fun onUpdate() {
        updatedAt = Instant.now()
    }
}

enum class UserStatus {
    ACTIVE, INACTIVE, SUSPENDED
}
```

### DTO with Bean Validation 3.0

```kotlin
package com.example.app.dto

import jakarta.validation.constraints.*
import java.util.UUID

data class CreateUserRequest(
    @field:NotBlank(message = "Email is required")
    @field:Email(message = "Invalid email format")
    val email: String,

    @field:NotBlank(message = "Name is required")
    @field:Size(min = 2, max = 100, message = "Name must be 2-100 characters")
    val name: String
)

data class UpdateUserRequest(
    @field:Size(min = 2, max = 100, message = "Name must be 2-100 characters")
    val name: String? = null,

    val status: String? = null
)

data class UserResponse(
    val id: UUID,
    val email: String,
    val name: String,
    val status: String,
    val createdAt: String
) {
    companion object {
        fun from(user: User) = UserResponse(
            id = user.id!!,
            email = user.email,
            name = user.name,
            status = user.status.name,
            createdAt = user.createdAt.toString()
        )
    }
}
```

## Repository Layer

### Spring Data JPA Repository

```kotlin
package com.example.app.repository

import com.example.app.domain.User
import com.example.app.domain.UserStatus
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import java.util.UUID

interface UserRepository : JpaRepository<User, UUID> {

    fun findByEmail(email: String): User?

    fun findByStatus(status: UserStatus): List<User>

    fun existsByEmail(email: String): Boolean

    @Query("""
        SELECT u FROM User u
        WHERE u.status = :status
        AND u.createdAt >= :since
        ORDER BY u.createdAt DESC
    """)
    fun findActiveUsersSince(
        status: UserStatus,
        since: java.time.Instant
    ): List<User>
}
```

## Service Layer

### Service with Business Logic

```kotlin
package com.example.app.service

import com.example.app.domain.User
import com.example.app.domain.UserStatus
import com.example.app.dto.CreateUserRequest
import com.example.app.dto.UpdateUserRequest
import com.example.app.repository.UserRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

@Service
class UserService(
    private val userRepository: UserRepository
) {

    fun findById(id: UUID): User =
        userRepository.findById(id)
            .orElseThrow { UserNotFoundException(id) }

    fun findByEmail(email: String): User =
        userRepository.findByEmail(email)
            ?: throw UserNotFoundException(email)

    @Transactional
    fun create(request: CreateUserRequest): User {
        if (userRepository.existsByEmail(request.email)) {
            throw EmailAlreadyExistsException(request.email)
        }

        val user = User(
            email = request.email,
            name = request.name
        )

        return userRepository.save(user)
    }

    @Transactional
    fun update(id: UUID, request: UpdateUserRequest): User {
        val user = findById(id)

        val updated = user.copy(
            name = request.name ?: user.name,
            status = request.status?.let { UserStatus.valueOf(it) } ?: user.status
        )

        return userRepository.save(updated)
    }

    @Transactional
    fun delete(id: UUID) {
        val user = findById(id)
        userRepository.delete(user)
    }
}

// Custom Exceptions
class UserNotFoundException(identifier: Any) :
    RuntimeException("User not found: $identifier")

class EmailAlreadyExistsException(email: String) :
    RuntimeException("Email already exists: $email")
```

## Controller Layer

### REST Controller with ProblemDetail (RFC 7807)

```kotlin
package com.example.app.controller

import com.example.app.dto.CreateUserRequest
import com.example.app.dto.UpdateUserRequest
import com.example.app.dto.UserResponse
import com.example.app.service.UserService
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import java.net.URI
import java.util.UUID

@RestController
@RequestMapping("/api/v1/users")
class UserController(
    private val userService: UserService
) {

    @GetMapping("/{id}")
    fun getUser(@PathVariable id: UUID): UserResponse =
        UserResponse.from(userService.findById(id))

    @PostMapping
    fun createUser(
        @Valid @RequestBody request: CreateUserRequest
    ): ResponseEntity<UserResponse> {
        val user = userService.create(request)
        val response = UserResponse.from(user)

        return ResponseEntity
            .created(URI.create("/api/v1/users/${user.id}"))
            .body(response)
    }

    @PutMapping("/{id}")
    fun updateUser(
        @PathVariable id: UUID,
        @Valid @RequestBody request: UpdateUserRequest
    ): UserResponse =
        UserResponse.from(userService.update(id, request))

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteUser(@PathVariable id: UUID) {
        userService.delete(id)
    }
}
```

### Global Exception Handler (ProblemDetail RFC 7807)

```kotlin
package com.example.app.config

import com.example.app.service.EmailAlreadyExistsException
import com.example.app.service.UserNotFoundException
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import java.net.URI

@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(UserNotFoundException::class)
    fun handleNotFound(ex: UserNotFoundException): ProblemDetail {
        return ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND,
            ex.message ?: "Resource not found"
        ).apply {
            type = URI.create("https://api.example.com/errors/not-found")
            title = "Not Found"
        }
    }

    @ExceptionHandler(EmailAlreadyExistsException::class)
    fun handleConflict(ex: EmailAlreadyExistsException): ProblemDetail {
        return ProblemDetail.forStatusAndDetail(
            HttpStatus.CONFLICT,
            ex.message ?: "Resource already exists"
        ).apply {
            type = URI.create("https://api.example.com/errors/conflict")
            title = "Conflict"
        }
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ProblemDetail {
        val errors = ex.bindingResult.fieldErrors
            .associate { it.field to (it.defaultMessage ?: "Invalid") }

        return ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST,
            "Validation failed"
        ).apply {
            type = URI.create("https://api.example.com/errors/validation")
            title = "Bad Request"
            setProperty("errors", errors)
        }
    }
}
```

## Virtual Threads (JDK 21 Project Loom)

### Enable Virtual Threads

```yaml
# application.yaml
spring:
  threads:
    virtual:
      enabled: true  # Spring Boot 4.x default
```

### Virtual Thread Configuration

```kotlin
package com.example.app.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.scheduling.annotation.EnableAsync
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor
import java.util.concurrent.Executor
import java.util.concurrent.Executors

@Configuration
@EnableAsync
class AsyncConfig {

    @Bean
    fun taskExecutor(): Executor {
        // Use virtual threads for async tasks
        return Executors.newVirtualThreadPerTaskExecutor()
    }
}
```

## Coroutines Integration (WebFlux)

### Suspend Functions in Controllers

```kotlin
package com.example.app.controller

import kotlinx.coroutines.delay
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/v1/async")
class AsyncController {

    @GetMapping("/data")
    suspend fun getAsyncData(): Map<String, Any> {
        // Non-blocking delay
        delay(100)

        return mapOf(
            "status" to "success",
            "timestamp" to System.currentTimeMillis()
        )
    }
}
```

### Coroutine Service

```kotlin
package com.example.app.service

import kotlinx.coroutines.*
import org.springframework.stereotype.Service

@Service
class AsyncDataService {

    suspend fun fetchMultipleSources(): Map<String, Any> = coroutineScope {
        val source1 = async { fetchFromSource1() }
        val source2 = async { fetchFromSource2() }
        val source3 = async { fetchFromSource3() }

        mapOf(
            "source1" to source1.await(),
            "source2" to source2.await(),
            "source3" to source3.await()
        )
    }

    private suspend fun fetchFromSource1(): String {
        delay(50) // Simulate I/O
        return "data1"
    }

    private suspend fun fetchFromSource2(): String {
        delay(50)
        return "data2"
    }

    private suspend fun fetchFromSource3(): String {
        delay(50)
        return "data3"
    }
}
```

## HTTP Interface Clients (Spring 6+)

### Declarative HTTP Client

```kotlin
package com.example.app.client

import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.service.annotation.*

@HttpExchange("/api/v1")
interface ExternalApiClient {

    @GetExchange("/users/{id}")
    fun getUser(@PathVariable id: String): ExternalUserDto

    @PostExchange("/users")
    fun createUser(@RequestBody request: CreateExternalUserRequest): ExternalUserDto

    @DeleteExchange("/users/{id}")
    fun deleteUser(@PathVariable id: String)
}

data class ExternalUserDto(
    val id: String,
    val name: String,
    val email: String
)

data class CreateExternalUserRequest(
    val name: String,
    val email: String
)
```

### HTTP Client Configuration

```kotlin
package com.example.app.config

import com.example.app.client.ExternalApiClient
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.web.client.RestClient
import org.springframework.web.client.support.RestClientAdapter
import org.springframework.web.service.invoker.HttpServiceProxyFactory

@Configuration
class HttpClientConfig {

    @Bean
    fun externalApiClient(): ExternalApiClient {
        val restClient = RestClient.builder()
            .baseUrl("https://api.external.com")
            .defaultHeader("Authorization", "Bearer \${API_KEY}")
            .build()

        val adapter = RestClientAdapter.create(restClient)
        val factory = HttpServiceProxyFactory.builderFor(adapter).build()

        return factory.createClient(ExternalApiClient::class.java)
    }
}
```

## Testing Patterns

### Unit Test with MockK

```kotlin
package com.example.app.unit

import com.example.app.domain.User
import com.example.app.dto.CreateUserRequest
import com.example.app.repository.UserRepository
import com.example.app.service.EmailAlreadyExistsException
import com.example.app.service.UserService
import io.kotest.core.spec.style.BehaviorSpec
import io.kotest.matchers.shouldBe
import io.kotest.assertions.throwables.shouldThrow
import io.mockk.*
import java.util.UUID

class UserServiceTest : BehaviorSpec({

    val userRepository = mockk<UserRepository>()
    val userService = UserService(userRepository)

    beforeTest {
        clearMocks(userRepository)
    }

    Given("a new user registration request") {
        val request = CreateUserRequest(
            email = "test@example.com",
            name = "Test User"
        )

        When("the email does not exist") {
            val savedUser = User(
                id = UUID.randomUUID(),
                email = request.email,
                name = request.name
            )

            every { userRepository.existsByEmail(request.email) } returns false
            every { userRepository.save(any()) } returns savedUser

            val result = userService.create(request)

            Then("should create the user successfully") {
                result.email shouldBe request.email
                result.name shouldBe request.name
            }

            Then("should call repository methods correctly") {
                verify(exactly = 1) { userRepository.existsByEmail(request.email) }
                verify(exactly = 1) { userRepository.save(any()) }
            }
        }

        When("the email already exists") {
            every { userRepository.existsByEmail("existing@example.com") } returns true

            Then("should throw EmailAlreadyExistsException") {
                shouldThrow<EmailAlreadyExistsException> {
                    userService.create(request.copy(email = "existing@example.com"))
                }
            }

            Then("should not save the user") {
                verify(exactly = 0) { userRepository.save(any()) }
            }
        }
    }
})
```

### Integration Test with Testcontainers

```kotlin
package com.example.app.integration

import com.example.app.dto.CreateUserRequest
import io.kotest.core.spec.style.FunSpec
import io.kotest.extensions.spring.SpringExtension
import io.kotest.matchers.shouldBe
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.post
import org.testcontainers.containers.PostgreSQLContainer
import com.fasterxml.jackson.databind.ObjectMapper

@SpringBootTest
@AutoConfigureMockMvc
class UserControllerIntegrationTest : FunSpec() {

    override fun extensions() = listOf(SpringExtension)

    companion object {
        val postgres = PostgreSQLContainer("postgres:16-alpine")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test")
            .apply { start() }

        @JvmStatic
        @DynamicPropertySource
        fun configureProperties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url", postgres::getJdbcUrl)
            registry.add("spring.datasource.username", postgres::getUsername)
            registry.add("spring.datasource.password", postgres::getPassword)
        }
    }

    @Autowired
    lateinit var mockMvc: MockMvc

    @Autowired
    lateinit var objectMapper: ObjectMapper

    init {
        test("create user returns 201 Created") {
            val request = CreateUserRequest(
                email = "new@example.com",
                name = "New User"
            )

            mockMvc.post("/api/v1/users") {
                contentType = MediaType.APPLICATION_JSON
                content = objectMapper.writeValueAsString(request)
            }.andExpect {
                status { isCreated() }
                jsonPath("$.email") { value("new@example.com") }
                jsonPath("$.name") { value("New User") }
            }
        }
    }
}
```

## Security Configuration

### Spring Security 7 with Kotlin DSL

```kotlin
package com.example.app.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain

@Configuration
@EnableWebSecurity
class SecurityConfig {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http {
            csrf { disable() }
            sessionManagement {
                sessionCreationPolicy = SessionCreationPolicy.STATELESS
            }
            authorizeHttpRequests {
                authorize("/api/v1/public/**", permitAll)
                authorize("/actuator/health", permitAll)
                authorize("/api/v1/admin/**", hasRole("ADMIN"))
                authorize("/api/v1/**", authenticated)
                authorize(anyRequest, denyAll)
            }
            oauth2ResourceServer {
                jwt { }
            }
        }

        return http.build()
    }
}
```

## Application Configuration

### application.yaml

```yaml
spring:
  application:
    name: my-app

  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
    username: ${DB_USERNAME:postgres}
    password: ${DB_PASSWORD:postgres}
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5

  jpa:
    hibernate:
      ddl-auto: validate  # Use Flyway for migrations
    open-in-view: false
    properties:
      hibernate:
        format_sql: true

  flyway:
    enabled: true
    locations: classpath:db/migration

  threads:
    virtual:
      enabled: true

server:
  port: 8080
  shutdown: graceful

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when_authorized

logging:
  level:
    root: INFO
    com.example.app: DEBUG
    org.hibernate.SQL: DEBUG
```

## Quick Reference

### Common Commands

```bash
# Build
./gradlew build

# Run tests
./gradlew test

# Run with dev profile
./gradlew bootRun --args='--spring.profiles.active=dev'

# Format with ktlint
./gradlew ktlintFormat

# Check code style
./gradlew ktlintCheck

# Generate JaCoCo report
./gradlew jacocoTestReport
```

### Kotlin Best Practices in Spring

1. **Use data classes for DTOs** - Immutable by default
2. **Prefer constructor injection** - Works naturally with Kotlin's primary constructor
3. **Use null safety** - Avoid `!!` operator, prefer `?:` and `?.let { }`
4. **Extension functions** - Great for utility methods
5. **Coroutines for async** - Better than CompletableFuture for Kotlin
6. **Sealed classes for state** - Type-safe state machines

---

**Remember**: Spring Boot 4.x + Kotlin 2.x provides a modern, type-safe, and performant backend stack. Leverage Kotlin's features (null safety, data classes, coroutines) alongside Spring's ecosystem for clean, maintainable code.
