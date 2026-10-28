---
name: security-patterns
description: |
  인증/인가 패턴 레퍼런스 — Spring Security JWT/OAuth2/RBAC, FastAPI OAuth2PasswordBearer/Depends 기반 권한, Three-Tier Boundary System, OWASP Top 10 매핑
  Reference for authentication/authorization patterns — Spring Security JWT/OAuth2/RBAC, FastAPI OAuth2PasswordBearer/Depends-based permissions, the Three-Tier Boundary System, and OWASP Top 10 mapping. Use when: implementing login/JWT/OAuth2 flows, designing RBAC, adding FastAPI auth dependencies, mapping OWASP risks.
---

# 인증/인가(Security) 패턴 레퍼런스

## Three-Tier Boundary System

보안 관련 의사결정을 위한 3단계 분류. 개발 중 "이것을 해도 되는가?"에 대한 즉시 판단 기준을 제공한다.

### Always Do (항상 수행)
- 사용자 입력을 **항상** 검증/이스케이프 (SQL, HTML, 쉘 명령 모두)
- 비밀번호는 **항상** bcrypt/scrypt/argon2로 해싱 (절대 평문 저장 안 함)
- 인증 토큰은 **항상** 서버 측에서 검증
- 민감 데이터(토큰, 비밀키)는 **항상** 환경 변수 또는 시크릿 매니저에서 로드
- HTTPS를 **항상** 강제 (HTTP redirect 포함)
- 에러 응답에 **절대** 스택 트레이스나 내부 구조를 노출하지 않음

### Ask First (확인 후 결정)
- CORS origin 확장 → 보안팀 또는 리드에게 확인
- 인증 예외 경로 추가 (permitAll) → 정말 공개 API인지 확인
- 외부 서비스에 사용자 데이터 전달 → 개인정보 처리 방침 확인
- 로깅에 사용자 식별 정보 포함 → 데이터 보존 정책 확인
- 암호화 알고리즘 변경 → 보안 담당자 리뷰

### Never Do (절대 하지 않음)
- 클라이언트 측에서만 인가 검사 (서버 검증 필수)
- 평문 비밀번호 저장 또는 가역적 암호화 사용
- 사용자 입력을 직접 SQL/쉘 명령에 삽입
- 프로덕션 시크릿을 코드/설정 파일에 하드코딩
- 보안 관련 리뷰 없이 인증/인가 코드 머지

## OWASP Top 10 매핑

현재 이 스킬의 패턴이 OWASP Top 10의 어떤 위협을 방어하는지 매핑:

| OWASP 위협 | 대응 패턴 (이 문서 내 위치) |
|------------|---------------------------|
| A01: Broken Access Control | RBAC 패턴 (§2, §4), @PreAuthorize, Depends 인가 |
| A02: Cryptographic Failures | JWT TokenProvider (§1), BCryptPasswordEncoder |
| A03: Injection | Parameterized query (Spring Data JPA/SQLAlchemy 기본 적용) |
| A04: Insecure Design | Three-Tier Boundary System (위 섹션) |
| A05: Security Misconfiguration | SecurityFilterChain 설정 (§1), CORS/CSRF 설정 |
| A06: Vulnerable Components | → Dependency Discipline (`/review-mr` 참조) |
| A07: Auth Failures | JWT 인증 필터 (§1), Refresh Token Rotation (§1) |
| A08: Data Integrity Failures | JWT 서명 검증, 역직렬화 제한 |
| A09: Logging Failures | → `observability-patterns` 스킬 참조 |
| A10: SSRF | → 외부 API 호출 시 URL 화이트리스트 적용 (Rate Limiting §6) |

---

## 1. Spring Security 인증 (Authentication)

### SecurityFilterChain Bean 설정 (Spring Security 6.x 람다 DSL)

