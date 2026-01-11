---
name: project-planner
description: |
  Claude 에이전트가 체계적인 프로젝트 계획 문서를 생성하기 위한 종합 템플릿입니다.
  웹 애플리케이션, AI/ML, API, 모바일, 데이터 파이프라인 등 다양한 프로젝트 유형에 적용 가능합니다.
version: 1.0.0
category: planning
supported_project_types:
  - web-application
  - api-service
  - ai-ml
  - mobile-app
  - data-pipeline
  - infrastructure
---

<!--
[Agent Guidance - 에이전트 가이드]
이 템플릿은 Claude 에이전트가 프로젝트 계획서를 생성할 때 사용합니다.

**사용 방법:**
1. {{PLACEHOLDER}} 형식의 변수를 실제 값으로 대체하세요
2. [선택사항] 표시된 섹션은 프로젝트 유형에 따라 포함 여부를 결정하세요
3. <!-- Agent: ... -- > 주석은 에이전트 가이드이며, 최종 문서에서 제거하세요
4. 프로젝트 유형에 맞지 않는 섹션은 "해당 없음" 또는 삭제 처리하세요

**프로젝트 유형별 필수 섹션:**
- Web Application: 2.1, 2.2, 3.1, 3.3, 4.1
- API Service: 2.1, 2.2, 3.3, 3.4, 4.1
- AI/ML: 2.1, 2.2, 3.1, 3.4, 4.1 + ML 특화 섹션
- Mobile App: 2.1, 2.2, 3.1, 4.1 + 플랫폼 특화 섹션
- Data Pipeline: 2.1, 2.2, 3.4, 4.1 + 데이터 특화 섹션
-->

# 프로젝트 계획서: {{PROJECT_NAME}}

## 메타 정보

| 항목 | 내용 |
|------|------|
| **프로젝트명** | {{PROJECT_NAME}} |
| **프로젝트 유형** | {{PROJECT_TYPE: web-application / api-service / ai-ml / mobile-app / data-pipeline / infrastructure}} |
| **버전** | {{VERSION: 1.0.0}} |
| **작성일** | {{YYYY-MM-DD}} |
| **작성자** | {{AUTHOR}} |
| **검토자** | {{REVIEWER}} |
| **상태** | {{STATUS: 초안 / 검토중 / 승인됨}} |

### 문서 이력

| 버전 | 일자 | 작성자 | 변경 내용 |
|------|------|--------|----------|
| 1.0.0 | {{YYYY-MM-DD}} | {{AUTHOR}} | 최초 작성 |

---

## 1. 프로젝트 개요

### 1.1. 배경 및 목적

<!-- Agent: 프로젝트가 시작된 비즈니스적 배경과 해결하고자 하는 핵심 문제를 기술하세요 -->

**비즈니스 배경:**
{{BUSINESS_CONTEXT}}

**핵심 문제:**
{{CORE_PROBLEM}}

**프로젝트 목적:**
{{PROJECT_PURPOSE}}

### 1.2. 범위 정의

<!-- Agent: In-scope와 Out-of-scope를 명확히 구분하여 기술하세요 -->

#### 포함 범위 (In-Scope)
- {{IN_SCOPE_ITEM_1}}
- {{IN_SCOPE_ITEM_2}}
- {{IN_SCOPE_ITEM_3}}

#### 제외 범위 (Out-of-Scope)
- {{OUT_OF_SCOPE_ITEM_1}}
- {{OUT_OF_SCOPE_ITEM_2}}

### 1.3. 성공 기준

<!-- Agent: 측정 가능한 KPI와 성공 지표를 정의하세요 -->

| 지표 | 목표값 | 측정 방법 |
|------|--------|----------|
| {{KPI_1}} | {{TARGET_1}} | {{MEASUREMENT_1}} |
| {{KPI_2}} | {{TARGET_2}} | {{MEASUREMENT_2}} |
| {{KPI_3}} | {{TARGET_3}} | {{MEASUREMENT_3}} |

