---
name: graphql-check
description: |
  GraphQL 스키마 검증 — 네이밍 컨벤션, N+1 감지, DataLoader 누락, depth limit, introspection, field-level 권한
  Validates GraphQL schemas — naming conventions, N+1 detection, missing DataLoaders, depth limits, introspection exposure, and field-level authorization. Use when: reviewing a GraphQL schema, checking resolvers for N+1, hardening depth limit or introspection settings, auditing field permissions.
category: validation
complexity: intermediate
mcp-servers: []
personas: []
---

# /graphql-check - GraphQL 스키마 & 성능 & 보안 검증

## Triggers
- GraphQL API의 스키마 품질을 점검하고 싶을 때
- N+1 쿼리 문제가 의심되거나 성능 최적화가 필요할 때
- 프로덕션 배포 전 보안 설정을 검증할 때
- GraphQL 스키마 네이밍 컨벤션 일관성을 확인하고 싶을 때
- 코드 리뷰에서 GraphQL 관련 체크리스트가 필요할 때

## Usage
```
/graphql-check [대상] [옵션]

Options:
  --focus schema|performance|security|all  검증 영역 (기본: all)
  --depth quick|deep                       분석 깊이 (기본: deep)
```

## Behavioral Flow

### 검증 플로우
1. **Discover**: GraphQL 스키마 파일, resolver 코드, 설정 파일 탐색
   - `.graphqls` / `.graphql` 스키마 파일
   - Kotlin: `@SchemaMapping`, `@QueryMapping`, `@MutationMapping`, `@BatchMapping`
   - Python: Strawberry `@strawberry.type`, `@strawberry.mutation`, resolver 함수
   - 설정: `application.yml`, GraphQL 보안/제한 설정
2. **Scan**: focus 영역별 검사
   - **schema**: 네이밍 컨벤션, nullable 일관성, Input/Type 분리, deprecated, description
   - **performance**: N+1 패턴, DataLoader/@BatchMapping 사용, 깊이/복잡도 제한
   - **security**: Introspection 설정, depth limit, field-level auth, input validation, rate limiting
3. **Evaluate**: 심각도 분류 + 영향도 분석
4. **Report**: 구조화된 리포트 (Bad/Good 코드 예시 포함)

## Detection Patterns

### Schema 검사
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| Type 이름이 PascalCase가 아님 | 🟡 Medium | GraphQL 네이밍 컨벤션 위반 |
| Field 이름이 camelCase가 아님 | 🟡 Medium | GraphQL 네이밍 컨벤션 위반 |
| Input type이 Output type과 필드 공유 | 🟢 Low | 리팩토링 제안 (분리 권장) |
| Public type에 description 누락 | 🟢 Low | 문서화 부족 |
| Nullable field에 명확한 이유 없음 | 🟡 Medium | 스키마 설계 재검토 필요 |
| Deprecated field에 reason 누락 | 🟡 Medium | 마이그레이션 가이드 부재 |

### Performance 검사
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| 리스트 resolver 내부에서 DB 쿼리 | 🔴 Critical | N+1 쿼리 문제 |
| 1:N 관계에 DataLoader 미사용 | 🔴 Critical | N+1 쿼리 문제 |
| 쿼리 depth limit 미설정 | 🟡 High | 재귀 쿼리로 서버 과부하 가능 |
| 쿼리 complexity limit 미설정 | 🟡 High | 복잡한 쿼리로 서버 과부하 가능 |
| `@BatchMapping` 미사용 (Spring) | 🟡 High | DataLoader 패턴 미적용 |
| 불필요한 over-fetching | 🟡 Medium | 요청하지 않은 필드까지 로딩 |

### Security 검사
| 패턴 | 심각도 | 설명 |
|------|--------|------|
| 프로덕션에서 Introspection 활성화 | 🔴 Critical | 스키마 노출 위험 |
| 민감 필드에 field-level auth 누락 | 🔴 Critical | 권한 없는 데이터 접근 가능 |
| Depth limit 미설정 | 🟡 High | DoS 공격 벡터 |
| Input size validation 미설정 | 🟡 Medium | 대량 데이터 주입 가능 |
| 클라이언트별 rate limiting 미설정 | 🟡 Medium | API 남용 가능 |

## Tool Coordination
- **Glob**: `.graphqls`, resolver 파일, 설정 파일 탐색
- **Grep**: 어노테이션 패턴, DB 쿼리 패턴, 설정값 검색
- **Read**: 스키마 정의, resolver 로직, 보안 설정 분석
- **Bash**: 스키마 유효성 검사 도구 실행

## Examples

### 전체 검증
```
/graphql-check
# 스키마 + 성능 + 보안 종합 검증
# 전체 GraphQL 관련 파일 스캔
```

### 성능 심층 분석
```
/graphql-check --focus performance --depth deep
# N+1 패턴 심층 추적, DataLoader 사용 현황, resolver→repository 호출 체인 분석
```

### 스키마 품질 검사 / 보안 점검
```
/graphql-check src/main/resources/graphql/ --focus schema
/graphql-check --focus security
```

### 빠른 스캔 (CI/CD 활용)
```
/graphql-check --depth quick
# Critical/High 항목만 빠르게 스캔
```

## Output Format

```
## GraphQL Check 검증 결과

### 요약
- 스캔 파일: 23개 (스키마 5, resolver 12, 설정 6)
- 발견 항목: 11건 (Critical: 3, High: 4, Medium: 3, Low: 1)

### 상세 결과 (심각도별 그룹, Bad/Good 코드 예시 포함)
| 심각도 | 영역 | 파일:라인 | 문제 | 제안 |
|--------|------|----------|------|------|
| 🔴 Critical | performance | ProductResolver.kt:35 | N+1 쿼리 (개별 DB 조회) | @BatchMapping + DataLoader 적용 |
| 🔴 Critical | security | application.yml:42 | Introspection 활성화 (prod) | introspection.enabled: false |
| 🟡 High | performance | GraphQLConfig.kt | Depth limit 미설정 | maxQueryDepth: 10 설정 |
```

## Boundaries

**Will:**
- GraphQL 스키마, resolver, 설정 파일의 정적 분석 수행
- N+1 쿼리 패턴 감지 및 DataLoader/@BatchMapping 적용 제안
- 보안 설정 검증 (Introspection, depth limit, auth)
- Bad/Good 코드 예시를 포함한 구체적인 개선 방안 제시
- 심각도별 우선순위 리포트 제공

**Will Not:**
- 실제 GraphQL 쿼리 실행을 통한 성능 측정
- 스키마 자동 수정 (제안만 제공)
- 클라이언트 측 쿼리 최적화 (서버 측 검증만)
- 외부 Federation/Gateway 설정 분석

## Related
- `/bean-check --focus graphql` — DI 관점의 GraphQL DataLoader 검증
- `/api-doc --format graphql-sdl` — GraphQL 스키마 문서 생성
- `/api-test --with-graphql` — GraphQL 쿼리/뮤테이션 테스트 생성