```kotlin
@Configuration
@EnableWebSecurity
class SecurityConfig(
    private val jwtAuthenticationFilter: JwtAuthenticationFilter,
    private val jwtAuthenticationEntryPoint: JwtAuthenticationEntryPoint,
) {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        return http
            .csrf { it.disable() }  // stateless API는 CSRF 불필요
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .exceptionHandling { it.authenticationEntryPoint(jwtAuthenticationEntryPoint) }
            .authorizeHttpRequests {
                it
                    .requestMatchers("/api/auth/**").permitAll()
                    .requestMatchers("/api/public/**").permitAll()
                    .requestMatchers("/actuator/health").permitAll()
                    .requestMatchers("/api/admin/**").hasRole("ADMIN")
                    .anyRequest().authenticated()
            }
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter::class.java)
            .build()
    }

    @Bean
    fun passwordEncoder(): PasswordEncoder = BCryptPasswordEncoder()

    @Bean
    fun authenticationManager(config: AuthenticationConfiguration): AuthenticationManager =
        config.authenticationManager
}
```

### JWT 인증 필터 (OncePerRequestFilter)

```kotlin
@Component
class JwtAuthenticationFilter(
    private val tokenProvider: TokenProvider,
    private val userDetailsService: UserDetailsService,
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        // 1. 토큰 추출
        val token = resolveToken(request)

        // 2. 토큰 검증 & SecurityContext 설정
        if (token != null && tokenProvider.validateToken(token)) {
            val username = tokenProvider.getUsername(token)
            val userDetails = userDetailsService.loadUserByUsername(username)
            val authentication = UsernamePasswordAuthenticationToken(
                userDetails, null, userDetails.authorities,
            )
            authentication.details = WebAuthenticationDetailsSource().buildDetails(request)
            SecurityContextHolder.getContext().authentication = authentication
        }

        filterChain.doFilter(request, response)
    }

    private fun resolveToken(request: HttpServletRequest): String? {
        val bearer = request.getHeader("Authorization") ?: return null
        return if (bearer.startsWith("Bearer ")) bearer.substring(7) else null
    }
}
```

### TokenProvider 구현

```kotlin
@Component
class TokenProvider(
    @Value("\${jwt.secret}") private val secret: String,
    @Value("\${jwt.access-token-expiry:3600000}") private val accessTokenExpiry: Long,
    @Value("\${jwt.refresh-token-expiry:604800000}") private val refreshTokenExpiry: Long,
) {
    private val key: SecretKey by lazy {
        Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret))
    }

    // Access Token 생성
    fun generateAccessToken(authentication: Authentication): String {
        val authorities = authentication.authorities.joinToString(",") { it.authority }
        val now = Date()
        return Jwts.builder()
            .subject(authentication.name)
            .claim("roles", authorities)
            .issuedAt(now)
            .expiration(Date(now.time + accessTokenExpiry))
            .signWith(key)
            .compact()
    }

    // Refresh Token 생성
    fun generateRefreshToken(username: String): String {
        val now = Date()
        return Jwts.builder()
            .subject(username)
            .issuedAt(now)
            .expiration(Date(now.time + refreshTokenExpiry))
            .signWith(key)
            .compact()
    }

    fun getUsername(token: String): String =
        getClaims(token).subject

    fun validateToken(token: String): Boolean {
        return try {
            getClaims(token)
            true
        } catch (ex: JwtException) {
            false
        }
    }

    private fun getClaims(token: String): Claims =
        Jwts.parser().verifyWith(key).build().parseSignedClaims(token).payload
}
```

### UserDetailsService 구현 패턴

```kotlin
@Service
class CustomUserDetailsService(
    private val userRepository: UserRepository,
) : UserDetailsService {

    override fun loadUserByUsername(username: String): UserDetails {
        val user = userRepository.findByEmail(username)
            ?: throw UsernameNotFoundException("사용자를 찾을 수 없습니다: $username")

        return org.springframework.security.core.userdetails.User.builder()
            .username(user.email)
            .password(user.password)
            .authorities(user.roles.map { SimpleGrantedAuthority("ROLE_${it.name}") })
            .build()
    }
}
```