---

## 2. 기술 스택 및 아키텍처

### 2.1. 기술 스택 선정

<!-- Agent: 각 기술 선택에 대한 근거를 포함하세요 -->

#### 프론트엔드 [선택사항: web-application, mobile-app]

| 기술 | 버전 | 선정 근거 |
|------|------|----------|
| {{FRONTEND_FRAMEWORK}} | {{VERSION}} | {{RATIONALE}} |
| {{STATE_MANAGEMENT}} | {{VERSION}} | {{RATIONALE}} |
| {{STYLING_SOLUTION}} | {{VERSION}} | {{RATIONALE}} |

#### 백엔드

| 기술 | 버전 | 선정 근거 |
|------|------|----------|
| {{BACKEND_LANGUAGE}} | {{VERSION}} | {{RATIONALE}} |
| {{BACKEND_FRAMEWORK}} | {{VERSION}} | {{RATIONALE}} |
| {{API_STYLE}} | - | {{RATIONALE: REST / GraphQL / gRPC}} |

#### 데이터베이스

| 유형 | 기술 | 용도 |
|------|------|------|
| Primary DB | {{PRIMARY_DB}} | {{USE_CASE}} |
| Cache | {{CACHE_SOLUTION}} | {{USE_CASE}} |
| 검색엔진 | {{SEARCH_ENGINE}} | {{USE_CASE}} |

#### AI/ML [선택사항: ai-ml]

| 구성요소 | 기술 | 용도 |
|----------|------|------|
| ML Framework | {{ML_FRAMEWORK}} | {{USE_CASE}} |
| Model Serving | {{MODEL_SERVING}} | {{USE_CASE}} |
| Vector DB | {{VECTOR_DB}} | {{USE_CASE}} |

#### DevOps / 인프라

| 구성요소 | 기술 | 비고 |
|----------|------|------|
| 클라우드 | {{CLOUD_PROVIDER}} | {{NOTES}} |
| 컨테이너 | {{CONTAINER_SOLUTION}} | {{NOTES}} |
| 오케스트레이션 | {{ORCHESTRATION}} | {{NOTES}} |
| CI/CD | {{CICD_TOOL}} | {{NOTES}} |
| 모니터링 | {{MONITORING_STACK}} | {{NOTES}} |

### 2.2. 시스템 아키텍처

<!-- Agent: Mermaid 다이어그램을 사용하여 시각화하세요 -->

#### 아키텍처 다이어그램

```mermaid
graph TB
    subgraph Client
        A[{{CLIENT_TYPE}}]
    end

    subgraph Backend
        B[API Gateway]
        C[{{SERVICE_1}}]
        D[{{SERVICE_2}}]
    end

    subgraph Data
        E[{{PRIMARY_DB}}]
        F[{{CACHE}}]
    end

    A --> B
    B --> C
    B --> D
    C --> E
    D --> F
```

#### 아키텍처 설명

{{ARCHITECTURE_DESCRIPTION}}

#### 핵심 설계 결정

| 결정 사항 | 선택 | 대안 | 근거 |
|----------|------|------|------|
| {{DECISION_1}} | {{CHOICE_1}} | {{ALTERNATIVE_1}} | {{RATIONALE_1}} |
| {{DECISION_2}} | {{CHOICE_2}} | {{ALTERNATIVE_2}} | {{RATIONALE_2}} |

### 2.3. 인프라 구성

<!-- Agent: 환경별(개발/스테이징/운영) 인프라 구성을 명시하세요 -->

| 환경 | 목적 | 인프라 규모 | 접근 제어 |
|------|------|------------|----------|
| Development | 개발 및 단위 테스트 | {{DEV_SCALE}} | {{DEV_ACCESS}} |
| Staging | 통합 테스트 및 QA | {{STG_SCALE}} | {{STG_ACCESS}} |
| Production | 실 서비스 운영 | {{PROD_SCALE}} | {{PROD_ACCESS}} |

