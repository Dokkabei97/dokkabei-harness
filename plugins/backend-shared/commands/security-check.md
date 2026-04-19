---
name: security-check
description: "인증/인가 설정 검증 — CORS, CSRF, 헤더 보안, 엔드포인트 보호 누락 탐지 (Spring Boot/FastAPI)"
category: validation
complexity: intermediate
mcp-servers: []
personas: []
---

# /security-check - 인증/인가 보안 검증

## Triggers
- 새로운 API 엔드포인트를 추가한 후 보안 설정을 확인하고 싶을 때
- Spring Security / FastAPI 인증 설정을 변경한 후 검증할 때
- CORS 설정이 올바른지 확인하고 싶을 때
- 프로덕션 배포 전 보안 점검을 수행할 때
- Actuator/관리 엔드포인트의 보안 상태를 점검할 때

## Usage
```
/security-check [대상] [옵션]

Options:
  --lang kotlin|python|auto     대상 언어 (기본: auto)
  --focus auth|cors|headers|endpoints|all  검증 영역 (기본: all)
  --fix                         자동 수정 제안 포함
```

## Behavioral Flow

### 검증 플로우
1. **Discover**: 보안 설정 파일 스캔, 인증 메커니즘 식별
   - Kotlin: `SecurityFilterChain`, `@EnableWebSecurity`, `SecurityConfig` 스캔
   - Python: 인증 미들웨어, `Depends` 기반 인증 가드, OAuth2 설정 스캔
2. **Scan**: focus 영역별 패턴 검사
   - **auth**: 엔드포인트-보안 매핑 분석, 인증 누락 엔드포인트, JWT 설정 검증
   - **cors**: CORS 설정, 허용 origin/method/header 범위 검사
   - **headers**: CSP, HSTS, X-Frame-Options, X-Content-Type-Options 등 보안 헤더 검사
   - **endpoints**: Actuator 노출, 디버그 엔드포인트, 관리 경로 보호 상태 검사
3. **Evaluate**: 발견 항목 심각도 분류 (Critical / High / Medium)
4. **Report**: 구조화된 리포트 출력
5. **Fix**: (--fix) 자동 수정 코드 제안

## Detection Patterns

### Spring Boot (Kotlin)
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| Mutation 엔드포인트에 인증 없음 | 🔴 Critical | 비인가 데이터 변경 위험 |
| Actuator 엔드포인트 무제한 노출 | 🔴 Critical | 서버 내부 정보 유출 |
| CORS origin에 와일드카드(`*`) | 🔴 Critical | CSRF 공격 취약 |
| JWT 서명 알고리즘 none 허용 | 🔴 Critical | 토큰 위조 가능 |
| 비밀번호 평문 저장 (설정 파일) | 🔴 Critical | 인증 정보 유출 |
| CSRF 비활성화 (세션 기반 앱) | 🟡 High | 크로스사이트 요청 위조 취약 |
| 보안 헤더 미설정 (CSP, HSTS, X-Frame) | 🟡 High | 클릭재킹, XSS 취약 |
| 에러 응답에 스택 트레이스 노출 | 🟡 High | 서버 내부 정보 유출 |

### FastAPI (Python)
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| Mutation 라우터에 인증 Depends 없음 | 🔴 Critical | 비인가 데이터 변경 |
| CORS `allow_origins=["*"]` | 🔴 Critical | CSRF 공격 취약 |
| JWT `secret_key` 하드코딩 | 🔴 Critical | 토큰 위조 가능 |
| 인증 미들웨어 미설정 | 🟡 High | 전역 인증 누락 |
| 디버그 모드 프로덕션 노출 | 🟡 High | 내부 정보 유출 |
| `TrustedHostMiddleware` 미사용 | 🟡 Medium | 호스트 헤더 인젝션 |

## Tool Coordination
- **Glob**: 프로젝트 전체 보안 설정 파일 탐색
- **Grep**: 보안 어노테이션, 인증 패턴, CORS/CSRF 설정 검색
- **Read**: 보안 설정 체인 추적, 코드 상세 분석
- **Bash**: 보안 스캐너 실행, 설정 검증

## Examples

### 전체 프로젝트 보안 스캔
```
/security-check
# 프로젝트 전체 인증 + CORS + 헤더 + 엔드포인트 보안 검증
# 종합 리포트 출력
```

### CORS 설정 집중 검증
```
/security-check src/main/kotlin/ --focus cors
# CORS 관련 설정만 집중 스캔
# origin, method, header 허용 범위 검증
```

### Python 인증 검증 + 자동 수정
```
/security-check app/ --lang python --focus auth --fix
# FastAPI 인증 미들웨어, Depends 가드 분석
# 수정 코드 제안 포함
```

### 엔드포인트 보호 상태 점검
```
/security-check --focus endpoints
# Actuator, 관리 엔드포인트 노출 확인
# 인증 없는 Mutation 엔드포인트 탐지
```

## Output Format
```
## Security Check 검증 결과

### 요약
- 스캔 파일: 32개
- 발견 항목: 6건 (Critical: 3, High: 2, Medium: 1)

### 상세 결과
| 심각도 | 카테고리 | 파일:라인 | 문제 | 제안 |
|--------|---------|----------|------|------|
| 🔴 Critical | auth | AdminController.kt:28 | DELETE 엔드포인트에 인증 없음 | @PreAuthorize("hasRole('ADMIN')") 추가 |
| 🔴 Critical | cors | SecurityConfig.kt:15 | CORS origin 와일드카드(*) 설정 | 허용 도메인 명시적 지정 |
| 🔴 Critical | auth | JwtConfig.kt:42 | JWT 서명 알고리즘 none 허용 | HS256/RS256 알고리즘 강제 |
| 🟡 High | headers | SecurityConfig.kt:30 | HSTS 헤더 미설정 | headers.httpStrictTransportSecurity() 추가 |
| 🟡 High | endpoints | application.yml:12 | Actuator health/info 외 엔드포인트 노출 | management.endpoints.web.exposure.include 제한 |
| 🟡 Medium | headers | SecurityConfig.kt:35 | CSP 헤더 미설정 | contentSecurityPolicy() 추가 |
```

## Boundaries

**Will:**
- 정적 코드 분석 기반의 인증/인가/보안 설정 문제 탐지
- CORS, CSRF, 보안 헤더 설정 검증
- 보호되지 않은 엔드포인트 식별 및 보고
- 심각도 기반 우선순위 리포트 제공
- 자동 수정 코드 제안 (--fix 옵션)

**Will Not:**
- 런타임 인증 플로우 시뮬레이션 또는 펜테스팅
- 실제 HTTP 요청을 통한 보안 취약점 검증
- 코드 자동 수정 적용 (제안만 제공, 적용은 사용자 판단)
- 외부 라이브러리 / 프레임워크 내부 보안 로직 분석

## Related
- `/bean-check` — DI/트랜잭션 설정 검증
- `/api-test` — 발견된 문제 수정 후 테스트 작성
- `/graphql-check` — GraphQL 스키마/보안 검증