### Refresh Token Rotation 패턴

```kotlin
@Service
class AuthService(
    private val tokenProvider: TokenProvider,
    private val refreshTokenRepository: RefreshTokenRepository,
    private val userRepository: UserRepository,
) {
    @Transactional
    fun refresh(request: TokenRefreshRequest): TokenResponse {
        val refreshToken = refreshTokenRepository.findByToken(request.refreshToken)
            ?: throw BusinessException(ErrorCode.INVALID_REFRESH_TOKEN)

        // 만료 확인
        if (refreshToken.isExpired()) {
            refreshTokenRepository.delete(refreshToken)
            throw BusinessException(ErrorCode.REFRESH_TOKEN_EXPIRED)
        }

        val user = userRepository.findById(refreshToken.userId)
            .orElseThrow { BusinessException(ErrorCode.USER_NOT_FOUND) }

        // 기존 토큰 삭제 (rotation)
        refreshTokenRepository.delete(refreshToken)

        // 새 토큰 쌍 발급
        val authentication = UsernamePasswordAuthenticationToken(user.email, null, user.authorities)
        val newAccessToken = tokenProvider.generateAccessToken(authentication)
        val newRefreshToken = tokenProvider.generateRefreshToken(user.email)

        refreshTokenRepository.save(
            RefreshToken(userId = user.id, token = newRefreshToken, expiryDate = Instant.now().plusMillis(604800000))
        )

        return TokenResponse(accessToken = newAccessToken, refreshToken = newRefreshToken)
    }
}
```

---

## 2. Spring Security 인가 (Authorization)

### @PreAuthorize 메서드 레벨 보안 (SpEL)

```kotlin
@Configuration
@EnableMethodSecurity(prePostEnabled = true)  // Spring Security 6.x
class MethodSecurityConfig

@Service
class OrderService(private val orderRepository: OrderRepository) {

    // 역할 기반 접근 제어
    @PreAuthorize("hasRole('ADMIN')")
    fun deleteOrder(orderId: Long) {
        orderRepository.deleteById(orderId)
    }

    // 복합 조건: 관리자이거나 본인 주문
    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.principal.id")
    fun getOrdersByUser(userId: Long): List<Order> {
        return orderRepository.findByUserId(userId)
    }

    // 커스텀 SpEL: 서비스 빈 참조
    @PreAuthorize("@orderAccessChecker.canAccess(#orderId, authentication)")
    fun getOrderDetail(orderId: Long): OrderDetailResponse {
        val order = orderRepository.findById(orderId)
            .orElseThrow { OrderNotFoundException(orderId) }
        return OrderDetailResponse.from(order)
    }

    // 반환값 필터링
    @PostAuthorize("returnObject.userId == authentication.principal.id or hasRole('ADMIN')")
    fun findOrder(orderId: Long): Order {
        return orderRepository.findById(orderId)
            .orElseThrow { OrderNotFoundException(orderId) }
    }
}
```

### @Secured vs @PreAuthorize 비교

| 항목 | `@Secured` | `@PreAuthorize` |
|---|---|---|
| SpEL 지원 | X | O |
| 역할 기반 | O (문자열 배열) | O (SpEL 표현식) |
| 메서드 파라미터 참조 | X | O (`#paramName`) |
| 반환값 기반 제어 | X | O (`@PostAuthorize`) |
| 복합 조건 (AND/OR) | X | O |
| 활성화 | `@EnableMethodSecurity(securedEnabled = true)` | `@EnableMethodSecurity(prePostEnabled = true)` |
| 권장 여부 | 단순 역할 체크만 필요 시 | 대부분의 경우 권장 |

```kotlin
// @Secured: 단순 역할 체크
@Secured("ROLE_ADMIN")
fun adminOnly() { /* ... */ }

// @PreAuthorize: 복합 조건
@PreAuthorize("hasRole('ADMIN') and #request.amount <= 1000000")
fun approveRefund(request: RefundRequest) { /* ... */ }
```

