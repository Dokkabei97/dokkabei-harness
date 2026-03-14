---
name: document-lastest
description: |
  코드 변경 작업 완료 후 Outline 위키 문서를 자동으로 최신화합니다.
  변경 내용을 분석하여 문서 유형을 자동 분류하고, 기존 문서 업데이트 또는 신규 문서 생성을 판단하여
  Outline 위키에 한국어 문서를 작성합니다. 민감정보 자동 마스킹을 포함합니다.
metadata:
  version: 1.0.0
  category: documentation
  domain: wiki-automation
  requires_mcp: outline
triggers:
  - "문서 업데이트"
  - "위키 업데이트"
  - "outline 업데이트"
  - "문서 동기화"
  - "문서화"
auto_suggest:
  keywords:
    - "작업 완료"
    - "커밋할게"
    - "PR 생성"
    - "API 변경"
    - "다 했어"
    - "머지"
  action: "Outline 위키에 변경사항을 반영할까요?"
  phase: 6
---

# Document Latest - Outline 위키 자동 업데이트

## Overview

코드 변경 작업 완료 후 Outline 위키 문서를 자동으로 최신화합니다.
변경된 파일 경로와 커밋 메시지를 분석하여 문서 유형(API/아키텍처/정책/인프라/일반)을 자동 분류하고,
기존 문서 업데이트 또는 신규 문서 생성을 판단합니다.
민감정보(API키, 비밀번호, 사설IP 등)는 자동 마스킹됩니다.

---

## 1. 활성화 규칙

| 트리거 유형 | 조건 | 동작 |
|-------------|------|------|
| **수동** | "문서 업데이트", "위키 업데이트", "outline 업데이트", "문서 동기화", "문서화" 등 명시적 호출 | Phase 1~6 전체 실행 |
| **자동 제안** | "작업 완료", "커밋할게", "PR 생성", "API 변경" 등 완료 신호 감지 | "Outline 위키에 변경사항을 반영할까요?" 질문 → 승인 시 Phase 2~6 실행 |
| **설정 초기화** | "outline 설정", "문서 설정" | Phase 1만 실행 (`.outline-context.json` 생성) |

---

## 2. 컬렉션 설정 (`.outline-context.json`)

프로젝트 루트에 배치하는 최소 설정 파일. 문서를 관리할 Outline 컬렉션 1개를 지정합니다.

### 설정 파일 구조

```json
{
  "collection_id": "uuid-of-collection",
  "language": "ko",
  "sensitive_patterns": ["password", "secret", "api_key", "token", "credential", "private_key", "db_password", "connection_string", "aws_access_key"]
}
```

### 설정 파일 초기화

파일이 존재하지 않을 때:
1. `mcp__outline__list_collections` 호출 → 컬렉션 목록 조회
2. 사용자에게 문서를 관리할 컬렉션 1개 선택 요청
3. 선택된 컬렉션의 `id`로 `.outline-context.json` 자동 생성
4. Git 커밋하여 팀 공유 (UUID만 포함, 보안 위험 없음)

### 컬렉션 동작 방식

- 모든 문서가 설정된 단일 컬렉션에 생성/업데이트됨
- 문서 카테고리(api/architecture/policy/infrastructure/general)는 문서 제목 접두어로 구분
  - 예: `[API] 결제 엔드포인트`, `[Architecture] 인증 모듈 구조`

---

## 3. Behavioral Flow

### Phase 1: Context Loading

```
1. 프로젝트 루트에서 `.outline-context.json` 파일 탐색
2. 파일 존재 → JSON 파싱 → collection_id, language, sensitive_patterns 추출
   파일 미존재 → 초기 설정 워크플로우 실행:
     a) mcp__outline__list_collections 호출 → 컬렉션 목록 조회
     b) 사용자에게 컬렉션 목록 표시 → 1개 선택 요청
     c) 선택된 컬렉션 ID로 `.outline-context.json` 자동 생성
     d) 생성 완료 알림
3. collection_id 유효성 검증 (빈 문자열 체크)
4. 검증 실패 시 → 사용자에게 알림, 재설정 안내
```

### Phase 2: Change Analysis

```
1. `git diff --name-only` → 변경 파일 목록 수집
2. `git diff --stat` → 변경 통계 (파일 수, 추가/삭제 라인)
3. `git log --oneline -10` → 최근 커밋 이력 수집
4. MR 컨텍스트 활용 (post-merge 스킬에서 위임 호출 시):
   - MR 제목/설명 → 문서 요약의 시드 데이터로 활용
   - MR 라벨 → 카테고리 힌트 (api, infrastructure 등 → Phase 3 가중치 부여)
   - 타겟 브랜치 → 문서화 우선순위 (main/master → 높음, develop → 보통)
5. 문서화 필요 여부 판단:
   - 변경 파일이 없으면 → "변경사항이 없습니다" 알림 후 종료
   - 변경 파일이 설정/문서 파일만이면 → 문서화 선택적 제안
   - 코드 변경이 있으면 → 문서화 진행
6. 변경 파일 목록과 커밋 메시지를 Phase 3에 전달
```

