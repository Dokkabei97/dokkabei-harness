---
name: api-doc
description: "코드 기반 API 문서 생성 — OpenAPI 3.0 스펙, GraphQL SDL, 요청/응답 예시, springdoc/FastAPI 어노테이션"
category: documentation
complexity: basic
mcp-servers: []
personas: []
---

# /api-doc - API 문서 자동 생성

## Triggers
- API 코드는 있지만 문서가 없거나 오래되었을 때
- OpenAPI(Swagger) 스펙 파일이 필요할 때
- GraphQL SDL 문서를 추출하고 싶을 때
- 코드 내 API 어노테이션(@Operation, description 등)을 보강하고 싶을 때
- 팀 내 API 공유를 위한 사람이 읽기 쉬운 문서가 필요할 때

## Usage
```
/api-doc [대상 파일|디렉토리] [옵션]

Options:
  --format openapi|graphql-sdl|markdown|all  출력 형식 (기본: auto-detect)
  --with-examples               요청/응답 예시 포함
  --update-annotations          코드 내 어노테이션 자동 추가 (@Operation, description)
```

## Behavioral Flow

### 문서 생성 플로우
1. **Discover**: 대상 코드 읽기, 엔드포인트/타입 추출, 프레임워크 감지
   - Kotlin Spring: `@RestController`, `@SchemaMapping` 기반 파싱
   - Python FastAPI: `@router`, `@strawberry.type` 기반 파싱
2. **Extract**: 코드에서 API 정보 추출
   - REST: path, method, parameters, request/response types, status codes, auth 요구사항
   - GraphQL: types, queries, mutations, subscriptions, input types, descriptions
3. **Generate**: 문서 생성
   - **OpenAPI**: YAML 형식, paths, components/schemas, security schemes
   - **GraphQL SDL**: type definitions with descriptions, query/mutation/subscription
   - **Markdown**: 사람이 읽기 쉬운 API 문서 (엔드포인트 목록, 파라미터 설명, 응답 구조)
4. **Enhance**: (--with-examples) 각 엔드포인트별 요청/응답 예시 JSON 생성
   - DTO/Schema 필드 타입 기반으로 현실적인 예시 데이터 생성
   - 에러 응답 예시 포함
5. **Annotate**: (--update-annotations) 코드에 문서 어노테이션 추가
   - Kotlin: `@Operation`, `@ApiResponse`, `@Schema` (springdoc-openapi)
   - Python: docstring, `response_model`, `description` 파라미터
   - GraphQL: schema/type definition의 `description` 필드

## Tool Coordination
- **Glob**: 대상 파일 탐색, 기존 문서 파일 확인
- **Read**: 컨트롤러/라우터, DTO/Schema, 설정 파일 분석
- **Write**: 문서 파일 생성, 어노테이션 추가
- **Grep**: 엔드포인트 매핑 패턴 검색

## Examples

### OpenAPI 스펙 생성 (Kotlin)
```
/api-doc src/main/kotlin/controller/ --format openapi --with-examples
# 생성: docs/openapi.yaml
# 전체 컨트롤러 기반 OpenAPI 3.0 스펙
# 각 엔드포인트별 요청/응답 JSON 예시 포함
```

### Markdown 문서 생성 (Python)
```
/api-doc app/api/ --format markdown
# 생성: docs/api-reference.md
# 사람이 읽기 쉬운 형식의 API 레퍼런스
# 엔드포인트 목록, 파라미터, 응답 구조 포함
```

### GraphQL SDL 추출
```
/api-doc src/main/kotlin/graphql/ --format graphql-sdl --with-examples
# 생성: docs/schema.graphql
# Type, Query, Mutation 정의 + 예시 쿼리
```

### 코드 어노테이션 보강
```
/api-doc --update-annotations
# 프로젝트 전체 컨트롤러/라우터 스캔
# 누락된 @Operation, @ApiResponse, @Schema 어노테이션 추가
# 기존 어노테이션은 유지, 누락분만 보강
```

### 전체 형식 동시 생성
```
/api-doc src/main/kotlin/ --format all --with-examples
# OpenAPI YAML + GraphQL SDL + Markdown 모두 생성
```

## Output Format
```
## API 문서 생성 결과

### 분석 요약
- 대상: src/main/kotlin/controller/
- 프레임워크: Spring Boot 3.x (springdoc-openapi)
- 엔드포인트: 12개 (REST 8, GraphQL 4)

### 생성된 파일
| 파일                  | 형식        | 엔드포인트 수 |
|---------------------|-----------|----------|
| docs/openapi.yaml    | OpenAPI   | 8        |
| docs/schema.graphql  | SDL       | 4        |

### 어노테이션 변경 (--update-annotations)
| 파일                        | 추가 수 | 변경 유형       |
|---------------------------|-------|-------------|
| OrderController.kt         | 5     | @Operation 추가 |
| UserController.kt          | 3     | @ApiResponse 추가 |
```

## Boundaries

**Will:**
- 코드를 분석하여 정확한 API 문서 생성 (OpenAPI, GraphQL SDL, Markdown)
- DTO/Schema 기반의 현실적인 요청/응답 예시 데이터 생성
- 누락된 문서 어노테이션 코드에 추가 (옵션 사용 시)
- 기존 문서와의 차이점 표시

**Will Not:**
- 실제 API 서버 실행을 통한 동적 문서 생성
- 기존 어노테이션 수정 또는 삭제 (누락분 추가만)
- API 설계 자체를 변경하는 제안
- 외부 서비스 API 문서 생성 (프로젝트 코드 기반만)

## Related
- `/api-gen` — API 스캐폴딩 생성 시 문서 동시 생성 (--with-docs)
- `/api-test` — 문서화된 API에 대한 테스트 생성
- `/graphql-check --focus schema` — GraphQL 스키마 네이밍/구조 검증