### RBAC 구현: GrantedAuthority & @RolesAllowed

```kotlin
enum class Role {
    USER, SELLER, ADMIN, SUPER_ADMIN;

    fun toAuthority(): SimpleGrantedAuthority =
        SimpleGrantedAuthority("ROLE_$name")
}

@Entity
@Table(name = "users")
class User(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0,

    @Column(unique = true, nullable = false)
    val email: String,

    @Column(nullable = false)
    val password: String,

    @ElementCollection(fetch = FetchType.EAGER)
    @Enumerated(EnumType.STRING)
    @CollectionTable(name = "user_roles", joinColumns = [JoinColumn(name = "user_id")])
    @Column(name = "role")
    val roles: MutableSet<Role> = mutableSetOf(Role.USER),
) {
    val authorities: List<SimpleGrantedAuthority>
        get() = roles.map { it.toAuthority() }
}
```

### URL 패턴 기반 인가

```kotlin
@Bean
fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
    return http
        .authorizeHttpRequests {
            // 공개 API
            it.requestMatchers(HttpMethod.GET, "/api/products/**").permitAll()
            it.requestMatchers("/api/auth/**").permitAll()

            // 판매자 전용
            it.requestMatchers("/api/seller/**").hasRole("SELLER")

            // 관리자 전용
            it.requestMatchers("/api/admin/**").hasAnyRole("ADMIN", "SUPER_ADMIN")

            // SUPER_ADMIN 전용
            it.requestMatchers(HttpMethod.DELETE, "/api/admin/users/**").hasRole("SUPER_ADMIN")

            // 나머지는 인증 필요
            it.anyRequest().authenticated()
        }
        .build()
}
```

### 커스텀 권한 체크 (도메인 객체 접근 제어)

```kotlin
@Component("orderAccessChecker")
class OrderAccessChecker(private val orderRepository: OrderRepository) {

    fun canAccess(orderId: Long, authentication: Authentication): Boolean {
        val order = orderRepository.findById(orderId).orElse(null) ?: return false
        val principal = authentication.principal as CustomUserDetails

        // 관리자이거나 주문 소유자
        return principal.hasRole(Role.ADMIN) || order.userId == principal.id
    }

    fun canCancel(orderId: Long, authentication: Authentication): Boolean {
        val order = orderRepository.findById(orderId).orElse(null) ?: return false
        val principal = authentication.principal as CustomUserDetails

        return (principal.hasRole(Role.ADMIN) || order.userId == principal.id)
            && order.status == OrderStatus.PENDING
    }
}

// 사용
@PreAuthorize("@orderAccessChecker.canCancel(#orderId, authentication)")
fun cancelOrder(orderId: Long) { /* ... */ }
```

---

## 3. FastAPI 인증

### OAuth2PasswordBearer 토큰 스킴 설정

```python
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, HTTPBearer, HTTPAuthorizationCredentials

app = FastAPI()

# OAuth2PasswordBearer: Swagger UI에 로그인 폼 자동 생성
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

# HTTPBearer: 단순 Bearer 토큰 검증 (Swagger UI에 토큰 입력 필드)
http_bearer = HTTPBearer()
```

### HTTPBearer 활용 패턴

```python
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

@app.get("/api/protected")
async def protected_route(
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    """Swagger UI에서 Bearer 토큰을 직접 입력하는 방식"""
    token = credentials.credentials
    payload = decode_token(token)
    return {"user_id": payload["sub"]}
```

### Depends 체인으로 토큰 추출/검증/사용자 로딩

```python
from jose import JWTError, jwt
from pydantic import BaseModel
from datetime import datetime, timedelta

# 설정
SECRET_KEY = "your-secret-key"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

class TokenData(BaseModel):
    username: str
    roles: list[str] = []

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """토큰 → 디코딩 → 사용자 조회 체인"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="인증 정보가 유효하지 않습니다",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username, roles=payload.get("roles", []))
    except JWTError:
        raise credentials_exception

    user = await user_repository.find_by_email(db, token_data.username)
    if user is None:
        raise credentials_exception
    return user

async def get_current_active_user(
    user: User = Depends(get_current_user),
) -> User:
    """활성 사용자 확인 체인"""
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="비활성화된 계정입니다",
        )
    return user
```