### Phase 3: Document Type Detection

파일 경로 패턴과 커밋 메시지 키워드를 분석하여 문서 카테고리를 자동 분류합니다.

**파일 경로 기반 분류 (1차):**

| 파일 경로 패턴 | 카테고리 | 가중치 |
|---------------|---------|--------|
| `controller/`, `route/`, `api/`, `handler/` | api | 3 |
| `src/core/`, `module/`, `service/` (신규 파일) | architecture | 3 |
| `.eslintrc`, `CONTRIBUTING`, `workflow/` | policy | 3 |
| `Dockerfile`, `k8s/`, `terraform/`, `.github/workflows/` | infrastructure | 3 |
| 기타 | general | 1 |

**커밋 메시지 키워드 기반 분류 (2차 보조):**

| 키워드 | 카테고리 | 가중치 |
|--------|---------|--------|
| `endpoint`, `api`, `rest`, `graphql`, `route` | api | 2 |
| `architecture`, `module`, `refactor`, `structure` | architecture | 2 |
| `lint`, `rule`, `policy`, `convention`, `standard` | policy | 2 |
| `deploy`, `docker`, `k8s`, `ci`, `cd`, `infra` | infrastructure | 2 |

```
분류 알고리즘:
1. 각 변경 파일의 경로 패턴을 분석 → 카테고리별 가중치 합산
2. 커밋 메시지 키워드 분석 → 카테고리별 가중치 추가
3. 가중치 합계가 가장 높은 카테고리 선택
4. 최고 가중치가 동일하면 → 사용자에게 카테고리 선택 질문
5. 모든 카테고리 가중치가 0이면 → general로 분류
```

### Phase 4: Document Discovery

```
1. 설정된 컬렉션(collection_id)에서 관련 문서 검색:
   → mcp__outline__search_documents 로 변경 내용 관련 키워드 검색
   → 검색 키워드: 변경된 모듈명, 주요 파일명, 커밋 메시지 핵심 키워드
2. 검색 결과 분석:
   a) 관련 문서 발견 → "기존 문서를 업데이트할까요, 새 문서를 만들까요?" 질문
      - 기존 문서 목록 표시 (제목, 마지막 수정일)
      - 사용자가 업데이트할 문서 선택 또는 신규 생성 선택
   b) 관련 문서 미발견 → 신규 문서 생성 진행
3. 기존 문서 업데이트 선택 시:
   → mcp__outline__read_document 로 기존 문서 내용 로드
   → 기존 내용에 변경사항 병합
```

### Phase 5: Content Generation & Security Filtering

```
1. 카테고리별 문서 템플릿에 따라 한국어 문서 생성 (아래 "카테고리별 문서 템플릿" 참조)
2. 보안 필터링 (필수):
   a) 다음 패턴을 감지하여 마스킹:
      - password, secret, api_key, token, credential, private_key
      - db_password, connection_string, aws_access_key
      - Bearer 토큰: Bearer [토큰값] → Bearer [MASKED]
      - SSH 키: -----BEGIN ... PRIVATE KEY----- → [SSH_KEY_MASKED]
      - 사설 IP: 10.x.x.x, 172.16-31.x.x, 192.168.x.x → [PRIVATE_IP_MASKED]
      - .outline-context.json의 sensitive_patterns에 정의된 추가 패턴
   b) 마스킹 적용 후 결과 사용자에게 보고:
      → "다음 민감정보가 마스킹되었습니다: [항목 목록]"
      → 마스킹 항목이 없으면 보고 생략
3. 생성된 문서 내용을 사용자에게 미리보기로 표시
4. 사용자 수정 요청이 있으면 반영
```

### Phase 6: Write to Outline

```
1. 사용자에게 최종 확인 요청:
   → "다음 내용으로 Outline에 [생성/업데이트]하겠습니다. 진행할까요?"
2. 승인 시:
   a) 신규 문서 생성:
      → mcp__outline__create_document(
          title="[카테고리] 문서 제목",
          text=생성된_마크다운,
          collectionId=collection_id,
          publish=true
        )
   b) 기존 문서 업데이트:
      → mcp__outline__update_document(
          id=문서_id,
          text=업데이트된_마크다운
        )
3. 성공 시 → 문서 URL 표시, 완료 알림
4. 실패 시 → 에러 내용 표시, 재시도 또는 로컬 파일 저장 제안
```

---