### 2.4. 외부 의존성

<!-- Agent: 외부 서비스, API, 라이브러리 의존성을 명시하세요 -->

| 의존성 | 유형 | 버전/계약 | 대체 방안 |
|--------|------|----------|----------|
| {{DEPENDENCY_1}} | {{TYPE: API / Service / Library}} | {{VERSION_OR_CONTRACT}} | {{FALLBACK}} |
| {{DEPENDENCY_2}} | {{TYPE}} | {{VERSION_OR_CONTRACT}} | {{FALLBACK}} |

---

## 3. 요구사항 및 기능 명세

### 3.1. 기능 요구사항

<!-- Agent: 우선순위(P0: 필수, P1: 중요, P2: 선택)를 반드시 포함하세요 -->

#### 핵심 기능 (P0 - 필수)

| ID | 기능명 | 설명 | 수용 기준 |
|----|--------|------|----------|
| FR-001 | {{FEATURE_NAME}} | {{DESCRIPTION}} | {{ACCEPTANCE_CRITERIA}} |
| FR-002 | {{FEATURE_NAME}} | {{DESCRIPTION}} | {{ACCEPTANCE_CRITERIA}} |

#### 주요 기능 (P1 - 중요)

| ID | 기능명 | 설명 | 수용 기준 |
|----|--------|------|----------|
| FR-101 | {{FEATURE_NAME}} | {{DESCRIPTION}} | {{ACCEPTANCE_CRITERIA}} |

#### 부가 기능 (P2 - 선택)

| ID | 기능명 | 설명 | 수용 기준 |
|----|--------|------|----------|
| FR-201 | {{FEATURE_NAME}} | {{DESCRIPTION}} | {{ACCEPTANCE_CRITERIA}} |

### 3.2. 비기능 요구사항

<!-- Agent: 성능, 보안, 확장성 등 품질 속성을 정량적으로 명시하세요 -->

#### 성능 요구사항

| 지표 | 목표값 | 측정 조건 |
|------|--------|----------|
| 응답 시간 (P95) | {{TARGET_LATENCY}} | {{CONDITION}} |
| 처리량 (TPS) | {{TARGET_TPS}} | {{CONDITION}} |
| 동시 사용자 | {{TARGET_CONCURRENT_USERS}} | {{CONDITION}} |

#### 가용성 및 안정성

| 지표 | 목표값 |
|------|--------|
| SLA | {{SLA_TARGET: 99.9%}} |
| MTTR | {{MTTR_TARGET}} |
| RPO | {{RPO_TARGET}} |
| RTO | {{RTO_TARGET}} |

#### 보안 요구사항

| 항목 | 요구사항 | 구현 방안 |
|------|----------|----------|
| 인증 | {{AUTH_REQUIREMENT}} | {{AUTH_SOLUTION}} |
| 인가 | {{AUTHZ_REQUIREMENT}} | {{AUTHZ_SOLUTION}} |
| 데이터 보호 | {{DATA_PROTECTION}} | {{ENCRYPTION_SOLUTION}} |
| 감사 로그 | {{AUDIT_REQUIREMENT}} | {{AUDIT_SOLUTION}} |

### 3.3. API 명세

<!-- Agent: 주요 API 엔드포인트를 RESTful 또는 GraphQL 형식으로 명시하세요 -->

#### REST API [선택사항: api-service, web-application]

| Method | Endpoint | 설명 | 인증 |
|--------|----------|------|------|
| GET | `/api/v1/{{RESOURCE}}` | {{RESOURCE}} 목록 조회 | {{AUTH: Yes/No}} |
| POST | `/api/v1/{{RESOURCE}}` | {{RESOURCE}} 생성 | {{AUTH}} |
| GET | `/api/v1/{{RESOURCE}}/{id}` | {{RESOURCE}} 상세 조회 | {{AUTH}} |
| PUT | `/api/v1/{{RESOURCE}}/{id}` | {{RESOURCE}} 수정 | {{AUTH}} |
| DELETE | `/api/v1/{{RESOURCE}}/{id}` | {{RESOURCE}} 삭제 | {{AUTH}} |