### JWT 토큰 생성/검증 (python-jose)

```python
from jose import jwt
from datetime import datetime, timedelta, timezone

def create_access_token(data: dict, expires_delta: timedelta | None = None) -> str:
    """Access Token 생성"""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=60))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def create_refresh_token(data: dict) -> str:
    """Refresh Token 생성"""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=7)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    """토큰 디코딩 & 검증"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="토큰이 만료되었습니다",
        )
    except jwt.JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효하지 않은 토큰입니다",
        )
```

### Refresh Token Rotation 패턴

```python
class AuthService:
    def __init__(self, db: AsyncSession, user_repo: UserRepository, token_repo: RefreshTokenRepository):
        self.db = db
        self.user_repo = user_repo
        self.token_repo = token_repo

    async def refresh(self, refresh_token_str: str) -> TokenResponse:
        """Refresh Token Rotation: 기존 토큰 폐기 → 새 토큰 쌍 발급"""
        # 1. 저장된 refresh token 확인
        stored_token = await self.token_repo.find_by_token(self.db, refresh_token_str)
        if not stored_token:
            raise HTTPException(status_code=401, detail="유효하지 않은 리프레시 토큰")

        # 2. 만료 확인
        if stored_token.expires_at < datetime.now(timezone.utc):
            await self.token_repo.delete(self.db, stored_token)
            raise HTTPException(status_code=401, detail="리프레시 토큰이 만료되었습니다")

        # 3. 사용자 조회
        user = await self.user_repo.find_by_id(self.db, stored_token.user_id)
        if not user:
            raise HTTPException(status_code=401, detail="사용자를 찾을 수 없습니다")

        # 4. 기존 토큰 삭제 (rotation)
        await self.token_repo.delete(self.db, stored_token)

        # 5. 새 토큰 쌍 발급
        new_access = create_access_token({"sub": user.email, "roles": user.role_names})
        new_refresh = create_refresh_token({"sub": user.email})

        await self.token_repo.save(self.db, RefreshToken(
            user_id=user.id,
            token=new_refresh,
            expires_at=datetime.now(timezone.utc) + timedelta(days=7),
        ))

        return TokenResponse(access_token=new_access, refresh_token=new_refresh)
```

---

## 4. FastAPI 인가

### Depends 기반 권한 검사

```python
from enum import Enum
from functools import wraps

class Role(str, Enum):
    USER = "USER"
    SELLER = "SELLER"
    ADMIN = "ADMIN"
    SUPER_ADMIN = "SUPER_ADMIN"

class RoleChecker:
    """Depends에서 사용할 역할 검사기"""
    def __init__(self, allowed_roles: list[Role]):
        self.allowed_roles = allowed_roles

    async def __call__(self, user: User = Depends(get_current_active_user)) -> User:
        if not any(role in self.allowed_roles for role in user.roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"권한이 부족합니다. 필요 역할: {[r.value for r in self.allowed_roles]}",
            )
        return user

# 재사용 가능한 역할 검사기 인스턴스
require_admin = RoleChecker([Role.ADMIN, Role.SUPER_ADMIN])
require_seller = RoleChecker([Role.SELLER, Role.ADMIN])
require_user = RoleChecker([Role.USER, Role.SELLER, Role.ADMIN])

@app.delete("/api/admin/users/{user_id}")
async def delete_user(
    user_id: int,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """관리자만 접근 가능"""
    await user_service.delete(db, user_id)
    return {"message": "사용자가 삭제되었습니다"}
```

### 퍼미션 기반 접근 제어