## 4. 카테고리별 문서 템플릿

### API 문서 템플릿

```markdown
# [API] {제목}

## 개요
{API 변경 내용 요약}

## Base URL
`{base_url}`

## 엔드포인트

### {HTTP_METHOD} {path}
- **설명**: {설명}
- **인증**: {인증 방식}

#### 요청
| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| {param} | {type} | {required} | {description} |

#### 응답
```json
{응답 예시}
```

## 에러 코드
| 코드 | 설명 |
|------|------|
| {code} | {description} |

## 변경 이력
| 날짜 | 변경 내용 | 커밋 |
|------|----------|------|
| {date} | {description} | {commit_hash} |
```

### 아키텍처 문서 템플릿

```markdown
# [Architecture] {제목}

## 개요
{아키텍처 변경 내용 요약}

## 시스템 구조
{전체 시스템 내에서의 위치와 역할}

## 주요 컴포넌트
| 컴포넌트 | 역할 | 위치 |
|----------|------|------|
| {name} | {role} | {path} |

## 데이터 흐름
{데이터 흐름 설명}

## 설계 결정
| 결정 | 이유 | 대안 |
|------|------|------|
| {decision} | {reason} | {alternatives} |

## 변경 이력
| 날짜 | 변경 내용 | 커밋 |
|------|----------|------|
| {date} | {description} | {commit_hash} |
```

### 정책 문서 템플릿

```markdown
# [Policy] {제목}

## 목적
{정책의 목적}

## 적용 범위
{정책이 적용되는 범위}

## 정책 내용
{구체적인 정책 규칙과 가이드라인}

## 예외 사항
{정책 예외가 허용되는 경우}

## 변경 이력
| 날짜 | 변경 내용 | 커밋 |
|------|----------|------|
| {date} | {description} | {commit_hash} |
```

### 인프라 문서 템플릿

```markdown
# [Infrastructure] {제목}

## 개요
{인프라 변경 내용 요약}

## 환경 구성
| 환경 | 설정 | 비고 |
|------|------|------|
| {env} | {config} | {note} |

## 배포 절차
1. {step1}
2. {step2}

## 롤백 절차
1. {rollback_step1}
2. {rollback_step2}

## 모니터링
| 항목 | 지표 | 임계값 |
|------|------|--------|
| {item} | {metric} | {threshold} |

## 변경 이력
| 날짜 | 변경 내용 | 커밋 |
|------|----------|------|
| {date} | {description} | {commit_hash} |
```

### 일반 문서 템플릿

```markdown
# {제목}

## 개요
{변경 내용 요약}

## 상세 내용
{변경 사항의 상세 설명}

## 영향 범위
{변경으로 인한 영향}

## 변경 이력
| 날짜 | 변경 내용 | 커밋 |
|------|----------|------|
| {date} | {description} | {commit_hash} |
```

---

## 5. 보안 필터링 규칙

### 감지 패턴

| 패턴 유형 | 정규식 | 마스킹 결과 |
|----------|--------|------------|
| 환경변수 값 | `(password\|secret\|api_key\|token\|credential\|private_key\|db_password\|connection_string\|aws_access_key)\s*[=:]\s*\S+` | `{key}=[MASKED]` |
| Bearer 토큰 | `Bearer\s+[A-Za-z0-9\-._~+/]+=*` | `Bearer [MASKED]` |
| SSH 키 | `-----BEGIN\s+\w+\s+PRIVATE\s+KEY-----[\s\S]*?-----END` | `[SSH_KEY_MASKED]` |
| 사설 IP (10.x) | `10\.\d{1,3}\.\d{1,3}\.\d{1,3}` | `[PRIVATE_IP_MASKED]` |
| 사설 IP (172.16-31.x) | `172\.(1[6-9]\|2[0-9]\|3[01])\.\d{1,3}\.\d{1,3}` | `[PRIVATE_IP_MASKED]` |
| 사설 IP (192.168.x) | `192\.168\.\d{1,3}\.\d{1,3}` | `[PRIVATE_IP_MASKED]` |

### 필터링 프로세스

```
1. 문서 생성 완료 후, 전체 텍스트에 대해 위 패턴 순차 검사
2. 매칭된 패턴을 마스킹 결과로 치환
3. 마스킹된 항목 목록 생성
4. 항목이 1개 이상이면 사용자에게 보고:
   "⚠ 다음 민감정보가 마스킹되었습니다:"
   - password 값 1건
   - 사설 IP 2건
   등
5. .outline-context.json의 sensitive_patterns에 추가 패턴이 있으면 해당 패턴도 검사
```

---

## 6. Tool Coordination

### Outline MCP 도구