#### GraphQL Schema [선택사항]

```graphql
type {{TYPE_NAME}} {
  id: ID!
  {{FIELD_1}}: {{TYPE}}
  {{FIELD_2}}: {{TYPE}}
}

type Query {
  {{QUERY_NAME}}({{ARGS}}): {{RETURN_TYPE}}
}

type Mutation {
  {{MUTATION_NAME}}({{ARGS}}): {{RETURN_TYPE}}
}
```

### 3.4. 데이터 모델

<!-- Agent: 핵심 엔티티와 관계를 명시하세요 -->

#### ERD (Entity Relationship Diagram)

```mermaid
erDiagram
    {{ENTITY_1}} ||--o{ {{ENTITY_2}} : {{RELATIONSHIP}}
    {{ENTITY_1}} {
        string id PK
        string {{FIELD_1}}
        datetime {{FIELD_2}}
    }
    {{ENTITY_2}} {
        string id PK
        string {{ENTITY_1}}_id FK
        string {{FIELD_1}}
    }
```

#### 엔티티 정의

| 엔티티 | 설명 | 주요 필드 |
|--------|------|----------|
| {{ENTITY_1}} | {{DESCRIPTION}} | {{FIELD_LIST}} |
| {{ENTITY_2}} | {{DESCRIPTION}} | {{FIELD_LIST}} |

---

## 4. 일정 및 마일스톤

### 4.1. 프로젝트 타임라인

<!-- Agent: 현실적인 일정을 수립하고, 버퍼를 포함하세요 -->

**프로젝트 기간:** {{START_DATE}} ~ {{END_DATE}} (총 {{DURATION}})

```mermaid
gantt
    title {{PROJECT_NAME}} 타임라인
    dateFormat YYYY-MM-DD

    section 기획
    요구사항 분석    :a1, {{START_DATE}}, {{DURATION_1}}
    설계 문서 작성   :a2, after a1, {{DURATION_2}}

    section 개발
    {{PHASE_1}}      :b1, after a2, {{DURATION_3}}
    {{PHASE_2}}      :b2, after b1, {{DURATION_4}}
    {{PHASE_3}}      :b3, after b2, {{DURATION_5}}

    section 테스트
    통합 테스트      :c1, after b3, {{DURATION_6}}
    QA              :c2, after c1, {{DURATION_7}}

    section 배포
    스테이징 배포    :d1, after c2, {{DURATION_8}}
    프로덕션 배포    :d2, after d1, {{DURATION_9}}
```

### 4.2. 마일스톤 정의

<!-- Agent: 각 마일스톤에 명확한 완료 기준을 정의하세요 -->

| 마일스톤 | 예정일 | 완료 기준 | 산출물 |
|----------|--------|----------|--------|
| M1: 킥오프 | {{DATE}} | {{CRITERIA}} | {{DELIVERABLES}} |
| M2: 설계 완료 | {{DATE}} | {{CRITERIA}} | {{DELIVERABLES}} |
| M3: MVP 완료 | {{DATE}} | {{CRITERIA}} | {{DELIVERABLES}} |
| M4: 베타 출시 | {{DATE}} | {{CRITERIA}} | {{DELIVERABLES}} |
| M5: GA 출시 | {{DATE}} | {{CRITERIA}} | {{DELIVERABLES}} |

### 4.3. 작업 분해 구조 (WBS)

<!-- Agent: 주요 작업을 2-3단계로 분해하세요 -->

#### Phase 1: {{PHASE_1_NAME}}

| Task ID | 작업명 | 담당 | 예상 공수 | 선행 작업 |
|---------|--------|------|----------|----------|
| 1.1 | {{TASK_NAME}} | {{ASSIGNEE}} | {{ESTIMATE}} | - |
| 1.2 | {{TASK_NAME}} | {{ASSIGNEE}} | {{ESTIMATE}} | 1.1 |
| 1.3 | {{TASK_NAME}} | {{ASSIGNEE}} | {{ESTIMATE}} | 1.1 |