```python
class Permission(str, Enum):
    READ_ORDERS = "read:orders"
    WRITE_ORDERS = "write:orders"
    DELETE_ORDERS = "delete:orders"
    MANAGE_USERS = "manage:users"

class PermissionChecker:
    """세분화된 퍼미션 검사기"""
    def __init__(self, required_permissions: list[Permission]):
        self.required_permissions = required_permissions

    async def __call__(self, user: User = Depends(get_current_active_user)) -> User:
        user_permissions = set(user.permissions)
        required = set(self.required_permissions)
        if not required.issubset(user_permissions):
            missing = required - user_permissions
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"권한 부족. 누락된 퍼미션: {[p.value for p in missing]}",
            )
        return user

require_order_write = PermissionChecker([Permission.WRITE_ORDERS])
require_user_manage = PermissionChecker([Permission.MANAGE_USERS])

@app.post("/api/orders")
async def create_order(
    request: CreateOrderRequest,
    user: User = Depends(require_order_write),
    db: AsyncSession = Depends(get_db),
):
    return await order_service.create(db, user, request)
```

### 데코레이터 패턴으로 Permission Check

```python
from functools import wraps
from typing import Callable

def require_permissions(*permissions: Permission):
    """데코레이터 기반 퍼미션 체크"""
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Depends로 주입된 current_user를 kwargs에서 가져옴
            user = kwargs.get("current_user")
            if not user:
                raise HTTPException(status_code=401, detail="인증 필요")
            user_perms = set(user.permissions)
            required = set(permissions)
            if not required.issubset(user_perms):
                raise HTTPException(status_code=403, detail="권한 부족")
            return await func(*args, **kwargs)
        return wrapper
    return decorator

@app.put("/api/orders/{order_id}/cancel")
@require_permissions(Permission.WRITE_ORDERS)
async def cancel_order(
    order_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    return await order_service.cancel(db, current_user, order_id)
```

### 미들웨어 기반 전역 인증

```python
from starlette.middleware.base import BaseHTTPMiddleware

# 인증 제외 경로
PUBLIC_PATHS = {"/api/auth/login", "/api/auth/register", "/api/public", "/docs", "/openapi.json"}

class AuthMiddleware(BaseHTTPMiddleware):
    """전역 JWT 토큰 검증 미들웨어"""

    async def dispatch(self, request: Request, call_next):
        # 공개 경로는 인증 스킵
        if any(request.url.path.startswith(path) for path in PUBLIC_PATHS):
            return await call_next(request)

        # Authorization 헤더 확인
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return JSONResponse(
                status_code=401,
                content={"detail": "인증 토큰이 필요합니다"},
            )

        token = auth_header.split(" ")[1]
        try:
            payload = decode_token(token)
            request.state.user_id = payload["sub"]
            request.state.roles = payload.get("roles", [])
        except HTTPException:
            return JSONResponse(
                status_code=401,
                content={"detail": "유효하지 않은 토큰입니다"},
            )

        return await call_next(request)

app.add_middleware(AuthMiddleware)
```

---

## 5. CORS / CSRF / 보안 헤더

### Spring Boot CORS 설정

```kotlin
// 방법 1: 글로벌 CorsConfigurationSource Bean (권장)
@Bean
fun corsConfigurationSource(): CorsConfigurationSource {
    val configuration = CorsConfiguration().apply {
        allowedOrigins = listOf("https://shop.example.com", "https://admin.example.com")
        allowedMethods = listOf("GET", "POST", "PUT", "DELETE", "PATCH")
        allowedHeaders = listOf("Authorization", "Content-Type", "X-Request-ID")
        exposedHeaders = listOf("X-Request-ID")
        allowCredentials = true
        maxAge = 3600  // pre-flight 캐시 1시간
    }
    val source = UrlBasedCorsConfigurationSource()
    source.registerCorsConfiguration("/api/**", configuration)
    return source
}

// 방법 2: @CrossOrigin (컨트롤러/메서드 레벨 — 간단한 경우만)
@CrossOrigin(origins = ["https://shop.example.com"])
@RestController
class ProductController { /* ... */ }
```