| 단계 | MCP 도구 | 용도 |
|------|----------|------|
| 컬렉션 조회 | `mcp__outline__list_collections` | 컬렉션 목록 조회 (초기 설정) |
| 문서 검색 | `mcp__outline__search_documents` | 기존 문서 탐색 |
| 문서 읽기 | `mcp__outline__read_document` | 기존 문서 내용 로드 (업데이트 시) |
| 문서 생성 | `mcp__outline__create_document` | 신규 문서 생성 |
| 문서 업데이트 | `mcp__outline__update_document` | 기존 문서 수정 |

### Git 도구 (Bash)

| 명령어 | 용도 |
|--------|------|
| `git diff --name-only` | 변경 파일 목록 수집 |
| `git diff --stat` | 변경 통계 (파일 수, 라인 수) |
| `git log --oneline -10` | 최근 커밋 이력 수집 |

### 파일 도구

| 도구 | 용도 |
|------|------|
| **Glob** | `.outline-context.json` 파일 탐색 |
| **Read** | `.outline-context.json` 설정 로드 |
| **Write** | `.outline-context.json` 초기 생성 |

---

## 7. Examples

### 예시 1: 최초 실행 (컬렉션 설정)

```
사용자: "문서 업데이트해줘"

[Phase 1] .outline-context.json 탐색 → 미존재
          → list_collections 호출 → 5개 컬렉션 발견
          1. "개발 문서" (id: abc-123)
          2. "API 문서" (id: def-456)
          3. "운영 가이드" (id: ghi-789)
          ...

에이전트: 문서를 관리할 Outline 컬렉션을 선택해주세요:
          1. 개발 문서
          2. API 문서
          3. 운영 가이드
          ...

사용자: "1번"

[Phase 1] .outline-context.json 생성:
          { "collection_id": "abc-123", "language": "ko", "sensitive_patterns": [...] }
          → Phase 2로 진행
```

### 예시 2: API 변경 후 문서 자동 업데이트

```
사용자: "API 변경했어, 문서화해줘"

[Phase 1] .outline-context.json 로드 → collection_id: "abc-123"
[Phase 2] git diff --name-only →
          src/controller/payment.controller.ts
          src/route/payment.route.ts
          src/service/payment.service.ts
[Phase 3] 파일 경로 분석 → controller/, route/ → api 카테고리 (가중치 6)
[Phase 4] search_documents("결제 API") → 기존 문서 "[API] 결제 엔드포인트" 발견

에이전트: 기존 문서 "[API] 결제 엔드포인트"를 업데이트할까요?

사용자: "응"

[Phase 5] 기존 문서 읽기 → 변경사항 반영 → 보안 필터링
          → "민감정보 마스킹: 없음"
[Phase 6] update_document 실행 → 완료
          → "문서가 업데이트되었습니다: https://wiki.example.com/doc/..."
```

### 예시 3: 인프라 변경 시 신규 문서 생성

```
사용자: "커밋할게"

에이전트: Outline 위키에 변경사항을 반영할까요?

사용자: "응"

[Phase 2] git diff --name-only →
          .github/workflows/deploy.yml
          k8s/deployment.yaml
          Dockerfile
[Phase 3] 파일 경로 분석 → .github/workflows/, k8s/, Dockerfile → infrastructure (가중치 9)
[Phase 4] search_documents("배포 파이프라인") → 관련 문서 없음

에이전트: 관련 문서가 없습니다. 새 문서를 생성할까요?
          제목: [Infrastructure] CI/CD 배포 파이프라인

사용자: "좋아"

[Phase 5] 인프라 템플릿으로 문서 생성 → 보안 필터링
          → "⚠ 다음 민감정보가 마스킹되었습니다: 사설 IP 2건"
[Phase 6] create_document 실행 → 완료
          → "문서가 생성되었습니다: https://wiki.example.com/doc/..."
```

### 예시 4: 자동 제안 (커밋 시)

```
사용자: "다 했어, 커밋할게"

에이전트: Outline 위키에 변경사항을 반영할까요?

사용자: "아니, 괜찮아"

에이전트: (문서화 생략, 다른 작업 계속)
```

---

## 8. Boundaries

**Will:**
- `.outline-context.json`으로 컬렉션 설정 자동 관리
- 변경 파일 분석 및 문서 유형 자동 분류
- 기존 문서 검색 및 업데이트/신규 생성 판단
- 카테고리별 템플릿 기반 한국어 문서 생성
- 민감정보 자동 감지 및 마스킹
- 사용자 확인 후 Outline 위키에 문서 작성

**Will Not:**
- 사용자 확인 없이 문서 생성/수정
- 문서 삭제 (Outline의 DISABLE_DELETE 설정 준수)
- 코드 자동 수정 또는 커밋
- 여러 컬렉션에 동시 문서 배포
- Outline 워크스페이스 설정 변경