#### Phase 2: {{PHASE_2_NAME}}

| Task ID | 작업명 | 담당 | 예상 공수 | 선행 작업 |
|---------|--------|------|----------|----------|
| 2.1 | {{TASK_NAME}} | {{ASSIGNEE}} | {{ESTIMATE}} | 1.3 |
| 2.2 | {{TASK_NAME}} | {{ASSIGNEE}} | {{ESTIMATE}} | 2.1 |

### 4.4. 리소스 계획

<!-- Agent: 필요한 인력 및 역할을 명시하세요 -->

| 역할 | 인원 | 투입 기간 | 주요 책임 |
|------|------|----------|----------|
| PM | {{COUNT}} | {{PERIOD}} | {{RESPONSIBILITIES}} |
| Backend Dev | {{COUNT}} | {{PERIOD}} | {{RESPONSIBILITIES}} |
| Frontend Dev | {{COUNT}} | {{PERIOD}} | {{RESPONSIBILITIES}} |
| DevOps | {{COUNT}} | {{PERIOD}} | {{RESPONSIBILITIES}} |
| QA | {{COUNT}} | {{PERIOD}} | {{RESPONSIBILITIES}} |

---

## 5. 위험 관리

### 5.1. 위험 식별

<!-- Agent: 발생 가능성과 영향도를 평가하여 우선순위를 결정하세요 -->

| ID | 위험 | 발생 가능성 | 영향도 | 우선순위 |
|----|------|------------|--------|----------|
| R-001 | {{RISK_DESCRIPTION}} | {{HIGH/MEDIUM/LOW}} | {{HIGH/MEDIUM/LOW}} | {{PRIORITY}} |
| R-002 | {{RISK_DESCRIPTION}} | {{HIGH/MEDIUM/LOW}} | {{HIGH/MEDIUM/LOW}} | {{PRIORITY}} |
| R-003 | {{RISK_DESCRIPTION}} | {{HIGH/MEDIUM/LOW}} | {{HIGH/MEDIUM/LOW}} | {{PRIORITY}} |

### 5.2. 완화 전략

| 위험 ID | 완화 전략 | 대응 계획 | 담당자 |
|---------|----------|----------|--------|
| R-001 | {{MITIGATION_STRATEGY}} | {{CONTINGENCY_PLAN}} | {{OWNER}} |
| R-002 | {{MITIGATION_STRATEGY}} | {{CONTINGENCY_PLAN}} | {{OWNER}} |
| R-003 | {{MITIGATION_STRATEGY}} | {{CONTINGENCY_PLAN}} | {{OWNER}} |

---

## 6. 부록

### 6.1. 용어 정의

| 용어 | 정의 |
|------|------|
| {{TERM_1}} | {{DEFINITION_1}} |
| {{TERM_2}} | {{DEFINITION_2}} |

### 6.2. 참고 문서

- [{{REFERENCE_1}}]({{URL_1}})
- [{{REFERENCE_2}}]({{URL_2}})

### 6.3. 변경 이력

| 버전 | 일자 | 변경자 | 변경 내용 |
|------|------|--------|----------|
| {{VERSION}} | {{DATE}} | {{AUTHOR}} | {{CHANGES}} |

---

<!--
[Agent Guidance - 템플릿 사용 후 체크리스트]

완료 전 확인 사항:
- [ ] 모든 {{PLACEHOLDER}}가 실제 값으로 대체되었는가?
- [ ] 프로젝트 유형에 맞지 않는 섹션이 적절히 처리되었는가?
- [ ] 일정이 현실적이며 버퍼가 포함되었는가?
- [ ] 위험 식별이 충분히 이루어졌는가?
- [ ] 성공 기준이 측정 가능한가?
- [ ] 모든 에이전트 가이드 주석이 제거되었는가?
-->