### Spring Boot CSRF & 보안 헤더

```kotlin
@Bean
fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
    return http
        // stateless REST API는 CSRF 비활성화
        .csrf { it.disable() }
        // 보안 헤더 설정
        .headers {
            it.contentSecurityPolicy { csp ->
                csp.policyDirectives("default-src 'self'; script-src 'self'")
            }
            it.frameOptions { frame -> frame.deny() }  // X-Frame-Options: DENY
            it.httpStrictTransportSecurity { hsts ->
                hsts.includeSubDomains(true)
                hsts.maxAgeInSeconds(31536000)  // 1년
            }
            it.contentTypeOptions { }  // X-Content-Type-Options: nosniff (기본 활성)
        }
        .build()
}
```

### FastAPI CORS 설정

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://shop.example.com", "https://admin.example.com"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=["X-Request-ID"],
    max_age=3600,
)
```

### FastAPI TrustedHostMiddleware & 보안 헤더

```python
from starlette.middleware.trustedhost import TrustedHostMiddleware

# 허용된 호스트만 수락 (Host 헤더 검증)
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["shop.example.com", "admin.example.com"],
)

# 커스텀 보안 헤더 미들웨어
class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        return response

app.add_middleware(SecurityHeadersMiddleware)
```

### CORS 설정 비교

| 항목 | Good | Bad |
|---|---|---|
| `allow_origins` | `["https://shop.example.com"]` | `["*"]` (와일드카드) |
| `allow_methods` | `["GET", "POST", "PUT"]` 필요한 것만 | `["*"]` (전체 허용) |
| `allow_headers` | `["Authorization", "Content-Type"]` 필요한 것만 | `["*"]` (전체 허용) |
| `allow_credentials` | `True` (쿠키/인증 필요 시) | origin이 `*`인데 `True` (브라우저 차단) |
| `max_age` | `3600` (1시간 캐시) | 미설정 (매 요청마다 preflight) |

### 보안 헤더 체크리스트

| 헤더 | 값 | 목적 |
|---|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | HTTPS 강제 |
| `X-Content-Type-Options` | `nosniff` | MIME 스니핑 방지 |
| `X-Frame-Options` | `DENY` | 클릭재킹 방지 |
| `Content-Security-Policy` | `default-src 'self'` | XSS/코드 주입 방지 |
| `X-XSS-Protection` | `1; mode=block` | 브라우저 XSS 필터 활성화 |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | 리퍼러 정보 노출 최소화 |
| `Permissions-Policy` | `camera=(), microphone=()` | 브라우저 기능 제한 |

---

## 6. API Key & Rate Limiting

### Kotlin: API Key 인증 필터

```kotlin
@Component
class ApiKeyAuthenticationFilter(
    @Value("\${api.keys}") private val validApiKeys: List<String>,
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val apiKey = request.getHeader("X-API-Key")

        if (apiKey == null || apiKey !in validApiKeys) {
            response.status = HttpServletResponse.SC_UNAUTHORIZED
            response.contentType = "application/json"
            response.writer.write("""{"detail": "유효하지 않은 API Key입니다"}""")
            return
        }

        // API Key를 SecurityContext에 설정
        val auth = UsernamePasswordAuthenticationToken(apiKey, null, listOf(SimpleGrantedAuthority("ROLE_API_CLIENT")))
        SecurityContextHolder.getContext().authentication = auth

        filterChain.doFilter(request, response)
    }

    override fun shouldNotFilter(request: HttpServletRequest): Boolean {
        // /api/external/** 경로만 API Key 인증 적용
        return !request.requestURI.startsWith("/api/external/")
    }
}
```

### Kotlin: bucket4j Rate Limiting

```kotlin
// build.gradle.kts
// implementation("com.bucket4j:bucket4j-core:8.7.0")
// implementation("com.bucket4j:bucket4j-redis:8.7.0")

@Component
class RateLimitFilter(
    private val rateLimitService: RateLimitService,
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val clientKey = resolveClientKey(request)
        val probe = rateLimitService.tryConsume(clientKey)

        // Rate Limit 헤더 설정
        response.setHeader("X-RateLimit-Remaining", probe.remainingTokens.toString())
        response.setHeader("X-RateLimit-Limit", "100")

        if (!probe.isConsumed) {
            response.status = HttpServletResponse.SC_TOO_MANY_REQUESTS
            response.contentType = "application/json"
            response.setHeader("Retry-After", probe.nanosToWaitForRefill.div(1_000_000_000).toString())
            response.writer.write("""{"detail": "요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요."}""")
            return
        }

        filterChain.doFilter(request, response)
    }

    private fun resolveClientKey(request: HttpServletRequest): String {
        // API Key 또는 IP 기반
        return request.getHeader("X-API-Key")
            ?: request.getHeader("X-Forwarded-For")?.split(",")?.firstOrNull()?.trim()
            ?: request.remoteAddr
    }
}

@Service
class RateLimitService {
    private val buckets = ConcurrentHashMap<String, Bucket>()

    fun tryConsume(key: String): ConsumptionProbe {
        val bucket = buckets.computeIfAbsent(key) { createBucket() }
        return bucket.tryConsumeAndReturnRemaining(1)
    }

    private fun createBucket(): Bucket {
        return Bucket.builder()
            .addLimit(
                BandwidthBuilder.builder()
                    .capacity(100)                           // 최대 100 토큰
                    .refillGreedy(100, Duration.ofMinutes(1)) // 1분마다 100 토큰 리필
                    .build()
            )
            .build()
    }
}
```

### Python: API Key Header 인증

```python
from fastapi import Security
from fastapi.security import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=True)

VALID_API_KEYS = {"key-abc-123", "key-def-456"}  # 실제로는 DB/환경변수에서 로드

async def verify_api_key(
    api_key: str = Security(api_key_header),
) -> str:
    """API Key 검증 의존성"""
    if api_key not in VALID_API_KEYS:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효하지 않은 API Key입니다",
        )
    return api_key

@app.get("/api/external/data")
async def get_external_data(
    api_key: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """외부 연동 API — API Key 인증 필요"""
    return await external_service.get_data(db)
```

### Python: slowapi Rate Limiting

```python
# pip install slowapi
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# 엔드포인트별 Rate Limiting
@app.get("/api/search")
@limiter.limit("30/minute")  # 분당 30회
async def search(request: Request, query: str):
    return await search_service.search(query)

@app.post("/api/auth/login")
@limiter.limit("5/minute")  # 로그인 시도: 분당 5회
async def login(request: Request, credentials: LoginRequest):
    return await auth_service.login(credentials)

# API Key 기반 키 함수 (IP 대신 API Key로 제한)
def get_api_key(request: Request) -> str:
    return request.headers.get("X-API-Key", get_remote_address(request))

@app.get("/api/external/heavy")
@limiter.limit("10/minute", key_func=get_api_key)
async def heavy_endpoint(request: Request):
    return await heavy_service.process()
```

### Rate Limiting 전략 비교

| 전략 | 동작 방식 | 장점 | 단점 | 사용 시기 |
|---|---|---|---|---|
| Fixed Window | 고정 시간 윈도우(1분) 내 카운트 | 구현 간단, 메모리 효율적 | 윈도우 경계에서 버스트 가능 | 단순 API 보호 |
| Sliding Window | 윈도우가 요청마다 이동 | 경계 버스트 방지 | 약간 더 복잡한 구현 | 정밀한 제어 필요 시 |
| Token Bucket | 일정 속도로 토큰 리필, 요청 시 토큰 소비 | 버스트 허용 + 평균 속도 제한 | 구현 복잡도 높음 | 트래픽 변동이 큰 API |
| Sliding Log | 각 요청 타임스탬프 기록 | 가장 정확한 제한 | 메모리 사용량 높음 | 과금/빌링 API |
